import {
  ConflictException,
  Injectable,
  Logger,
  NotFoundException,
} from '@nestjs/common';
import { Prisma } from '../generated/prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { DisplayRealtimeGateway } from '../realtime/display-realtime.gateway';

export const DELETE_RESOURCES = {
  layanan: 'layanan',
  dokter: 'dokter',
  loket: 'loket',
  'jadwal-layanan': 'jadwal_layanan',
  'jadwal-praktik': 'jadwal_praktik',
  'slot-praktik': 'slot_praktik',
  'penugasan-petugas': 'penugasan_petugas',
  'perangkat-display': 'perangkat_tampilan',
} as const;
export type DeleteResource = keyof typeof DELETE_RESOURCES;
type Tx = Prisma.TransactionClient;

@Injectable()
export class AdminDeleteService {
  private readonly logger = new Logger('AdminDeleteAudit');
  constructor(
    private readonly prisma: PrismaService,
    private readonly display: DisplayRealtimeGateway,
  ) {}

  private blocked(alasan: string): never {
    throw new ConflictException({
      message: `${alasan}. Data tidak dihapus; gunakan Nonaktifkan.`,
      code: 'DATA_MASIH_DIGUNAKAN',
      alasan,
      bolehNonaktifkan: true,
    });
  }

  async remove(resource: DeleteResource, id: string, actorId: string) {
    // Table identifiers come exclusively from this server-side whitelist.
    const table = Prisma.raw(`"${DELETE_RESOURCES[resource]}"`);
    try {
      await this.prisma.$transaction(
        async (tx) => {
          await tx.$executeRaw`SET LOCAL lock_timeout = '5s'`;
          // These configurations have indirect operational references, without a FK.
          // Exclusive table locks wait for existing transactional readers and prevent
          // new ones until reference checks and deletion commit together.
          if (
            resource === 'jadwal-layanan' ||
            resource === 'penugasan-petugas'
          ) {
            await tx.$executeRaw(
              Prisma.sql`LOCK TABLE ${table} IN ACCESS EXCLUSIVE MODE`,
            );
          }
          const found = await tx.$queryRaw<{ id: string }[]>(
            Prisma.sql`SELECT id FROM ${table} WHERE id = ${id}::uuid FOR UPDATE`,
          );
          if (!found.length)
            throw new NotFoundException(
              'Data tidak ditemukan atau sudah dihapus',
            );
          await this.checkReferences(tx, resource, id);
          await tx.$executeRaw(
            Prisma.sql`DELETE FROM ${table} WHERE id = ${id}::uuid`,
          );
        },
        {
          isolationLevel: Prisma.TransactionIsolationLevel.Serializable,
          maxWait: 5000,
          timeout: 10000,
        },
      );
    } catch (error: unknown) {
      const code =
        typeof error === 'object' && error !== null && 'code' in error
          ? String(error.code)
          : '';
      const meta =
        typeof error === 'object' && error !== null && 'meta' in error
          ? (
              error as {
                meta?: {
                  code?: string;
                  driverAdapterError?: {
                    cause?: { originalCode?: string; code?: string };
                  };
                };
              }
            ).meta
          : undefined;
      const sqlCode =
        meta?.code ??
        meta?.driverAdapterError?.cause?.originalCode ??
        meta?.driverAdapterError?.cause?.code;
      if (code === 'P2003' || sqlCode === '23503')
        this.blocked('Data masih memiliki referensi yang digunakan');
      if (
        ['P2034', 'P2028'].includes(code) ||
        ['40001', '40P01', '55P03'].includes(sqlCode ?? '')
      ) {
        throw new ConflictException({
          message:
            'Data sedang berubah atau digunakan oleh permintaan lain. Muat ulang dan coba lagi; gunakan Nonaktifkan bila data masih diperlukan.',
          code: 'KONFLIK_PERUBAHAN',
        });
      }
      throw error;
    }
    // Only after commit: deleted credentials can no longer authenticate; disconnect
    // sockets using the existing revocation mechanism. No token is returned/logged.
    if (resource === 'perangkat-display') this.display.cabutPerangkat(id);
    this.logger.log(
      JSON.stringify({
        aksi: 'HAPUS_PERMANEN',
        resource,
        id,
        aktorId: actorId,
        terjadiPada: new Date().toISOString(),
      }),
    );
    return { id, dihapus: true };
  }

