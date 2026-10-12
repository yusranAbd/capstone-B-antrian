import { Inject, Injectable, Logger } from '@nestjs/common';
import { randomUUID } from 'node:crypto';

import { RealtimeGateway } from './realtime.gateway';
import { DisplayRealtimeGateway } from './display-realtime.gateway';
import type { QueueUpdatedInput, QueueUpdatedEvent } from './realtime-events.types';

/** Mengubah hasil operasi yang sudah commit menjadi notifikasi Socket.IO.
 * Pengiriman tidak dijamin persisten; klien wajib menggunakan REST snapshot
 * saat pertama terhubung dan setelah reconnect.
 */
@Injectable()
export class RealtimeBroadcastService {
  private readonly logger = new Logger(RealtimeBroadcastService.name);

  // Argumen kedua opsional pada level TypeScript demi kompatibilitas Unit Test lama.
  constructor(
    private readonly gateway: RealtimeGateway,
    @Inject(DisplayRealtimeGateway)
    private readonly displayGateway?: DisplayRealtimeGateway,
  ) {}

  async kirim(input: QueueUpdatedInput): Promise<void> {
    const event: QueueUpdatedEvent = {
      ...input,
      versiSkema: 1,
      eventId: randomUUID(),
      terjadiPada: new Date().toISOString(),
    };

    // Kedua kanal independen; kegagalan satu tidak menahan kanal lain.
    const [operasional, publik] = await Promise.allSettled([
      this.gateway.broadcastPerubahan(event),
      this.displayGateway?.broadcastPerubahan(event) ?? Promise.resolve(),
    ]);
    if (publik.status === 'rejected') {
      this.logger.warn('Broadcast perangkat display gagal; database tetap tersimpan');
    }
    if (operasional.status === 'rejected') throw operasional.reason;
  }
}
