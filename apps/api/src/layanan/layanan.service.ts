import {
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';

import { ModeReservasi, PeranPengguna, Prisma } from '../generated/prisma/client';

import { PrismaService } from '../prisma/prisma.service';
import { CreateLayananDto } from './dto/create-layanan.dto';
import { UpdateLayananDto } from './dto/update-layanan.dto';

@Injectable()
export class LayananService {
  constructor(private readonly prisma: PrismaService) {}

  // =====================================
  // CREATE
  // =====================================

  async create(dto: CreateLayananDto) {
    try {
      return await this.prisma.layanan.create({
        data: {
          kode: dto.kode,
          nama: dto.nama.trim(),
          deskripsi: dto.deskripsi ?? null,
          prefixAntrean: dto.prefixAntrean,
          durasiDasarMenit: dto.durasiDasarMenit,
          modeReservasi: dto.modeReservasi ?? ModeReservasi.ANTREAN_HARIAN,
          aktif: true,
        },
      });
    } catch (error: unknown) {
      this.handleDatabaseError(error);
    }
  }

  // =====================================
  // READ ALL
  // =====================================

  findAll(peran: PeranPengguna) {
    const adalahAdmin = peran === PeranPengguna.ADMIN;

    return this.prisma.layanan.findMany({
      where: adalahAdmin ? undefined : { aktif: true },

      orderBy: {
        kode: 'asc',
      },
    });
  }

  // =====================================
  // READ ONE
  // =====================================

  async findOne(id: string, peran: PeranPengguna) {
    const adalahAdmin = peran === PeranPengguna.ADMIN;

    const layanan = await this.prisma.layanan.findFirst({
      where: {
        id,
        ...(adalahAdmin ? {} : { aktif: true }),
      },
    });

    if (!layanan) {
      throw new NotFoundException('Layanan tidak ditemukan');
    }

    return layanan;
  }

  // =====================================
  // UPDATE
  // =====================================

  async update(id: string, dto: UpdateLayananDto) {
    await this.ensureExists(id);

    try {
      return await this.prisma.layanan.update({
        where: {
          id,
        },
        data: {
          kode: dto.kode,
          nama: dto.nama !== undefined ? dto.nama.trim() : undefined,
          deskripsi: dto.deskripsi,
          prefixAntrean: dto.prefixAntrean,
          durasiDasarMenit: dto.durasiDasarMenit,
          aktif: dto.aktif,
        },
      });
    } catch (error: unknown) {
      this.handleDatabaseError(error);
    }
  }

  // =====================================
  // SOFT DELETE
  // =====================================

  async remove(id: string) {
    await this.ensureExists(id);

    try {
      return await this.prisma.layanan.update({
        where: {
          id,
        },
        data: {
          aktif: false,
        },
      });
    } catch (error: unknown) {
      this.handleDatabaseError(error);
    }
  }

  // =====================================
  // INTERNAL HELPERS
  // =====================================

  private async ensureExists(id: string) {
    const layanan = await this.prisma.layanan.findUnique({
      where: { id },
      select: { id: true },
    });

    if (!layanan) {
      throw new NotFoundException('Layanan tidak ditemukan');
    }
  }

  private handleDatabaseError(error: unknown): never {
    if (error instanceof Prisma.PrismaClientKnownRequestError) {
      if (error.code === 'P2002') {
        throw new ConflictException('Kode layanan sudah digunakan');
      }

      if (error.code === 'P2025') {
        throw new NotFoundException('Layanan tidak ditemukan');
      }
    }

    throw error;
  }
}
