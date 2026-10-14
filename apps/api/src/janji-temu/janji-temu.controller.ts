import { Body, Controller, Get, Param, ParseUUIDPipe, Post, UseGuards } from '@nestjs/common';
import type { AuthenticatedUser } from '../auth/auth.types';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { Roles } from '../auth/decorators/roles.decorator';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import { PeranPengguna } from '../generated/prisma/client';
import { CreateJanjiTemuDto } from './dto/create-janji-temu.dto';
import { JanjiTemuService } from './janji-temu.service';

@Controller('janji-temu')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(PeranPengguna.USER)
export class JanjiTemuController {
  constructor(private readonly service: JanjiTemuService) {}

  @Post()
  create(@Body() dto: CreateJanjiTemuDto, @CurrentUser() user: AuthenticatedUser) {
    return this.service.create(dto, user.id);
  }

  @Get()
  findAll(@CurrentUser() user: AuthenticatedUser) {
    return this.service.findAll(user.id);
  }

  @Get(':id')
  findOne(@Param('id', ParseUUIDPipe) id: string, @CurrentUser() user: AuthenticatedUser) {
    return this.service.findOne(id, user.id);
  }

  @Post(':id/batalkan')
  batalkan(@Param('id', ParseUUIDPipe) id: string, @CurrentUser() user: AuthenticatedUser) {
    return this.service.batalkan(id, user.id);
  }
}
