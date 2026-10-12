import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { OnGatewayInit, WebSocketGateway } from '@nestjs/websockets';
import type { Namespace, Socket } from 'socket.io';

import type { AccessTokenPayload } from '../auth/auth.types';
import { JwtStrategy } from '../auth/jwt.strategy';
import { PeranPengguna } from '../generated/prisma/client';

/**
 * 01G-E.1-C: koneksi Socket.IO hanya diterima setelah autentikasi.
 * Middleware namespace berjalan SEBELUM event "connection".
 * Room dan broadcast akan ditambahkan pada milestone berikutnya.
 */
@WebSocketGateway({ namespace: '/queue' })
export class RealtimeGateway implements OnGatewayInit<Namespace> {
  constructor(
    private readonly jwtService: JwtService,
    private readonly configService: ConfigService,
    private readonly jwtStrategy: JwtStrategy,
  ) {}

  afterInit(server: Namespace): void {
    server.use((client, next) => {
      void this.autentikasiKoneksi(client)
        .then(() => next())
        .catch(() => next(new Error('UNAUTHORIZED')));
    });
  }

  private async autentikasiKoneksi(client: Socket): Promise<void> {
    const token: unknown = client.handshake.auth?.token;

    // Token mentah, bukan string "Bearer ..." dan bukan refresh token.
    if (
      typeof token !== 'string' ||
      token.length === 0 ||
      token.length > 8192
    ) {
      throw new Error('Access token tidak valid');
    }

    // Verifikasi tanda tangan dan expiry sebelum mempercayai payload.
    const payload = await this.jwtService.verifyAsync<AccessTokenPayload>(
      token,
      {
        secret: this.configService.getOrThrow<string>('JWT_ACCESS_SECRET'),
      },
    );

    // Gunakan aturan REST yang sama: user aktif dan sesi masih sah.
    const user = await this.jwtStrategy.validate(payload);

    if (
      user.peran !== PeranPengguna.ADMIN &&
      user.peran !== PeranPengguna.PETUGAS
    ) {
      throw new Error('Peran tidak diizinkan');
    }

    // Jangan simpan token, email atau nama pengguna dalam data socket.
    client.data.authenticatedUser = {
      id: user.id,
      peran: user.peran,
    };
  }
}
