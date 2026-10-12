import type { Namespace, Socket } from 'socket.io';
import { DisplayRealtimeAccessService, type IdentitasDisplay } from './display-realtime-access.service';
import { DisplayRealtimeGateway } from './display-realtime.gateway';
import type { QueueUpdatedEvent } from './realtime-events.types';

const layananId = '00000000-0000-4000-8000-000000000001';
const otherId = '00000000-0000-4000-8000-000000000009';
const identitas: IdentitasDisplay = {
  perangkatId: '00000000-0000-4000-8000-000000000002', layananId, tokenHash: 'a'.repeat(64),
};
const event: QueueUpdatedEvent = {
  versiSkema: 1,
  eventId: '00000000-0000-4000-8000-000000000003',
  terjadiPada: '2026-10-12T02:00:00.000Z',
  aksi: 'CALL', layananId,
  tiketId: '00000000-0000-4000-8000-000000000004',
  nomorAntrean: 'A-025', status: 'DIPANGGIL',
};

describe('DisplayRealtimeGateway', () => {
  const autentikasi = jest.fn();
  const masihBerwenang = jest.fn();
  let gateway: DisplayRealtimeGateway;
  let middleware: ((socket: Socket, next: (error?: Error) => void) => void) | undefined;

  function buatClient(layanan: string = layananId, joined = true) {
    const emit = jest.fn();
    const disconnect = jest.fn();
    const join = jest.fn().mockResolvedValue(undefined);
    const leave = jest.fn().mockResolvedValue(undefined);
    const client = {
      id: 'socket-uji',
      data: { display: { ...identitas, layananId: layanan } },
      handshake: { auth: { token: 'a'.repeat(64), layananId: layanan } },
      rooms: new Set(joined ? [`display:layanan:${layanan}`] : []),
      emit, disconnect, join, leave,
    } as unknown as Socket;
    return { client, emit, disconnect, join, leave };
  }

  function aktifkan(...clients: Socket[]): void {
    const use = jest.fn((fn: typeof middleware) => { middleware = fn; });
    gateway.afterInit({
      use,
      sockets: new Map(clients.map((client) => [client.id, client])),
    } as unknown as Namespace);
  }

  beforeEach(() => {
    jest.clearAllMocks();
    middleware = undefined;
    autentikasi.mockResolvedValue(identitas);
    masihBerwenang.mockResolvedValue(true);
    gateway = new DisplayRealtimeGateway({
      autentikasi, masihBerwenang,
    } as unknown as DisplayRealtimeAccessService);
  });

  it('menolak koneksi jika middleware gagal memverifikasi token', async () => {
    autentikasi.mockRejectedValueOnce(new Error('UNAUTHORIZED'));
    const a = buatClient();
    aktifkan(a.client);
    const next = jest.fn();
    middleware?.(a.client, next);
    await Promise.resolve();
    await Promise.resolve();
    expect(next).toHaveBeenCalledWith(expect.objectContaining({ message: 'UNAUTHORIZED' }));
  });

  it('menempatkan perangkat sah ke room sendiri lalu mengirim display:ready', async () => {
    const a = buatClient();
    await gateway.handleConnection(a.client);
    expect(a.join).toHaveBeenCalledWith(`display:layanan:${layananId}`);
    expect(a.emit).toHaveBeenCalledWith('display:ready', { versiSkema: 1, layananId });
  });

  it('memutus perangkat yang dicabut sebelum bergabung', async () => {
    masihBerwenang.mockResolvedValueOnce(false);
    const a = buatClient();
    await gateway.handleConnection(a.client);
    expect(a.disconnect).toHaveBeenCalledWith(true);
    expect(a.join).not.toHaveBeenCalled();
  });

  it('mengirim display:updated minimal ke room yang berwenang', async () => {
    const a = buatClient();
    aktifkan(a.client);
    await gateway.broadcastPerubahan(event);
    expect(a.emit).toHaveBeenCalledWith('display:updated', {
      versiSkema: 1, eventId: event.eventId, terjadiPada: event.terjadiPada,
      layananId, aksi: 'CALL', perluPeriksaPengumuman: true,
    });
    const payload: unknown = a.emit.mock.calls[0]?.[1];
    expect(JSON.stringify(payload)).not.toContain(event.tiketId);
    expect(JSON.stringify(payload)).not.toContain(event.nomorAntrean);
  });

  it('tidak mengirim ke perangkat dari layanan lain', async () => {
    const a = buatClient(otherId);
    aktifkan(a.client);
    await gateway.broadcastPerubahan(event);
    expect(a.emit).not.toHaveBeenCalled();
    expect(masihBerwenang).not.toHaveBeenCalled();
  });

  it('tidak mengirim ke perangkat yang belum masuk room', async () => {
    const a = buatClient(layananId, false);
    aktifkan(a.client);
    await gateway.broadcastPerubahan(event);
    expect(a.emit).not.toHaveBeenCalled();
  });

  it('memutus perangkat yang dicabut ketika akan mengirim', async () => {
    masihBerwenang.mockResolvedValueOnce(false);
    const a = buatClient();
    aktifkan(a.client);
    await gateway.broadcastPerubahan(event);
    expect(a.emit).not.toHaveBeenCalled();
    expect(a.leave).toHaveBeenCalledWith(`display:layanan:${layananId}`);
    expect(a.disconnect).toHaveBeenCalledWith(true);
  });

  it('gagal tertutup saat database otorisasi tidak tersedia', async () => {
    masihBerwenang.mockRejectedValueOnce(new Error('DB error'));
    const a = buatClient();
    aktifkan(a.client);
    await expect(gateway.broadcastPerubahan(event)).resolves.toBeUndefined();
    expect(a.emit).not.toHaveBeenCalled();
    expect(a.disconnect).toHaveBeenCalledWith(true);
  });

  it('tidak meminta pengumuman TTS untuk operasi COMPLETE', async () => {
    const a = buatClient();
    aktifkan(a.client);
    await gateway.broadcastPerubahan({ ...event, aksi: 'COMPLETE' });
    expect(a.emit).toHaveBeenCalledWith('display:updated', expect.objectContaining({
      aksi: 'COMPLETE', perluPeriksaPengumuman: false,
    }));
  });
});
