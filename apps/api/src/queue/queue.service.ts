import {
  ConflictException,
  ForbiddenException,
  Injectable,
  Logger,
  NotFoundException,
} from '@nestjs/common';

import {
  HariLayanan,
  PeranPengguna,
  Prisma,
  StatusTiket,
} from '../generated/prisma/client';

import { PrismaService } from '../prisma/prisma.service';
import { RealtimeBroadcastService } from '../realtime/realtime-broadcast.service';
import type { JenisPerubahanAntrean } from '../realtime/realtime-events.types';
import type { SnapshotAntrean, SnapshotTiketAktif } from './queue-snapshot.types';

import {
  AKSI_ANTREAN,
  bolehTransisiAntrean,
  jalankanTransisiAntrean,
} from './queue-state-machine';

const NAMA_HARI: HariLayanan[] = [
  HariLayanan.MINGGU,
  HariLayanan.SENIN,
  HariLayanan.SELASA,
  HariLayanan.RABU,
  HariLayanan.KAMIS,
  HariLayanan.JUMAT,
  HariLayanan.SABTU,
];

interface KonteksTanggal {
  tanggal: string;
  tanggalDb: Date;
  hari: HariLayanan;
}

@Injectable()
export class QueueService {
  private readonly logger = new Logger(QueueService.name);

  // Parameter kedua opsional pada level TypeScript agar Unit Test lama yang
  // menginstansiasi QueueService secara langsung tetap kompatibel.
  // Pada runtime NestJS, RealtimeBroadcastService wajib tersedia dari QueueModule.
  constructor(
    private readonly prisma: PrismaService,
    private readonly realtime?: RealtimeBroadcastService,
  ) {}

  /** Best effort: kegagalan Socket.IO tidak membatalkan transaksi yang sudah commit. */
  private async kirimSetelahCommit(
    hasil: {
      tiketId: string;
      layananId: string;
      nomorAntrean: string;
      status: StatusTiket;
      loketId?: string | null;
      kodeLoket?: string;
      urutanMasukAntrean?: number | null;
      versi?: number;
    },
    aksi: JenisPerubahanAntrean,
    loketId?: string,
  ): Promise<void> {
    if (!this.realtime) return;
    try {
      await this.realtime.kirim({
        aksi,
        layananId: hasil.layananId,
        tiketId: hasil.tiketId,
        nomorAntrean: hasil.nomorAntrean,
        status: hasil.status,
        loketId: hasil.loketId ?? loketId ?? null,
        ...(hasil.kodeLoket ? { kodeLoket: hasil.kodeLoket } : {}),
        ...(hasil.urutanMasukAntrean !== undefined
          ? { urutanMasukAntrean: hasil.urutanMasukAntrean }
          : {}),
        ...(hasil.versi !== undefined ? { versi: hasil.versi } : {}),
      });
    } catch {
      this.logger.warn(`Broadcast ${aksi} gagal; perubahan database tetap tersimpan`);
    }
  }

  // ==========================================
  // CHECK_IN -> MENUNGGU
  // ==========================================

  async masukAntrean(tiketId: string, petugasId: string, loketId: string) {
    const maksimalPercobaan = 3;

    for (let percobaan = 1; percobaan <= maksimalPercobaan; percobaan++) {
      const sekarang = new Date();
      const tanggalLokal = this.dapatkanTanggalPelayanan(sekarang);

      try {
        const hasil = await this.prisma.$transaction(
          async (tx) => {
            // 1. Validasi identitas PETUGAS.
            const petugas = await tx.pengguna.findUnique({
              where: {
                id: petugasId,
              },
              select: {
                id: true,
                peran: true,
                aktif: true,
              },
            });

            if (
              !petugas ||
              !petugas.aktif ||
              petugas.peran !== PeranPengguna.PETUGAS
            ) {
              throw new ForbiddenException('Pengguna bukan PETUGAS aktif');
            }

            // 2. Ambil tiket beserta layanan.
            const tiket = await tx.tiketAntrean.findUnique({
              where: {
                id: tiketId,
              },
              select: {
                id: true,
                layananId: true,
                tanggalAntrean: true,
                nomorUrut: true,
                status: true,
                versi: true,
                checkInPada: true,
                urutanMasukAntrean: true,
                layanan: {
                  select: {
                    aktif: true,
                    prefixAntrean: true,
                  },
                },
              },
            });

            if (!tiket) {
              throw new NotFoundException('Tiket antrean tidak ditemukan');
            }

            // 3. Validasi State Machine.
            if (
              !bolehTransisiAntrean(tiket.status, AKSI_ANTREAN.MASUK_ANTREAN)
            ) {
              throw new ConflictException(
                `Tiket berstatus ${tiket.status} ` +
                  'tidak dapat masuk antrean',
              );
            }

            if (!tiket.checkInPada) {
              throw new ConflictException(
                'Tiket belum memiliki waktu check-in',
              );
            }

            if (tiket.urutanMasukAntrean !== null) {
              throw new ConflictException(
                'Tiket sudah memiliki urutan antrean',
              );
            }

            if (!tiket.layanan.aktif) {
              throw new ConflictException('Layanan tidak aktif');
            }

            // 4. Pastikan tanggal pelayanan
            // sama dengan tanggal hari ini.
            const tanggalTiket = tiket.tanggalAntrean
              .toISOString()
              .slice(0, 10);

            if (tanggalTiket !== tanggalLokal.tanggal) {
              throw new ConflictException(
                'Tanggal tiket tidak sesuai dengan hari pelayanan',
              );
            }

            // 5. Validasi penugasan PETUGAS
            // pada loket layanan yang sama.
            const penugasan = await tx.penugasanPetugas.findFirst({
              where: {
                petugasId,
                loketId,
                aktif: true,
                tanggalMulai: {
                  lte: tanggalLokal.tanggalDb,
                },
                OR: [
                  {
                    tanggalSelesai: null,
                  },
                  {
                    tanggalSelesai: {
                      gte: tanggalLokal.tanggalDb,
                    },
                  },
                ],
              },
              select: {
                id: true,
                loket: {
                  select: {
                    aktif: true,
                    layananId: true,
                    layanan: {
                      select: {
                        aktif: true,
                      },
                    },
                  },
                },
              },
            });

            if (
              !penugasan ||
              !penugasan.loket.aktif ||
              !penugasan.loket.layanan.aktif ||
              penugasan.loket.layananId !== tiket.layananId
            ) {
              throw new ForbiddenException(
                'Petugas tidak memiliki penugasan aktif pada loket layanan ini',
              );
            }

            // 6. Pastikan jadwal hari
            // pelayanan masih aktif.
            const jadwal = await tx.jadwalLayanan.findUnique({
              where: {
                layananId_hari: {
                  layananId: tiket.layananId,
                  hari: tanggalLokal.hari,
                },
              },
              select: {
                aktif: true,
              },
            });

            if (!jadwal?.aktif) {
              throw new ConflictException(
                'Jadwal layanan hari ini tidak aktif',
              );
            }

            // 7. Ambil counter harian yang
            // sudah dibuat saat reservasi.
            const kunciCounter = {
              layananId_tanggal: {
                layananId: tiket.layananId,
                tanggal: tiket.tanggalAntrean,
              },
            };

            const counterAda = await tx.urutanAntreanHarian.findUnique({
              where: kunciCounter,
              select: {
                id: true,
              },
            });

            if (!counterAda) {
              throw new ConflictException(
                'Counter antrean harian belum tersedia',
              );
            }

            // Increment atomik dalam transaksi.
            const counter = await tx.urutanAntreanHarian.update({
              where: kunciCounter,
              data: {
                urutanMasukTerakhir: {
                  increment: 1,
                },
              },
              select: {
                urutanMasukTerakhir: true,
              },
            });

            const transisi = jalankanTransisiAntrean(
              tiket.status,
              AKSI_ANTREAN.MASUK_ANTREAN,
            );

            // 8. Update bersyarat.
            const perubahan = await tx.tiketAntrean.updateMany({
              where: {
                id: tiket.id,
                versi: tiket.versi,
                status: StatusTiket.CHECK_IN,
                checkInPada: {
                  not: null,
                },
                urutanMasukAntrean: null,
              },
              data: {
                status: transisi.statusSesudah,
                urutanMasukAntrean: counter.urutanMasukTerakhir,
                masukAntreanPada: sekarang,
                versi: {
                  increment: 1,
                },
              },
            });

            if (perubahan.count !== 1) {
              throw new ConflictException(
                'Tiket sudah diproses oleh request lain',
              );
            }

            // 9. Audit status dalam transaksi sama.
            await tx.peristiwaAntrean.create({
              data: {
                tiketAntreanId: tiket.id,
                aktorId: petugasId,
                tipe: transisi.tipePeristiwa,
                statusSebelum: transisi.statusSebelum,
                statusSesudah: transisi.statusSesudah,
                dataTambahan: {
                  metode: 'QUEUE_ENQUEUE',
                  loketId,
                  penugasanId: penugasan.id,
                  urutanMasukAntrean: counter.urutanMasukTerakhir,
                },
              },
            });

            // 10. Kembalikan hasil.
            return {
              tiketId: tiket.id,
              layananId: tiket.layananId,
              nomorAntrean:
                `${tiket.layanan.prefixAntrean.trim()}-` +
                String(tiket.nomorUrut).padStart(3, '0'),
              status: transisi.statusSesudah,
              urutanMasukAntrean: counter.urutanMasukTerakhir,
              masukAntreanPada: sekarang.toISOString(),
            };
          },
          {
            isolationLevel: Prisma.TransactionIsolationLevel.Serializable,
            maxWait: 10000,
            timeout: 15000,
          },
        );
        await this.kirimSetelahCommit(hasil, 'ENQUEUE', loketId);
        return hasil;
      } catch (error: unknown) {
        // Retry hanya untuk konflik
        // serialisasi PostgreSQL.
        if (
          error instanceof Prisma.PrismaClientKnownRequestError &&
          error.code === 'P2034'
        ) {
          if (percobaan < maksimalPercobaan) {
            continue;
          }

          throw new ConflictException(
            'Antrean sedang diproses, silakan coba kembali',
          );
        }

        throw error;
      }
    }

    throw new ConflictException(
      'Operasi antrean gagal setelah beberapa percobaan',
    );
  }

