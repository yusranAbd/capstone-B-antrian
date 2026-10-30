import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import {
  OnGatewayConnection,
  OnGatewayDisconnect,
  OnGatewayInit,
  ConnectedSocket,
  MessageBody,
  SubscribeMessage,
  WebSocketGateway,
} from '@nestjs/websockets';
import { randomUUID } from 'node:crypto';
import type { Namespace, Socket } from 'socket.io';
import type { AccessTokenPayload } from '../auth/auth.types';
import { JwtStrategy } from '../auth/jwt.strategy';
import { keamananHandshakeSocket } from '../config/socket-handshake-security';
import { PeranPengguna } from '../generated/prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { validPatientQueueDate } from '../layanan/dto/patient-queue-query.dto';

type PatientIdentity = { id: string; sid: string; exp: number };
export type PatientInvalidation = {
  versiSkema: 1;
  eventId: string;
  jenis: 'TIKET' | 'KATALOG' | 'ANTREAN';
  terjadiPada: string;
  layananId?: string;
  tanggalPelayanan?: string;
};

/** Server-scoped subscriptions: no client-provided room, ticket or user ID. */
@Injectable()
@WebSocketGateway({ namespace: '/patient' })
export class PatientRealtimeGateway
  implements OnGatewayInit<Namespace>, OnGatewayConnection, OnGatewayDisconnect
{
  private server?: Namespace;
  private readonly expiry = new Map<string, ReturnType<typeof setTimeout>>();
  private readonly watchEpoch = new Map<string, number>();
  private readonly watchPending = new Map<string, Promise<unknown>>();
  private readonly logger = new Logger(PatientRealtimeGateway.name);
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
        keamananHandshakeSocket.periksa(client, 'patient');
      } catch (error) {
        next(
          new Error(error instanceof Error ? error.message : 'UNAUTHORIZED'),
        );
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
      throw new Error('UNAUTHORIZED');
    const payload = await this.jwt.verifyAsync<
      AccessTokenPayload & { exp: number; type?: unknown }
    >(token, {
      secret: this.config.getOrThrow<string>('JWT_ACCESS_SECRET'),
    });
    if (
      payload.type !== undefined ||
      !Number.isFinite(payload.exp) ||
      payload.exp * 1000 <= Date.now()
    )
      throw new Error('UNAUTHORIZED');
    const user = await this.strategy.validate(payload);
    if (user.peran !== PeranPengguna.USER) throw new Error('UNAUTHORIZED');
    client.data.patientIdentity = {
      id: user.id,
      sid: payload.sid,
      exp: payload.exp,
    } satisfies PatientIdentity;
  }

  handleConnection(client: Socket) {
    const identity = client.data.patientIdentity as PatientIdentity | undefined;
    if (!identity) {
      client.disconnect(true);
      return;
    }
    const timer = setTimeout(
      () => client.disconnect(true),
      Math.min(identity.exp * 1000 - Date.now(), 2_147_483_647),
    );
    timer.unref();
    this.expiry.set(client.id, timer);
    client.emit('patient:ready', { versiSkema: 1 });
  }

  handleDisconnect(client: Socket) {
    clearTimeout(this.expiry.get(client.id));
    this.expiry.delete(client.id);
    this.watchEpoch.delete(client.id);
    this.watchPending.delete(client.id);
  }

  @SubscribeMessage('patient:antrean:ikuti')
  async watchQueue(
    @ConnectedSocket() client: Socket,
    @MessageBody() value: unknown,
  ) {
    const epoch = (this.watchEpoch.get(client.id) ?? 0) + 1;
    this.watchEpoch.set(client.id, epoch);
    const pending = (this.watchPending.get(client.id) ?? Promise.resolve())
      .catch(() => undefined)
      .then(async () => {
        const denied = { ok: false, versiSkema: 1 };
        if (this.watchEpoch.get(client.id) !== epoch || !client.connected)
          return denied;
        const input = value as {
          layananIds?: unknown;
          tanggalPelayanan?: unknown;
        } | null;
        if (
          !input ||
          !Array.isArray(input.layananIds) ||
          input.layananIds.length > 100 ||
          !validPatientQueueDate(input.tanggalPelayanan) ||
          input.layananIds.some(
            (id) =>
              typeof id !== 'string' ||
              !/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
                id,
              ),
          ) ||
          new Set(input.layananIds).size !== input.layananIds.length
        )
          return denied;
        const ids = input.layananIds as string[],
          date = input.tanggalPelayanan;
        const identity = client.data.patientIdentity as
          PatientIdentity | undefined;
        if (!identity || identity.exp * 1000 <= Date.now()) {
          client.disconnect(true);
          return denied;
        }
        try {
          const session = await this.prisma.sesiPengguna.findFirst({
            where: {
              id: identity.sid,
              penggunaId: identity.id,
              dicabutPada: null,
              kedaluwarsaPada: { gt: new Date() },
              pengguna: { aktif: true, peran: PeranPengguna.USER },
            },
            select: { id: true },
          });
          if (!session) {
            client.disconnect(true);
            return denied;
          }
          const services = await this.prisma.layanan.findMany({
            where: { id: { in: ids }, aktif: true },
            select: { id: true },
          });
          if (
            services.length !== ids.length ||
            this.watchEpoch.get(client.id) !== epoch ||
            !client.connected
          )
            return denied;
          for (const room of client.rooms)
            if (room.startsWith('patient-antrean:')) await client.leave(room);
          const canonicalIds = services.map((service) => service.id);
          for (const id of canonicalIds)
            await client.join(this.queueRoom(id, date));
          return {
            ok: true,
            versiSkema: 1,
            layananIds: canonicalIds,
            tanggalPelayanan: date,
          };
        } catch {
          return denied;
        }
      });
    this.watchPending.set(client.id, pending);
    try {
      return await pending;
    } finally {
      if (this.watchPending.get(client.id) === pending)
        this.watchPending.delete(client.id);
    }
  }

  private queueRoom(service: string, date: string) {
    return `patient-antrean:${date}:${service}`;
  }

  /** After commit only. Membership and current USER session are both enforced. */
  async invalidateQueue(layananId: string, tanggalPelayanan: string) {
    if (!this.server || !validPatientQueueDate(tanggalPelayanan)) return;
    const room = this.queueRoom(layananId, tanggalPelayanan);
    const clients = [...this.server.sockets.values()].filter((c) =>
      c.rooms.has(room),
    );
    if (!clients.length) return;
    const active = await this.prisma.layanan.findFirst({
      where: { id: layananId, aktif: true },
      select: { id: true },
    });
    if (!active) return;
    await this.emitAuthorized(clients, {
      versiSkema: 1,
      eventId: randomUUID(),
      jenis: 'ANTREAN',
      terjadiPada: new Date().toISOString(),
      layananId,
      tanggalPelayanan,
    });
  }

  /** Called only after the HTTP operation has resolved (its DB transaction committed). */
  async invalidate(jenis: PatientInvalidation['jenis'], penggunaId?: string) {
    if (jenis === 'ANTREAN') return; // Use the validated service/date method.
    if (!this.server || (jenis === 'TIKET' && !penggunaId)) return;
    const event: PatientInvalidation = {
      versiSkema: 1,
      eventId: randomUUID(),
      jenis,
      terjadiPada: new Date().toISOString(),
    };
    const clients = [...this.server.sockets.values()].filter(
      (client) =>
        jenis === 'KATALOG' || client.data.patientIdentity?.id === penggunaId,
    );
    if (!clients.length) return;
    await this.emitAuthorized(clients, event);
  }

  private async emitAuthorized(clients: Socket[], event: PatientInvalidation) {
    try {
      const sessions = await this.prisma.sesiPengguna.findMany({
        where: {
          id: {
            in: [
              ...new Set(
                clients
                  .map(
                    (c) =>
                      (c.data.patientIdentity as PatientIdentity | undefined)
                        ?.sid,
                  )
                  .filter((id): id is string => !!id),
              ),
            ],
          },
          dicabutPada: null,
          kedaluwarsaPada: { gt: new Date() },
          pengguna: { aktif: true, peran: PeranPengguna.USER },
        },
        select: { id: true, penggunaId: true },
      });
      const valid = new Map(
        sessions.map((session) => [session.id, session.penggunaId]),
      );
      for (const client of clients) {
        const identity = client.data.patientIdentity as
          PatientIdentity | undefined;
        if (
          !identity ||
          identity.exp * 1000 <= Date.now() ||
          valid.get(identity.sid) !== identity.id
        ) {
          client.disconnect(true);
          continue;
        }
        // No status, ticket ID, queue number, patient identity, QR or private data.
        client.emit('patient:updated', event);
      }
    } catch {
      for (const client of clients) client.disconnect(true);
      this.logger.warn('Invalidasi pasien ditahan karena validasi sesi gagal');
    }
  }
}
