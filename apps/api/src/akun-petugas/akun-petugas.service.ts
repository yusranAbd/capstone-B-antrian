import {
  ConflictException,
  Injectable,
  Logger,
  NotFoundException,
} from '@nestjs/common';
import { PasswordService } from '../auth/password.service';
import { Prisma } from '../generated/prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { CreateAkunPetugasDto } from './akun-petugas.dto';

const metadata = {
  id: true,
  nama: true,
  email: true,
  peran: true,
  aktif: true,
} as const;

@Injectable()
export class AkunPetugasService {
  private readonly logger = new Logger('AdminAccountAudit');
  constructor(
    private readonly prisma: PrismaService,
    private readonly password: PasswordService,
  ) {}

  list() {
    return this.prisma.pengguna.findMany({
      where: { peran: 'PETUGAS' },
      select: metadata,
      orderBy: [{ nama: 'asc' }, { email: 'asc' }],
    });
  }

  async create(dto: CreateAkunPetugasDto, actorId: string) {
    const hash = await this.password.hash(dto.kataSandi);
    try {
      const akun = await this.prisma.pengguna.create({
        data: {
          nama: dto.nama.trim(),
          email: dto.email.trim().toLowerCase(),
          kataSandiHash: hash,
          peran: 'PETUGAS',
          aktif: true,
        },
        select: metadata,
      });
      this.audit('BUAT_AKUN_PETUGAS', akun.id, actorId);
      return akun;
    } catch (error) {
      if (
        error instanceof Prisma.PrismaClientKnownRequestError &&
        error.code === 'P2002'
      )
        throw new ConflictException(
          'Email sudah digunakan. Gunakan email lain.',
        );
      throw error;
    }
  }

  async status(id: string, aktif: boolean, actorId: string) {
    const akun = await this.prisma.$transaction(async (tx) => {
      // Same row lock as assignment writes: account validity cannot change midway.
      await tx.$queryRaw`SELECT id FROM pengguna WHERE id = ${id}::uuid FOR UPDATE`;
      const existing = await tx.pengguna.findUnique({
        where: { id },
        select: metadata,
      });
      if (!existing || existing.peran !== 'PETUGAS')
        throw new NotFoundException('Akun PETUGAS tidak ditemukan');
      const result = await tx.pengguna.update({
        where: { id },
        data: { aktif },
        select: metadata,
      });
      if (!aktif)
        await tx.sesiPengguna.updateMany({
          where: { penggunaId: id, dicabutPada: null },
          data: { dicabutPada: new Date() },
        });
      return result;
    });
    this.audit(
      aktif ? 'AKTIFKAN_AKUN_PETUGAS' : 'NONAKTIFKAN_AKUN_PETUGAS',
      id,
      actorId,
    );
    return akun;
  }

  private audit(aksi: string, id: string, aktorId: string) {
    this.logger.log(
      JSON.stringify({
        aksi,
        id,
        aktorId,
        terjadiPada: new Date().toISOString(),
      }),
    );
  }
}
