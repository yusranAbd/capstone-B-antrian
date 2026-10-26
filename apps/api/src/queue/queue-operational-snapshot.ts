import { BadRequestException } from '@nestjs/common';
import { Prisma, StatusTiket } from '../generated/prisma/client';
import type {
  SnapshotTiketMenunggu,
  SnapshotPasien,
} from './queue-snapshot.types';

// Called only inside the authorized PETUGAS snapshot transaction. Never broadcast PII.
const identitas = {
  id: true,
  nomorUrut: true,
  status: true,
  loketId: true,
  checkInPada: true,
  pengguna: { select: { nama: true } },
} as const;

export async function bacaPasienOperasional(
  tx: Prisma.TransactionClient,
  layananId: string,
  loketId: string,
  tanggal: Date,
  menunggu: SnapshotTiketMenunggu[],
  totalMenunggu: number,
  aktifIds: string[],
  prefix: string,
  halaman = 1,
) {
  if (!Number.isSafeInteger(halaman) || halaman < 1 || (halaman - 1) * 100 > 2_147_483_647)
    throw new BadRequestException('halamanTindakLanjut minimal 1');
  const scope = { layananId, tanggalAntrean: tanggal };
  const tindakLanjut: Prisma.TiketAntreanWhereInput = {
    ...scope,
    OR: [
      { status: StatusTiket.DILEWATI },
      {
        status: StatusTiket.CHECK_IN,
        OR: [
          { janjiTemu: { is: null } },
          {
            janjiTemu: { is: { slotPraktik: { jadwalPraktik: { loketId } } } },
          },
        ],
      },
    ],
  };
  const [pasien, lanjutan, total] = await Promise.all([
    tx.tiketAntrean.findMany({
      where: {
        ...scope,
        id: { in: [...menunggu.map((t) => t.tiketId), ...aktifIds] },
      },
      select: identitas,
    }),
    tx.tiketAntrean.findMany({
      where: tindakLanjut,
      select: identitas,
      orderBy: [{ checkInPada: 'asc' }, { id: 'asc' }],
      take: 100,
      skip: (halaman - 1) * 100,
    }),
    tx.tiketAntrean.count({ where: tindakLanjut }),
  ]);
  const nama = new Map(pasien.map((t) => [t.id, t]));
  const data = (t: (typeof pasien)[number] | undefined) => ({
    namaPasien: t?.pengguna.nama ?? null,
    checkInPada: t?.checkInPada?.toISOString() ?? null,
    loketId: t?.loketId ?? null,
  });
  const tiket: SnapshotPasien[] = [
    // Keep the exact queue selector order. The following groups are display-only.
    ...menunggu.map((t) => ({ ...t, ...data(nama.get(t.tiketId)) })),
    ...lanjutan.map((t) => ({
      tiketId: t.id,
      nomorAntrean: `${prefix.trim()}-${String(t.nomorUrut).padStart(3, '0')}`,
      status:
        t.status === StatusTiket.CHECK_IN
          ? ('CHECK_IN' as const)
          : ('DILEWATI' as const),
      ...data(t),
      bisaAntreUlang:
        t.status === StatusTiket.DILEWATI && t.loketId === loketId,
      bisaMasukAntrean: t.status === StatusTiket.CHECK_IN,
    })),
  ];
  return {
    daftarPasien: {
      total: totalMenunggu + total,
      ditampilkan: tiket.length,
      halamanTindakLanjut: halaman,
      jumlahHalamanTindakLanjut: Math.max(1, Math.ceil(total / 100)),
      tiket,
    },
    nama,
  };
}
