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
import { PeranPengguna } from '../generated/prisma/client';
import { PrismaService } from '../prisma/prisma.service';

type PatientIdentity = { id: string; sid: string; exp: number };
export type PatientInvalidation = {
  versiSkema: 1;
  eventId: string;
  jenis: 'TIKET' | 'KATALOG';
  terjadiPada: string;
};

/** Server-scoped subscriptions: no client-provided room, ticket or user ID. */
@Injectable()
@WebSocketGateway({ namespace: '/patient' })
export class PatientRealtimeGateway
  implements OnGatewayInit<Namespace>, OnGatewayConnection, OnGatewayDisconnect
{
  private server?: Namespace;
  private readonly expiry = new Map<string, ReturnType<typeof setTimeout>>();
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
  }

  /** Called only after the HTTP operation has resolved (its DB transaction committed). */
  async invalidate(jenis: PatientInvalidation['jenis'], penggunaId?: string) {
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
