/** Kontrak v1, seluruh field aman ditampilkan pada layar publik. */
export interface DisplayTiketAktif {
  nomorAntrean: string;
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
  loket: DisplayLoket[];
  pengumumanTerakhir: DisplayPengumuman | null;
}
