import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import type { Namespace, Socket } from 'socket.io';

import { JwtStrategy } from '../auth/jwt.strategy';
import { PeranPengguna } from '../generated/prisma/client';
import { RealtimeGateway } from './realtime.gateway';

type MiddlewareKoneksi = (
  client: Socket,
  next: (error?: Error) => void,
) => void;

describe('RealtimeGateway - autentikasi JWT Socket.IO', () => {
  const petugasId = '69bd8820-b911-4ce7-90c8-7107faf7ad11';
  const accessToken = 'access-token-uji';
  const jwtPayload = { sub: petugasId, sid: 'sesi-uji', role: PeranPengguna.PETUGAS };

  const verifyAsync = jest.fn();
  const getOrThrow = jest.fn();
  const validate = jest.fn();

  let gateway: RealtimeGateway;
  let middleware: MiddlewareKoneksi;
  let use: jest.Mock;

  beforeEach(() => {
    jest.clearAllMocks();
    verifyAsync.mockResolvedValue(jwtPayload);
    getOrThrow.mockReturnValue('secret-access-uji');
    validate.mockResolvedValue({ id: petugasId, peran: PeranPengguna.PETUGAS });

    gateway = new RealtimeGateway(
      { verifyAsync } as unknown as JwtService,
      { getOrThrow } as unknown as ConfigService,
      { validate } as unknown as JwtStrategy,
    );

    use = jest.fn((callback: MiddlewareKoneksi) => {
      middleware = callback;
    });
    gateway.afterInit({ use } as unknown as Namespace);
  });

  function buatKlien(token: unknown = accessToken) {
    const join = jest.fn();
    const emit = jest.fn();
    const client = {
      handshake: { auth: { token } },
      data: {} as Record<string, unknown>,
      join,
      emit,
    } as unknown as Socket;
    return { client, join, emit };
  }

  async function ujiHandshake(client: Socket): Promise<Error | undefined> {
    return new Promise((resolve) => {
      middleware(client, (error) => resolve(error));
    });
  }

  it('mendaftarkan middleware autentikasi pada namespace /queue', () => {
    expect(use).toHaveBeenCalledTimes(1);
    expect(typeof middleware).toBe('function');
  });

  it('menerima PETUGAS dengan JWT valid dan sesi aktif', async () => {
    const { client, join, emit } = buatKlien();
    expect(await ujiHandshake(client)).toBeUndefined();
    expect(verifyAsync).toHaveBeenCalledWith(accessToken, {
      secret: 'secret-access-uji',
    });
    expect(validate).toHaveBeenCalledWith(jwtPayload);
    expect(client.data.authenticatedUser).toEqual({
      id: petugasId,
      peran: PeranPengguna.PETUGAS,
    });
    expect(join).not.toHaveBeenCalled();
    expect(emit).not.toHaveBeenCalled();
  });

  it('menerima ADMIN yang telah lolos verifikasi pengguna dan sesi', async () => {
    validate.mockResolvedValue({ id: petugasId, peran: PeranPengguna.ADMIN });
    const { client } = buatKlien();
    expect(await ujiHandshake(client)).toBeUndefined();
    expect(client.data.authenticatedUser).toEqual({
      id: petugasId,
      peran: PeranPengguna.ADMIN,
    });
  });

  it('menolak koneksi tanpa access token', async () => {
    const { client } = buatKlien();
    // Pastikan field token betul-betul tidak disediakan.
    client.handshake.auth = {};
    expect((await ujiHandshake(client))?.message).toBe('UNAUTHORIZED');
    expect(verifyAsync).not.toHaveBeenCalled();
    expect(validate).not.toHaveBeenCalled();
  });

  it.each([null, 123, {}, '', 'x'.repeat(8193)])(
    'menolak token handshake yang tidak sesuai: %p',
    async (token) => {
      const { client } = buatKlien(token);
      expect((await ujiHandshake(client))?.message).toBe('UNAUTHORIZED');
      expect(verifyAsync).not.toHaveBeenCalled();
    },
  );

  it('menolak JWT bertanda tangan tidak sah atau kedaluwarsa', async () => {
    verifyAsync.mockRejectedValue(new Error('jwt expired'));
    const { client } = buatKlien();
    expect((await ujiHandshake(client))?.message).toBe('UNAUTHORIZED');
    expect(validate).not.toHaveBeenCalled();
    expect(client.data.authenticatedUser).toBeUndefined();
  });

  it('menolak sesi yang dicabut atau akun yang nonaktif', async () => {
    validate.mockRejectedValue(new Error('Sesi tidak aktif'));
    const { client } = buatKlien();
    expect((await ujiHandshake(client))?.message).toBe('UNAUTHORIZED');
    expect(client.data.authenticatedUser).toBeUndefined();
  });

  it('menolak akun USER meskipun JWT valid', async () => {
    validate.mockResolvedValue({ id: petugasId, peran: PeranPengguna.USER });
    const { client } = buatKlien();
    expect((await ujiHandshake(client))?.message).toBe('UNAUTHORIZED');
    expect(client.data.authenticatedUser).toBeUndefined();
  });

  it('tidak memberikan room dan tidak mengirim event saat otentikasi gagal', async () => {
    verifyAsync.mockRejectedValue(new Error('invalid signature'));
    const { client, join, emit } = buatKlien();
    await ujiHandshake(client);
    expect(join).not.toHaveBeenCalled();
    expect(emit).not.toHaveBeenCalled();
  });

  it('tidak mengekspos email, nama dan access token melalui client.data', async () => {
    validate.mockResolvedValue({
      id: petugasId,
      peran: PeranPengguna.PETUGAS,
      email: 'uji@test.local',
      nama: 'Petugas Contoh',
    });
    const { client } = buatKlien();
    expect(await ujiHandshake(client)).toBeUndefined();
    expect(client.data.authenticatedUser).toEqual({
      id: petugasId,
      peran: PeranPengguna.PETUGAS,
    });
    expect(JSON.stringify(client.data)).not.toContain(accessToken);
    expect(JSON.stringify(client.data)).not.toContain('uji@test.local');
  });
});