  // ==========================================
  // MEMBACA ANTREAN MENUNGGU (FIFO)
  // ==========================================

  async daftarMenunggu(petugasId: string, loketId: string) {
    const sekarang = new Date();

    const tanggalLokal = this.dapatkanTanggalPelayanan(sekarang);

    // 1. Pastikan pemanggil adalah PETUGAS aktif.
    const petugas = await this.prisma.pengguna.findUnique({
      where: {
        id: petugasId,
      },
      select: {
        id: true,
        peran: true,
        aktif: true,
      },
    });

    if (!petugas || !petugas.aktif || petugas.peran !== PeranPengguna.PETUGAS) {
      throw new ForbiddenException('Pengguna bukan PETUGAS aktif');
    }

    // 2. Pastikan petugas memiliki penugasan
    // aktif pada loket dan tanggal saat ini.
    const penugasan = await this.prisma.penugasanPetugas.findFirst({
      where: {
        petugasId,
        loketId,
        aktif: true,
        tanggalMulai: {
          lte: tanggalLokal.tanggalDb,
        },
        OR: [
          {
            tanggalSelesai: null,
          },
          {
            tanggalSelesai: {
              gte: tanggalLokal.tanggalDb,
            },
          },
        ],
      },
      select: {
        loket: {
          select: {
            aktif: true,
            layananId: true,
            layanan: {
              select: {
                aktif: true,
              },
            },
          },
        },
      },
    });

    if (
      !penugasan ||
      !penugasan.loket.aktif ||
      !penugasan.loket.layanan.aktif
    ) {
      throw new ForbiddenException(
        'Petugas tidak memiliki penugasan aktif pada loket layanan ini',
      );
    }

    // 3. Ambil antrean berdasarkan layanan,
    // bukan berdasarkan loket check-in.
    const tiketMenunggu = await this.prisma.tiketAntrean.findMany({
      where: {
        layananId: penugasan.loket.layananId,
        tanggalAntrean: tanggalLokal.tanggalDb,
        status: StatusTiket.MENUNGGU,
        urutanMasukAntrean: {
          not: null,
        },
      },
      select: {
        id: true,
        nomorUrut: true,
        status: true,
        urutanMasukAntrean: true,
        masukAntreanPada: true,
        layanan: {
          select: {
            prefixAntrean: true,
          },
        },
      },
      orderBy: [
        {
          urutanMasukAntrean: 'asc',
        },
        {
          id: 'asc',
        },
      ],
      take: 100,
    });

    // 4. Format hasil untuk konsumsi API.
    return tiketMenunggu.map((tiket) => ({
      tiketId: tiket.id,
      nomorAntrean:
        `${tiket.layanan.prefixAntrean.trim()}-` +
        String(tiket.nomorUrut).padStart(3, '0'),
      status: tiket.status,
      urutanMasukAntrean: tiket.urutanMasukAntrean,
      masukAntreanPada: tiket.masukAntreanPada?.toISOString() ?? null,
    }));
  }

  // ==========================================
  // SNAPSHOT ANTREAN OPERASIONAL (MVP)
  // ==========================================

