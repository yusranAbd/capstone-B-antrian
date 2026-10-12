import { RealtimeBroadcastService } from '../realtime/realtime-broadcast.service';
import type { PrismaService } from '../prisma/prisma.service';
import { QueueService } from './queue.service';

/** Fokus pengujian: batas COMMIT -> notifikasi, tanpa mengulang fixture
 * State Machine dan transaksi yang sudah diuji di suite Queue Engine.
 */
describe('QueueService - broadcast sesudah commit', () => {
  const hasil = {
    tiketId: 'c4f2d963-7d32-4c82-a7dd-e4b16052e703',
    layananId: '409b34d0-6f8d-41f9-b1c9-01464571d6f1',
    loketId: '3b8cde33-439c-4483-a8b6-30aa1d52232f',
    kodeLoket: 'A1',
    nomorAntrean: 'A-001',
    status: 'DIPANGGIL',
    urutanMasukAntrean: 1,
    versi: 3,
  };
  const petugasId = '34554467-c6cb-4e59-9763-9481626dfda4';
  const operasi = [
    { aksi: 'ENQUEUE', jalankan: (service: QueueService) => service.masukAntrean(hasil.tiketId, petugasId, hasil.loketId) },
    { aksi: 'CALL', jalankan: (service: QueueService) => service.panggilBerikutnya(petugasId, hasil.loketId) },
    { aksi: 'RECALL', jalankan: (service: QueueService) => service.panggilUlang(hasil.tiketId, petugasId, hasil.loketId) },
    { aksi: 'SKIP', jalankan: (service: QueueService) => service.lewatiAntrean(hasil.tiketId, petugasId, hasil.loketId) },
    { aksi: 'REQUEUE', jalankan: (service: QueueService) => service.antreUlang(hasil.tiketId, petugasId, hasil.loketId) },
    { aksi: 'START', jalankan: (service: QueueService) => service.mulaiPelayanan(hasil.tiketId, petugasId, hasil.loketId) },
    { aksi: 'COMPLETE', jalankan: (service: QueueService) => service.selesaikanPelayanan(hasil.tiketId, petugasId, hasil.loketId) },
  ];

  const kirim = jest.fn().mockResolvedValue(undefined);
  const transaction = jest.fn().mockResolvedValue(hasil);
  let service: QueueService;

  beforeEach(() => {
    jest.clearAllMocks();
    transaction.mockResolvedValue(hasil);
    kirim.mockResolvedValue(undefined);
    service = new QueueService(
      { $transaction: transaction } as unknown as PrismaService,
      { kirim } as unknown as RealtimeBroadcastService,
    );
  });

  it.each(operasi)('$aksi hanya mengirim setelah transaction berhasil commit', async ({ aksi, jalankan }) => {
    let selesaikan!: (value: typeof hasil) => void;
    transaction.mockImplementationOnce(
      () => new Promise<typeof hasil>((resolve) => { selesaikan = resolve; }),
    );
    const proses = jalankan(service);
    expect(kirim).not.toHaveBeenCalled();
    selesaikan(hasil);
    await expect(proses).resolves.toEqual(hasil);
    expect(kirim).toHaveBeenCalledTimes(1);
    expect(kirim).toHaveBeenCalledWith(
      expect.objectContaining({
        aksi,
        layananId: hasil.layananId,
        tiketId: hasil.tiketId,
        nomorAntrean: hasil.nomorAntrean,
      }),
    );
  });

  it('tidak mengirim event ketika transaksi gagal', async () => {
    transaction.mockRejectedValueOnce(new Error('audit gagal'));
    await expect(operasi[1].jalankan(service)).rejects.toThrow('audit gagal');
    expect(kirim).not.toHaveBeenCalled();
  });

  it('kesalahan Socket.IO tidak membuat transaksi yang berhasil terlihat gagal', async () => {
    kirim.mockRejectedValueOnce(new Error('socket tidak tersedia'));
    await expect(operasi[1].jalankan(service)).resolves.toEqual(hasil);
    expect(kirim).toHaveBeenCalledTimes(1);
  });
});
