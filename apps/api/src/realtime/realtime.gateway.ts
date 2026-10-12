import { OnGatewayConnection, WebSocketGateway } from '@nestjs/websockets';
import type { Socket } from 'socket.io';

/**
 * Fondasi namespace realtime antrean.
 *
 * SENGAJA MENOLAK semua koneksi pada milestone 01G-E.1-B.
 * JWT dan otorisasi room akan diterapkan pada 01G-E.1-C/1-D.
 * Tidak ada broadcast sebelum otorisasi selesai.
 */
@WebSocketGateway({ namespace: '/queue' })
export class RealtimeGateway implements OnGatewayConnection {
  handleConnection(client: Socket): void {
    client.disconnect(true);
  }
}
