import { Controller, Get, Query, UseGuards } from '@nestjs/common';
import type { AuthenticatedUser } from '../auth/auth.types';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { Roles } from '../auth/decorators/roles.decorator';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import { PeranPengguna } from '../generated/prisma/client';
import { PortalTanggalDto, PortalSnapshotDto } from './portal-query.dto';
import { PortalDokterService } from './portal-dokter.service';
@Controller('portal-dokter')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(PeranPengguna.DOKTER)
export class PortalDokterController {
  constructor(private readonly portal: PortalDokterService) {}
  @Get('profil') profil(@CurrentUser() u: AuthenticatedUser) {
    return this.portal.profil(u.id);
  }
  @Get('jadwal') jadwal(
    @CurrentUser() u: AuthenticatedUser,
    @Query() q: PortalTanggalDto,
  ) {
    return this.portal.jadwal(u.id, q.tanggal);
  }
  @Get('janji-temu') janji(
    @CurrentUser() u: AuthenticatedUser,
    @Query() q: PortalTanggalDto,
  ) {
    return this.portal.janjiTemu(u.id, q.tanggal);
  }
  @Get('antrean/snapshot') snapshot(
    @CurrentUser() u: AuthenticatedUser,
    @Query() q: PortalSnapshotDto,
  ) {
    return this.portal.snapshot(u.id, q.jadwalPraktikId);
  }
}
