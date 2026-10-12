import { RealtimeBroadcastService } from './realtime-broadcast.service';
import { RealtimeGateway } from './realtime.gateway';
import { DisplayRealtimeGateway } from './display-realtime.gateway';

describe('RealtimeBroadcastService - dua kanal independen', () => {
  const input = {
    aksi: 'CALL' as const,
    layananId: '00000000-0000-4000-8000-000000000001',
    tiketId: '00000000-0000-4000-8000-000000000002',
    nomorAntrean: 'A-025',
    status: 'DIPANGGIL',
  };

  it('mengirim event identik ke kanal petugas dan display', async () => {
    const broadcastOperasional = jest.fn().mockResolvedValue(undefined);
    const broadcastDisplay = jest.fn().mockResolvedValue(undefined);
    const service = new RealtimeBroadcastService(
      { broadcastPerubahan: broadcastOperasional } as unknown as RealtimeGateway,
      { broadcastPerubahan: broadcastDisplay } as unknown as DisplayRealtimeGateway,
    );
    await service.kirim(input);
    expect(broadcastOperasional).toHaveBeenCalledTimes(1);
    expect(broadcastDisplay).toHaveBeenCalledWith(broadcastOperasional.mock.calls[0]?.[0]);
  });

  it('kegagalan display tidak mengganggu kanal petugas', async () => {
    const broadcastOperasional = jest.fn().mockResolvedValue(undefined);
    const broadcastDisplay = jest.fn().mockRejectedValue(new Error('display sedang mati'));
    const service = new RealtimeBroadcastService(
      { broadcastPerubahan: broadcastOperasional } as unknown as RealtimeGateway,
      { broadcastPerubahan: broadcastDisplay } as unknown as DisplayRealtimeGateway,
    );
    await expect(service.kirim(input)).resolves.toBeUndefined();
    expect(broadcastOperasional).toHaveBeenCalledTimes(1);
  });

  it('kegagalan kanal petugas tetap meneruskan display dan diteruskan kepada QueueService', async () => {
    const broadcastOperasional = jest.fn().mockRejectedValue(new Error('gagal petugas'));
    const broadcastDisplay = jest.fn().mockResolvedValue(undefined);
    const service = new RealtimeBroadcastService(
      { broadcastPerubahan: broadcastOperasional } as unknown as RealtimeGateway,
      { broadcastPerubahan: broadcastDisplay } as unknown as DisplayRealtimeGateway,
    );
    await expect(service.kirim(input)).rejects.toThrow('gagal petugas');
    expect(broadcastDisplay).toHaveBeenCalledTimes(1);
  });
});
