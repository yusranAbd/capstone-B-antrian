import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';

import { PeranPengguna, Prisma } from '../generated/prisma/client';

import { PrismaService } from '../prisma/prisma.service';

import { CreatePenugasanPetugasDto } from './dto/create-penugasan-petugas.dto';
import { UpdatePenugasanPetugasDto } from './dto/update-penugasan-petugas.dto';

const relasiPenugasan = {
  petugas: {
    select: {
      id: true,
      nama: true,
      email: true,
      peran: true,
      aktif: true,
    },
  },
  loket: {
    select: {
      id: true,
      kode: true,
      nama: true,
      aktif: true,
      layanan: {
        select: {
          id: true,
          kode: true,
          nama: true,
          aktif: true,
        },
      },
    },
  },
} as const;

@Injectable()
export class PenugasanPetugasService {
  constructor(private readonly prisma: PrismaService) {}

  // ==========================================
  // CREATE
  // ==========================================

  async create(dto: CreatePenugasanPetugasDto) {
    const mulai = this.parseTanggal(dto.tanggalMulai);
    const selesai = dto.tanggalSelesai
      ? this.parseTanggal(dto.tanggalSelesai)
      : null;

    this.validasiRentang(mulai, selesai);

    try {
      return await this.prisma.$transaction(
        async (tx) => {
          await this.kunciPetugas(tx, [dto.petugasId]);
          await this.validasiPetugas(dto.petugasId, tx);
          await this.validasiLoket(dto.loketId, tx);
          await this.validasiKonflik(
            dto.petugasId,
            mulai,
            selesai,
            undefined,
            tx,
          );
          return tx.penugasanPetugas.create({
            data: {
              tanggalMulai: mulai,
              tanggalSelesai: selesai,
              aktif: true,
              petugas: {
                connect: { id: dto.petugasId },
              },
              loket: {
                connect: { id: dto.loketId },
              },
            },
            include: relasiPenugasan,
          });
        },
        { isolationLevel: Prisma.TransactionIsolationLevel.ReadCommitted },
      );
    } catch (error: unknown) {
      this.handleDatabaseError(error);
    }
  }

  // ==========================================
  // READ ALL
  // ==========================================

  findAll(peran: PeranPengguna, penggunaId: string) {
    const where: Prisma.PenugasanPetugasWhereInput =
      peran === PeranPengguna.ADMIN ? {} : { petugasId: penggunaId };

    return this.prisma.penugasanPetugas.findMany({
      where,
      include: relasiPenugasan,
      orderBy: [{ tanggalMulai: 'desc' }, { dibuatPada: 'desc' }],
    });
  }

  // ==========================================
  // READ ONE
  // ==========================================

  async findOne(id: string, peran: PeranPengguna, penggunaId: string) {
    const where: Prisma.PenugasanPetugasWhereInput = {
      id,
      ...(peran === PeranPengguna.ADMIN ? {} : { petugasId: penggunaId }),
    };

    const data = await this.prisma.penugasanPetugas.findFirst({
      where,
      include: relasiPenugasan,
    });

    if (!data) {
      throw new NotFoundException('Penugasan petugas tidak ditemukan');
    }

    return data;
  }

  // ==========================================
  // UPDATE
  // ==========================================

  async update(id: string, dto: UpdatePenugasanPetugasDto) {
    try {
      return await this.prisma.$transaction(
        async (tx) => {
          await tx.$queryRaw`SELECT id FROM penugasan_petugas WHERE id = ${id}::uuid FOR UPDATE`;
          const existing = await tx.penugasanPetugas.findUnique({
            where: { id },
            select: {
              id: true,
              petugasId: true,
              loketId: true,
              tanggalMulai: true,
              tanggalSelesai: true,
              aktif: true,
            },
          });

          if (!existing) {
            throw new NotFoundException('Penugasan petugas tidak ditemukan');
          }

          const petugasId = dto.petugasId ?? existing.petugasId;
          const loketId = dto.loketId ?? existing.loketId;
          await this.kunciPetugas(tx, [existing.petugasId, petugasId]);

          const mulai =
            dto.tanggalMulai !== undefined
              ? this.parseTanggal(dto.tanggalMulai)
              : existing.tanggalMulai;

          const selesai =
            dto.tanggalSelesai === undefined
              ? existing.tanggalSelesai
              : dto.tanggalSelesai === null
                ? null
                : this.parseTanggal(dto.tanggalSelesai);

          const aktif = dto.aktif ?? existing.aktif;

          this.validasiRentang(mulai, selesai);

          // Periksa ulang jika referensi berubah
          // atau penugasan tetap/menjadi aktif.
          if (aktif || dto.petugasId !== undefined) {
            await this.validasiPetugas(petugasId, tx);
          }

          if (aktif || dto.loketId !== undefined) {
            await this.validasiLoket(loketId, tx);
          }

          if (aktif) {
            await this.validasiKonflik(petugasId, mulai, selesai, id, tx);
          }

          return tx.penugasanPetugas.update({
            where: { id },
            data: {
              petugas:
                dto.petugasId !== undefined
                  ? { connect: { id: petugasId } }
                  : undefined,

              loket:
                dto.loketId !== undefined
                  ? { connect: { id: loketId } }
                  : undefined,

              tanggalMulai: dto.tanggalMulai !== undefined ? mulai : undefined,

              tanggalSelesai:
                dto.tanggalSelesai !== undefined ? selesai : undefined,

              aktif: dto.aktif,
            },
            include: relasiPenugasan,
          });
        },
        { isolationLevel: Prisma.TransactionIsolationLevel.ReadCommitted },
      );
    } catch (error: unknown) {
      this.handleDatabaseError(error);
    }
  }

