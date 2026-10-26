import { Prisma, StatusTiket } from '../generated/prisma/client';
import { bacaPasienOperasional } from './queue-operational-snapshot';

describe('Snapshot pasien PETUGAS V4', () => {
  const day = new Date('2026-10-27T00:00:00Z');
  const checked = new Date('2026-10-27T02:00:00Z');
  const waiting = [
    {
      tiketId: 'later',
      nomorAntrean: 'AN-009',
      status: 'MENUNGGU' as const,
      urutanMasukAntrean: 1,
      masukAntreanPada: checked.toISOString(),
      versi: 3,
    },
    {
      tiketId: 'earlier',
      nomorAntrean: 'AN-001',
      status: 'MENUNGGU' as const,
      urutanMasukAntrean: 2,
      masukAntreanPada: checked.toISOString(),
      versi: 3,
    },
  ];
  const person = (
    id: string,
    status: StatusTiket,
    room: string | null = null,
  ) => ({
    id,
    nomorUrut: 1,
    status,
    loketId: room,
    checkInPada: checked,
    pengguna: { nama: `Nama lengkap ${id}` },
  });
  function mock() {
    const findMany = jest
      .fn()
      .mockResolvedValueOnce([
        person('earlier', StatusTiket.MENUNGGU),
        person('later', StatusTiket.MENUNGGU),
        person('active', StatusTiket.DIPANGGIL, 'room'),
      ])
      .mockResolvedValueOnce([
        person('skip', StatusTiket.DILEWATI, 'room'),
        person('other-room', StatusTiket.DILEWATI, 'other'),
        person('check', StatusTiket.CHECK_IN),
      ]);
    return {
      tiketAntrean: { findMany, count: jest.fn().mockResolvedValue(3) },
    };
  }
  it('mempertahankan ranking selector dan identitas/check-in aktual; SKIP tidak masuk grup menunggu', async () => {
    const tx = mock();
    const before = JSON.stringify(waiting);
    const result = await bacaPasienOperasional(
      tx as unknown as Prisma.TransactionClient,
      'clinic',
      'room',
      day,
      waiting,
      12,
      ['active'],
      'AN',
    );
    expect(result.daftarPasien.tiket.map((t) => t.tiketId)).toEqual([
      'later',
      'earlier',
      'skip',
      'other-room',
      'check',
    ]);
    expect(result.daftarPasien.total).toBe(15);
    expect(result.daftarPasien.tiket[0]).toMatchObject({
      namaPasien: 'Nama lengkap later',
      checkInPada: checked.toISOString(),
    });
    expect(result.daftarPasien.tiket[2]).toMatchObject({
      status: 'DILEWATI',
      bisaAntreUlang: true,
    });
    expect(result.daftarPasien.tiket[3].bisaAntreUlang).toBe(false);
    expect(result.daftarPasien.tiket[4].bisaMasukAntrean).toBe(true);
    expect(result.nama.get('active')?.pengguna.nama).toBe(
      'Nama lengkap active',
    );
    expect(JSON.stringify(waiting)).toBe(before);
  });
  it('semua bacaan identitas dibatasi poliklinik/tanggal dan tidak membaca secret atau identitas tambahan', async () => {
    const tx = mock();
    await bacaPasienOperasional(
      tx as unknown as Prisma.TransactionClient,
      'clinic',
      'room',
      day,
      waiting,
      12,
      [],
      'AN',
    );
    for (const call of tx.tiketAntrean.findMany.mock.calls) {
      expect(call[0].where).toMatchObject({
        layananId: 'clinic',
        tanggalAntrean: day,
      });
      expect(call[0].select.pengguna).toEqual({ select: { nama: true } });
      expect(JSON.stringify(call)).not.toMatch(/token|email|kataSandi|nik/i);
    }
    expect(tx.tiketAntrean.findMany.mock.calls[1][0]).toMatchObject({
      take: 100,
      where: {
        OR: expect.arrayContaining([
          { status: StatusTiket.DILEWATI },
          {
            status: StatusTiket.CHECK_IN,
            OR: [
              { janjiTemu: { is: null } },
              {
                janjiTemu: {
                  is: { slotPraktik: { jadwalPraktik: { loketId: 'room' } } },
                },
              },
            ],
          },
        ]),
      },
    });
  });
  it('pagination memakai skip terbatas; nilai halaman invalid ditolak', async () => {
    const tx = mock();
    tx.tiketAntrean.count.mockResolvedValue(203);
    const result = await bacaPasienOperasional(
      tx as unknown as Prisma.TransactionClient,
      'clinic',
      'room',
      day,
      waiting,
      12,
      [],
      'AN',
      2,
    );
    expect(tx.tiketAntrean.findMany.mock.calls[1][0]).toMatchObject({
      take: 100,
      skip: 100,
    });
    expect(result.daftarPasien).toMatchObject({
      halamanTindakLanjut: 2,
      jumlahHalamanTindakLanjut: 3,
    });
    for (const page of [0, -1, Number.MAX_SAFE_INTEGER])
      await expect(
        bacaPasienOperasional(
          tx as unknown as Prisma.TransactionClient,
          'clinic',
          'room',
          day,
          waiting,
          12,
          [],
          'AN',
          page,
        ),
      ).rejects.toThrow('halamanTindakLanjut');
    expect(tx.tiketAntrean.findMany).toHaveBeenCalledTimes(2);
  });
});