  /**
   * Sumber data sinkronisasi dashboard sesudah join room / reconnect.
   * Hanya PETUGAS yang aktif dan masih ditugaskan pada loket ini.
   * Query menunggu, total, dan tiket aktif dibaca dari satu snapshot DB.
   */
  async snapshotAntrean(petugasId: string, loketId: string): Promise<SnapshotAntrean> {
    const tanggal = this.dapatkanTanggalPelayanan(new Date());

    const snapshot = await this.prisma.$transaction(
      async (tx) => {
        const petugas = await tx.pengguna.findUnique({
          where: { id: petugasId },
          select: { id: true, aktif: true, peran: true },
        });

        if (
          !petugas ||
          !petugas.aktif ||
          petugas.peran !== PeranPengguna.PETUGAS
        ) {
          throw new ForbiddenException('Pengguna bukan PETUGAS aktif');
        }

        const penugasan = await tx.penugasanPetugas.findFirst({
          where: {
            petugasId,
            loketId,
            aktif: true,
            tanggalMulai: { lte: tanggal.tanggalDb },
            OR: [
              { tanggalSelesai: null },
              { tanggalSelesai: { gte: tanggal.tanggalDb } },
            ],
            loket: {
              aktif: true,
              layanan: { aktif: true },
            },
          },
          select: {
            loket: {
              select: {
                id: true,
                kode: true,
                nama: true,
                layananId: true,
                layanan: {
                  select: {
                    id: true,
                    kode: true,
                    nama: true,
                    prefixAntrean: true,
                  },
                },
              },
            },
          },
        });

        if (!penugasan) {
          throw new ForbiddenException(
            'Petugas tidak memiliki penugasan aktif pada loket layanan ini',
          );
        }

        const layanan = penugasan.loket.layanan;
        const layananId = penugasan.loket.layananId;
        const whereHariIni = {
          layananId,
          tanggalAntrean: tanggal.tanggalDb,
        };

        const [loketLayanan, tiketMenunggu, totalMenunggu, tiketAktif] =
          await Promise.all([
            tx.loket.findMany({
              where: { layananId, aktif: true },
              select: { id: true, kode: true, nama: true },
              orderBy: [{ kode: 'asc' }, { id: 'asc' }],
            }),
            tx.tiketAntrean.findMany({
              where: {
                ...whereHariIni,
                status: StatusTiket.MENUNGGU,
                urutanMasukAntrean: { not: null },
              },
              select: {
                id: true,
                nomorUrut: true,
                status: true,
                versi: true,
                urutanMasukAntrean: true,
                masukAntreanPada: true,
              },
              orderBy: [
                { urutanMasukAntrean: 'asc' },
                { id: 'asc' },
              ],
              take: 100,
            }),
            tx.tiketAntrean.count({
              where: {
                ...whereHariIni,
                status: StatusTiket.MENUNGGU,
                urutanMasukAntrean: { not: null },
              },
            }),
            tx.tiketAntrean.findMany({
              where: {
                ...whereHariIni,
                status: {
                  in: [StatusTiket.DIPANGGIL, StatusTiket.DILAYANI],
                },
                loketId: { not: null },
              },
              select: {
                id: true,
                loketId: true,
                nomorUrut: true,
                status: true,
                versi: true,
                urutanMasukAntrean: true,
                dipanggilPada: true,
                pelayananDimulaiPada: true,
              },
              orderBy: [{ dipanggilPada: 'asc' }, { id: 'asc' }],
            }),
          ]);

        const nomorAntrean = (nomorUrut: number): string =>
          `${layanan.prefixAntrean.trim()}-${String(nomorUrut).padStart(3, '0')}`;

        const aktifPerLoket = new Map<string, SnapshotTiketAktif[]>();
        for (const tiket of tiketAktif) {
          if (!tiket.loketId) continue;
          const daftar = aktifPerLoket.get(tiket.loketId) ?? [];
          daftar.push({
            tiketId: tiket.id,
            nomorAntrean: nomorAntrean(tiket.nomorUrut),
            status:
              tiket.status === StatusTiket.DILAYANI
                ? StatusTiket.DILAYANI
                : StatusTiket.DIPANGGIL,
            urutanMasukAntrean: tiket.urutanMasukAntrean,
            versi: tiket.versi,
            dipanggilPada: tiket.dipanggilPada?.toISOString() ?? null,
            pelayananDimulaiPada:
              tiket.pelayananDimulaiPada?.toISOString() ?? null,
          });
          aktifPerLoket.set(tiket.loketId, daftar);
        }

        return {
          versiSkema: 1 as const,
          tanggalPelayanan: tanggal.tanggal,
          layanan: { id: layanan.id, kode: layanan.kode, nama: layanan.nama },
          loketPeminta: {
            id: penugasan.loket.id,
            kode: penugasan.loket.kode,
            nama: penugasan.loket.nama,
          },
          menunggu: {
            total: totalMenunggu,
            ditampilkan: tiketMenunggu.length,
            tiket: tiketMenunggu.map((tiket) => ({
              tiketId: tiket.id,
              nomorAntrean: nomorAntrean(tiket.nomorUrut),
              status: StatusTiket.MENUNGGU,
              urutanMasukAntrean: tiket.urutanMasukAntrean,
              masukAntreanPada:
                tiket.masukAntreanPada?.toISOString() ?? null,
              versi: tiket.versi,
            })),
          },
          loket: loketLayanan.map((loket) => ({
            ...loket,
            tiketAktif: aktifPerLoket.get(loket.id) ?? [],
          })),
        };
      },
      { isolationLevel: Prisma.TransactionIsolationLevel.RepeatableRead },
    );

    return { ...snapshot, diperolehPada: new Date().toISOString() };
  }

  // ==========================================
  // PANGGIL TIKET BERIKUTNYA BERDASARKAN FIFO
  // ==========================================

  async panggilBerikutnya(petugasId: string, loketId: string) {
    const maksimalPercobaan = 3;

    for (let percobaan = 1; percobaan <= maksimalPercobaan; percobaan++) {
      const sekarang = new Date();
      const konteks = this.dapatkanTanggalPelayanan(sekarang);

      try {
        const hasil = await this.prisma.$transaction(
          async (tx) => {
            // 1. Validasi identitas PETUGAS.
            const petugas = await tx.pengguna.findUnique({
              where: {
                id: petugasId,
              },
              select: {
                id: true,
                peran: true,
                aktif: true,
              },
            });

            if (
              !petugas ||
              !petugas.aktif ||
              petugas.peran !== PeranPengguna.PETUGAS
            ) {
              throw new ForbiddenException('Pengguna bukan PETUGAS aktif');
            }

            // 2. Validasi penugasan pada loket.
            const penugasan = await tx.penugasanPetugas.findFirst({
              where: {
                petugasId,
                loketId,
                aktif: true,
                tanggalMulai: {
                  lte: konteks.tanggalDb,
                },
                OR: [
                  {
                    tanggalSelesai: null,
                  },
                  {
                    tanggalSelesai: {
                      gte: konteks.tanggalDb,
                    },
                  },
                ],
              },
              select: {
                id: true,
                loket: {
                  select: {
                    id: true,
                    kode: true,
                    aktif: true,
                    layananId: true,
                    layanan: {
                      select: {
                        aktif: true,
                        prefixAntrean: true,
                      },
                    },
                  },
                },
              },
            });

            if (
              !penugasan ||
              !penugasan.loket.aktif ||
              !penugasan.loket.layanan.aktif
            ) {
              throw new ForbiddenException(
                'Petugas tidak memiliki penugasan aktif pada loket ini',
              );
            }

            const layananId = penugasan.loket.layananId;

            // 3. Validasi jadwal layanan.
            const jadwal = await tx.jadwalLayanan.findUnique({
              where: {
                layananId_hari: {
                  layananId,
                  hari: konteks.hari,
                },
              },
              select: {
                aktif: true,
              },
            });

            if (!jadwal?.aktif) {
              throw new ConflictException(
                'Jadwal layanan hari ini tidak aktif',
              );
            }

            // 4. Satu loket hanya boleh memiliki
            // satu tiket DIPANGGIL atau DILAYANI.
            const tiketAktif = await tx.tiketAntrean.findFirst({
              where: {
                loketId,
                tanggalAntrean: konteks.tanggalDb,
                status: {
                  in: [StatusTiket.DIPANGGIL, StatusTiket.DILAYANI],
                },
              },
              select: {
                id: true,
              },
            });

            if (tiketAktif) {
              throw new ConflictException(
                'Loket masih memiliki tiket yang sedang dipanggil atau dilayani',
              );
            }

            // 5. Pilih antrean MENUNGGU
            // dengan urutan FIFO terkecil.
            const tiket = await tx.tiketAntrean.findFirst({
              where: {
                layananId,
                tanggalAntrean: konteks.tanggalDb,
                status: StatusTiket.MENUNGGU,
                urutanMasukAntrean: {
                  not: null,
                },
              },
              orderBy: [
                {
                  urutanMasukAntrean: 'asc',
                },
                {
                  id: 'asc',
                },
              ],
              select: {
                id: true,
                nomorUrut: true,
                status: true,
                versi: true,
                loketId: true,
                urutanMasukAntrean: true,
              },
            });

            if (!tiket) {
              throw new NotFoundException(
                'Tidak ada tiket MENUNGGU pada layanan ini',
              );
            }

            // 6. Validasi Queue State Machine.
            const transisi = jalankanTransisiAntrean(
              tiket.status,
              AKSI_ANTREAN.PANGGIL,
            );

            // 7. Claim tiket secara atomik.
            const perubahan = await tx.tiketAntrean.updateMany({
              where: {
                id: tiket.id,
                layananId,
                tanggalAntrean: konteks.tanggalDb,
                status: StatusTiket.MENUNGGU,
                versi: tiket.versi,
                urutanMasukAntrean: tiket.urutanMasukAntrean,
              },
              data: {
                status: transisi.statusSesudah,
                loketId,
                dipanggilPada: sekarang,
                versi: {
                  increment: 1,
                },
              },
            });

            if (perubahan.count !== 1) {
              throw new ConflictException(
                'Tiket sedang diproses oleh petugas lain',
              );
            }

            // 8. Catat audit dalam transaksi
            // yang sama dengan perubahan tiket.
            await tx.peristiwaAntrean.create({
              data: {
                tiketAntreanId: tiket.id,
                aktorId: petugasId,
                tipe: transisi.tipePeristiwa,
                statusSebelum: transisi.statusSebelum,
                statusSesudah: transisi.statusSesudah,
                dataTambahan: {
                  metode: 'QUEUE_CALL',
                  loketId,
                  kodeLoket: penugasan.loket.kode,
                  penugasanId: penugasan.id,
                  loketSebelumnya: tiket.loketId,
                  urutanMasukAntrean: tiket.urutanMasukAntrean,
                },
              },
            });

            // 9. Kembalikan tiket yang dipanggil.
            return {
              tiketId: tiket.id,
              layananId,
              loketId,
              kodeLoket: penugasan.loket.kode,
              nomorAntrean:
                `${penugasan.loket.layanan.prefixAntrean.trim()}-` +
                String(tiket.nomorUrut).padStart(3, '0'),
              status: transisi.statusSesudah,
              urutanMasukAntrean: tiket.urutanMasukAntrean,
              dipanggilPada: sekarang.toISOString(),
              versi: tiket.versi + 1,
            };
          },
          {
            isolationLevel: Prisma.TransactionIsolationLevel.Serializable,
            maxWait: 10000,
            timeout: 15000,
          },
        );
        await this.kirimSetelahCommit(hasil, 'CALL');
        return hasil;
      } catch (error: unknown) {
        // 10. Retry hanya ketika terjadi
        // konflik serialisasi PostgreSQL.
        if (
          error instanceof Prisma.PrismaClientKnownRequestError &&
          error.code === 'P2034'
        ) {
          if (percobaan < maksimalPercobaan) {
            continue;
          }

          throw new ConflictException(
            'Antrean sedang dipanggil petugas lain, silakan coba kembali',
          );
        }

        throw error;
      }
    }

    throw new ConflictException(
      'Pemanggilan antrean gagal setelah beberapa percobaan',
    );
  }

