import {
  CallHandler,
  ExecutionContext,
  Injectable,
  NestInterceptor,
} from '@nestjs/common';
import { PATH_METADATA } from '@nestjs/common/constants';
import type { Request } from 'express';
import { concatMap } from 'rxjs';
import { DoctorRealtimeGateway } from './doctor-realtime.gateway';
/** Appointment booking/cancellation and CHECK_IN also invalidate the authorized live session. */
@Injectable()
export class DoctorInvalidationInterceptor implements NestInterceptor {
  constructor(private readonly gateway: DoctorRealtimeGateway) {}
  intercept(context: ExecutionContext, next: CallHandler) {
    if (context.getType() !== 'http') return next.handle();
    const req = context.switchToHttp().getRequest<Request>();
    const controller = Reflect.getMetadata(
      PATH_METADATA,
      context.getClass(),
    ) as string;
    if (
      req.method !== 'POST' ||
      !['janji-temu', 'check-in'].includes(controller)
    )
      return next.handle();
    return next.handle().pipe(
      concatMap(async (data: unknown) => {
        const r = data as { tiketId?: string; tiket?: { id?: string } } | null;
        const id = r?.tiketId ?? r?.tiket?.id;
        if (id) await this.gateway.invalidateTicket(id);
        return data;
      }),
    );
  }
}
