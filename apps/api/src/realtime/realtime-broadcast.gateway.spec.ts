import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import type { Namespace, Socket } from 'socket.io';

import { JwtStrategy } from '../auth/jwt.strategy';
import { PeranPengguna } from '../generated/prisma/client';
import { RealtimeGateway } from './realtime.gateway';
import { RealtimeRoomAccessService } from './realtime-room-access.service';
import type { QueueUpdatedEvent } from './realtime-events.types';

const layananId = 'd9b27074-2d19-4434-b535-786b4f18a7fa';
const payload: QueueUpdatedEvent = {
  eventId: '70b028ab-01a6-4db9-9d20-ae595354694a',
  versiSkema: 1,
  terjadiPada: new Date().toISOString(),
  aksi: 'CALL',
  tiketId: '00000000-0000-4000-8000-000000000101',
  layananId,
  nomorAntrean: 'A-001',
  status: 'DIPANGGIL',
};

describe('RealtimeGateway - broadcast dan revalidasi penerima', () => {
  const periksa = jest.fn();
  let gateway: RealtimeGateway;
  const room = `layanan:${layananId}`;

  function socket(id: string, termasukRoom: boolean) {
    const emit = jest.fn();
    const leave = jest.fn().mockResolvedValue(undefined);
    const disconnect = jest.fn();
    const client = {
      id,
      rooms: new Set(termasukRoom ? [room] : []),
      data: { authenticatedUser: {
        id,
        sid: 'sesi-uji',
        peran: PeranPengguna.PETUGAS,
        exp: Math.floor(Date.now() / 1000) + 3600,
      } },
      emit, leave, disconnect,
    } as unknown as Socket;
    return { client, emit, leave, disconnect };
  }

  beforeEach(() => {
    jest.clearAllMocks();
    periksa.mockResolvedValue('ALLOWED');
    gateway = new RealtimeGateway(
      {} as JwtService,
      {} as ConfigService,
      {} as JwtStrategy,
      { periksa } as unknown as RealtimeRoomAccessService,
    );
  });

  function aktifkan(...clients: Socket[]) {
    const use = jest.fn();
    gateway.afterInit({ use, sockets: new Map(clients.map((client) => [client.id, client])) } as unknown as Namespace);
  }

  it('mengirim event hanya ke anggota room yang masih sah', async () => {
    const a = socket('petugas-1', true);
    const b = socket('petugas-2', false);
    aktifkan(a.client, b.client);
    await gateway.broadcastPerubahan(payload);
    expect(a.emit).toHaveBeenCalledWith('queue:updated', payload);
    expect(b.emit).not.toHaveBeenCalled();
    expect(periksa).toHaveBeenCalledTimes(1);
  });

  it('menahan event ketika penugasan telah dicabut', async () => {
    const a = socket('petugas-1', true);
    periksa.mockResolvedValue('FORBIDDEN');
    aktifkan(a.client);
    await gateway.broadcastPerubahan(payload);
    expect(a.emit).not.toHaveBeenCalled();
    expect(a.leave).toHaveBeenCalledWith(room);
    expect(a.disconnect).not.toHaveBeenCalled();
  });

  it('memutus socket dengan sesi yang dicabut', async () => {
    const a = socket('petugas-1', true);
    periksa.mockResolvedValue('UNAUTHORIZED');
    aktifkan(a.client);
    await gateway.broadcastPerubahan(payload);
    expect(a.emit).not.toHaveBeenCalled();
    expect(a.leave).toHaveBeenCalledWith(room);
    expect(a.disconnect).toHaveBeenCalledWith(true);
  });

  it('gagal tertutup saat database otorisasi bermasalah', async () => {
    const a = socket('petugas-1', true);
    periksa.mockRejectedValue(new Error('database tidak tersedia'));
    aktifkan(a.client);
    await expect(gateway.broadcastPerubahan(payload)).resolves.toBeUndefined();
    expect(a.emit).not.toHaveBeenCalled();
    expect(a.leave).toHaveBeenCalledWith(room);
  });
});
