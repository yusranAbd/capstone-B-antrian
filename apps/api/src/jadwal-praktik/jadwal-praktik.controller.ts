import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';
import type { AuthenticatedUser } from '../auth/auth.types';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { Roles } from '../auth/decorators/roles.decorator';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import { PeranPengguna } from '../generated/prisma/client';
import { CariJadwalPraktikDto } from './dto/cari-jadwal-praktik.dto';
import { CreateJadwalPraktikDto } from './dto/create-jadwal-praktik.dto';
import { UpdateJadwalPraktikDto } from './dto/update-jadwal-praktik.dto';
import { JadwalPraktikService } from './jadwal-praktik.service';

@Controller('jadwal-praktik')
@UseGuards(JwtAuthGuard, RolesGuard)
export class JadwalPraktikController {
  constructor(private readonly jadwalPraktikService: JadwalPraktikService) {}

  @Post()
  @Roles(PeranPengguna.ADMIN)
  create(@Body() dto: CreateJadwalPraktikDto) {
    return this.jadwalPraktikService.create(dto);
  }

  @Get()
  findAll(
    @CurrentUser() user: AuthenticatedUser,
    @Query() query: CariJadwalPraktikDto,
  ) {
    return this.jadwalPraktikService.findAll(user.peran, query);
  }

  @Get(':id')
  findOne(
    @Param('id', ParseUUIDPipe) id: string,
    @CurrentUser() user: AuthenticatedUser,
  ) {
    return this.jadwalPraktikService.findOne(id, user.peran);
  }

  @Patch(':id')
  @Roles(PeranPengguna.ADMIN)
  update(@Param('id', ParseUUIDPipe) id: string, @Body() dto: UpdateJadwalPraktikDto) {
    return this.jadwalPraktikService.update(id, dto);
  }

  @Delete(':id')
  @Roles(PeranPengguna.ADMIN)
  remove(@Param('id', ParseUUIDPipe) id: string) {
    return this.jadwalPraktikService.remove(id);
  }
}
