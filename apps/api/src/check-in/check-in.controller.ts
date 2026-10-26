import {
  Body,
  Controller,
  HttpCode,
  HttpStatus,
  Post,
  UseGuards,
} from '@nestjs/common';

import type { AuthenticatedUser } from '../auth/auth.types';

import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { Roles } from '../auth/decorators/roles.decorator';

import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';

import { PeranPengguna } from '../generated/prisma/client';

import { AutoCheckInService } from './auto-check-in.service';
import { CheckInService } from './check-in.service';
import { ProsesCheckInDto } from './dto/proses-check-in.dto';

@Controller('check-in')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(PeranPengguna.PETUGAS)
export class CheckInController {
  constructor(private readonly checkInService: CheckInService, private readonly autoCheckIn: AutoCheckInService) {}

  @Post()
  @HttpCode(HttpStatus.OK)
  proses(
    @Body() dto: ProsesCheckInDto,
    @CurrentUser() user: AuthenticatedUser,
  ) {
    return this.checkInService.proses(dto, user.id);
  }
  @Post('auto-antrean')
  @HttpCode(HttpStatus.OK)
  otomatis(@Body() dto: ProsesCheckInDto, @CurrentUser() user: AuthenticatedUser) {
    return this.autoCheckIn.proses(dto, user.id);
  }

}
