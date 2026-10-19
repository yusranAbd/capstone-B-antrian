import { cookieToken } from '../display/display-cookie';
import { Logger } from '@nestjs/common';
import {
  OnGatewayConnection,
  OnGatewayInit,
  WebSocketGateway,
  WebSocketServer,
} from '@nestjs/websockets';
import type { Namespace, Socket } from 'socket.io';
import { keamananHandshakeSocket } from '../config/socket-handshake-security';
import {
  DisplayRealtimeAccessService,
  type IdentitasDisplay,
} from './display-realtime-access.service';
import type { DisplayReadyEvent, DisplayUpdatedEvent } from './display-realtime.types';
import type { QueueUpdatedEvent } from './realtime-events.types';

/** Monitor memakai token perangkat, bukan JWT staf. */
@WebSocketGateway({ namespace: '/display' })
export class DisplayRealtimeGateway
  implements OnGatewayInit<Namespace>, OnGatewayConnection<Socket> {
  private readonly logger = new Logger(DisplayRealtimeGateway.name);

  @WebSocketServer()
  private server?: Namespace;

  constructor(private readonly akses: DisplayRealtimeAccessService) {}

  afterInit(server: Namespace): void {
    this.server = server;
    server.use((client, next) => {
      try {
        keamananHandshakeSocket.periksa(client, 'display');
      } catch (error) {
        next(new Error(error instanceof Error ? error.message : 'UNAUTHORIZED'));
        return;
      }
      void this.akses
        .autentikasi(client.handshake.auth?.token ?? cookieToken(client.handshake.headers.cookie), client.handshake.auth?.layananId)
        .then((identitas) => {
          client.data.display = identitas;
          next();
        })
        .catch(() => next(new Error('UNAUTHORIZED')));
    });
  }

  async handleConnection(client: Socket): Promise<void> {
    const identitas = this.ambilIdentitas(client);
    if (!identitas) {
      client.disconnect(true);
      return;
    }
    try {
      if (!(await this.akses.masihBerwenang(identitas))) {
        client.disconnect(true);
        return;
      }
      await client.join(this.namaRoom(identitas.layananId));
      const siap: DisplayReadyEvent = { versiSkema: 1, layananId: identitas.layananId };
      client.emit('display:ready', siap);
    } catch {
      client.disconnect(true);
    }
  }

  /** Event minimal: tidak mengandung tiketId, pengguna, QR, atau token. */
  async broadcastPerubahan(event: QueueUpdatedEvent): Promise<void> {
    if (!this.server) return;
    const room = this.namaRoom(event.layananId);
    const pemberitahuan: DisplayUpdatedEvent = {
      versiSkema: 1,
      eventId: event.eventId,
      layananId: event.layananId,
      terjadiPada: event.terjadiPada,
      aksi: event.aksi,
      perluPeriksaPengumuman: event.aksi === 'CALL' || event.aksi === 'RECALL',
    };

    for (const client of this.server.sockets.values()) {
      if (!client.rooms.has(room)) continue;
      const identitas = this.ambilIdentitas(client);
      if (!identitas || identitas.layananId !== event.layananId) {
        await client.leave(room);
        client.disconnect(true);
        continue;
      }
      try {
        if (!(await this.akses.masihBerwenang(identitas))) {
          await client.leave(room);
          client.disconnect(true);
          continue;
        }
        client.emit('display:updated', pemberitahuan);
      } catch {
        await client.leave(room);
        client.disconnect(true);
        this.logger.warn('Broadcast display ditahan karena pemeriksaan akses gagal');
      }
    }
  }

  cabutPerangkat(perangkatId: string): void {
    for (const client of this.server?.sockets.values() ?? []) {
      if (this.ambilIdentitas(client)?.perangkatId === perangkatId) client.disconnect(true);
    }
  }

  private ambilIdentitas(client: Socket): IdentitasDisplay | null {
    const data: unknown = client.data.display;
    if (typeof data !== 'object' || data === null || Array.isArray(data)) return null;
    const identitas = data as Partial<IdentitasDisplay>;
    if (
      typeof identitas.perangkatId !== 'string' ||
      typeof identitas.layananId !== 'string' ||
      typeof identitas.tokenHash !== 'string'
    ) return null;
    return identitas as IdentitasDisplay;
  }

  private namaRoom(layananId: string): string {
    return `display:layanan:${layananId}`;
  }
}