  // ==========================================
  // PANGGIL ULANG TIKET YANG SEDANG DIPANGGIL
  // ==========================================

  async panggilUlang(tiketId: string, petugasId: string, loketId: string) {
    const maksimalPercobaan = 3;

    for (let percobaan = 1; percobaan <= maksimalPercobaan; percobaan++) {
      const sekarang = new Date();
      const konteks = this.dapatkanTanggalPelayanan(sekarang);

      try {
        const hasil = await this.prisma.$transaction(
          async (tx) => {
            // 1. Hanya PETUGAS aktif yang boleh melakukan RECALL.
            const petugas = await tx.pengguna.findUnique({
              where: { id: petugasId },
              select: { id: true, peran: true, aktif: true },
            });

            if (
              !petugas ||
              !petugas.aktif ||
              petugas.peran !== PeranPengguna.PETUGAS
            ) {
              throw new ForbiddenException('Pengguna bukan PETUGAS aktif');
            }

            // 2. Tiket harus ada, DIPANGGIL, dan milik loket yang sama.
            const tiket = await tx.tiketAntrean.findUnique({
              where: { id: tiketId },
              select: {
                id: true,
                layananId: true,
                tanggalAntrean: true,
                loketId: true,
                nomorUrut: true,
                status: true,
                versi: true,
                urutanMasukAntrean: true,
                dipanggilPada: true,
                layanan: {
                  select: { aktif: true, prefixAntrean: true },
                },
              },
            });

            if (!tiket) {
              throw new NotFoundException('Tiket antrean tidak ditemukan');
            }

            if (
              !bolehTransisiAntrean(
                tiket.status,
                AKSI_ANTREAN.PANGGIL_ULANG,
              )
            ) {
              throw new ConflictException(
                `Tiket berstatus ${tiket.status} tidak dapat dipanggil ulang`,
              );
            }

            if (tiket.loketId !== loketId) {
              throw new ForbiddenException(
                'Tiket tidak sedang dipanggil pada loket petugas',
              );
            }

            if (!tiket.dipanggilPada) {
              throw new ConflictException(
                'Tiket belum mempunyai catatan pemanggilan pertama',
              );
            }

            if (
              tiket.tanggalAntrean.toISOString().slice(0, 10) !==
              konteks.tanggal
            ) {
              throw new ConflictException(
                'Tanggal tiket tidak sesuai hari pelayanan',
              );
            }

            if (!tiket.layanan.aktif) {
              throw new ConflictException('Layanan tidak aktif');
            }

            // 3. PETUGAS wajib ditugaskan pada loket dan layanan tiket.
            const penugasan = await tx.penugasanPetugas.findFirst({
              where: {
                petugasId,
                loketId,
                aktif: true,
                tanggalMulai: { lte: konteks.tanggalDb },
                OR: [
                  { tanggalSelesai: null },
                  { tanggalSelesai: { gte: konteks.tanggalDb } },
                ],
              },
              select: {
                id: true,
                loket: {
                  select: {
                    kode: true,
                    aktif: true,
                    layananId: true,
                    layanan: { select: { aktif: true } },
                  },
                },
              },
            });

            if (
              !penugasan ||
              !penugasan.loket.aktif ||
              !penugasan.loket.layanan.aktif ||
              penugasan.loket.layananId !== tiket.layananId
            ) {
              throw new ForbiddenException(
                'Petugas tidak memiliki penugasan aktif pada loket tiket ini',
              );
            }

            // 4. Kebijakan jadwal konsisten dengan CALL.
            const jadwal = await tx.jadwalLayanan.findUnique({
              where: {
                layananId_hari: {
                  layananId: tiket.layananId,
                  hari: konteks.hari,
                },
              },
              select: { aktif: true },
            });

            if (!jadwal?.aktif) {
              throw new ConflictException('Jadwal layanan hari ini tidak aktif');
            }

            // 5. Status tetap DIPANGGIL; versi dinaikkan atomik.
            // Waktu CALL pertama dipertahankan; waktu RECALL ada di audit.
            const transisi = jalankanTransisiAntrean(
              tiket.status,
              AKSI_ANTREAN.PANGGIL_ULANG,
            );

            const perubahan = await tx.tiketAntrean.updateMany({
              where: {
                id: tiket.id,
                layananId: tiket.layananId,
                loketId,
                tanggalAntrean: konteks.tanggalDb,
                status: StatusTiket.DIPANGGIL,
                versi: tiket.versi,
              },
              data: {
                status: transisi.statusSesudah,
                versi: { increment: 1 },
              },
            });

            if (perubahan.count !== 1) {
              throw new ConflictException(
                'Tiket sedang diproses oleh petugas lain',
              );
            }

            // 6. Audit RECALL disimpan di transaksi yang sama.
            await tx.peristiwaAntrean.create({
              data: {
                tiketAntreanId: tiket.id,
                aktorId: petugasId,
                tipe: 'RECALL',
                statusSebelum: transisi.statusSebelum,
                statusSesudah: transisi.statusSesudah,
                dataTambahan: {
                  metode: 'QUEUE_RECALL',
                  loketId,
                  kodeLoket: penugasan.loket.kode,
                  penugasanId: penugasan.id,
                  urutanMasukAntrean: tiket.urutanMasukAntrean,
                },
              },
            });

            return {
              tiketId: tiket.id,
              layananId: tiket.layananId,
              loketId,
              kodeLoket: penugasan.loket.kode,
              nomorAntrean:
                `${tiket.layanan.prefixAntrean.trim()}-` +
                String(tiket.nomorUrut).padStart(3, '0'),
              status: transisi.statusSesudah,
              urutanMasukAntrean: tiket.urutanMasukAntrean,
              dipanggilPada: tiket.dipanggilPada.toISOString(),
              dipanggilUlangPada: sekarang.toISOString(),
              versi: tiket.versi + 1,
            };
          },
          {
            isolationLevel: Prisma.TransactionIsolationLevel.Serializable,
            maxWait: 10000,
            timeout: 15000,
          },
        );
        await this.kirimSetelahCommit(hasil, 'RECALL');
        return hasil;
      } catch (error: unknown) {
        if (
          error instanceof Prisma.PrismaClientKnownRequestError &&
          error.code === 'P2034'
        ) {
          if (percobaan < maksimalPercobaan) {
            continue;
          }

          throw new ConflictException(
            'Pemanggilan ulang sedang diproses, silakan coba kembali',
          );
        }
        throw error;
      }
    }

    throw new ConflictException(
      'Pemanggilan ulang gagal setelah beberapa percobaan',
    );
  }

