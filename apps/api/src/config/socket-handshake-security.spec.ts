import type { Socket } from 'socket.io';
import { SocketHandshakeSecurity } from './socket-handshake-security';

describe('SocketHandshakeSecurity: Origin dan pembatasan koneksi', () => {
  const lama = process.env.CORS_ALLOWED_ORIGINS;
  const nodeEnv = process.env.NODE_ENV;
  const originDiizinkan = 'http://localhost:5173';

  function klien(origin: unknown, alamat: unknown = '127.0.0.1'): Socket {
    const headers: Record<string, unknown> = {};
    if (origin !== undefined) headers.origin = origin;
    return { handshake: { headers, address: alamat } } as unknown as Socket;
  }

  beforeEach(() => {
    process.env.CORS_ALLOWED_ORIGINS = 'http://localhost:3000,http://localhost:5173';
  });

  afterEach(() => {
    if (lama === undefined) delete process.env.CORS_ALLOWED_ORIGINS;
    else process.env.CORS_ALLOWED_ORIGINS = lama;
    if (nodeEnv !== undefined) process.env.NODE_ENV = nodeEnv;
  });

  it('menerima Origin browser terdaftar', () => {
    expect(() => new SocketHandshakeSecurity().periksa(klien(originDiizinkan), 'queue')).not.toThrow();
  });

  it('menerima origin terdaftar lain untuk display', () => {
    expect(() => new SocketHandshakeSecurity().periksa(klien('http://localhost:3000'), 'display')).not.toThrow();
  });

  it('menolak browser dari origin tak dikenal', () => {
    expect(() => new SocketHandshakeSecurity().periksa(klien('https://jahat.invalid'), 'queue'))
      .toThrow('ORIGIN_NOT_ALLOWED');
  });

  it('menolak Origin null, tanpa wildcard', () => {
    expect(() => new SocketHandshakeSecurity().periksa(klien('null'), 'display'))
      .toThrow('ORIGIN_NOT_ALLOWED');
  });

  it('menolak origin dengan path yang tidak persis sama', () => {
    expect(() => new SocketHandshakeSecurity().periksa(klien('http://localhost:5173/path'), 'queue'))
      .toThrow('ORIGIN_NOT_ALLOWED');
  });

  it('tidak menolak klien native tanpa Origin; token tetap diperiksa oleh Gateway', () => {
    expect(() => new SocketHandshakeSecurity().periksa(klien(undefined), 'queue')).not.toThrow();
  });

  it('menolak koneksi yang melebihi batas pada satu IP', () => {
    const keamanan = new SocketHandshakeSecurity(2);
    keamanan.periksa(klien(originDiizinkan), 'queue', 1);
    keamanan.periksa(klien(originDiizinkan), 'queue', 2);
    expect(() => keamanan.periksa(klien(originDiizinkan), 'queue', 3))
      .toThrow('RATE_LIMITED');
  });

  it('memisahkan kuota koneksi per namespace', () => {
    const keamanan = new SocketHandshakeSecurity(1);
    keamanan.periksa(klien(undefined), 'queue', 0);
    expect(() => keamanan.periksa(klien(undefined), 'display', 1)).not.toThrow();
    expect(() => keamanan.periksa(klien(undefined), 'queue', 1)).toThrow('RATE_LIMITED');
  });

  it('memisahkan kuota antar alamat koneksi', () => {
    const keamanan = new SocketHandshakeSecurity(1);
    keamanan.periksa(klien(undefined, '127.0.0.1'), 'queue', 0);
    expect(() => keamanan.periksa(klien(undefined, '127.0.0.2'), 'queue', 1)).not.toThrow();
  });

  it('mengatur ulang kuota setelah 60 detik', () => {
    const keamanan = new SocketHandshakeSecurity(1);
    keamanan.periksa(klien(undefined), 'queue', 0);
    expect(() => keamanan.periksa(klien(undefined), 'queue', 60_000)).not.toThrow();
  });

  it('menolak IP baru saat kapasitas counter penuh, tanpa pertumbuhan tanpa batas', () => {
    const keamanan = new SocketHandshakeSecurity(3, 60_000, 1);
    keamanan.periksa(klien(undefined, '127.0.0.1'), 'queue', 0);
    expect(() => keamanan.periksa(klien(undefined, '127.0.0.2'), 'queue', 1))
      .toThrow('RATE_LIMITED');
  });

  it('membersihkan IP kadaluwarsa ketika kapasitas counter penuh', () => {
    const keamanan = new SocketHandshakeSecurity(1, 60_000, 1);
    keamanan.periksa(klien(undefined, '127.0.0.1'), 'queue', 0);
    expect(() => keamanan.periksa(klien(undefined, '127.0.0.2'), 'queue', 60_000)).not.toThrow();
  });

  it('menolak Origin browser jika daftar origin production tidak ditentukan', () => {
    delete process.env.CORS_ALLOWED_ORIGINS;
    process.env.NODE_ENV = 'production';
    expect(() => new SocketHandshakeSecurity().periksa(klien(originDiizinkan), 'queue'))
      .toThrow('ORIGIN_NOT_ALLOWED');
  });
});
