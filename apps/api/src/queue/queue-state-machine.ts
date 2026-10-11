import { StatusTiket } from '../generated/prisma/client';

// ==========================================
// AKSI OPERASIONAL ANTREAN
// ==========================================

export const AKSI_ANTREAN = {
  MASUK_ANTREAN: 'MASUK_ANTREAN',
  PANGGIL: 'PANGGIL',
  PANGGIL_ULANG: 'PANGGIL_ULANG',
  MULAI_PELAYANAN: 'MULAI_PELAYANAN',
  LEWATI: 'LEWATI',
  ANTRE_ULANG: 'ANTRE_ULANG',
  SELESAIKAN_PELAYANAN: 'SELESAIKAN_PELAYANAN',
} as const;

export type AksiAntrean = (typeof AKSI_ANTREAN)[keyof typeof AKSI_ANTREAN];

// ==========================================
// JENIS PERISTIWA UNTUK AUDIT
// ==========================================

export const TIPE_PERISTIWA_ANTREAN = {
  MASUK_ANTREAN: 'ENQUEUE',
  PANGGIL: 'CALL',
  PANGGIL_ULANG: 'RECALL',
  MULAI_PELAYANAN: 'START_SERVICE',
  LEWATI: 'SKIP',
  ANTRE_ULANG: 'REQUEUE',
  SELESAIKAN_PELAYANAN: 'COMPLETE',
} as const;

// ==========================================
// TIPE DATA
// ==========================================

interface AturanTransisi {
  readonly dari: StatusTiket;
  readonly ke: StatusTiket;
  readonly tipePeristiwa: string;
}

export interface HasilTransisiAntrean {
  readonly aksi: AksiAntrean;
  readonly statusSebelum: StatusTiket;
  readonly statusSesudah: StatusTiket;
  readonly tipePeristiwa: string;
  readonly statusBerubah: boolean;
}

// ==========================================
// MATRIKS ATURAN TRANSISI
// ==========================================

const ATURAN_TRANSISI: Readonly<Record<AksiAntrean, AturanTransisi>> = {
  [AKSI_ANTREAN.MASUK_ANTREAN]: {
    dari: StatusTiket.CHECK_IN,
    ke: StatusTiket.MENUNGGU,
    tipePeristiwa: TIPE_PERISTIWA_ANTREAN.MASUK_ANTREAN,
  },

  [AKSI_ANTREAN.PANGGIL]: {
    dari: StatusTiket.MENUNGGU,
    ke: StatusTiket.DIPANGGIL,
    tipePeristiwa: TIPE_PERISTIWA_ANTREAN.PANGGIL,
  },

  [AKSI_ANTREAN.PANGGIL_ULANG]: {
    dari: StatusTiket.DIPANGGIL,
    ke: StatusTiket.DIPANGGIL,
    tipePeristiwa: TIPE_PERISTIWA_ANTREAN.PANGGIL_ULANG,
  },

  [AKSI_ANTREAN.MULAI_PELAYANAN]: {
    dari: StatusTiket.DIPANGGIL,
    ke: StatusTiket.DILAYANI,
    tipePeristiwa: TIPE_PERISTIWA_ANTREAN.MULAI_PELAYANAN,
  },

  [AKSI_ANTREAN.LEWATI]: {
    dari: StatusTiket.DIPANGGIL,
    ke: StatusTiket.DILEWATI,
    tipePeristiwa: TIPE_PERISTIWA_ANTREAN.LEWATI,
  },

  [AKSI_ANTREAN.ANTRE_ULANG]: {
    dari: StatusTiket.DILEWATI,
    ke: StatusTiket.MENUNGGU,
    tipePeristiwa: TIPE_PERISTIWA_ANTREAN.ANTRE_ULANG,
  },

  [AKSI_ANTREAN.SELESAIKAN_PELAYANAN]: {
    dari: StatusTiket.DILAYANI,
    ke: StatusTiket.SELESAI,
    tipePeristiwa: TIPE_PERISTIWA_ANTREAN.SELESAIKAN_PELAYANAN,
  },
};

// ==========================================
// ERROR DOMAIN
// ==========================================

export class TransisiAntreanTidakValidError extends Error {
  constructor(
    public readonly statusSaatIni: StatusTiket,
    public readonly aksi: AksiAntrean,
  ) {
    super(
      `Aksi ${aksi} tidak diperbolehkan ` +
        `ketika tiket berstatus ${statusSaatIni}`,
    );

    this.name = 'TransisiAntreanTidakValidError';
  }
}

// ==========================================
// PEMERIKSAAN TRANSISI
// ==========================================

export function bolehTransisiAntrean(
  statusSaatIni: StatusTiket,
  aksi: AksiAntrean,
): boolean {
  const aturan = ATURAN_TRANSISI[aksi];

  return aturan?.dari === statusSaatIni;
}

// ==========================================
// EKSEKUSI LOGIKA STATE MACHINE
// ==========================================

export function jalankanTransisiAntrean(
  statusSaatIni: StatusTiket,
  aksi: AksiAntrean,
): HasilTransisiAntrean {
  if (!bolehTransisiAntrean(statusSaatIni, aksi)) {
    throw new TransisiAntreanTidakValidError(statusSaatIni, aksi);
  }

  const aturan = ATURAN_TRANSISI[aksi];

  return {
    aksi,
    statusSebelum: statusSaatIni,
    statusSesudah: aturan.ke,
    tipePeristiwa: aturan.tipePeristiwa,
    statusBerubah: statusSaatIni !== aturan.ke,
  };
}
