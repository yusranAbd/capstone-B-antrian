import {
  BadRequestException,
  ConflictException,
  Injectable,
  Logger,
  UnauthorizedException,
} from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { PasswordService } from '../password.service';
import { ChangeOwnPasswordDto, UpdateOwnProfileDto } from './profile.dto';

export const OWN_PROFILE_SELECT = {
  id: true,
  nama: true,
  email: true,
  peran: true,
  aktif: true,
  avatarProfil: true,
  dibuatPada: true,
} as const;

@Injectable()
export class ProfileService {
  private readonly logger = new Logger('ProfileAudit');
  constructor(
    private readonly prisma: PrismaService,
    private readonly passwords: PasswordService,
  ) {}

  async read(id: string) {
    const user = await this.prisma.pengguna.findUnique({
      where: { id },
      select: OWN_PROFILE_SELECT,
    });
    if (!user?.aktif) throw new UnauthorizedException('Akun tidak aktif');
    return user;
  }

  async update(id: string, dto: UpdateOwnProfileDto) {
    const result = await this.prisma.pengguna.updateMany({
      where: { id, aktif: true },
      data: { nama: dto.nama },
    });
    if (!result.count) throw new UnauthorizedException('Akun tidak aktif');
    this.audit('UBAH_NAMA', id);
    return this.read(id);
  }

  async changePassword(id: string, dto: ChangeOwnPasswordDto) {
    const observed = await this.prisma.pengguna.findUnique({
      where: { id },
      select: { kataSandiHash: true, aktif: true },
    });
    if (!observed?.aktif) throw new UnauthorizedException('Akun tidak aktif');
    if (
      !(await this.passwords.verify(dto.kataSandiLama, observed.kataSandiHash))
    )
      throw new BadRequestException('Kata sandi lama tidak sesuai');
    if (await this.passwords.verify(dto.kataSandiBaru, observed.kataSandiHash))
      throw new BadRequestException('Kata sandi baru harus berbeda');
    const hash = await this.passwords.hash(dto.kataSandiBaru);
    await this.prisma.$transaction(
      async (tx) => {
        await tx.$executeRaw`SET LOCAL lock_timeout = '5s'`;
        await tx.$queryRaw`SELECT id FROM pengguna WHERE id = ${id}::uuid FOR UPDATE`;
        const changed = await tx.pengguna.updateMany({
          where: { id, aktif: true, kataSandiHash: observed.kataSandiHash },
          data: { kataSandiHash: hash },
        });
        if (changed.count !== 1)
          throw new ConflictException(
            'Keamanan akun sedang berubah. Muat ulang dan coba kembali',
          );
        await tx.sesiPengguna.updateMany({
          where: { penggunaId: id, dicabutPada: null },
          data: { dicabutPada: new Date() },
        });
      },
      { timeout: 10000 },
    );
    this.audit('UBAH_KATA_SANDI_CABUT_SESI', id);
    return {
      message: 'Kata sandi berhasil diubah. Silakan masuk kembali.',
      loginUlang: true,
    };
  }

  private audit(aksi: string, penggunaId: string) {
    this.logger.log(
      JSON.stringify({
        aksi,
        penggunaId,
        terjadiPada: new Date().toISOString(),
      }),
    );
  }
}
