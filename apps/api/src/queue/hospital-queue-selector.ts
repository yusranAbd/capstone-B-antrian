import { ModeReservasi } from '../generated/prisma/client';

/**
 * H3.3: selector murni tanpa operasi database.
 * Berlaku hanya untuk mode JANJI_TEMU_DOKTER/HIBRIDA; ANTREAN_HARIAN
 * tetap melewati jalur FIFO lama di QueueService.
 *
 * Slot yang sudah dimulai layak dipanggil di loket yang ditetapkan dokter,
 * selama rantai relasinya aktif dan sesi praktik masih berlangsung pada
 * tanggal tiket. Akhir slot adalah estimasi konsultasi,
 * bukan kedaluwarsa hak pasien yang masih MENUNGGU (kebijakan H1).
 * Toleransi keterlambatan dan anti-starvation numerik tidak ditetapkan di sini.
 */
export interface KandidatHospital {
  id: string;
  urutanMasukAntrean: number | null;
  checkInPada: Date | null;
  tanggalAntrean: Date;
  /** Query hanya mengambil audit REQUEUE terbaru; bukan bagian respons API. */
  peristiwaAntrean?: readonly { terjadiPada: Date }[];
  janjiTemu: {
    slotPraktik: {
      aktif: boolean;
      mulaiPada: Date;
      selesaiPada: Date;
      jadwalPraktik: {
        aktif: boolean;
        loketId: string;
        tanggal: Date;
        mulaiPada: Date;
        selesaiPada: Date;
        dokterLayanan: {
          aktif: boolean;
          dokter: { aktif: boolean };
        };
      };
    };
  } | null;
}

export type JenisAntreanHospital = 'JANJI_TEMU' | 'WALK_IN';

export interface KandidatTerurut<T extends KandidatHospital> {
  tiket: T;
  jenisAntrean: JenisAntreanHospital;
  layakDipanggil: boolean;
  slotMulaiPada: string | null;
  prioritas: number;
}

function waktuPrioritas(tiket: KandidatHospital): number {
  return (tiket.peristiwaAntrean?.[0]?.terjadiPada ?? tiket.checkInPada)?.getTime() ??
    Number.MAX_SAFE_INTEGER;
}

function statusKandidat<T extends KandidatHospital>(
  tiket: T,
  mode: ModeReservasi,
  loketId: string,
  sekarang: Date,
): KandidatTerurut<T> {
  const slot = tiket.janjiTemu?.slotPraktik;
  if (!slot) {
    const bolehWalkIn = mode === ModeReservasi.HIBRIDA && tiket.checkInPada !== null;
    return {
      tiket,
      jenisAntrean: 'WALK_IN',
      layakDipanggil: bolehWalkIn,
      slotMulaiPada: null,
      prioritas: bolehWalkIn ? 1 : 2,
    };
  }
  const layak =
    tiket.checkInPada !== null &&
    slot.aktif &&
    slot.jadwalPraktik.aktif &&
    slot.jadwalPraktik.dokterLayanan.aktif &&
    slot.jadwalPraktik.dokterLayanan.dokter.aktif &&
    slot.jadwalPraktik.loketId === loketId &&
    slot.jadwalPraktik.tanggal.getTime() === tiket.tanggalAntrean.getTime() &&
    slot.jadwalPraktik.mulaiPada.getTime() <= sekarang.getTime() &&
    sekarang.getTime() < slot.jadwalPraktik.selesaiPada.getTime() &&
    slot.mulaiPada.getTime() <= sekarang.getTime();
  return {
    tiket,
    jenisAntrean: 'JANJI_TEMU',
    layakDipanggil: layak,
    slotMulaiPada: slot.mulaiPada.toISOString(),
    prioritas: layak ? 0 : 2,
  };
}

/**
 * Satu sumber logika untuk CALL, GET menunggu dan REST snapshot.
 * Total order deterministik: prioritas > slot > waktu REQUEUE terbaru
 * (atau check-in jika belum pernah REQUEUE) > urutan masuk > id.
 * Tidak mengubah nomor tiket permanen atau waktu check-in asli.
 */
export function urutkanKandidatHospital<T extends KandidatHospital>(
  kandidat: readonly T[],
  mode: ModeReservasi,
  loketId: string,
  sekarang: Date,
): Array<KandidatTerurut<T>> {
  const terurut = kandidat.map((tiket) => statusKandidat(tiket, mode, loketId, sekarang));
  terurut.sort((a, b) => {
    if (a.prioritas !== b.prioritas) return a.prioritas - b.prioritas;
    // Appointment pada slot lebih awal berhak dipanggil lebih dahulu.
    if (a.jenisAntrean === 'JANJI_TEMU' && b.jenisAntrean === 'JANJI_TEMU') {
      const waktuSlotA = a.tiket.janjiTemu?.slotPraktik.mulaiPada.getTime() ?? Number.MAX_SAFE_INTEGER;
      const waktuSlotB = b.tiket.janjiTemu?.slotPraktik.mulaiPada.getTime() ?? Number.MAX_SAFE_INTEGER;
      if (waktuSlotA !== waktuSlotB) return waktuSlotA - waktuSlotB;
    }
    const waktuA = waktuPrioritas(a.tiket);
    const waktuB = waktuPrioritas(b.tiket);
    if (waktuA !== waktuB) return waktuA - waktuB;
    const urutanA = a.tiket.urutanMasukAntrean ?? Number.MAX_SAFE_INTEGER;
    const urutanB = b.tiket.urutanMasukAntrean ?? Number.MAX_SAFE_INTEGER;
    if (urutanA !== urutanB) return urutanA - urutanB;
    return a.tiket.id.localeCompare(b.tiket.id);
  });
  return terurut;
}

/** Slot mendatang, relasi nonaktif atau ruang lain tidak boleh di-CALL. */
export function pilihBerikutnyaHospital<T extends KandidatHospital>(
  kandidat: readonly T[],
  mode: ModeReservasi,
  loketId: string,
  sekarang: Date,
): T | null {
  return (
    urutkanKandidatHospital(kandidat, mode, loketId, sekarang)
      .find((item) => item.layakDipanggil)?.tiket ?? null
  );
}
