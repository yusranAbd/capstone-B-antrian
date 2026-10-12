import type { JenisPerubahanAntrean } from './realtime-events.types';

/** Hanya sinyal invalidasi. Klien mengambil rincian lewat REST Snapshot. */
export interface DisplayUpdatedEvent {
  versiSkema: 1;
  eventId: string;
  layananId: string;
  terjadiPada: string;
  aksi: JenisPerubahanAntrean;
  perluPeriksaPengumuman: boolean;
}

export interface DisplayReadyEvent {
  versiSkema: 1;
  layananId: string;
}
