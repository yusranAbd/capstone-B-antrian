import { Injectable } from '@nestjs/common';

import { PeranPengguna } from '../generated/prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { waktuPelayanan } from '../hospital/hospital-context';

export interface IdentitasSocket {
  id: string;
  sid: string;
  peran: PeranPengguna;
  exp: number;
}

export type HasilOtorisasiRoom = 'ALLOWED' | 'UNAUTHORIZED' | 'FORBIDDEN';

/** Otorisasi room selalu menggunakan kondisi database terkini. */
@Injectable()
export class RealtimeRoomAccessService {
  constructor(private readonly prisma: PrismaService) {}

  async periksa(
    identitas: IdentitasSocket,
    layananId: string,
  ): Promise<HasilOtorisasiRoom> {
    if (identitas.exp * 1000 <= Date.now()) {
      return 'UNAUTHORIZED';
    }

    // Cegah sesi dicabut, kedaluwarsa, akun nonaktif, atau role berubah.
    const sesi = await this.prisma.sesiPengguna.findFirst({
      where: {
        id: identitas.sid,
        penggunaId: identitas.id,
        dicabutPada: null,
        kedaluwarsaPada: { gt: new Date() },
        pengguna: { aktif: true, peran: identitas.peran },
      },
      select: { id: true },
    });
    if (!sesi) {
      return 'UNAUTHORIZED';
    }

    const layanan = await this.prisma.layanan.findFirst({
      where: { id: layananId, aktif: true },
      select: { id: true },
    });
    if (!layanan) {
      return 'FORBIDDEN';
    }

    if (identitas.peran === PeranPengguna.ADMIN) {
      return 'ALLOWED';
    }
    if (identitas.peran !== PeranPengguna.PETUGAS) {
      return 'FORBIDDEN';
    }

    const hariIni = waktuPelayanan(new Date()).tanggalDb;
    const penugasan = await this.prisma.penugasanPetugas.findFirst({
      where: {
        petugasId: identitas.id,
        aktif: true,
        tanggalMulai: { lte: hariIni },
        OR: [{ tanggalSelesai: null }, { tanggalSelesai: { gte: hariIni } }],
        loket: {
          aktif: true,
          layananId,
          layanan: { aktif: true },
        },
      },
      select: { id: true },
    });

    return penugasan ? 'ALLOWED' : 'FORBIDDEN';
  }

}
