import { RealtimeBroadcastService } from './realtime-broadcast.service';
import { RealtimeGateway } from './realtime.gateway';

describe('RealtimeBroadcastService', () => {
  it('menambahkan metadata minimal dan eventId tanpa data pribadi', async () => {
    const broadcastPerubahan = jest.fn().mockResolvedValue(undefined);
    const service = new RealtimeBroadcastService(
      { broadcastPerubahan } as unknown as RealtimeGateway,
    );
    await service.kirim({
      aksi: 'CALL',
      layananId: 'bd284582-b62a-477a-a064-33db214b1d02',
      tiketId: '8da2bf71-ef80-4a68-82e5-123bc62dfe19',
      nomorAntrean: 'A-003',
      status: 'DIPANGGIL',
      loketId: '09bbe25b-fd35-4355-a2d2-45a72e5c56b5',
    });
    expect(broadcastPerubahan).toHaveBeenCalledWith(expect.objectContaining({
      versiSkema: 1,
      aksi: 'CALL',
      nomorAntrean: 'A-003',
      eventId: expect.any(String),
      terjadiPada: expect.any(String),
    }));
    const first: unknown = broadcastPerubahan.mock.calls[0]?.[0];
    expect(JSON.stringify(first)).not.toContain('email');
    expect(JSON.stringify(first)).not.toContain('namaPengguna');
  });
});
