import {
  Body, Controller, Delete, Get, Param, ParseUUIDPipe, Patch, Post, Query, UseGuards,
} from '@nestjs/common';
import type { AuthenticatedUser } from '../auth/auth.types';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { Roles } from '../auth/decorators/roles.decorator';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import { PeranPengguna } from '../generated/prisma/client';
import { CariSlotPraktikDto } from './dto/cari-slot-praktik.dto';
import { CreateSlotPraktikDto } from './dto/create-slot-praktik.dto';
import { UpdateSlotPraktikDto } from './dto/update-slot-praktik.dto';
import { SlotPraktikService } from './slot-praktik.service';

@Controller('slot-praktik')
@UseGuards(JwtAuthGuard, RolesGuard)
export class SlotPraktikController {
  constructor(private readonly service: SlotPraktikService) {}

  @Post()
  @Roles(PeranPengguna.ADMIN)
  create(@Body() dto: CreateSlotPraktikDto) {
    return this.service.create(dto);
  }

  @Get()
  findAll(@CurrentUser() user: AuthenticatedUser, @Query() query: CariSlotPraktikDto) {
    return this.service.findAll(user.peran, query);
  }

  @Get(':id')
  findOne(@Param('id', ParseUUIDPipe) id: string, @CurrentUser() user: AuthenticatedUser) {
    return this.service.findOne(id, user.peran);
  }

  @Patch(':id')
  @Roles(PeranPengguna.ADMIN)
  update(@Param('id', ParseUUIDPipe) id: string, @Body() dto: UpdateSlotPraktikDto) {
    return this.service.update(id, dto);
  }

  @Delete(':id')
  @Roles(PeranPengguna.ADMIN)
  remove(@Param('id', ParseUUIDPipe) id: string) {
    return this.service.remove(id);
  }
}
