import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
  UnprocessableEntityException,
} from '@nestjs/common';

import { PeranPengguna, Prisma } from '../generated/prisma/client';
import { PrismaService } from '../prisma/prisma.service';

import { PasswordService } from '../auth/password.service';
import { ProvisionAkunDokterDto } from './dto/provision-akun-dokter.dto';
import { CreateDokterDto } from './dto/create-dokter.dto';
import { HubungkanDokterLayananDto } from './dto/hubungkan-dokter-layanan.dto';
import { UpdateDokterDto } from './dto/update-dokter.dto';

@Injectable()
export class DokterService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly password?: PasswordService,
  ) {}

  akunTersedia() {
    return this.prisma.pengguna.findMany({
      where: { peran: 'DOKTER', aktif: true, dokter: { is: null } },
      select: { id: true, nama: true, email: true, aktif: true },
      orderBy: { nama: 'asc' },
    });
  }

  async provisionAkun(id: string, dto: ProvisionAkunDokterDto) {
    if (
      dto.penggunaId
        ? dto.email !== undefined || dto.kataSandi !== undefined
        : !dto.email || !dto.kataSandi
    ) {
      throw new BadRequestException(
        'Pilih penggunaId atau pasangan email dan kataSandi',
      );
    }
    const hash = dto.kataSandi
      ? await this.password!.hash(dto.kataSandi)
      : undefined;
    try {
      return await this.prisma.$transaction(async (tx) => {
        const dokter = await tx.dokter.findUnique({ where: { id } });
        if (!dokter) throw new NotFoundException('Dokter tidak ditemukan');
        if (!dokter.aktif)
          throw new UnprocessableEntityException('Dokter tidak aktif');
        if (dokter.penggunaId)
          throw new ConflictException('Dokter sudah memiliki akun');
        const akun = dto.penggunaId
          ? await tx.pengguna.findUnique({
              where: { id: dto.penggunaId },
              select: {
                id: true,
                nama: true,
                email: true,
                peran: true,
                aktif: true,
              },
            })
          : await tx.pengguna.create({
              data: {
                nama: dokter.nama,
                email: dto.email!.trim().toLowerCase(),
                kataSandiHash: hash!,
                peran: 'DOKTER',
              },
              select: {
                id: true,
                nama: true,
                email: true,
                peran: true,
                aktif: true,
              },
            });
        if (!akun || akun.peran !== 'DOKTER' || !akun.aktif)
          throw new UnprocessableEntityException('Akun harus DOKTER aktif');
        const linked = await tx.dokter.updateMany({
          where: { id, penggunaId: null, aktif: true },
          data: { penggunaId: akun.id },
        });
        if (linked.count !== 1)
          throw new ConflictException(
            'Dokter sudah ditautkan atau tidak aktif',
          );
        return { dokterId: id, akun };
      });
    } catch (error) {
      this.handleDatabaseError(error);
    }
  }

  async create(dto: CreateDokterDto) {
    try {
      return await this.prisma.dokter.create({
        data: {
          kode: dto.kode,
          nama: dto.nama.trim(),
          spesialisasi: dto.spesialisasi?.trim() || null,
          aktif: true,
        },
      });
    } catch (error: unknown) {
      this.handleDatabaseError(error);
    }
  }

  findAll(peran: PeranPengguna) {
    const admin = peran === PeranPengguna.ADMIN;
    return this.prisma.dokter.findMany({
      where: admin
        ? undefined
        : {
            aktif: true,
            dokterLayanan: {
              some: { aktif: true, layanan: { aktif: true } },
            },
          },
      omit: { penggunaId: !admin },
      include: {
        pengguna: admin
          ? { select: { nama: true, email: true, aktif: true } }
          : false,
        dokterLayanan: {
          where: admin ? undefined : { aktif: true, layanan: { aktif: true } },
          select: {
            id: true,
            layananId: true,
            aktif: true,
            layanan: {
              select: { id: true, kode: true, nama: true, aktif: true },
            },
          },
        },
      },
      orderBy: { kode: 'asc' },
    });
  }

  async findOne(id: string, peran: PeranPengguna) {
    const admin = peran === PeranPengguna.ADMIN;
    const dokter = await this.prisma.dokter.findFirst({
      where: {
        id,
        ...(admin
          ? {}
          : {
              aktif: true,
              dokterLayanan: {
                some: { aktif: true, layanan: { aktif: true } },
              },
            }),
      },
      omit: { penggunaId: !admin },
      include: {
        pengguna: admin
          ? { select: { nama: true, email: true, aktif: true } }
          : false,
        dokterLayanan: {
          where: admin ? undefined : { aktif: true, layanan: { aktif: true } },
          select: {
            id: true,
            layananId: true,
            aktif: true,
            layanan: {
              select: { id: true, kode: true, nama: true, aktif: true },
            },
          },
        },
      },
    });
    if (!dokter) throw new NotFoundException('Dokter tidak ditemukan');
    return dokter;
  }

  async update(id: string, dto: UpdateDokterDto) {
    await this.ensureDokterExists(id);
    try {
      return await this.prisma.dokter.update({
        where: { id },
        data: {
          kode: dto.kode,
          nama: dto.nama !== undefined ? dto.nama.trim() : undefined,
          spesialisasi:
            dto.spesialisasi === undefined
              ? undefined
              : dto.spesialisasi?.trim() || null,
          aktif: dto.aktif,
        },
      });
    } catch (error: unknown) {
      this.handleDatabaseError(error);
    }
  }

  async remove(id: string) {
    await this.ensureDokterExists(id);
    try {
      return await this.prisma.dokter.update({
        where: { id },
        data: { aktif: false },
      });
    } catch (error: unknown) {
      this.handleDatabaseError(error);
    }
  }

  async findLayanan(id: string, peran: PeranPengguna) {
    const dokter = await this.findOne(id, peran);
    return dokter.dokterLayanan;
  }

  async hubungkanLayanan(id: string, dto: HubungkanDokterLayananDto) {
    const [dokter, layanan] = await Promise.all([
      this.prisma.dokter.findUnique({
        where: { id },
        select: { id: true, aktif: true },
      }),
      this.prisma.layanan.findUnique({
        where: { id: dto.layananId },
        select: { id: true, aktif: true },
      }),
    ]);

    if (!dokter) throw new NotFoundException('Dokter tidak ditemukan');
    if (!layanan) throw new NotFoundException('Layanan tidak ditemukan');
    if (!dokter.aktif) {
      throw new UnprocessableEntityException('Dokter tidak aktif');
    }
    if (!layanan.aktif) {
      throw new UnprocessableEntityException('Layanan tidak aktif');
    }

    // Upsert mengaktifkan kembali relasi yang pernah dinonaktifkan.
    try {
      return await this.prisma.dokterLayanan.upsert({
        where: {
          dokterId_layananId: { dokterId: id, layananId: dto.layananId },
        },
        create: { dokterId: id, layananId: dto.layananId, aktif: true },
        update: { aktif: true },
        include: {
          layanan: {
            select: { id: true, kode: true, nama: true, aktif: true },
          },
        },
      });
    } catch (error: unknown) {
      this.handleDatabaseError(error);
    }
  }

  async nonaktifkanLayanan(id: string, layananId: string) {
    await this.ensureDokterExists(id);
    const relasi = await this.prisma.dokterLayanan.findUnique({
      where: { dokterId_layananId: { dokterId: id, layananId } },
      select: { id: true },
    });
    if (!relasi) {
      throw new NotFoundException('Relasi dokter dan layanan tidak ditemukan');
    }

    try {
      return await this.prisma.dokterLayanan.update({
        where: { id: relasi.id },
        data: { aktif: false },
      });
    } catch (error: unknown) {
      this.handleDatabaseError(error);
    }
  }

  private async ensureDokterExists(id: string) {
    const dokter = await this.prisma.dokter.findUnique({
      where: { id },
      select: { id: true },
    });
    if (!dokter) throw new NotFoundException('Dokter tidak ditemukan');
  }

  private handleDatabaseError(error: unknown): never {
    if (error instanceof Prisma.PrismaClientKnownRequestError) {
      if (error.code === 'P2002') {
        throw new ConflictException(
          'Kode dokter, email, akun atau relasi dokter sudah digunakan',
        );
      }
      if (error.code === 'P2025') {
        throw new NotFoundException(
          'Dokter atau relasi layanan tidak ditemukan',
        );
      }
    }
    throw error;
  }
}
