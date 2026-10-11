import { StatusTiket } from '../generated/prisma/client';

import {
  AKSI_ANTREAN,
  type AksiAntrean,
  bolehTransisiAntrean,
  jalankanTransisiAntrean,
  TransisiAntreanTidakValidError,
} from './queue-state-machine';

// ==========================================
// DATA TRANSISI YANG DIIZINKAN
// ==========================================

const transisiValid: Array<{
  aksi: AksiAntrean;
  dari: StatusTiket;
  ke: StatusTiket;
  peristiwa: string;
}> = [
  {
    aksi: AKSI_ANTREAN.MASUK_ANTREAN,
    dari: StatusTiket.CHECK_IN,
    ke: StatusTiket.MENUNGGU,
    peristiwa: 'ENQUEUE',
  },
  {
    aksi: AKSI_ANTREAN.PANGGIL,
    dari: StatusTiket.MENUNGGU,
    ke: StatusTiket.DIPANGGIL,
    peristiwa: 'CALL',
  },
  {
    aksi: AKSI_ANTREAN.PANGGIL_ULANG,
    dari: StatusTiket.DIPANGGIL,
    ke: StatusTiket.DIPANGGIL,
    peristiwa: 'RECALL',
  },
  {
    aksi: AKSI_ANTREAN.MULAI_PELAYANAN,
    dari: StatusTiket.DIPANGGIL,
    ke: StatusTiket.DILAYANI,
    peristiwa: 'START_SERVICE',
  },
  {
    aksi: AKSI_ANTREAN.LEWATI,
    dari: StatusTiket.DIPANGGIL,
    ke: StatusTiket.DILEWATI,
    peristiwa: 'SKIP',
  },
  {
    aksi: AKSI_ANTREAN.ANTRE_ULANG,
    dari: StatusTiket.DILEWATI,
    ke: StatusTiket.MENUNGGU,
    peristiwa: 'REQUEUE',
  },
  {
    aksi: AKSI_ANTREAN.SELESAIKAN_PELAYANAN,
    dari: StatusTiket.DILAYANI,
    ke: StatusTiket.SELESAI,
    peristiwa: 'COMPLETE',
  },
];

// ==========================================
// DATA TRANSISI YANG DITOLAK
// ==========================================

const transisiTidakValid: Array<{
  dari: StatusTiket;
  aksi: AksiAntrean;
}> = [
  {
    dari: StatusTiket.DIPESAN,
    aksi: AKSI_ANTREAN.MASUK_ANTREAN,
  },
  {
    dari: StatusTiket.DIPESAN,
    aksi: AKSI_ANTREAN.PANGGIL,
  },
  {
    dari: StatusTiket.CHECK_IN,
    aksi: AKSI_ANTREAN.PANGGIL,
  },
  {
    dari: StatusTiket.MENUNGGU,
    aksi: AKSI_ANTREAN.MASUK_ANTREAN,
  },
  {
    dari: StatusTiket.MENUNGGU,
    aksi: AKSI_ANTREAN.MULAI_PELAYANAN,
  },
  {
    dari: StatusTiket.DIPANGGIL,
    aksi: AKSI_ANTREAN.PANGGIL,
  },
  {
    dari: StatusTiket.DILAYANI,
    aksi: AKSI_ANTREAN.PANGGIL_ULANG,
  },
  {
    dari: StatusTiket.DILEWATI,
    aksi: AKSI_ANTREAN.SELESAIKAN_PELAYANAN,
  },
  {
    dari: StatusTiket.SELESAI,
    aksi: AKSI_ANTREAN.PANGGIL,
  },
  {
    dari: StatusTiket.DIBATALKAN,
    aksi: AKSI_ANTREAN.MASUK_ANTREAN,
  },
];

describe('Queue State Machine', () => {
  // ========================================
  // A. TRANSISI VALID - 7 TEST
  // ========================================

  describe('Transisi yang diperbolehkan', () => {
    it.each(transisiValid)(
      '$aksi: $dari menjadi $ke',
      ({ aksi, dari, ke, peristiwa }) => {
        expect(bolehTransisiAntrean(dari, aksi)).toBe(true);

        const hasil = jalankanTransisiAntrean(dari, aksi);

        expect(hasil).toEqual({
          aksi,
          statusSebelum: dari,
          statusSesudah: ke,
          tipePeristiwa: peristiwa,
          statusBerubah: dari !== ke,
        });
      },
    );
  });

  // ========================================
  // B. TRANSISI TIDAK VALID - 10 TEST
  // ========================================

  describe('Transisi yang harus ditolak', () => {
    it.each(transisiTidakValid)(
      'menolak $aksi ketika status $dari',
      ({ dari, aksi }) => {
        expect(bolehTransisiAntrean(dari, aksi)).toBe(false);

        expect(() => jalankanTransisiAntrean(dari, aksi)).toThrow(
          TransisiAntreanTidakValidError,
        );
      },
    );
  });

  // ========================================
  // C. ALUR NORMAL - 1 TEST
  // ========================================

  it('menjalankan alur CHECK_IN hingga SELESAI', () => {
    const aksi: AksiAntrean[] = [
      AKSI_ANTREAN.MASUK_ANTREAN,
      AKSI_ANTREAN.PANGGIL,
      AKSI_ANTREAN.MULAI_PELAYANAN,
      AKSI_ANTREAN.SELESAIKAN_PELAYANAN,
    ];

    const statusAkhir = aksi.reduce<StatusTiket>(
      (status, tindakan) =>
        jalankanTransisiAntrean(status, tindakan).statusSesudah,
      StatusTiket.CHECK_IN,
    );

    expect(statusAkhir).toBe(StatusTiket.SELESAI);
  });

  // ========================================
  // D. ALUR SKIP DAN REQUEUE - 1 TEST
  // ========================================

  it('mendukung SKIP dan REQUEUE tanpa mengubah aturan status', () => {
    const dipanggil = jalankanTransisiAntrean(
      StatusTiket.MENUNGGU,
      AKSI_ANTREAN.PANGGIL,
    );

    const dilewati = jalankanTransisiAntrean(
      dipanggil.statusSesudah,
      AKSI_ANTREAN.LEWATI,
    );

    const antreUlang = jalankanTransisiAntrean(
      dilewati.statusSesudah,
      AKSI_ANTREAN.ANTRE_ULANG,
    );

    expect(dilewati.statusSesudah).toBe(StatusTiket.DILEWATI);

    expect(antreUlang.statusSesudah).toBe(StatusTiket.MENUNGGU);

    expect(antreUlang.tipePeristiwa).toBe('REQUEUE');
  });

  // ========================================
  // E. RECALL - 1 TEST
  // ========================================

  it('RECALL mempertahankan status tetapi menghasilkan peristiwa audit', () => {
    const hasil = jalankanTransisiAntrean(
      StatusTiket.DIPANGGIL,
      AKSI_ANTREAN.PANGGIL_ULANG,
    );

    expect(hasil.statusSebelum).toBe(StatusTiket.DIPANGGIL);

    expect(hasil.statusSesudah).toBe(StatusTiket.DIPANGGIL);

    expect(hasil.statusBerubah).toBe(false);

    expect(hasil.tipePeristiwa).toBe('RECALL');
  });
});
