import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import {
  ConnectedSocket,
  MessageBody,
  OnGatewayInit,
  SubscribeMessage,
  WebSocketGateway,
} from '@nestjs/websockets';
import type { Namespace, Socket } from 'socket.io';

import type { AccessTokenPayload } from '../auth/auth.types';
import { JwtStrategy } from '../auth/jwt.strategy';
import { PeranPengguna } from '../generated/prisma/client';
import {
  RealtimeRoomAccessService,
  type IdentitasSocket,
} from './realtime-room-access.service';

const POLA_UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

type BalasanRoom =
  | { ok: true; layananId: string }
  | { ok: false; kode: 'INVALID_REQUEST' | 'UNAUTHORIZED' | 'FORBIDDEN' };

/** Namespace operasional. Room harus diotorisasi di server, bukan dipercaya dari client. */
@WebSocketGateway({ namespace: '/queue' })
export class RealtimeGateway implements OnGatewayInit<Namespace> {
  constructor(
    private readonly jwtService: JwtService,
    private readonly configService: ConfigService,
    private readonly jwtStrategy: JwtStrategy,
    private readonly aksesRoom: RealtimeRoomAccessService,
  ) {}

  afterInit(server: Namespace): void {
    server.use((client, next) => {
      void this.autentikasiKoneksi(client)
        .then(() => next())
        .catch(() => next(new Error('UNAUTHORIZED')));
    });
  }

  @SubscribeMessage('queue:join')
  async bergabung(
    @ConnectedSocket() client: Socket,
    @MessageBody() body: unknown,
  ): Promise<BalasanRoom> {
    const layananId = this.ambilLayananId(body);
    if (!layananId) {
      return { ok: false, kode: 'INVALID_REQUEST' };
    }

    const identitas = this.ambilIdentitas(client);
    if (!identitas) {
      return { ok: false, kode: 'UNAUTHORIZED' };
    }

    // Pemeriksaan terakhir tepat sebelum masuk room.
    const hasil = await this.aksesRoom.periksa(identitas, layananId);
    if (hasil === 'UNAUTHORIZED') {
      await client.leave(this.namaRoom(layananId));
      client.disconnect(true);
      return { ok: false, kode: 'UNAUTHORIZED' };
    }
    if (hasil !== 'ALLOWED') {
      await client.leave(this.namaRoom(layananId));
      return { ok: false, kode: 'FORBIDDEN' };
    }

    await client.join(this.namaRoom(layananId));
    return { ok: true, layananId };
  }

  @SubscribeMessage('queue:leave')
  async keluar(
    @ConnectedSocket() client: Socket,
    @MessageBody() body: unknown,
  ): Promise<BalasanRoom> {
    const layananId = this.ambilLayananId(body);
    if (!layananId) {
      return { ok: false, kode: 'INVALID_REQUEST' };
    }
    if (!this.ambilIdentitas(client)) {
      return { ok: false, kode: 'UNAUTHORIZED' };
    }

    await client.leave(this.namaRoom(layananId));
    return { ok: true, layananId };
  }

  private async autentikasiKoneksi(client: Socket): Promise<void> {
    const token: unknown = client.handshake.auth?.token;
    if (typeof token !== 'string' || token.length === 0 || token.length > 8192) {
      throw new Error('Access token tidak valid');
    }

    const payload = await this.jwtService.verifyAsync<AccessTokenPayload & { exp?: number }>(
      token,
      { secret: this.configService.getOrThrow<string>('JWT_ACCESS_SECRET') },
    );
    const user = await this.jwtStrategy.validate(payload);
    if (
      user.peran !== PeranPengguna.ADMIN &&
      user.peran !== PeranPengguna.PETUGAS
    ) {
      throw new Error('Peran tidak diizinkan');
    }
    // Semua token access terbitan AuthService memiliki exp.
    if (
      typeof payload.exp !== 'number' ||
      !Number.isFinite(payload.exp) ||
      payload.exp * 1000 <= Date.now()
    ) {
      throw new Error('Access token kedaluwarsa atau tidak valid');
    }

    // Simpan metadata minimal untuk revalidasi sesi ketika join; jangan simpan token.
    client.data.authenticatedUser = {
      id: user.id,
      sid: payload.sid,
      peran: user.peran,
      exp: payload.exp,
    } satisfies IdentitasSocket;
  }

  private ambilIdentitas(client: Socket): IdentitasSocket | null {
    const data: unknown = client.data.authenticatedUser;
    if (typeof data !== 'object' || data === null) return null;
    const pengguna = data as Partial<IdentitasSocket>;
    if (
      typeof pengguna.id !== 'string' ||
      typeof pengguna.sid !== 'string' ||
      typeof pengguna.exp !== 'number' ||
      (pengguna.peran !== PeranPengguna.ADMIN &&
        pengguna.peran !== PeranPengguna.PETUGAS)
    ) return null;
    return pengguna as IdentitasSocket;
  }

  private ambilLayananId(body: unknown): string | null {
    if (typeof body !== 'object' || body === null || Array.isArray(body)) {
      return null;
    }
    const data = body as Record<string, unknown>;
    if (Object.keys(data).length !== 1 || typeof data.layananId !== 'string') {
      return null;
    }
    const id = data.layananId;
    return POLA_UUID.test(id) ? id.toLowerCase() : null;
  }

  private namaRoom(layananId: string): string {
    return `layanan:${layananId}`;
  }
}
