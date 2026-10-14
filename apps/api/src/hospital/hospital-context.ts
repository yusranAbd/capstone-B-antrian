import { HariLayanan, ModeReservasi } from '../generated/prisma/client';

export type AlasanTidakLayakHospital =
  | 'BELUM_CHECK_IN'
  | 'SLOT_BELUM_DIMULAI'
  | 'SESI_BELUM_DIMULAI'
  | 'SESI_BERAKHIR'
  | 'RUANG_BERBEDA'
  | 'TANGGAL_TIDAK_SESUAI'
  | 'RELASI_TIDAK_AKTIF'
  | 'RELASI_TIDAK_SESUAI'
  | 'JADWAL_TIDAK_VALID'
  | 'APPOINTMENT_TIDAK_ADA'
  | 'SESI_WALK_IN_TIDAK_TERSEDIA';

export interface KonteksSlotHospital {
  aktif: boolean;
  mulaiPada: Date;
  selesaiPada: Date;
  jadwalPraktik: {
    aktif: boolean;
    tanggal: Date;
    mulaiPada: Date;
    selesaiPada: Date;
    loketId: string;
    loket: { aktif: boolean; layananId: string };
    dokterLayanan: {
      aktif: boolean;
      layananId: string;
      dokter: { aktif: boolean };
      layanan: { aktif: boolean };
    };
  };
}

/** Select internal; tidak menyertakan identitas pasien atau rahasia QR. */
export const PILIH_JANJI_TEMU_HOSPITAL = {
  select: {
    slotPraktik: {
      select: {
        aktif: true,
        mulaiPada: true,
        selesaiPada: true,
        jadwalPraktik: {
          select: {
            aktif: true,
            tanggal: true,
            mulaiPada: true,
            selesaiPada: true,
            loketId: true,
            loket: { select: { aktif: true, layananId: true } },
            dokterLayanan: {
              select: {
                aktif: true,
                layananId: true,
                dokter: { select: { aktif: true } },
                layanan: { select: { aktif: true } },
              },
            },
          },
        },
      },
    },
  },
} as const;

export function waktuPelayanan(waktu: Date) {
  const bagian = new Intl.DateTimeFormat('en-GB', {
    timeZone: process.env.SERVICE_TIME_ZONE ?? 'Asia/Jakarta',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hourCycle: 'h23',
  }).formatToParts(waktu);
  const ambil = (jenis: string) =>
    bagian.find((item) => item.type === jenis)?.value ?? '';
  const tanggal = `${ambil('year')}-${ambil('month')}-${ambil('day')}`;
  const tanggalDb = new Date(`${tanggal}T00:00:00.000Z`);
  const hari = [
    HariLayanan.MINGGU,
    HariLayanan.SENIN,
    HariLayanan.SELASA,
    HariLayanan.RABU,
    HariLayanan.KAMIS,
    HariLayanan.JUMAT,
    HariLayanan.SABTU,
  ][tanggalDb.getUTCDay()];
  return {
    tanggal,
    tanggalDb,
    hari,
    jam: `${ambil('hour')}:${ambil('minute')}:${ambil('second')}`,
  };
}

export function alasanRelasiSlot(
  slot: KonteksSlotHospital,
  layananId: string,
  tanggalAntrean: Date,
): AlasanTidakLayakHospital | null {
  const sesi = slot.jadwalPraktik;
  const relasi = sesi.dokterLayanan;
  if (
    !slot.aktif ||
    !sesi.aktif ||
    !sesi.loket.aktif ||
    !relasi.aktif ||
    !relasi.dokter.aktif ||
    !relasi.layanan.aktif
  )
    return 'RELASI_TIDAK_AKTIF';
  if (relasi.layananId !== layananId || sesi.loket.layananId !== layananId)
    return 'RELASI_TIDAK_SESUAI';
  const tanggal = tanggalAntrean.toISOString().slice(0, 10);
  if (
    sesi.tanggal.toISOString().slice(0, 10) !== tanggal ||
    [sesi.mulaiPada, sesi.selesaiPada].some(
      (waktu) => waktuPelayanan(waktu).tanggal !== tanggal,
    )
  ) {
    return 'TANGGAL_TIDAK_SESUAI';
  }
  if (
    sesi.selesaiPada <= sesi.mulaiPada ||
    slot.selesaiPada <= slot.mulaiPada ||
    slot.mulaiPada < sesi.mulaiPada ||
    slot.selesaiPada > sesi.selesaiPada
  )
    return 'JADWAL_TIDAK_VALID';
  return null;
}

export function alasanPenerimaanHospital(
  tiket: {
    layananId: string;
    tanggalAntrean: Date;
    modeReservasi?: ModeReservasi;
    janjiTemu?: { slotPraktik: KonteksSlotHospital } | null;
  },
  loketId: string,
  sekarang: Date,
): AlasanTidakLayakHospital | null {
  const slot = tiket.janjiTemu?.slotPraktik;
  if (!slot)
    return tiket.modeReservasi === ModeReservasi.JANJI_TEMU_DOKTER
      ? 'APPOINTMENT_TIDAK_ADA'
      : null;
  if (
    tiket.modeReservasi !== ModeReservasi.JANJI_TEMU_DOKTER &&
    tiket.modeReservasi !== ModeReservasi.HIBRIDA
  )
    return 'RELASI_TIDAK_SESUAI';
  const alasan = alasanRelasiSlot(slot, tiket.layananId, tiket.tanggalAntrean);
  if (alasan) return alasan;
  if (slot.jadwalPraktik.loketId !== loketId) return 'RUANG_BERBEDA';
  if (slot.jadwalPraktik.selesaiPada <= sekarang) return 'SESI_BERAKHIR';
  // Datang sebelum sesi/slot boleh selama poli buka; tidak menetapkan toleransi menit.
  return null;
}

export function rentangDalamJamLayanan(
  slot: KonteksSlotHospital,
  harian: { aktif: boolean; jamBuka: Date; jamTutup: Date },
): boolean {
  const mulai = waktuPelayanan(slot.jadwalPraktik.mulaiPada).jam;
  const selesai = waktuPelayanan(slot.jadwalPraktik.selesaiPada).jam;
  return (
    harian.aktif &&
    mulai >= harian.jamBuka.toISOString().slice(11, 19) &&
    selesai <= harian.jamTutup.toISOString().slice(11, 19)
  );
}
