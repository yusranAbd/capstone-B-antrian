import { Injectable, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PassportStrategy } from '@nestjs/passport';
import { ExtractJwt, Strategy } from 'passport-jwt';
import { PrismaService } from '../prisma/prisma.service';
import { UsersService } from '../users/users.service';
import type { AccessTokenPayload, AuthenticatedUser } from './auth.types';

@Injectable()
export class JwtStrategy extends PassportStrategy(Strategy, 'jwt') {
  constructor(
    configService: ConfigService,
    private readonly usersService: UsersService,
    private readonly prisma: PrismaService,
  ) {
    super({
      jwtFromRequest: ExtractJwt.fromAuthHeaderAsBearerToken(),
      ignoreExpiration: false,
      secretOrKey: configService.getOrThrow<string>('JWT_ACCESS_SECRET'),
    });
  }

  async validate(payload: AccessTokenPayload): Promise<AuthenticatedUser> {
    if (
      typeof payload.sub !== 'string' ||
      typeof payload.sid !== 'string' ||
      !payload.sub ||
      !payload.sid
    ) {
      throw new UnauthorizedException('Access token tidak valid');
    }

    const [user, session] = await Promise.all([
      this.usersService.findById(payload.sub),

      this.prisma.sesiPengguna.findUnique({
        where: {
          id: payload.sid,
        },
      }),
    ]);

    if (!user || !user.aktif) {
      throw new UnauthorizedException('Pengguna tidak valid atau tidak aktif');
    }

    if (
      !session ||
      session.penggunaId !== user.id ||
      session.dicabutPada !== null ||
      session.kedaluwarsaPada <= new Date()
    ) {
      throw new UnauthorizedException('Sesi tidak aktif atau telah berakhir');
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

    return {
      id: user.id,
      nama: user.nama,
      email: user.email,
      peran: user.peran,
    };
  }
}
