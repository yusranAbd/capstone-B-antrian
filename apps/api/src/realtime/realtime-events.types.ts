/** Kontrak event operasional untuk klien monitoring.
 * Data pribadi pengguna tidak diperbolehkan dalam payload.
 */
export type JenisPerubahanAntrean =
  | 'ENQUEUE'
  | 'CALL'
  | 'RECALL'
  | 'SKIP'
  | 'REQUEUE'
  | 'START'
  | 'COMPLETE';

export interface QueueUpdatedInput {
  aksi: JenisPerubahanAntrean;
  layananId: string;
  tiketId: string;
  nomorAntrean: string;
  status: string;
  loketId?: string | null;
  kodeLoket?: string;
  urutanMasukAntrean?: number | null;
  versi?: number;
}

export interface QueueUpdatedEvent extends QueueUpdatedInput {
  versiSkema: 1;
  eventId: string;
  terjadiPada: string;
}
