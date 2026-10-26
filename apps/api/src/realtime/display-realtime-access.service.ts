import { createHash } from 'node:crypto';
import { Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';

const POLA_UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const POLA_TOKEN = /^[0-9a-f]{64}$/i;

/** Metadata khusus server. Token mentah tidak disimpan pada socket.data. */
export interface IdentitasDisplay {
  perangkatId: string;
  layananId: string;
  tokenHash: string;
}

@Injectable()
export class DisplayRealtimeAccessService {
  constructor(private readonly prisma: PrismaService) {}

  async autentikasi(token: unknown, layananId: unknown, deviceId?: unknown): Promise<IdentitasDisplay> {
    if (
      typeof token !== 'string' || !POLA_TOKEN.test(token) ||
      typeof layananId !== 'string' || !POLA_UUID.test(layananId)
    ) throw new Error('UNAUTHORIZED');

    const tokenHash = createHash('sha256').update(token, 'utf8').digest('hex');
    const perangkat = await this.prisma.perangkatTampilan.findUnique({
      where: { tokenHash },
      select: {
        sesiBerakhirPada: true, id: true, tokenHash: true, aktif: true, layananId: true,
        layanan: { select: { aktif: true } },
      },
    });
    if (
      !perangkat || (deviceId !== undefined && perangkat.id !== deviceId) || (perangkat.sesiBerakhirPada && perangkat.sesiBerakhirPada <= new Date()) || !perangkat.aktif || !perangkat.layanan.aktif ||
      perangkat.layananId !== layananId
    ) throw new Error('UNAUTHORIZED');

    return { perangkatId: perangkat.id, layananId: perangkat.layananId, tokenHash };
  }

  /** Periksa status perangkat, status layanan, dan rotasi token sebelum emit. */
  async masihBerwenang(identitas: IdentitasDisplay): Promise<boolean> {
    const perangkat = await this.prisma.perangkatTampilan.findUnique({
      where: { id: identitas.perangkatId },
      select: {
        sesiBerakhirPada: true, aktif: true, layananId: true, tokenHash: true,
        layanan: { select: { aktif: true } },
      },
    });
    return Boolean(
      perangkat && (!perangkat.sesiBerakhirPada || perangkat.sesiBerakhirPada > new Date()) && perangkat.aktif && perangkat.layanan.aktif &&
      perangkat.layananId === identitas.layananId &&
      perangkat.tokenHash === identitas.tokenHash,
    );
  }
}