  // ==========================================
  // LEWATI TIKET YANG SEDANG DIPANGGIL (SKIP)
  // ==========================================

  async lewatiAntrean(tiketId: string, petugasId: string, loketId: string) {
    const maksimalPercobaan = 3;

    for (let percobaan = 1; percobaan <= maksimalPercobaan; percobaan++) {
      const sekarang = new Date();
      const konteks = this.dapatkanTanggalPelayanan(sekarang);

      try {
        const hasil = await this.prisma.$transaction(
          async (tx) => {
            // 1. Pastikan pemanggil adalah PETUGAS aktif.
            const petugas = await tx.pengguna.findUnique({
              where: { id: petugasId },
              select: { id: true, peran: true, aktif: true },
            });

            if (
              !petugas ||
              !petugas.aktif ||
              petugas.peran !== PeranPengguna.PETUGAS
            ) {
              throw new ForbiddenException('Pengguna bukan PETUGAS aktif');
            }

            // 2. Tiket harus DIPANGGIL pada loket yang sama.
            const tiket = await tx.tiketAntrean.findUnique({
              where: { id: tiketId },
              select: {
                id: true,
                layananId: true,
                tanggalAntrean: true,
                loketId: true,
                nomorUrut: true,
                status: true,
                versi: true,
                urutanMasukAntrean: true,
                dipanggilPada: true,
                layanan: {
                  select: { aktif: true, prefixAntrean: true },
                },
              },
            });

            if (!tiket) {
              throw new NotFoundException('Tiket antrean tidak ditemukan');
            }

            if (!bolehTransisiAntrean(tiket.status, AKSI_ANTREAN.LEWATI)) {
              throw new ConflictException(
                `Tiket berstatus ${tiket.status} tidak dapat dilewati`,
              );
            }

            if (tiket.loketId !== loketId) {
              throw new ForbiddenException(
                'Tiket tidak sedang dipanggil pada loket petugas',
              );
            }

            if (!tiket.dipanggilPada) {
              throw new ConflictException(
                'Tiket belum mempunyai catatan pemanggilan pertama',
              );
            }

            if (
              tiket.tanggalAntrean.toISOString().slice(0, 10) !==
              konteks.tanggal
            ) {
              throw new ConflictException(
                'Tanggal tiket tidak sesuai hari pelayanan',
              );
            }

            if (!tiket.layanan.aktif) {
              throw new ConflictException('Layanan tidak aktif');
            }

            // 3. PETUGAS harus mempunyai penugasan aktif pada loket tiket.
            const penugasan = await tx.penugasanPetugas.findFirst({
              where: {
                petugasId,
                loketId,
                aktif: true,
                tanggalMulai: { lte: konteks.tanggalDb },
                OR: [
                  { tanggalSelesai: null },
                  { tanggalSelesai: { gte: konteks.tanggalDb } },
                ],
              },
              select: {
                id: true,
                loket: {
                  select: {
                    kode: true,
                    aktif: true,
                    layananId: true,
                    layanan: { select: { aktif: true } },
                  },
                },
              },
            });

            if (
              !penugasan ||
              !penugasan.loket.aktif ||
              !penugasan.loket.layanan.aktif ||
              penugasan.loket.layananId !== tiket.layananId
            ) {
              throw new ForbiddenException(
                'Petugas tidak memiliki penugasan aktif pada loket tiket ini',
              );
            }

            // 4. Kebijakan jadwal sama dengan CALL dan RECALL.
            const jadwal = await tx.jadwalLayanan.findUnique({
              where: {
                layananId_hari: {
                  layananId: tiket.layananId,
                  hari: konteks.hari,
                },
              },
              select: { aktif: true },
            });

            if (!jadwal?.aktif) {
              throw new ConflictException('Jadwal layanan hari ini tidak aktif');
            }

            // 5. Status dan versi diperbarui secara atomik.
            const transisi = jalankanTransisiAntrean(
              tiket.status,
              AKSI_ANTREAN.LEWATI,
            );

            const perubahan = await tx.tiketAntrean.updateMany({
              where: {
                id: tiket.id,
                layananId: tiket.layananId,
                loketId,
                tanggalAntrean: konteks.tanggalDb,
                status: StatusTiket.DIPANGGIL,
                versi: tiket.versi,
              },
              data: {
                status: transisi.statusSesudah,
                versi: { increment: 1 },
              },
            });

            if (perubahan.count !== 1) {
              throw new ConflictException(
                'Tiket sedang diproses oleh petugas lain',
              );
            }

            // 6. Audit SKIP wajib berada pada transaksi yang sama.
            // Loket dan waktu CALL pertama tetap tersimpan pada tiket.
            await tx.peristiwaAntrean.create({
              data: {
                tiketAntreanId: tiket.id,
                aktorId: petugasId,
                tipe: transisi.tipePeristiwa,
                statusSebelum: transisi.statusSebelum,
                statusSesudah: transisi.statusSesudah,
                dataTambahan: {
                  metode: 'QUEUE_SKIP',
                  loketId,
                  kodeLoket: penugasan.loket.kode,
                  penugasanId: penugasan.id,
                  urutanMasukAntrean: tiket.urutanMasukAntrean,
                },
              },
            });

            return {
              tiketId: tiket.id,
              layananId: tiket.layananId,
              loketId,
              kodeLoket: penugasan.loket.kode,
              nomorAntrean:
                `${tiket.layanan.prefixAntrean.trim()}-` +
                String(tiket.nomorUrut).padStart(3, '0'),
              status: transisi.statusSesudah,
              urutanMasukAntrean: tiket.urutanMasukAntrean,
              dipanggilPada: tiket.dipanggilPada.toISOString(),
              dilewatiPada: sekarang.toISOString(),
              versi: tiket.versi + 1,
            };
          },
          {
            isolationLevel: Prisma.TransactionIsolationLevel.Serializable,
            maxWait: 10000,
            timeout: 15000,
          },
        );
        await this.kirimSetelahCommit(hasil, 'SKIP');
        return hasil;
      } catch (error: unknown) {
        if (
          error instanceof Prisma.PrismaClientKnownRequestError &&
          error.code === 'P2034'
        ) {
          if (percobaan < maksimalPercobaan) {
            continue;
          }

          throw new ConflictException(
            'Antrean sedang diproses, silakan coba kembali',
          );
        }

        throw error;
      }
    }

    throw new ConflictException(
      'Operasi lewati antrean gagal setelah beberapa percobaan',
    );
  }