  private async checkReferences(tx: Tx, resource: DeleteResource, id: string) {
    switch (resource) {
      case 'layanan': {
        if (await tx.tiketAntrean.count({ where: { layananId: id } }))
          this.blocked(
            'Poliklinik sudah memiliki tiket atau riwayat pelayanan',
          );
        if (await tx.urutanAntreanHarian.count({ where: { layananId: id } }))
          this.blocked('Poliklinik sudah memiliki riwayat nomor antrean');
        if (await tx.loket.count({ where: { layananId: id } }))
          this.blocked('Poliklinik masih memiliki ruang/loket');
        if (await tx.jadwalLayanan.count({ where: { layananId: id } }))
          this.blocked('Poliklinik masih memiliki jam dan kapasitas');
        if (await tx.dokterLayanan.count({ where: { layananId: id } }))
          this.blocked('Poliklinik masih terhubung dengan dokter');
        if (await tx.perangkatTampilan.count({ where: { layananId: id } }))
          this.blocked('Poliklinik masih memiliki perangkat display');
        break;
      }
      case 'dokter': {
        const dokter = await tx.dokter.findUniqueOrThrow({
          where: { id },
          select: { penggunaId: true },
        });
        if (
          await tx.jadwalPraktik.count({
            where: { dokterLayanan: { dokterId: id } },
          })
        )
          this.blocked('Dokter sudah memiliki jadwal praktik atau appointment');
        if (dokter.penggunaId)
          this.blocked('Dokter sudah terhubung dengan akun pengguna');
        // Only unused configuration links, never schedules, appointments or users.
        await tx.dokterLayanan.deleteMany({ where: { dokterId: id } });
        break;
      }
      case 'loket': {
        if (await tx.tiketAntrean.count({ where: { loketId: id } }))
          this.blocked('Ruang/loket sudah memiliki tiket pelayanan');
        if (await tx.jadwalPraktik.count({ where: { loketId: id } }))
          this.blocked('Ruang/loket masih memiliki jadwal praktik');
        if (await tx.penugasanPetugas.count({ where: { loketId: id } }))
          this.blocked('Ruang/loket masih memiliki penugasan petugas');
        break;
      }
      case 'jadwal-layanan': {
        const row = await tx.jadwalLayanan.findUniqueOrThrow({
          where: { id },
          select: { layananId: true },
        });
        if (
          await tx.tiketAntrean.count({ where: { layananId: row.layananId } })
        )
          this.blocked(
            'Poliklinik pada jadwal ini sudah memiliki tiket pelayanan',
          );
        if (
          await tx.jadwalPraktik.count({
            where: { dokterLayanan: { layananId: row.layananId } },
          })
        )
          this.blocked(
            'Poliklinik pada jadwal ini sudah memiliki sesi praktik',
          );
        break;
      }
      case 'jadwal-praktik': {
        const row = await tx.jadwalPraktik.findUniqueOrThrow({
          where: { id },
          include: { dokterLayanan: { select: { layananId: true } } },
        });
        if (
          await tx.tiketAntrean.count({
            where: {
              layananId: row.dokterLayanan.layananId,
              tanggalAntrean: row.tanggal,
              OR: [{ loketId: row.loketId }, { loketId: null }],
            },
          })
        )
          this.blocked(
            'Sesi praktik sudah memiliki tiket pada tanggal dan ruang pelayanan',
          );
        if (
          await tx.janjiTemu.count({
            where: { slotPraktik: { jadwalPraktikId: id } },
          })
        )
          this.blocked(
            'Jadwal praktik sudah memiliki appointment, termasuk yang dibatalkan',
          );
        if (await tx.slotPraktik.count({ where: { jadwalPraktikId: id } }))
          this.blocked(
            'Jadwal praktik masih memiliki slot; hapus slot yang belum digunakan terlebih dahulu',
          );
        break;
      }
      case 'slot-praktik':
        if (await tx.janjiTemu.count({ where: { slotPraktikId: id } }))
          this.blocked(
            'Slot sudah memiliki appointment, termasuk yang dibatalkan',
          );
        break;
      case 'penugasan-petugas': {
        const row = await tx.penugasanPetugas.findUniqueOrThrow({
          where: { id },
        });
        if (
          await tx.tiketAntrean.count({
            where: {
              loketId: row.loketId,
              tanggalAntrean: {
                gte: row.tanggalMulai,
                ...(row.tanggalSelesai ? { lte: row.tanggalSelesai } : {}),
              },
            },
          })
        )
          this.blocked(
            'Ruang/loket sudah memiliki tiket dalam periode penugasan',
          );
        break;
      }
      case 'perangkat-display':
        break;
    }
  }
}
