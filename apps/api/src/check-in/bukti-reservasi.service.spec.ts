import { BadRequestException, ForbiddenException, NotFoundException } from '@nestjs/common';
import { StatusTiket } from '../generated/prisma/client';
import { CheckInService } from './check-in.service';
import { PrismaService } from '../prisma/prisma.service';

const code = 'TK0123456789ABCDEF01234567';
const dto = { qrPayload: `QBR1.${code}`, loketId: '11111111-1111-4111-8111-111111111111' };
const petugas = '22222222-2222-4222-8222-222222222222';
const ticket = {
  id: '33333333-3333-4333-8333-333333333333',
  layananId: '44444444-4444-4444-8444-444444444444',
  tanggalAntrean: new Date('2030-01-01T00:00:00.000Z'),
  nomorUrut: 7,
  status: StatusTiket.DIPESAN,
  layanan: {
    id: '44444444-4444-4444-8444-444444444444',
    nama: 'Pendaftaran', prefixAntrean: 'PD', aktif: true,
  },
};
const assignment = {
  loket: {
    aktif: true, layananId: ticket.layananId, layanan: { aktif: true },
  },
};

describe('QR bukti reservasi QBR1 (read-only)', () => {
  const findUnique = jest.fn();
  const findFirst = jest.fn();
  const updateMany = jest.fn();
  const prisma = {
    tiketAntrean: { findUnique, updateMany },
    penugasanPetugas: { findFirst },
  } as unknown as PrismaService;
  const service = new CheckInService(prisma);

  beforeEach(() => {
    jest.clearAllMocks();
    findUnique.mockResolvedValue(ticket);
    findFirst.mockResolvedValue(assignment);
  });

  it('memverifikasi kode tanpa mutasi DB atau menerbitkan SQ1', async () => {
    const result = await service.verifikasiBuktiReservasi(dto, petugas);
    expect(result.jenis).toBe('BUKTI_RESERVASI');
    expect(result.nomorAntrean).toBe('PD-007');
    expect(result.checkInDilakukan).toBe(false);
    expect(findUnique).toHaveBeenCalledWith(expect.objectContaining({
      where: { kodeTiket: code },
    }));
    expect(updateMany).not.toHaveBeenCalled();
    expect(JSON.stringify(result)).not.toContain('penggunaId');
  });

  it('menolak QR palsu / format SQ1', async () => {
    await expect(service.verifikasiBuktiReservasi({ ...dto, qrPayload: 'SQ1.temporer' }, petugas))
      .rejects.toBeInstanceOf(BadRequestException);
    expect(findUnique).not.toHaveBeenCalled();
  });

  it('menolak QR yang tidak ditemukan', async () => {
    findUnique.mockResolvedValue(null);
    await expect(service.verifikasiBuktiReservasi(dto, petugas))
      .rejects.toBeInstanceOf(NotFoundException);
  });

  it('menolak petugas tanpa penugasan pada layanan tersebut', async () => {
    findFirst.mockResolvedValue(null);
    await expect(service.verifikasiBuktiReservasi(dto, petugas))
      .rejects.toBeInstanceOf(ForbiddenException);
    expect(updateMany).not.toHaveBeenCalled();
  });

  it('tiket dibatalkan dinyatakan tidak berlaku', async () => {
    findUnique.mockResolvedValue({ ...ticket, status: StatusTiket.DIBATALKAN });
    const result = await service.verifikasiBuktiReservasi(dto, petugas);
    expect(result.buktiBerlaku).toBe(false);
    expect(result.checkInDilakukan).toBe(false);
  });
});