  // ==========================================
  // KEMBALIKAN TIKET DILEWATI KE AKHIR FIFO (REQUEUE)
  // ==========================================

  async antreUlang(tiketId: string, petugasId: string, loketId: string) {
    const maksimalPercobaan = 3;

    for (let percobaan = 1; percobaan <= maksimalPercobaan; percobaan++) {
      const sekarang = new Date();
      const konteks = this.dapatkanTanggalPelayanan(sekarang);

      try {
        const hasil = await this.prisma.$transaction(
          async (tx) => {
            // 1. Hanya PETUGAS aktif yang boleh melakukan REQUEUE.
            const petugas = await tx.pengguna.findUnique({
              where: { id: petugasId },
              select: { id: true, peran: true, aktif: true },
            });

            if (
              !petugas ||
              !petugas.aktif ||
              petugas.peran !== PeranPengguna.PETUGAS
            ) {
              throw new ForbiddenException('Pengguna bukan PETUGAS aktif');
            }

            // 2. Tiket harus DILEWATI dan masih terikat pada loket asal.
            const tiket = await tx.tiketAntrean.findUnique({
              where: { id: tiketId },
              select: {
                id: true,
                layananId: true,
                tanggalAntrean: true,
                loketId: true,
                nomorUrut: true,
                status: true,
                versi: true,
                urutanMasukAntrean: true,
                dipanggilPada: true,
                layanan: {
                  select: { aktif: true, prefixAntrean: true },
                },
              },
            });

            if (!tiket) {
              throw new NotFoundException('Tiket antrean tidak ditemukan');
            }

            if (!bolehTransisiAntrean(tiket.status, AKSI_ANTREAN.ANTRE_ULANG)) {
              throw new ConflictException(
                `Tiket berstatus ${tiket.status} tidak dapat antre ulang`,
              );
            }

            if (tiket.loketId !== loketId) {
              throw new ForbiddenException(
                'Tiket tidak berasal dari loket petugas',
              );
            }

            if (!tiket.dipanggilPada || tiket.urutanMasukAntrean === null) {
              throw new ConflictException(
                'Tiket tidak memiliki riwayat pemanggilan dan urutan FIFO yang lengkap',
              );
            }

            if (
              tiket.tanggalAntrean.toISOString().slice(0, 10) !==
              konteks.tanggal
            ) {
              throw new ConflictException(
                'Tanggal tiket tidak sesuai hari pelayanan',
              );
            }

            if (!tiket.layanan.aktif) {
              throw new ConflictException('Layanan tidak aktif');
            }

            // 3. PETUGAS harus aktif bertugas pada loket asal dan layanan tiket.
            const penugasan = await tx.penugasanPetugas.findFirst({
              where: {
                petugasId,
                loketId,
                aktif: true,
                tanggalMulai: { lte: konteks.tanggalDb },
                OR: [
                  { tanggalSelesai: null },
                  { tanggalSelesai: { gte: konteks.tanggalDb } },
                ],
              },
              select: {
                id: true,
                loket: {
                  select: {
                    kode: true,
                    aktif: true,
                    layananId: true,
                    layanan: { select: { aktif: true } },
                  },
                },
              },
            });

            if (
              !penugasan ||
              !penugasan.loket.aktif ||
              !penugasan.loket.layanan.aktif ||
              penugasan.loket.layananId !== tiket.layananId
            ) {
              throw new ForbiddenException(
                'Petugas tidak memiliki penugasan aktif pada loket tiket ini',
              );
            }

            // 4. Jadwal pelayanan harus aktif, konsisten dengan CALL/SKIP.
            const jadwal = await tx.jadwalLayanan.findUnique({
              where: {
                layananId_hari: {
                  layananId: tiket.layananId,
                  hari: konteks.hari,
                },
              },
              select: { aktif: true },
            });

            if (!jadwal?.aktif) {
              throw new ConflictException('Jadwal layanan hari ini tidak aktif');
            }

            // 5. Counter FIFO unik per layanan dan tanggal; jangan buat baru.
            const kunciCounter = {
              layananId_tanggal: {
                layananId: tiket.layananId,
                tanggal: tiket.tanggalAntrean,
              },
            };

            const counterAda = await tx.urutanAntreanHarian.findUnique({
              where: kunciCounter,
              select: { id: true },
            });

            if (!counterAda) {
              throw new ConflictException(
                'Counter antrean harian belum tersedia',
              );
            }

            // Increment dan update tiket berada dalam transaksi Serializable.
            // Jika update tiket atau audit gagal, increment ikut di-rollback.
            const counter = await tx.urutanAntreanHarian.update({
              where: kunciCounter,
              data: {
                urutanMasukTerakhir: { increment: 1 },
              },
              select: { urutanMasukTerakhir: true },
            });

            // 6. Pindahkan ke urutan FIFO terbaru, pertahankan nomor tiket.
            const transisi = jalankanTransisiAntrean(
              tiket.status,
              AKSI_ANTREAN.ANTRE_ULANG,
            );

            const perubahan = await tx.tiketAntrean.updateMany({
              where: {
                id: tiket.id,
                layananId: tiket.layananId,
                tanggalAntrean: konteks.tanggalDb,
                loketId,
                status: StatusTiket.DILEWATI,
                versi: tiket.versi,
                urutanMasukAntrean: tiket.urutanMasukAntrean,
              },
              data: {
                status: transisi.statusSesudah,
                urutanMasukAntrean: counter.urutanMasukTerakhir,
                masukAntreanPada: sekarang,
                loketId: null,
                dipanggilPada: null,
                versi: { increment: 1 },
              },
            });

            if (perubahan.count !== 1) {
              throw new ConflictException(
                'Tiket sedang diproses oleh petugas lain',
              );
            }

            // 7. Audit REQUEUE dalam transaksi yang sama.
            await tx.peristiwaAntrean.create({
              data: {
                tiketAntreanId: tiket.id,
                aktorId: petugasId,
                tipe: transisi.tipePeristiwa,
                statusSebelum: transisi.statusSebelum,
                statusSesudah: transisi.statusSesudah,
                dataTambahan: {
                  metode: 'QUEUE_REQUEUE',
                  loketSebelumnya: loketId,
                  kodeLoketSebelumnya: penugasan.loket.kode,
                  penugasanId: penugasan.id,
                  urutanMasukSebelumnya: tiket.urutanMasukAntrean,
                  urutanMasukSesudah: counter.urutanMasukTerakhir,
                },
              },
            });

            return {
              tiketId: tiket.id,
              layananId: tiket.layananId,
              nomorAntrean:
                `${tiket.layanan.prefixAntrean.trim()}-` +
                String(tiket.nomorUrut).padStart(3, '0'),
              status: transisi.statusSesudah,
              loketId: null,
              loketSebelumnya: loketId,
              urutanMasukSebelumnya: tiket.urutanMasukAntrean,
              urutanMasukAntrean: counter.urutanMasukTerakhir,
              masukAntreanPada: sekarang.toISOString(),
              dipanggilPada: null,
              versi: tiket.versi + 1,
            };
          },
          {
            isolationLevel: Prisma.TransactionIsolationLevel.Serializable,
            maxWait: 10000,
            timeout: 15000,
          },
        );
        await this.kirimSetelahCommit(hasil, 'REQUEUE');
        return hasil;
      } catch (error: unknown) {
        if (
          error instanceof Prisma.PrismaClientKnownRequestError &&
          error.code === 'P2034'
        ) {
          if (percobaan < maksimalPercobaan) {
            continue;
          }

          throw new ConflictException(
            'Antre ulang sedang diproses, silakan coba kembali',
          );
        }

        throw error;
      }
    }

    throw new ConflictException(
      'Antre ulang gagal setelah beberapa percobaan',
    );
  }

