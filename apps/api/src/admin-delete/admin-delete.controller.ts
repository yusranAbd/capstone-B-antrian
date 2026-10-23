import {
  Controller,
  Delete,
  Param,
  ParseUUIDPipe,
  UseGuards,
} from '@nestjs/common';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import { Roles } from '../auth/decorators/roles.decorator';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import type { AuthenticatedUser } from '../auth/auth.types';
import { PeranPengguna } from '../generated/prisma/client';
import { AdminDeleteService } from './admin-delete.service';

@Controller()
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(PeranPengguna.ADMIN)
export class AdminDeleteController {
  constructor(private readonly service: AdminDeleteService) {}
  @Delete('layanan/:id/permanen')
  hapusLayanan(
    @Param('id', new ParseUUIDPipe({ version: '4' })) id: string,
    @CurrentUser() user: AuthenticatedUser,
  ) {
    return this.service.remove('layanan', id, user.id);
  }
  @Delete('dokter/:id/permanen')
  hapusDokter(
    @Param('id', new ParseUUIDPipe({ version: '4' })) id: string,
    @CurrentUser() user: AuthenticatedUser,
  ) {
    return this.service.remove('dokter', id, user.id);
  }
  @Delete('loket/:id/permanen')
  hapusLoket(
    @Param('id', new ParseUUIDPipe({ version: '4' })) id: string,
    @CurrentUser() user: AuthenticatedUser,
  ) {
    return this.service.remove('loket', id, user.id);
  }
  @Delete('jadwal-layanan/:id/permanen')
  hapusJadwalLayanan(
    @Param('id', new ParseUUIDPipe({ version: '4' })) id: string,
    @CurrentUser() user: AuthenticatedUser,
  ) {
    return this.service.remove('jadwal-layanan', id, user.id);
  }
  @Delete('jadwal-praktik/:id/permanen')
  hapusJadwalPraktik(
    @Param('id', new ParseUUIDPipe({ version: '4' })) id: string,
    @CurrentUser() user: AuthenticatedUser,
  ) {
    return this.service.remove('jadwal-praktik', id, user.id);
  }
  @Delete('slot-praktik/:id/permanen')
  hapusSlotPraktik(
    @Param('id', new ParseUUIDPipe({ version: '4' })) id: string,
    @CurrentUser() user: AuthenticatedUser,
  ) {
    return this.service.remove('slot-praktik', id, user.id);
  }
  @Delete('penugasan-petugas/:id/permanen')
  hapusPenugasanPetugas(
    @Param('id', new ParseUUIDPipe({ version: '4' })) id: string,
    @CurrentUser() user: AuthenticatedUser,
  ) {
    return this.service.remove('penugasan-petugas', id, user.id);
  }
  @Delete('perangkat-display/:id/permanen')
  hapusPerangkatDisplay(
    @Param('id', new ParseUUIDPipe({ version: '4' })) id: string,
    @CurrentUser() user: AuthenticatedUser,
  ) {
    return this.service.remove('perangkat-display', id, user.id);
  }
}
