import { ForbiddenException, Injectable } from '@nestjs/common';
import { ModeReservasi, Prisma, StatusTiket } from '../generated/prisma/client';
import {
  PILIH_JANJI_TEMU_HOSPITAL,
  waktuPelayanan,
} from '../hospital/hospital-context';
import { PrismaService } from '../prisma/prisma.service';
import { urutkanKandidatHospital } from '../queue/hospital-queue-selector';

const ruang = { id: true, kode: true, nama: true, lokasi: true } as const;
const poli = { id: true, kode: true, nama: true } as const;
const sesiSelect = {
  id: true,
  tanggal: true,
  mulaiPada: true,
  selesaiPada: true,
  aktif: true,
  loket: { select: ruang },
  dokterLayanan: { select: { layanan: { select: poli } } },
} as const;
const sesiAktif = {
  aktif: true,
  loket: { aktif: true, layanan: { aktif: true } },
  dokterLayanan: {
    aktif: true,
    layanan: { aktif: true },
    dokter: { aktif: true },
  },
} satisfies Prisma.JadwalPraktikWhereInput;

@Injectable()
export class PortalDokterService {
  constructor(private readonly prisma: PrismaService) {}
  async identitas(penggunaId: string) {
    const dokter = await this.prisma.dokter.findFirst({
      where: {
        penggunaId,
        aktif: true,
        pengguna: { aktif: true, peran: 'DOKTER' },
      },
      select: {
        id: true,
        kode: true,
        nama: true,
        spesialisasi: true,
        aktif: true,
        dokterLayanan: {
          where: { aktif: true, layanan: { aktif: true } },
          select: { layanan: { select: poli } },
        },
      },
    });
    if (!dokter)
      throw new ForbiddenException('Akun tidak memiliki profil dokter aktif');
    return dokter;
  }
  async profil(penggunaId: string) {
    const d = await this.identitas(penggunaId);
    return {
      id: d.id,
      kode: d.kode,
      nama: d.nama,
      spesialisasi: d.spesialisasi,
      aktif: d.aktif,
      poliklinik: d.dokterLayanan.map((r) => r.layanan),
    };
  }
  async jadwal(
    penggunaId: string,
    tanggal = waktuPelayanan(new Date()).tanggal,
  ) {
    const d = await this.identitas(penggunaId);
    const data = await this.prisma.jadwalPraktik.findMany({
      where: { tanggal: new Date(tanggal), dokterLayanan: { dokterId: d.id } },
      select: sesiSelect,
      orderBy: [{ mulaiPada: 'asc' }, { id: 'asc' }],
    });
    return data.map((s) => ({
      id: s.id,
      tanggal: s.tanggal,
      mulaiPada: s.mulaiPada,
      selesaiPada: s.selesaiPada,
      aktif: s.aktif,
      ruang: s.loket,
      poliklinik: s.dokterLayanan.layanan,
    }));
  }
  async janjiTemu(
    penggunaId: string,
    tanggal = waktuPelayanan(new Date()).tanggal,
  ) {
    const d = await this.identitas(penggunaId);
    const data = await this.prisma.janjiTemu.findMany({
      where: {
        slotPraktik: { jadwalPraktik: { dokterLayanan: { dokterId: d.id } } },
        tiket: { tanggalAntrean: new Date(tanggal) },
      },
      select: {
        slotPraktik: {
          select: {
            mulaiPada: true,
            selesaiPada: true,
            jadwalPraktik: { select: sesiSelect },
          },
        },
        tiket: {
          select: {
            nomorUrut: true,
            status: true,
            tanggalAntrean: true,
            layanan: { select: { prefixAntrean: true } },
          },
        },
      },
      orderBy: [{ slotPraktik: { mulaiPada: 'asc' } }, { id: 'asc' }],
    });
    return data.map((a) => ({
      nomorAntrean: this.nomor(
        a.tiket.layanan.prefixAntrean,
        a.tiket.nomorUrut,
      ),
      tanggalPelayanan: a.tiket.tanggalAntrean,
      mulaiPada: a.slotPraktik.mulaiPada,
      selesaiPada: a.slotPraktik.selesaiPada,
      status: a.tiket.status,
      poliklinik: a.slotPraktik.jadwalPraktik.dokterLayanan.layanan,
      ruang: a.slotPraktik.jadwalPraktik.loket,
      jadwalPraktikId: a.slotPraktik.jadwalPraktik.id,
    }));
  }
  /** Only current active own session grants live room visibility. No arbitrary loketId. */
  async snapshot(penggunaId: string, jadwalPraktikId: string) {
    const d = await this.identitas(penggunaId),
      now = new Date(),
      today = waktuPelayanan(now);
    return this.prisma.$transaction(
      async (tx) => {
        const s = await tx.jadwalPraktik.findFirst({
          where: {
            ...sesiAktif,
            id: jadwalPraktikId,
            tanggal: today.tanggalDb,
            mulaiPada: { lte: now },
            selesaiPada: { gt: now },
            dokterLayanan: { ...sesiAktif.dokterLayanan, dokterId: d.id },
          },
          select: {
            ...sesiSelect,
            loketId: true,
            dokterLayanan: {
              select: {
                layananId: true,
                layanan: {
                  select: { ...poli, modeReservasi: true, prefixAntrean: true },
                },
              },
            },
          },
        });
        if (!s)
          throw new ForbiddenException(
            'Sesi/ruang bukan kewenangan dokter atau tidak aktif saat ini',
          );
        const layanan = s.dokterLayanan.layanan;
        const tickets = await tx.tiketAntrean.findMany({
          where: {
            layananId: s.dokterLayanan.layananId,
            tanggalAntrean: today.tanggalDb,
            status: {
              in: [
                StatusTiket.MENUNGGU,
                StatusTiket.DIPANGGIL,
                StatusTiket.DILAYANI,
              ],
            },
            OR: [
              {
                loketId: s.loketId,
                janjiTemu: { slotPraktik: { jadwalPraktikId: s.id } },
              },
              ...(layanan.modeReservasi === ModeReservasi.HIBRIDA
                ? [{ loketId: s.loketId, janjiTemu: { is: null } }]
                : layanan.modeReservasi === ModeReservasi.ANTREAN_HARIAN
                  ? [
                      {
                        janjiTemu: { is: null },
                        // Daily waiting is shared across the clinic; CALL assigns its room.
                        // Active tickets remain visible only in the authorized session room.
                        OR: [
                          { status: StatusTiket.MENUNGGU },
                          { loketId: s.loketId },
                        ],
                      },
                    ]
                  : []),
            ],
          },
          select: {
            id: true,
            nomorUrut: true,
            status: true,
            urutanMasukAntrean: true,
            checkInPada: true,
            tanggalAntrean: true,
            layananId: true,
            dipanggilPada: true,
            peristiwaAntrean: {
              where: { tipe: 'REQUEUE' },
              orderBy: { terjadiPada: 'desc' },
              take: 1,
              select: { terjadiPada: true },
            },
            janjiTemu: PILIH_JANJI_TEMU_HOSPITAL,
          },
          orderBy: [{ urutanMasukAntrean: 'asc' }, { id: 'asc' }],
        });
        const waiting = tickets.filter(
          (t) =>
            t.status === StatusTiket.MENUNGGU && t.urutanMasukAntrean !== null,
        );
        const ordered =
          layanan.modeReservasi === ModeReservasi.ANTREAN_HARIAN
            ? // Already ordered by queue entry sequence + id, exactly like daily CALL.
              // Hospital slot/check-in ranking must not replace daily FIFO.
              waiting.map((tiket) => ({
                tiket,
                jenisAntrean: 'WALK_IN' as const,
                layakDipanggil: true,
              }))
            : urutkanKandidatHospital(
                waiting,
                layanan.modeReservasi,
                s.loketId,
                now,
                layanan.modeReservasi === ModeReservasi.HIBRIDA,
              );
        return {
          versiSkema: 1,
          diperolehPada: now.toISOString(),
          tanggalPelayanan: today.tanggal,
          sesi: {
            id: s.id,
            mulaiPada: s.mulaiPada,
            selesaiPada: s.selesaiPada,
          },
          ruang: s.loket,
          poliklinik: {
            id: layanan.id,
            kode: layanan.kode,
            nama: layanan.nama,
          },
          totalMenunggu: waiting.length,
          menunggu: ordered.slice(0, 100).map((k) => ({
            nomorAntrean: this.nomor(layanan.prefixAntrean, k.tiket.nomorUrut),
            status: k.tiket.status,
            jenisAntrean: k.jenisAntrean,
            layakDipanggil: k.layakDipanggil,
          })),
          aktif: tickets
            .filter((t) => t.status !== StatusTiket.MENUNGGU)
            .map((t) => ({
              nomorAntrean: this.nomor(layanan.prefixAntrean, t.nomorUrut),
              status: t.status,
            })),
        };
      },
      { isolationLevel: Prisma.TransactionIsolationLevel.RepeatableRead },
    );
  }
  private nomor(prefix: string, urut: number) {
    return `${prefix.trim()}-${String(urut).padStart(3, '0')}`;
  }
}
