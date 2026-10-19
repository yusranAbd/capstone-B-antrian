import { createHash, createHmac, randomBytes, randomInt } from 'node:crypto';
import {
  ConflictException,
  GoneException,
  Injectable,
  NotFoundException,
  UnauthorizedException,
  UnprocessableEntityException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PrismaService } from '../prisma/prisma.service';
import { DisplayRealtimeGateway } from '../realtime/display-realtime.gateway';
import { DISPLAY_SESSION_MS } from './display-cookie';
import { CreateDisplayDeviceDto } from './display-device.dto';
const hash = (v: string) => createHash('sha256').update(v).digest('hex');
const metadata = {
  id: true,
  nama: true,
  layananId: true,
  aktif: true,
  terakhirAktifPada: true,
  dibuatPada: true,
  diperbaruiPada: true,
  layanan: { select: { id: true, nama: true, kode: true, aktif: true } },
} as const;
@Injectable()
export class DisplayDeviceService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly gateway: DisplayRealtimeGateway,
    private readonly config: ConfigService,
  ) {}
  private activationHash(code: string): string {
    return createHmac(
      'sha256',
      this.config.getOrThrow<string>('JWT_REFRESH_SECRET'),
    )
      .update('queueb:display:activation:v1:' + code)
      .digest('hex');
  }
  list() {
    return this.prisma.perangkatTampilan.findMany({
      select: metadata,
      orderBy: [{ layananId: 'asc' }, { nama: 'asc' }],
    });
  }
  async create(dto: CreateDisplayDeviceDto) {
    const layanan = await this.prisma.layanan.findUnique({
      where: { id: dto.layananId },
    });
    if (!layanan?.aktif)
      throw new UnprocessableEntityException('Poliklinik harus aktif');
    // A newly registered device has no usable credential until pairing.
    return this.prisma.perangkatTampilan.create({
      data: {
        nama: dto.nama.trim(),
        layananId: dto.layananId,
        tokenHash: hash(randomBytes(32).toString('hex')),
      },
      select: metadata,
    });
  }
  async activation(id: string) {
    const kode = Array.from({ length: 12 }, () => randomInt(10)).join('');
    const berlakuHingga = new Date(Date.now() + 5 * 60_000);
    const changed = await this.prisma.perangkatTampilan.updateMany({
      where: { id, layanan: { aktif: true } },
      data: {
        aktif: true,
        kodeAktivasiHash: this.activationHash(kode),
        kodeBerlakuHingga: berlakuHingga,
        kodeDigunakanPada: null,
        tokenHash: hash(randomBytes(32).toString('hex')),
        sesiBerakhirPada: null,
      },
    });
    if (changed.count !== 1)
      throw new NotFoundException(
        'Perangkat atau poliklinik aktif tidak ditemukan',
      );
    // Rotation revokes the previous connection immediately, even with no queue event.
    this.gateway.cabutPerangkat(id);
    return { kode, berlakuHingga };
  }
  async deactivate(id: string) {
    const changed = await this.prisma.perangkatTampilan.updateMany({
      where: { id },
      data: {
        aktif: false,
        tokenHash: hash(randomBytes(32).toString('hex')),
        kodeAktivasiHash: null,
        kodeBerlakuHingga: null,
        kodeDigunakanPada: null,
        sesiBerakhirPada: null,
      },
    });
    if (changed.count !== 1)
      throw new NotFoundException('Perangkat tidak ditemukan');
    this.gateway.cabutPerangkat(id);
    return { id, aktif: false };
  }
  async pair(kode: string) {
    const now = new Date();
    const kodeAktivasiHash = this.activationHash(kode);
    const token = randomBytes(32).toString('hex');
    const device = await this.prisma.$transaction(async (tx) => {
      const current = await tx.perangkatTampilan.findUnique({
        where: { kodeAktivasiHash },
      });
      if (!current)
        throw new UnauthorizedException(
          'Kode aktivasi salah atau sudah diganti',
        );
      if (!current.aktif)
        throw new UnauthorizedException('Perangkat dinonaktifkan');
      if (current.kodeDigunakanPada)
        throw new GoneException('Kode aktivasi sudah digunakan');
      if (!current.kodeBerlakuHingga || current.kodeBerlakuHingga <= now)
        throw new GoneException('Kode aktivasi kedaluwarsa');
      // Atomic claim: concurrent requests may read the same code; only one may consume it.
      const claimed = await tx.perangkatTampilan.updateMany({
        where: {
          id: current.id,
          aktif: true,
          kodeAktivasiHash,
          kodeDigunakanPada: null,
          kodeBerlakuHingga: { gt: now },
          layanan: { aktif: true },
        },
        data: {
          kodeDigunakanPada: now,
          tokenHash: hash(token),
          sesiBerakhirPada: new Date(now.getTime() + DISPLAY_SESSION_MS),
          terakhirAktifPada: now,
        },
      });
      if (claimed.count !== 1)
        throw new ConflictException(
          'Kode sudah digunakan atau perangkat tidak aktif. Minta kode baru.',
        );
      return tx.perangkatTampilan.findUniqueOrThrow({
        where: { id: current.id },
        select: metadata,
      });
    });
    return { token, device };
  }
  async session(token: string | undefined) {
    if (!token)
      throw new UnauthorizedException('Aktivasi perangkat diperlukan');
    const current = await this.prisma.perangkatTampilan.findUnique({
      where: { tokenHash: hash(token) },
      select: { ...metadata, sesiBerakhirPada: true },
    });
    if (
      !current ||
      !current.aktif ||
      !current.layanan.aktif ||
      !current.sesiBerakhirPada ||
      current.sesiBerakhirPada <= new Date()
    ) {
      throw new UnauthorizedException(
        'Sesi perangkat berakhir atau perangkat dinonaktifkan',
      );
    }
    const { sesiBerakhirPada: _expiry, ...device } = current;
    await this.prisma.perangkatTampilan.updateMany({
      where: {
        id: current.id,
        tokenHash: hash(token),
        OR: [
          { terakhirAktifPada: null },
          { terakhirAktifPada: { lt: new Date(Date.now() - 60_000) } },
        ],
      },
      data: { terakhirAktifPada: new Date() },
    });
    return device;
  }
  async forget(token: string | undefined) {
    if (token) {
      const current = await this.prisma.perangkatTampilan.findUnique({
        where: { tokenHash: hash(token) },
        select: { id: true },
      });
      if (current) {
        const revoked = await this.prisma.perangkatTampilan.updateMany({
          where: { id: current.id, tokenHash: hash(token) },
          data: {
            tokenHash: hash(randomBytes(32).toString('hex')),
            sesiBerakhirPada: null,
          },
        });
        // A concurrent rotation may already have replaced this credential.
        // Never disconnect its new session when the conditional revoke loses.
        if (revoked.count === 1) this.gateway.cabutPerangkat(current.id);
      }
    }
    return { ok: true };
  }
}
