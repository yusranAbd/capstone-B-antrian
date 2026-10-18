import {
  ConflictException,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService, JwtSignOptions } from '@nestjs/jwt';
import { createHash, randomUUID } from 'crypto';
import { PrismaService } from '../prisma/prisma.service';
import { UsersService } from '../users/users.service';
import { AccessTokenPayload, RefreshTokenPayload } from './auth.types';
import { LoginDto } from './dto/login.dto';
import { RefreshTokenDto } from './dto/refresh-token.dto';
import { RegisterDto } from './dto/register.dto';
import { PasswordService } from './password.service';

@Injectable()
export class AuthService {
  constructor(
    private readonly usersService: UsersService,
    private readonly passwordService: PasswordService,
    private readonly jwtService: JwtService,
    private readonly configService: ConfigService,
    private readonly prisma: PrismaService,
  ) {}

  async register(dto: RegisterDto) {
    const email = dto.email.trim().toLowerCase();

    const existingUser = await this.usersService.findByEmail(email);

    if (existingUser) {
      throw new ConflictException('Email sudah terdaftar');
    }

    const kataSandiHash = await this.passwordService.hash(dto.kataSandi);

    const user = await this.usersService.create({
      nama: dto.nama.trim(),
      email,
      kataSandiHash,
    });

    return {
      id: user.id,
      nama: user.nama,
      email: user.email,
      peran: user.peran,
    };
  }

  async login(dto: LoginDto) {
    const email = dto.email.trim().toLowerCase();

    const user = await this.usersService.findByEmail(email);

    if (!user || !user.aktif) {
      throw new UnauthorizedException('Email atau kata sandi tidak valid');
    }

    const validPassword = await this.passwordService.verify(
      dto.kataSandi,
      user.kataSandiHash,
    );

    if (!validPassword) {
      throw new UnauthorizedException('Email atau kata sandi tidak valid');
    }

    if (
      user.peran === 'DOKTER' &&
      !(await this.prisma.dokter.findFirst({
        where: { penggunaId: user.id, aktif: true },
        select: { id: true },
      }))
    ) {
      throw new UnauthorizedException('Profil dokter tidak aktif atau belum ditautkan');
    }

    const sessionId = randomUUID();

    const tokens = await this.generateTokens({
      userId: user.id,
      email: user.email,
      role: user.peran,
      sessionId,
    });

    await this.prisma.sesiPengguna.create({
      data: {
        id: sessionId,
        penggunaId: user.id,
        tokenRefreshHash: this.hashRefreshToken(tokens.refreshToken),
        namaPerangkat: dto.namaPerangkat ?? null,
        kedaluwarsaPada: this.getRefreshExpirationDate(),
      },
    });

    return {
      ...tokens,
      user: {
        id: user.id,
        nama: user.nama,
        email: user.email,
        peran: user.peran,
      },
    };
  }

  async refresh(dto: RefreshTokenDto) {
    const payload = await this.verifyRefreshToken(dto.refreshToken);

    const session = await this.prisma.sesiPengguna.findUnique({
      where: {
        id: payload.sid,
      },
    });

    const now = new Date();

    if (
      !session ||
      session.dicabutPada ||
      session.kedaluwarsaPada <= now ||
      session.penggunaId !== payload.sub
    ) {
      throw new UnauthorizedException('Sesi tidak valid atau telah berakhir');
    }

    const oldHash = this.hashRefreshToken(dto.refreshToken);

    if (session.tokenRefreshHash !== oldHash) {
      throw new UnauthorizedException('Refresh token tidak valid');
    }

    const user = await this.usersService.findById(payload.sub);

    if (!user || !user.aktif) {
      throw new UnauthorizedException('Pengguna tidak valid atau tidak aktif');
    }

    if (
      user.peran === 'DOKTER' &&
      !(await this.prisma.dokter.findFirst({
        where: { penggunaId: user.id, aktif: true },
        select: { id: true },
      }))
    ) {
      throw new UnauthorizedException('Profil dokter tidak aktif atau belum ditautkan');
    }

    const tokens = await this.generateTokens({
      userId: user.id,
      email: user.email,
      role: user.peran,
      sessionId: session.id,
    });

    // Atomic compare-and-swap:
    // Pembaruan hanya berhasil jika hash token lama
    // masih sesuai dengan nilai di database.
    const result = await this.prisma.sesiPengguna.updateMany({
      where: {
        id: session.id,
        penggunaId: user.id,
        tokenRefreshHash: oldHash,
        dicabutPada: null,
        kedaluwarsaPada: {
          gt: new Date(),
        },
      },
      data: {
        tokenRefreshHash: this.hashRefreshToken(tokens.refreshToken),
        kedaluwarsaPada: this.getRefreshExpirationDate(),
      },
    });

    if (result.count !== 1) {
      throw new UnauthorizedException(
        'Refresh token sudah digunakan atau sesi tidak aktif',
      );
    }

    return {
      ...tokens,
      user: {
        id: user.id,
        nama: user.nama,
        email: user.email,
        peran: user.peran,
      },
    };
  }

