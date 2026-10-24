import {
  Body,
  Controller,
  Get,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  UseGuards,
} from '@nestjs/common';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { Roles } from '../auth/decorators/roles.decorator';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import type { AuthenticatedUser } from '../auth/auth.types';
import { PeranPengguna } from '../generated/prisma/client';
import { CreateAkunPetugasDto, StatusAkunPetugasDto } from './akun-petugas.dto';
import { AkunPetugasService } from './akun-petugas.service';

@Controller('akun-petugas')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(PeranPengguna.ADMIN)
export class AkunPetugasController {
  constructor(private readonly service: AkunPetugasService) {}

  @Get()
  list() {
    return this.service.list();
  }

  @Post()
  create(
    @Body() dto: CreateAkunPetugasDto,
    @CurrentUser() user: AuthenticatedUser,
  ) {
    return this.service.create(dto, user.id);
  }

  @Patch(':id')
  status(
    @Param('id', new ParseUUIDPipe({ version: '4' })) id: string,
    @Body() dto: StatusAkunPetugasDto,
    @CurrentUser() user: AuthenticatedUser,
  ) {
    return this.service.status(id, dto.aktif, user.id);
  }
}