  // ==========================================
  // MULAI PELAYANAN TIKET YANG DIPANGGIL (START)
  // DIPANGGIL -> DILAYANI
  // ==========================================

  async mulaiPelayanan(tiketId: string, petugasId: string, loketId: string) {
    const maksimalPercobaan = 3;

    for (let percobaan = 1; percobaan <= maksimalPercobaan; percobaan++) {
      const sekarang = new Date();
      const konteks = this.dapatkanTanggalPelayanan(sekarang);

      try {
        const hasil = await this.prisma.$transaction(
          async (tx) => {
            // 1. Validasi PETUGAS aktif.
            const petugas = await tx.pengguna.findUnique({
              where: { id: petugasId },
              select: { id: true, peran: true, aktif: true },
            });

            if (
              !petugas ||
              !petugas.aktif ||
              petugas.peran !== PeranPengguna.PETUGAS
            ) {
              throw new ForbiddenException('Pengguna bukan PETUGAS aktif');
            }

            // 2. Tiket harus DIPANGGIL pada loket yang sama.
            const tiket = await tx.tiketAntrean.findUnique({
              where: { id: tiketId },
              select: {
                id: true,
                layananId: true,
                tanggalAntrean: true,
                loketId: true,
                nomorUrut: true,
                status: true,
                versi: true,
                urutanMasukAntrean: true,
                dipanggilPada: true,
                pelayananDimulaiPada: true,
                pelayananSelesaiPada: true,
                layanan: {
                  select: { aktif: true, prefixAntrean: true },
                },
              },
            });

            if (!tiket) {
              throw new NotFoundException('Tiket antrean tidak ditemukan');
            }

            if (
              !bolehTransisiAntrean(
                tiket.status,
                AKSI_ANTREAN.MULAI_PELAYANAN,
              )
            ) {
              throw new ConflictException(
                `Tiket berstatus ${tiket.status} tidak dapat memulai pelayanan`,
              );
            }

            if (tiket.loketId !== loketId) {
              throw new ForbiddenException(
                'Tiket tidak sedang dipanggil pada loket petugas',
              );
            }

            if (!tiket.dipanggilPada || tiket.urutanMasukAntrean === null) {
              throw new ConflictException(
                'Tiket belum memiliki riwayat CALL dan urutan FIFO yang lengkap',
              );
            }

            if (tiket.pelayananDimulaiPada || tiket.pelayananSelesaiPada) {
              throw new ConflictException(
                'Tiket sudah memiliki catatan waktu pelayanan',
              );
            }

            if (
              tiket.tanggalAntrean.toISOString().slice(0, 10) !==
              konteks.tanggal
            ) {
              throw new ConflictException(
                'Tanggal tiket tidak sesuai hari pelayanan',
              );
            }

            if (!tiket.layanan.aktif) {
              throw new ConflictException('Layanan tidak aktif');
            }

            // 3. PETUGAS harus ditugaskan pada loket dan layanan tiket.
            const penugasan = await tx.penugasanPetugas.findFirst({
              where: {
                petugasId,
                loketId,
                aktif: true,
                tanggalMulai: { lte: konteks.tanggalDb },
                OR: [
                  { tanggalSelesai: null },
                  { tanggalSelesai: { gte: konteks.tanggalDb } },
                ],
              },
              select: {
                id: true,
                loket: {
                  select: {
                    kode: true,
                    aktif: true,
                    layananId: true,
                    layanan: { select: { aktif: true } },
                  },
                },
              },
            });

            if (
              !penugasan ||
              !penugasan.loket.aktif ||
              !penugasan.loket.layanan.aktif ||
              penugasan.loket.layananId !== tiket.layananId
            ) {
              throw new ForbiddenException(
                'Petugas tidak memiliki penugasan aktif pada loket tiket ini',
              );
            }

            // 4. Jadwal layanan hari ini harus aktif.
            const jadwal = await tx.jadwalLayanan.findUnique({
              where: {
                layananId_hari: {
                  layananId: tiket.layananId,
                  hari: konteks.hari,
                },
              },
              select: { aktif: true },
            });

            if (!jadwal?.aktif) {
              throw new ConflictException('Jadwal layanan hari ini tidak aktif');
            }

            // 5. Transisi dan update atomik memakai status dan versi.
            const transisi = jalankanTransisiAntrean(
              tiket.status,
              AKSI_ANTREAN.MULAI_PELAYANAN,
            );

            const perubahan = await tx.tiketAntrean.updateMany({
              where: {
                id: tiket.id,
                layananId: tiket.layananId,
                loketId,
                tanggalAntrean: konteks.tanggalDb,
                status: StatusTiket.DIPANGGIL,
                versi: tiket.versi,
                dipanggilPada: { not: null },
                pelayananDimulaiPada: null,
                pelayananSelesaiPada: null,
              },
              data: {
                status: transisi.statusSesudah,
                pelayananDimulaiPada: sekarang,
                versi: { increment: 1 },
              },
            });

            if (perubahan.count !== 1) {
              throw new ConflictException(
                'Tiket sedang diproses oleh petugas lain',
              );
            }

            // 6. Audit START_SERVICE dalam transaksi yang sama.
            await tx.peristiwaAntrean.create({
              data: {
                tiketAntreanId: tiket.id,
                aktorId: petugasId,
                tipe: transisi.tipePeristiwa,
                statusSebelum: transisi.statusSebelum,
                statusSesudah: transisi.statusSesudah,
                dataTambahan: {
                  metode: 'QUEUE_START_SERVICE',
                  loketId,
                  kodeLoket: penugasan.loket.kode,
                  penugasanId: penugasan.id,
                  urutanMasukAntrean: tiket.urutanMasukAntrean,
                  dipanggilPada: tiket.dipanggilPada.toISOString(),
                },
              },
            });

            return {
              tiketId: tiket.id,
              layananId: tiket.layananId,
              loketId,
              kodeLoket: penugasan.loket.kode,
              nomorAntrean:
                `${tiket.layanan.prefixAntrean.trim()}-` +
                String(tiket.nomorUrut).padStart(3, '0'),
              status: transisi.statusSesudah,
              urutanMasukAntrean: tiket.urutanMasukAntrean,
              dipanggilPada: tiket.dipanggilPada.toISOString(),
              pelayananDimulaiPada: sekarang.toISOString(),
              versi: tiket.versi + 1,
            };
          },
          {
            isolationLevel: Prisma.TransactionIsolationLevel.Serializable,
            maxWait: 10000,
            timeout: 15000,
          },
        );
        await this.kirimSetelahCommit(hasil, 'START');
        return hasil;
      } catch (error: unknown) {
        if (
          error instanceof Prisma.PrismaClientKnownRequestError &&
          error.code === 'P2034'
        ) {
          if (percobaan < maksimalPercobaan) {
            continue;
          }

          throw new ConflictException(
            'Mulai pelayanan sedang diproses, silakan coba kembali',
          );
        }

        throw error;
      }
    }

    throw new ConflictException(
      'Mulai pelayanan gagal setelah beberapa percobaan',
    );
  }

  // ==========================================
  // SELESAIKAN PELAYANAN TIKET (COMPLETE)
  // DILAYANI -> SELESAI
  // ==========================================