  async logout(dto: RefreshTokenDto) {
    const payload = await this.verifyRefreshToken(dto.refreshToken);

    const session = await this.prisma.sesiPengguna.findUnique({
      where: {
        id: payload.sid,
      },
    });

    if (!session || session.penggunaId !== payload.sub) {
      throw new UnauthorizedException('Sesi tidak valid');
    }

    const providedHash = this.hashRefreshToken(dto.refreshToken);

    if (providedHash !== session.tokenRefreshHash) {
      throw new UnauthorizedException('Refresh token tidak valid');
    }

    await this.prisma.sesiPengguna.update({
      where: {
        id: session.id,
      },
      data: {
        dicabutPada: new Date(),
      },
    });

    return {
      message: 'Logout berhasil',
    };
  }

  private async generateTokens(params: {
    userId: string;
    email: string;
    role: AccessTokenPayload['role'];
    sessionId: string;
  }) {
    const accessPayload: AccessTokenPayload = {
      sub: params.userId,
      sid: params.sessionId,
      email: params.email,
      role: params.role,
    };

    const refreshPayload: RefreshTokenPayload = {
      sub: params.userId,
      sid: params.sessionId,
      type: 'refresh',
      jti: randomUUID(),
    };

    const accessExpiresIn = this.configService.getOrThrow<string>(
      'JWT_ACCESS_EXPIRES_IN',
    );

    const refreshExpiresIn = this.configService.getOrThrow<string>(
      'JWT_REFRESH_EXPIRES_IN',
    );

    const [accessToken, refreshToken] = await Promise.all([
      this.jwtService.signAsync(accessPayload, {
        secret: this.configService.getOrThrow<string>('JWT_ACCESS_SECRET'),
        expiresIn: accessExpiresIn as JwtSignOptions['expiresIn'],
      }),

      this.jwtService.signAsync(refreshPayload, {
        secret: this.configService.getOrThrow<string>('JWT_REFRESH_SECRET'),
        expiresIn: refreshExpiresIn as JwtSignOptions['expiresIn'],
      }),
    ]);

    return {
      accessToken,
      refreshToken,
    };
  }

  private async verifyRefreshToken(
    refreshToken: string,
  ): Promise<RefreshTokenPayload> {
    try {
      const payload = await this.jwtService.verifyAsync<RefreshTokenPayload>(
        refreshToken,
        {
          secret: this.configService.getOrThrow<string>('JWT_REFRESH_SECRET'),
        },
      );

      if (
        payload.type !== 'refresh' ||
        !payload.sid ||
        !payload.sub ||
        !payload.jti
      ) {
        throw new UnauthorizedException('Refresh token tidak valid');
      }

      return payload;
    } catch {
      throw new UnauthorizedException(
        'Refresh token tidak valid atau kedaluwarsa',
      );
    }
  }

  private hashRefreshToken(refreshToken: string): string {
    return createHash('sha256').update(refreshToken).digest('hex');
  }

  private getRefreshExpirationDate(): Date {
    const value = this.configService.getOrThrow<string>(
      'JWT_REFRESH_EXPIRES_IN',
    );

    const durationMs = this.durationToMilliseconds(value);

    return new Date(Date.now() + durationMs);
  }

  private durationToMilliseconds(value: string): number {
    const match = /^(\d+)(s|m|h|d)$/.exec(value);

    if (!match) {
      throw new Error(`Format durasi JWT tidak valid: ${value}`);
    }

    const amount = Number(match[1]);
    const unit = match[2];

    const multipliers: Record<string, number> = {
      s: 1_000,
      m: 60_000,
      h: 3_600_000,
      d: 86_400_000,
    };

    return amount * multipliers[unit];
  }
}
