import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  UseGuards,
} from '@nestjs/common';

import type { AuthenticatedUser } from '../auth/auth.types';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { Roles } from '../auth/decorators/roles.decorator';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import { PeranPengguna } from '../generated/prisma/client';

import { ProvisionAkunDokterDto } from './dto/provision-akun-dokter.dto';
import { CreateDokterDto } from './dto/create-dokter.dto';
import { HubungkanDokterLayananDto } from './dto/hubungkan-dokter-layanan.dto';
import { UpdateDokterDto } from './dto/update-dokter.dto';
import { DokterService } from './dokter.service';

@Controller('dokter')
@UseGuards(JwtAuthGuard, RolesGuard)
export class DokterController {
  constructor(private readonly dokterService: DokterService) {}

  @Post()
  @Roles(PeranPengguna.ADMIN)
  create(@Body() dto: CreateDokterDto) {
    return this.dokterService.create(dto);
  }

  @Post(':id/akun')
  @Roles(PeranPengguna.ADMIN)
  provisionAkun(
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: ProvisionAkunDokterDto,
  ) {
    return this.dokterService.provisionAkun(id, dto);
  }

  @Get()
  findAll(@CurrentUser() user: AuthenticatedUser) {
    return this.dokterService.findAll(user.peran);
  }

  @Get('akun-tersedia')
  @Roles(PeranPengguna.ADMIN)
  akunTersedia() {
    return this.dokterService.akunTersedia();
  }

  @Get(':id')
  findOne(
    @Param('id', ParseUUIDPipe) id: string,
    @CurrentUser() user: AuthenticatedUser,
  ) {
    return this.dokterService.findOne(id, user.peran);
  }

  @Patch(':id')
  @Roles(PeranPengguna.ADMIN)
  update(@Param('id', ParseUUIDPipe) id: string, @Body() dto: UpdateDokterDto) {
    return this.dokterService.update(id, dto);
  }

  @Delete(':id')
  @Roles(PeranPengguna.ADMIN)
  remove(@Param('id', ParseUUIDPipe) id: string) {
    return this.dokterService.remove(id);
  }

  @Get(':id/layanan')
  findLayanan(
    @Param('id', ParseUUIDPipe) id: string,
    @CurrentUser() user: AuthenticatedUser,
  ) {
    return this.dokterService.findLayanan(id, user.peran);
  }

  @Post(':id/layanan')
  @Roles(PeranPengguna.ADMIN)
  hubungkanLayanan(
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: HubungkanDokterLayananDto,
  ) {
    return this.dokterService.hubungkanLayanan(id, dto);
  }

  @Delete(':id/layanan/:layananId')
  @Roles(PeranPengguna.ADMIN)
  nonaktifkanLayanan(
    @Param('id', ParseUUIDPipe) id: string,
    @Param('layananId', ParseUUIDPipe) layananId: string,
  ) {
    return this.dokterService.nonaktifkanLayanan(id, layananId);
  }
}