  async selesaikanPelayanan(tiketId: string, petugasId: string, loketId: string) {
    const maksimalPercobaan = 3;

    for (let percobaan = 1; percobaan <= maksimalPercobaan; percobaan++) {
      const sekarang = new Date();
      const konteks = this.dapatkanTanggalPelayanan(sekarang);

      try {
        const hasil = await this.prisma.$transaction(
          async (tx) => {
            // 1. Validasi identitas dan status PETUGAS.
            const petugas = await tx.pengguna.findUnique({
              where: { id: petugasId },
              select: { id: true, peran: true, aktif: true },
            });

            if (
              !petugas ||
              !petugas.aktif ||
              petugas.peran !== PeranPengguna.PETUGAS
            ) {
              throw new ForbiddenException('Pengguna bukan PETUGAS aktif');
            }

            // 2. Tiket harus sedang DILAYANI di loket yang sama.
            const tiket = await tx.tiketAntrean.findUnique({
              where: { id: tiketId },
              select: {
                id: true,
                layananId: true,
                tanggalAntrean: true,
                loketId: true,
                nomorUrut: true,
                status: true,
                versi: true,
                urutanMasukAntrean: true,
                dipanggilPada: true,
                pelayananDimulaiPada: true,
                pelayananSelesaiPada: true,
                layanan: {
                  select: { aktif: true, prefixAntrean: true },
                },
              },
            });

            if (!tiket) {
              throw new NotFoundException('Tiket antrean tidak ditemukan');
            }

            if (
              !bolehTransisiAntrean(
                tiket.status,
                AKSI_ANTREAN.SELESAIKAN_PELAYANAN,
              )
            ) {
              throw new ConflictException(
                `Tiket berstatus ${tiket.status} tidak dapat diselesaikan`,
              );
            }

            if (tiket.loketId !== loketId) {
              throw new ForbiddenException(
                'Tiket tidak sedang dilayani pada loket petugas',
              );
            }

            if (
              !tiket.dipanggilPada ||
              !tiket.pelayananDimulaiPada ||
              tiket.urutanMasukAntrean === null
            ) {
              throw new ConflictException(
                'Tiket belum memiliki riwayat CALL dan START yang lengkap',
              );
            }

            if (tiket.pelayananSelesaiPada) {
              throw new ConflictException(
                'Tiket sudah memiliki catatan waktu selesai pelayanan',
              );
            }

            if (
              tiket.tanggalAntrean.toISOString().slice(0, 10) !==
              konteks.tanggal
            ) {
              throw new ConflictException(
                'Tanggal tiket tidak sesuai hari pelayanan',
              );
            }

            if (!tiket.layanan.aktif) {
              throw new ConflictException('Layanan tidak aktif');
            }

            // 3. Validasi penugasan PETUGAS pada loket tiket.
            const penugasan = await tx.penugasanPetugas.findFirst({
              where: {
                petugasId,
                loketId,
                aktif: true,
                tanggalMulai: { lte: konteks.tanggalDb },
                OR: [
                  { tanggalSelesai: null },
                  { tanggalSelesai: { gte: konteks.tanggalDb } },
                ],
              },
              select: {
                id: true,
                loket: {
                  select: {
                    kode: true,
                    aktif: true,
                    layananId: true,
                    layanan: { select: { aktif: true } },
                  },
                },
              },
            });

            if (
              !penugasan ||
              !penugasan.loket.aktif ||
              !penugasan.loket.layanan.aktif ||
              penugasan.loket.layananId !== tiket.layananId
            ) {
              throw new ForbiddenException(
                'Petugas tidak memiliki penugasan aktif pada loket tiket ini',
              );
            }

            // 4. Jadwal layanan konsisten dengan CALL dan START.
            const jadwal = await tx.jadwalLayanan.findUnique({
              where: {
                layananId_hari: {
                  layananId: tiket.layananId,
                  hari: konteks.hari,
                },
              },
              select: { aktif: true },
            });

            if (!jadwal?.aktif) {
              throw new ConflictException('Jadwal layanan hari ini tidak aktif');
            }

            // 5. Perbarui status, waktu selesai, dan versi secara atomik.
            const transisi = jalankanTransisiAntrean(
              tiket.status,
              AKSI_ANTREAN.SELESAIKAN_PELAYANAN,
            );

            const perubahan = await tx.tiketAntrean.updateMany({
              where: {
                id: tiket.id,
                layananId: tiket.layananId,
                loketId,
                tanggalAntrean: konteks.tanggalDb,
                status: StatusTiket.DILAYANI,
                versi: tiket.versi,
                dipanggilPada: { not: null },
                pelayananDimulaiPada: { not: null },
                pelayananSelesaiPada: null,
              },
              data: {
                status: transisi.statusSesudah,
                pelayananSelesaiPada: sekarang,
                versi: { increment: 1 },
              },
            });

            if (perubahan.count !== 1) {
              throw new ConflictException(
                'Tiket sedang diproses oleh petugas lain',
              );
            }

            // 6. Audit COMPLETE bersama perubahan tiket dalam transaksi sama.
            await tx.peristiwaAntrean.create({
              data: {
                tiketAntreanId: tiket.id,
                aktorId: petugasId,
                tipe: transisi.tipePeristiwa,
                statusSebelum: transisi.statusSebelum,
                statusSesudah: transisi.statusSesudah,
                dataTambahan: {
                  metode: 'QUEUE_COMPLETE_SERVICE',
                  loketId,
                  kodeLoket: penugasan.loket.kode,
                  penugasanId: penugasan.id,
                  urutanMasukAntrean: tiket.urutanMasukAntrean,
                  pelayananDimulaiPada: tiket.pelayananDimulaiPada.toISOString(),
                  pelayananSelesaiPada: sekarang.toISOString(),
                },
              },
            });

            // Status SELESAI membebaskan loket bagi CALL berikutnya.
            return {
              tiketId: tiket.id,
              layananId: tiket.layananId,
              loketId,
              kodeLoket: penugasan.loket.kode,
              nomorAntrean:
                `${tiket.layanan.prefixAntrean.trim()}-` +
                String(tiket.nomorUrut).padStart(3, '0'),
              status: transisi.statusSesudah,
              urutanMasukAntrean: tiket.urutanMasukAntrean,
              pelayananDimulaiPada: tiket.pelayananDimulaiPada.toISOString(),
              pelayananSelesaiPada: sekarang.toISOString(),
              versi: tiket.versi + 1,
            };
          },
          {
            isolationLevel: Prisma.TransactionIsolationLevel.Serializable,
            maxWait: 10000,
            timeout: 15000,
          },
        );
        await this.kirimSetelahCommit(hasil, 'COMPLETE');
        return hasil;
      } catch (error: unknown) {
        if (
          error instanceof Prisma.PrismaClientKnownRequestError &&
          error.code === 'P2034'
        ) {
          if (percobaan < maksimalPercobaan) {
            continue;
          }

          throw new ConflictException(
            'Penyelesaian pelayanan sedang diproses, silakan coba kembali',
          );
        }

        throw error;
      }
    }

    throw new ConflictException(
      'Penyelesaian pelayanan gagal setelah beberapa percobaan',
    );
  }

  // ==========================================
  // KONTEKS TANGGAL PELAYANAN
  // ==========================================

  private dapatkanTanggalPelayanan(sekarang: Date): KonteksTanggal {
    const zonaWaktu = process.env.SERVICE_TIME_ZONE ?? 'Asia/Jakarta';

    const formatter = new Intl.DateTimeFormat('en-GB', {
      timeZone: zonaWaktu,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
    });

    const bagian = formatter.formatToParts(sekarang);

    const ambil = (tipe: string): string =>
      bagian.find((item) => item.type === tipe)?.value ?? '';

    const tanggal = [ambil('year'), ambil('month'), ambil('day')].join('-');

    const tanggalDb = new Date(`${tanggal}T00:00:00.000Z`);

    return {
      tanggal,
      tanggalDb,
      hari: NAMA_HARI[tanggalDb.getUTCDay()],
    };
  }
}
