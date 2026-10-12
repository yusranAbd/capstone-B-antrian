import type { Socket } from 'socket.io';

type KanalSocket = 'queue' | 'display';

interface Percobaan {
  jumlah: number;
  berakhirPada: number;
}

/**
 * Pemeriksaan Origin dan pembatasan handshake per alamat IP.
 * Batas ini berlaku per proses Node.js. Reverse proxy tetap diperlukan pada production.
 */
export class SocketHandshakeSecurity {
  private readonly percobaan = new Map<string, Percobaan>();

  constructor(
    private readonly batasPerMenit = 60,
    private readonly jendelaMs = 60_000,
    private readonly kapasitasIp = 10_000,
  ) {}

  periksa(client: Socket, kanal: KanalSocket, sekarang = Date.now()): void {
    const origin: unknown = client.handshake.headers?.origin;
    if (origin !== undefined) {
      if (typeof origin !== 'string' || !this.originDiizinkan().includes(origin)) {
        throw new Error('ORIGIN_NOT_ALLOWED');
      }
    }

    // Browser selalu mengirim Origin pada WebSocket; klien native mungkin tidak.
    // Origin bukan autentikasi. JWT atau token perangkat tetap wajib diverifikasi.
    // Gunakan alamat koneksi Socket.IO, bukan X-Forwarded-For dari klien.
    const alamat: unknown = client.handshake.address;
    // Handshake Socket.IO nyata menyediakan alamat. Mock tanpa alamat
    // tetap diberi kuota bersama supaya tidak ada bypass rate limit.
    const ip = typeof alamat === 'string' && alamat.trim() ? alamat : 'unknown';
    const kunci = `${kanal}:${ip}`;
    const lama = this.percobaan.get(kunci);
    if (lama && lama.berakhirPada > sekarang) {
      if (lama.jumlah >= this.batasPerMenit) throw new Error('RATE_LIMITED');
      lama.jumlah += 1;
      return;
    }

    if (this.percobaan.size >= this.kapasitasIp) {
      for (const [ip, data] of this.percobaan) {
        if (data.berakhirPada <= sekarang) this.percobaan.delete(ip);
      }
    }
    // Memori dibatasi. Saat penuh, koneksi baru ditolak (fail closed).
    if (!this.percobaan.has(kunci) && this.percobaan.size >= this.kapasitasIp) {
      throw new Error('RATE_LIMITED');
    }
    this.percobaan.set(kunci, { jumlah: 1, berakhirPada: sekarang + this.jendelaMs });
  }

  private originDiizinkan(): string[] {
    // env.validation.ts sudah memvalidasi format dan mewajibkan daftar di production.
    const raw = process.env.CORS_ALLOWED_ORIGINS;
    if (raw !== undefined) {
      return raw.split(',').map((origin) => origin.trim()).filter(Boolean);
    }
    return process.env.NODE_ENV === 'production'
      ? []
      : ['http://localhost:3000', 'http://localhost:5173'];
  }
}

/** Kedua namespace berbagi pembatasan memori; counter tetap dipisah per namespace. */
export const keamananHandshakeSocket = new SocketHandshakeSecurity();
