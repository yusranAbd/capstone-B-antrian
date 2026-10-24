import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import {
  OnGatewayConnection,
  OnGatewayDisconnect,
  OnGatewayInit,
  WebSocketGateway,
} from '@nestjs/websockets';
import { randomUUID } from 'node:crypto';
import type { Namespace, Socket } from 'socket.io';
import type { AccessTokenPayload } from '../auth/auth.types';
import { JwtStrategy } from '../auth/jwt.strategy';
import { keamananHandshakeSocket } from '../config/socket-handshake-security';
import { PrismaService } from '../prisma/prisma.service';
import { waktuPelayanan } from '../hospital/hospital-context';

type Identity = { id: string; sid: string; exp: number };
/** No subscription messages and no staff rooms. Scope is recomputed from DB before emitting. */
@Injectable()
@WebSocketGateway({ namespace: '/doctor' })
export class DoctorRealtimeGateway
  implements OnGatewayInit<Namespace>, OnGatewayConnection, OnGatewayDisconnect
{
  private server?: Namespace;
  private readonly expiry = new Map<string, ReturnType<typeof setTimeout>>();
  private readonly logger = new Logger(DoctorRealtimeGateway.name);
  constructor(
    private readonly jwt: JwtService,
    private readonly config: ConfigService,
    private readonly strategy: JwtStrategy,
    private readonly prisma: PrismaService,
  ) {}
  afterInit(server: Namespace) {
    this.server = server;
    server.use((client, next) => {
      try {
        keamananHandshakeSocket.periksa(client, 'doctor');
      } catch {
        next(new Error('UNAUTHORIZED'));
        return;
      }
      void this.authenticate(client)
        .then(() => next())
        .catch(() => next(new Error('UNAUTHORIZED')));
    });
  }
  private async authenticate(client: Socket) {
    const token: unknown = client.handshake.auth?.token;
    if (typeof token !== 'string' || !token || token.length > 8192)
      throw Error('UNAUTHORIZED');
    const p = await this.jwt.verifyAsync<
      AccessTokenPayload & { exp: number; type?: unknown }
    >(token, { secret: this.config.getOrThrow<string>('JWT_ACCESS_SECRET') });
    if (
      p.type !== undefined ||
      !Number.isFinite(p.exp) ||
      p.exp * 1000 <= Date.now()
    )
      throw Error('UNAUTHORIZED');
    const u = await this.strategy.validate(p);
    if (u.peran !== 'DOKTER') throw Error('UNAUTHORIZED');
    client.data.doctorIdentity = {
      id: u.id,
      sid: p.sid,
      exp: p.exp,
    } satisfies Identity;
  }
  handleConnection(client: Socket) {
    const i = client.data.doctorIdentity as Identity | undefined;
    if (!i) {
      client.disconnect(true);
      return;
    }
    const timer = setTimeout(
      () => client.disconnect(true),
      Math.min(i.exp * 1000 - Date.now(), 2147483647),
    );
    timer.unref();
    this.expiry.set(client.id, timer);
    client.emit('doctor:ready', { versiSkema: 1 });
  }
  handleDisconnect(client: Socket) {
    clearTimeout(this.expiry.get(client.id));
    this.expiry.delete(client.id);
  }
  /** Post-commit only. Payload never includes numbers, IDs or patient data. */
  async invalidateTicket(tiketId: string) {
    if (!this.server?.sockets.size) return;
    try {
      const now = new Date(),
        today = waktuPelayanan(now);
      const ticket = await this.prisma.tiketAntrean.findUnique({
        where: { id: tiketId },
        select: {
          layananId: true,
          loketId: true,
          tanggalAntrean: true,
          layanan: { select: { modeReservasi: true } },
          janjiTemu: {
            select: { slotPraktik: { select: { jadwalPraktikId: true } } },
          },
        },
      });
      if (
        !ticket ||
        ticket.tanggalAntrean.getTime() !== today.tanggalDb.getTime()
      )
        return;
      const harian = ticket.layanan.modeReservasi === 'ANTREAN_HARIAN';
      // Daily waiting has no assigned room. All live sessions in this clinic
      // must refresh when the shared pool changes, including after CALL.
      if (!ticket.janjiTemu && !ticket.loketId && !harian) return;
      const sessions = await this.prisma.jadwalPraktik.findMany({
        where: {
          ...(ticket.janjiTemu
            ? { id: ticket.janjiTemu.slotPraktik.jadwalPraktikId }
            : harian
              ? {}
              : { loketId: ticket.loketId! }),
          tanggal: today.tanggalDb,
          aktif: true,
          mulaiPada: { lte: now },
          selesaiPada: { gt: now },
          loket: { aktif: true, layananId: ticket.layananId },
          dokterLayanan: {
            aktif: true,
            layananId: ticket.layananId,
            layanan: {
              aktif: true,
              ...(!ticket.janjiTemu
                ? {
                    modeReservasi: {
                      in: ['HIBRIDA' as const, 'ANTREAN_HARIAN' as const],
                    },
                  }
                : {}),
            },
            dokter: { aktif: true, pengguna: { aktif: true, peran: 'DOKTER' } },
          },
        },
        select: {
          dokterLayanan: {
            select: { dokter: { select: { penggunaId: true } } },
          },
        },
      });
      const owners = new Set(
        sessions.map((s) => s.dokterLayanan.dokter.penggunaId),
      );
      const clients = [...this.server.sockets.values()].filter((c) =>
        owners.has((c.data.doctorIdentity as Identity | undefined)?.id ?? null),
      );
      const event = {
        versiSkema: 1,
        eventId: randomUUID(),
        jenis: 'ANTREAN',
        terjadiPada: now.toISOString(),
      };
      for (const c of clients) {
        const i = c.data.doctorIdentity as Identity;
        // Recheck session, role, account and linked profile; never trust handshake forever.
        const valid = await this.prisma.sesiPengguna.findFirst({
          where: {
            id: i.sid,
            penggunaId: i.id,
            dicabutPada: null,
            kedaluwarsaPada: { gt: new Date() },
            pengguna: { aktif: true, peran: 'DOKTER', dokter: { aktif: true } },
          },
          select: { id: true },
        });
        if (!valid || i.exp * 1000 <= Date.now()) c.disconnect(true);
        else c.emit('doctor:updated', event);
      }
    } catch {
      this.logger.warn(
        'Invalidasi dokter gagal; REST tetap menjadi sumber data',
      );
    }
  }
}
