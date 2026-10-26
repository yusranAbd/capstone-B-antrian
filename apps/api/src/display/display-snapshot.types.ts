/** Kontrak v1. Nama adalah proyeksi sesuai kebijakan fasilitas, bukan objek pengguna mentah. */
export interface DisplayTiketAktif {
  nomorAntrean: string;
  namaPasien?: string | null;
  status: 'DIPANGGIL' | 'DILAYANI';
  dipanggilPada: string | null;
}

export interface DisplayLoket {
  kode: string;
  nama: string;
  tiketAktif: DisplayTiketAktif[];
}

/** Event audit berbeda untuk CALL dan RECALL walaupun status tiket tetap DIPANGGIL. */
export interface DisplayPengumuman {
  peristiwaId: string;
  aksi: 'CALL' | 'RECALL';
  terjadiPada: string;
  nomorAntrean: string;
  namaPasien?: string | null;
  kodeLoket: string;
  teks: string;
  bahasa: 'id-ID';
}

export interface DisplaySnapshot {
  versiSkema: 1;
  tanggalPelayanan: string;
  diperolehPada: string;
  layanan: { kode: string; nama: string };
  totalMenunggu: number;
  totalDilewati?: number;
  totalAntrianPasien?: number;
  antrianPasien?: Array<{
    nomorAntrean: string;
    namaPasien: string | null;
    status: 'MENUNGGU' | 'DILEWATI';
  }>;
  modeNama?: 'SAMAR' | 'LENGKAP' | 'TANPA_NAMA';
  menunggu?: Array<{ nomorAntrean: string; namaPasien: string | null }>;

  loket: DisplayLoket[];
  pengumumanTerakhir: DisplayPengumuman | null;
}
