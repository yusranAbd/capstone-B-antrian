import { createHash } from 'node:crypto';

import {
  ForbiddenException,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';

import { Prisma, StatusTiket } from '../generated/prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import type {
  DisplayPengumuman,
  DisplaySnapshot,
  DisplayTiketAktif,
} from './display-snapshot.types';

const POLA_TOKEN = /^[0-9a-f]{64}$/i;

@Injectable()
export class DisplayService {
  constructor(private readonly prisma: PrismaService) {}

  /** SHA-256 untuk token acak kriptografis 32 byte, bukan untuk kata sandi pengguna. */
  private hashToken(token: string): string {
    return createHash('sha256').update(token, 'utf8').digest('hex');
  }

  async snapshot(layananId: string, token: string | undefined): Promise<DisplaySnapshot> {
    if (typeof token !== 'string' || !POLA_TOKEN.test(token)) {
      throw new UnauthorizedException('Token perangkat display tidak valid');
    }

    const tanggal = this.tanggalPelayanan(new Date());
    const hashToken = this.hashToken(token);

    // Semua query harus konsisten; jangan keluarkan objek Prisma mentah ke publik.
    const data = await this.prisma.$transaction(
      async (tx) => {
        const perangkat = await tx.perangkatTampilan.findUnique({
          where: { tokenHash: hashToken },
          select: { aktif: true, layananId: true, layanan: { select: { aktif: true } } },
        });
        if (!perangkat) {
          throw new UnauthorizedException('Token perangkat display tidak valid');
        }
        if (!perangkat.aktif || !perangkat.layanan.aktif || perangkat.layananId !== layananId) {
          throw new ForbiddenException('Perangkat tidak berwenang untuk layanan ini');
        }

        const layanan = await tx.layanan.findUniqueOrThrow({
          where: { id: layananId },
          select: { kode: true, nama: true, prefixAntrean: true },
        });

        const [loketAktif, tiketAktif, totalMenunggu, panggilan] = await Promise.all([
          tx.loket.findMany({
            where: { layananId, aktif: true },
            select: { id: true, kode: true, nama: true },
            orderBy: [{ kode: 'asc' }, { id: 'asc' }],
          }),
          tx.tiketAntrean.findMany({
            where: {
              layananId,
              tanggalAntrean: tanggal.tanggalDb,
              status: { in: [StatusTiket.DIPANGGIL, StatusTiket.DILAYANI] },
              loket: { is: { aktif: true } },
            },
            select: {
              loketId: true,
              nomorUrut: true,
              status: true,
              dipanggilPada: true,
            },
            orderBy: [{ dipanggilPada: 'asc' }, { id: 'asc' }],
          }),
          tx.tiketAntrean.count({
            where: {
              layananId,
              tanggalAntrean: tanggal.tanggalDb,
              status: StatusTiket.MENUNGGU,
              urutanMasukAntrean: { not: null },
            },
          }),
          tx.peristiwaAntrean.findFirst({
            where: {
              tipe: { in: ['CALL', 'RECALL'] },
              tiketAntrean: {
                is: {
                  layananId,
                  tanggalAntrean: tanggal.tanggalDb,
                  status: StatusTiket.DIPANGGIL,
                  loket: { is: { aktif: true } },
                },
              },
            },
            select: {
              id: true,
              tipe: true,
              terjadiPada: true,
              tiketAntrean: {
                select: {
                  nomorUrut: true,
                  loket: { select: { kode: true } },
                },
              },
            },
            orderBy: [{ terjadiPada: 'desc' }, { id: 'desc' }],
          }),
        ]);

        const nomor = (urut: number): string =>
          `${layanan.prefixAntrean.trim()}-${String(urut).padStart(3, '0')}`;

        const tiketPerLoket = new Map<string, DisplayTiketAktif[]>();
        for (const tiket of tiketAktif) {
          if (!tiket.loketId) continue;
          const daftar = tiketPerLoket.get(tiket.loketId) ?? [];
          daftar.push({
            nomorAntrean: nomor(tiket.nomorUrut),
            status: tiket.status === StatusTiket.DILAYANI ? 'DILAYANI' : 'DIPANGGIL',
            dipanggilPada: tiket.dipanggilPada?.toISOString() ?? null,
          });
          tiketPerLoket.set(tiket.loketId, daftar);
        }

        let pengumumanTerakhir: DisplayPengumuman | null = null;
        if (panggilan && panggilan.tiketAntrean.loket) {
          const nomorAntrean = nomor(panggilan.tiketAntrean.nomorUrut);
          const kodeLoket = panggilan.tiketAntrean.loket.kode;
          pengumumanTerakhir = {
            peristiwaId: panggilan.id,
            aksi: panggilan.tipe === 'RECALL' ? 'RECALL' : 'CALL',
            terjadiPada: panggilan.terjadiPada.toISOString(),
            nomorAntrean,
            kodeLoket,
            teks: `Nomor antrean ${nomorAntrean}, silakan menuju loket ${kodeLoket}.`,
            bahasa: 'id-ID',
          };
        }

        return {
          versiSkema: 1 as const,
          tanggalPelayanan: tanggal.tanggal,
          layanan: { kode: layanan.kode, nama: layanan.nama },
          totalMenunggu,
          loket: loketAktif.map(({ id, kode, nama }) => ({
            kode,
            nama,
            tiketAktif: tiketPerLoket.get(id) ?? [],
          })),
          pengumumanTerakhir,
        };
      },
      { isolationLevel: Prisma.TransactionIsolationLevel.RepeatableRead },
    );

    return { ...data, diperolehPada: new Date().toISOString() };
  }

  private tanggalPelayanan(sekarang: Date): { tanggal: string; tanggalDb: Date } {
    const zonaWaktu = process.env.SERVICE_TIME_ZONE ?? 'Asia/Jakarta';
    const bagian = new Intl.DateTimeFormat('en-GB', {
      timeZone: zonaWaktu,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
    }).formatToParts(sekarang);
    const ambil = (jenis: string): string =>
      bagian.find((item) => item.type === jenis)?.value ?? '';
    const tanggal = `${ambil('year')}-${ambil('month')}-${ambil('day')}`;
    return { tanggal, tanggalDb: new Date(`${tanggal}T00:00:00.000Z`) };
  }
}