  // ==========================================
  // SOFT DELETE
  // ==========================================

  async remove(id: string) {
    return this.update(id, { aktif: false });
  }

  private async kunciPetugas(tx: Prisma.TransactionClient, ids: string[]) {
    // Stable order also covers moving an assignment to another account.
    // READ COMMITTED + this lock makes the following conflict read see prior commits.
    for (const id of [...new Set(ids)].sort()) {
      await tx.$queryRaw`SELECT id FROM pengguna WHERE id = ${id}::uuid FOR UPDATE`;
    }
  }

  // ==========================================
  // VALIDASI PENGGUNA
  // ==========================================

  private async validasiPetugas(
    petugasId: string,
    tx: Prisma.TransactionClient,
  ): Promise<void> {
    const pengguna = await tx.pengguna.findUnique({
      where: { id: petugasId },
      select: {
        id: true,
        peran: true,
        aktif: true,
      },
    });

    if (!pengguna) {
      throw new NotFoundException('Pengguna petugas tidak ditemukan');
    }

    if (pengguna.peran !== PeranPengguna.PETUGAS) {
      throw new BadRequestException('Pengguna harus memiliki peran PETUGAS');
    }
    if (!pengguna.aktif)
      throw new BadRequestException('Akun PETUGAS harus aktif');
  }

  // ==========================================
  // VALIDASI LOKET
  // ==========================================

  private async validasiLoket(
    loketId: string,
    tx: Prisma.TransactionClient,
  ): Promise<void> {
    const loket = await tx.loket.findUnique({
      where: { id: loketId },
      select: {
        id: true,
        aktif: true,
        layanan: {
          select: { aktif: true },
        },
      },
    });

    if (!loket) {
      throw new NotFoundException('Loket tidak ditemukan');
    }

    if (!loket.aktif || !loket.layanan.aktif) {
      throw new BadRequestException('Loket dan layanan induknya harus aktif');
    }
  }

  // ==========================================
  // VALIDASI PERIODE TANGGAL
  // ==========================================

  private parseTanggal(value: string): Date {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) {
      throw new BadRequestException(
        'Tanggal harus menggunakan format YYYY-MM-DD',
      );
    }

    const tanggal = new Date(`${value}T00:00:00.000Z`);

    if (
      Number.isNaN(tanggal.getTime()) ||
      tanggal.toISOString().slice(0, 10) !== value
    ) {
      throw new BadRequestException('Tanggal kalender tidak valid');
    }

    return tanggal;
  }

  private validasiRentang(mulai: Date, selesai: Date | null): void {
    if (selesai && selesai.getTime() < mulai.getTime()) {
      throw new BadRequestException(
        'Tanggal selesai tidak boleh sebelum tanggal mulai',
      );
    }
  }

  // ==========================================
  // VALIDASI BENTURAN PENUGASAN
  // ==========================================

  private async validasiKonflik(
    petugasId: string,
    mulai: Date,
    selesai: Date | null,
    kecualiId?: string,
    tx: Prisma.TransactionClient = this.prisma,
  ): Promise<void> {
    const where: Prisma.PenugasanPetugasWhereInput = {
      petugasId,
      aktif: true,

      ...(kecualiId ? { id: { not: kecualiId } } : {}),

      // Jika tanggal selesai baru tersedia,
      // penugasan lama harus mulai sebelum
      // atau pada tanggal tersebut.
      ...(selesai ? { tanggalMulai: { lte: selesai } } : {}),

      // Penugasan lama yang belum berakhir,
      // atau selesai setelah tanggal mulai baru,
      // dianggap bertabrakan.
      OR: [{ tanggalSelesai: null }, { tanggalSelesai: { gte: mulai } }],
    };

    const bentrok = await tx.penugasanPetugas.findFirst({
      where,
      select: { id: true },
    });

    if (bentrok) {
      throw new ConflictException(
        'Petugas sudah memiliki penugasan aktif pada periode tersebut',
      );
    }
  }

  // ==========================================
  // PENANGANAN ERROR DATABASE
  // ==========================================

  private handleDatabaseError(error: unknown): never {
    const code =
      typeof error === 'object' && error !== null && 'code' in error
        ? String(error.code)
        : '';
    if (['P2034', 'P2028'].includes(code))
      throw new ConflictException(
        'Penugasan sedang berubah. Muat ulang dan coba lagi.',
      );
    if (error instanceof Prisma.PrismaClientKnownRequestError) {
      if (error.code === 'P2025') {
        throw new NotFoundException('Penugasan atau relasi tidak ditemukan');
      }

      if (error.code === 'P2003') {
        throw new BadRequestException('Relasi petugas atau loket tidak valid');
      }

      if (error.code === 'P2002') {
        throw new ConflictException('Data penugasan sudah digunakan');
      }
    }

    throw error;
  }
}
