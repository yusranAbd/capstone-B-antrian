import {
  CallHandler,
  ExecutionContext,
  Injectable,
  Logger,
  NestInterceptor,
} from '@nestjs/common';
import { PATH_METADATA } from '@nestjs/common/constants';
import type { Request } from 'express';
import { concatMap, type Observable } from 'rxjs';
import type { AuthenticatedUser } from '../auth/auth.types';
import { PeranPengguna } from '../generated/prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { PatientRealtimeGateway } from './patient-realtime.gateway';

const catalogControllers = new Set([
  'layanan',
  'dokter',
  'loket',
  'jadwal-layanan',
  'jadwal-praktik',
  'slot-praktik',
]);

/** HTTP success is downstream of the existing transaction; errors emit nothing.
 * Explicit controller whitelist avoids broadcasting unrelated writes or secrets.
 * Services/transaction rules and public REST responses are unchanged.
 */
@Injectable()
export class PatientInvalidationInterceptor implements NestInterceptor {
  private readonly logger = new Logger(PatientInvalidationInterceptor.name);
  constructor(
    private readonly gateway: PatientRealtimeGateway,
    private readonly prisma: PrismaService,
  ) {}
  intercept(context: ExecutionContext, next: CallHandler): Observable<unknown> {
    if (context.getType() !== 'http') return next.handle();
    const request = context
      .switchToHttp()
      .getRequest<Request & { user?: AuthenticatedUser }>();
    if (!['POST', 'PATCH', 'DELETE'].includes(request.method))
      return next.handle();
    const controller = Reflect.getMetadata(
      PATH_METADATA,
      context.getClass(),
    ) as string;
    if (
      !catalogControllers.has(controller) &&
      !['reservasi', 'janji-temu', 'queue', 'check-in'].includes(controller)
    )
      return next.handle();
    return next.handle().pipe(
      concatMap(async (result: unknown) => {
        try {
          if (
            catalogControllers.has(controller) &&
            request.user?.peran === PeranPengguna.ADMIN
          ) {
            await this.gateway.invalidate('KATALOG');
          } else if (
            ['reservasi', 'janji-temu'].includes(controller) &&
            request.user?.peran === PeranPengguna.USER
          ) {
            await this.gateway.invalidate('TIKET', request.user.id);
            await this.gateway.invalidate('KATALOG');
          } else if (
            ['queue', 'check-in'].includes(controller) &&
            request.user?.peran === PeranPengguna.PETUGAS
          ) {
            const data = result as { tiketId?: string } | null;
            if (typeof data?.tiketId === 'string') {
              const ticket = await this.prisma.tiketAntrean.findUnique({
                where: { id: data.tiketId },
                select: { penggunaId: true },
              });
              if (ticket)
                await this.gateway.invalidate('TIKET', ticket.penggunaId);
            }
          }
        } catch {
          this.logger.warn(
            'Invalidasi pasien gagal; transaksi tetap tersimpan dan REST tetap tersedia',
          );
        }
        return result;
      }),
    );
  }
}
