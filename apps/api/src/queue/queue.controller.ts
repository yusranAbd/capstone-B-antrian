import {
  Body,
  Controller,
  ForbiddenException,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  ParseUUIDPipe,
  Post,
  Query,
  Req,
  UnauthorizedException,
  UseGuards,
} from '@nestjs/common';

import { AuthGuard } from '@nestjs/passport';
import type { Request } from 'express';

import { PeranPengguna } from '../generated/prisma/client';
import { MasukAntreanDto } from './dto/masuk-antrean.dto';
import { QueueService } from './queue.service';
import { PanggilBerikutnyaDto } from './dto/panggil-berikutnya.dto';

// ==========================================
// IDENTITAS PENGGUNA DARI JWT
// ==========================================

interface IdentitasJwt {
  id?: string;
  sub?: string;
  peran?: PeranPengguna;
}

type RequestTerautentikasi = Request & {
  user?: IdentitasJwt;
};

// ==========================================
// QUEUE CONTROLLER
// ==========================================

@Controller('queue')
@UseGuards(AuthGuard('jwt'))
export class QueueController {
  constructor(private readonly queueService: QueueService) {}

  // ========================================
  // MENDAPATKAN IDENTITAS PETUGAS
  // ========================================

  private ambilPetugasId(request: RequestTerautentikasi): string {
    const pengguna = request.user;

    if (!pengguna) {
      throw new UnauthorizedException('Autentikasi diperlukan');
    }

    if (pengguna.peran !== PeranPengguna.PETUGAS) {
      throw new ForbiddenException('Fitur ini hanya dapat diakses PETUGAS');
    }

    const petugasId = pengguna.id ?? pengguna.sub;

    if (!petugasId) {
      throw new UnauthorizedException('Identitas PETUGAS tidak valid');
    }

    return petugasId;
  }

  // ========================================
  // POST /api/v1/queue/:tiketId/masuk
  // CHECK_IN -> MENUNGGU
  // ========================================

  @Post(':tiketId/masuk')
  @HttpCode(HttpStatus.OK)
  async masukAntrean(
    @Param('tiketId', new ParseUUIDPipe({ version: '4' }))
    tiketId: string,

    @Body()
    dto: MasukAntreanDto,

    @Req()
    request: RequestTerautentikasi,
  ) {
    const petugasId = this.ambilPetugasId(request);

    return this.queueService.masukAntrean(tiketId, petugasId, dto.loketId);
  }

  // ========================================
  // GET /api/v1/queue/menunggu
  // DAFTAR FIFO BERDASARKAN LAYANAN
  // ========================================

  @Get('menunggu')
  async daftarMenunggu(
    @Query('loketId', new ParseUUIDPipe({ version: '4' }))
    loketId: string,

    @Req()
    request: RequestTerautentikasi,
  ) {
    const petugasId = this.ambilPetugasId(request);

    return this.queueService.daftarMenunggu(petugasId, loketId);
  }

  // ========================================
  // POST /api/v1/queue/:tiketId/panggil-ulang
  // RECALL TIKET DIPANGGIL
  // ========================================

  @Post(':tiketId/panggil-ulang')
  @HttpCode(HttpStatus.OK)
  async panggilUlang(
    @Param('tiketId', new ParseUUIDPipe({ version: '4' }))
    tiketId: string,

    @Body()
    dto: PanggilBerikutnyaDto,

    @Req()
    request: RequestTerautentikasi,
  ) {
    const petugasId = this.ambilPetugasId(request);

    return this.queueService.panggilUlang(tiketId, petugasId, dto.loketId);
  }

  // ========================================
  // POST /api/v1/queue/:tiketId/lewati
  // SKIP TIKET YANG SEDANG DIPANGGIL
  // ========================================

  @Post(':tiketId/lewati')
  @HttpCode(HttpStatus.OK)
  async lewatiAntrean(
    @Param('tiketId', new ParseUUIDPipe({ version: '4' }))
    tiketId: string,

    @Body()
    dto: PanggilBerikutnyaDto,

    @Req()
    request: RequestTerautentikasi,
  ) {
    const petugasId = this.ambilPetugasId(request);

    return this.queueService.lewatiAntrean(tiketId, petugasId, dto.loketId);
  }

  // ========================================
  // POST /api/v1/queue/:tiketId/antre-ulang
  // REQUEUE TIKET DILEWATI KE AKHIR FIFO
  // ========================================

  @Post(':tiketId/antre-ulang')
  @HttpCode(HttpStatus.OK)
  async antreUlang(
    @Param('tiketId', new ParseUUIDPipe({ version: '4' }))
    tiketId: string,

    @Body()
    dto: PanggilBerikutnyaDto,

    @Req()
    request: RequestTerautentikasi,
  ) {
    const petugasId = this.ambilPetugasId(request);

    return this.queueService.antreUlang(tiketId, petugasId, dto.loketId);
  }

  // ========================================
  // POST /api/v1/queue/panggil
  // PANGGIL TIKET FIFO BERIKUTNYA
  // ========================================

  @Post('panggil')
  @HttpCode(HttpStatus.OK)
  async panggilBerikutnya(
    @Body()
    dto: PanggilBerikutnyaDto,

    @Req()
    request: RequestTerautentikasi,
  ) {
    const petugasId = this.ambilPetugasId(request);

    return this.queueService.panggilBerikutnya(petugasId, dto.loketId);
  }
}
