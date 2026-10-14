import type { AlasanTidakLayakHospital } from '../hospital/hospital-context';
/** Kontrak respons REST khusus dashboard PETUGAS, tanpa data pribadi. */
export interface SnapshotTiketMenunggu {
  tiketId: string;
  nomorAntrean: string;
  status: 'MENUNGGU';
  urutanMasukAntrean: number | null;
  masukAntreanPada: string | null;
  versi: number;
  /** H3.3: hanya ada untuk mode Hospital; kontrak v1 tetap kompatibel. */
  jenisAntrean?: 'JANJI_TEMU' | 'WALK_IN';
  layakDipanggil?: boolean;
  slotMulaiPada?: string | null;
  alasanTidakLayak?: AlasanTidakLayakHospital | null;
}

export interface SnapshotTiketAktif {
  tiketId: string;
  nomorAntrean: string;
  status: 'DIPANGGIL' | 'DILAYANI';
  urutanMasukAntrean: number | null;
  versi: number;
  dipanggilPada: string | null;
  pelayananDimulaiPada: string | null;
}

export interface SnapshotAntrean {
  versiSkema: 1;
  diperolehPada: string;
  tanggalPelayanan: string;
  layanan: { id: string; kode: string; nama: string };
  loketPeminta: { id: string; kode: string; nama: string };
  menunggu: {
    total: number;
    ditampilkan: number;
    tiket: SnapshotTiketMenunggu[];
  };
  loket: Array<{
    id: string;
    kode: string;
    nama: string;
    /** Array agar data tetap terlihat jika ditemukan >1 tiket aktif per loket. */
    tiketAktif: SnapshotTiketAktif[];
  }>;
}
