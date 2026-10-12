import { Injectable } from '@nestjs/common';
import { randomUUID } from 'node:crypto';

import { RealtimeGateway } from './realtime.gateway';
import type { QueueUpdatedInput } from './realtime-events.types';

/** Mengubah hasil operasi yang sudah commit menjadi notifikasi Socket.IO.
 * Pengiriman tidak dijamin persisten; klien wajib menggunakan REST snapshot
 * saat pertama terhubung dan setelah reconnect.
 */
@Injectable()
export class RealtimeBroadcastService {
  constructor(private readonly gateway: RealtimeGateway) {}

  async kirim(input: QueueUpdatedInput): Promise<void> {
    await this.gateway.broadcastPerubahan({
      ...input,
      versiSkema: 1,
      eventId: randomUUID(),
      terjadiPada: new Date().toISOString(),
    });
  }
}
