import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { Prisma, StatusTiket } from '../generated/prisma/client';
import { waktuPelayanan } from '../hospital/hospital-context';
import { PrismaService } from '../prisma/prisma.service';
import {
  PatientQueueQueryDto,
  validPatientQueueDate,
} from './dto/patient-queue-query.dto';

/** Public queue numbers and aggregates only, never ticket/person records. */
@Injectable()
export class PatientQueueSummaryService {
  constructor(private readonly prisma: PrismaService) {}

  async snapshot(query: PatientQueueQueryDto) {
    const tanggalPelayanan =
      query.tanggal ?? waktuPelayanan(new Date()).tanggal;
    if (!validPatientQueueDate(tanggalPelayanan))
      throw new BadRequestException('Tanggal pelayanan tidak valid.');
    const tanggalAntrean = new Date(tanggalPelayanan + 'T00:00:00.000Z');
    return this.prisma.$transaction(
      async (tx) => {
        const layanan = await tx.layanan.findMany({
          where: {
            aktif: true,
            ...(query.layananId ? { id: { in: query.layananId } } : {}),
          },
          select: { id: true, prefixAntrean: true },
          orderBy: { kode: 'asc' },
        });
        if (query.layananId && layanan.length !== query.layananId.length) {
          throw new NotFoundException('Layanan tidak tersedia.');
        }
        const where = {
          layananId: { in: layanan.map((l) => l.id) },
          tanggalAntrean,
        };
        const [checked, waiting, serving] = await Promise.all([
          // One row per ticket PK, no joins: retries/events cannot duplicate count.
          tx.tiketAntrean.groupBy({
            by: ['layananId'],
            where: { ...where, checkInPada: { not: null } },
            _count: { _all: true },
          }),
          tx.tiketAntrean.groupBy({
            by: ['layananId'],
            where: {
              ...where,
              status: StatusTiket.MENUNGGU,
              checkInPada: { not: null },
              urutanMasukAntrean: { not: null },
            },
            _count: { _all: true },
          }),
          tx.tiketAntrean.findMany({
            where: {
              ...where,
              status: StatusTiket.DILAYANI,
              checkInPada: { not: null },
              loket: { is: { aktif: true } },
            },
            select: {
              layananId: true,
              nomorUrut: true,
              loket: { select: { id: true, kode: true, layananId: true } },
            },
            orderBy: [{ loketId: 'asc' }, { id: 'asc' }],
          }),
        ]);
        const totals = new Map(
          checked.map((r) => [r.layananId, r._count._all]),
        );
        const waits = new Map(waiting.map((r) => [r.layananId, r._count._all]));
        const prefixes = new Map(
          layanan.map((l) => [l.id, l.prefixAntrean.trim()]),
        );
        const active = new Map<
          string,
          Array<{ loketId: string; kodeLoket: string; nomorAntrean: string }>
        >();
        for (const ticket of serving) {
          if (!ticket.loket || ticket.loket.layananId !== ticket.layananId)
            continue;
          const numbers = active.get(ticket.layananId) ?? [];
          numbers.push({
            loketId: ticket.loket.id,
            kodeLoket: ticket.loket.kode,
            nomorAntrean: `${prefixes.get(ticket.layananId)}-${String(ticket.nomorUrut).padStart(3, '0')}`,
          });
          active.set(ticket.layananId, numbers);
        }
        return {
          versiSkema: 1 as const,
          tanggalPelayanan,
          diperolehPada: new Date().toISOString(),
          layanan: layanan.map((l) => ({
            layananId: l.id,
            totalCheckIn: totals.get(l.id) ?? 0,
            jumlahMenunggu: waits.get(l.id) ?? 0,
            sedangDilayani: active.get(l.id) ?? [],
          })),
        };
      },
      {
        isolationLevel: Prisma.TransactionIsolationLevel.RepeatableRead,
        maxWait: 3000,
        timeout: 10000,
      },
    );
  }
}
