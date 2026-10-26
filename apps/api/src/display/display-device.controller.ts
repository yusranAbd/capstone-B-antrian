import { DisplayErrorFilter } from './display-error.filter';
import {
  Body,
  Controller,
  UseFilters,
  Get,
  Header,
  HttpCode,
  Param,
  Patch,
  ParseUUIDPipe,
  Post,
  Req,
  Res,
  UseGuards,
} from '@nestjs/common';
import { Throttle, ThrottlerGuard } from '@nestjs/throttler';
import type { Request, Response } from 'express';
import { Roles } from '../auth/decorators/roles.decorator';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import { PeranPengguna } from '../generated/prisma/client';
import {
  checkDisplayOrigin,
  cookieToken,
  displayCookie,
} from './display-cookie';
import {
  CreateDisplayDeviceDto,
  PairDisplayDto,
  UpdateDisplayDeviceDto,
} from './display-device.dto';
import { DisplayDeviceService } from './display-device.service';
@Controller('perangkat-display')
@UseFilters(DisplayErrorFilter)
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(PeranPengguna.ADMIN)
export class DisplayDeviceController {
  constructor(private readonly devices: DisplayDeviceService) {}
  @Get() @Header('Cache-Control', 'no-store') list() {
    return this.devices.list();
  }
  @Post() create(@Body() dto: CreateDisplayDeviceDto) {
    return this.devices.create(dto);
  }
  @Patch(':id')
  rename(
    @Param('id', new ParseUUIDPipe({ version: '4' })) id: string,
    @Body() dto: UpdateDisplayDeviceDto,
  ) {
    return this.devices.rename(id, dto);
  }
  @Post(':id/aktivasi')
  @HttpCode(200)
  @Header('Cache-Control', 'no-store')
  @UseGuards(ThrottlerGuard)
  @Throttle({ default: { limit: 20, ttl: 60_000 } })
  activation(@Param('id', new ParseUUIDPipe({ version: '4' })) id: string) {
    return this.devices.activation(id);
  }
  @Post(':id/nonaktifkan')
  @HttpCode(200)
  deactivate(@Param('id', new ParseUUIDPipe({ version: '4' })) id: string) {
    return this.devices.deactivate(id);
  }
}
@Controller('display')
@UseFilters(DisplayErrorFilter)
export class DisplayPairingController {
  constructor(private readonly devices: DisplayDeviceService) {}
  @Post('pairing')
  @HttpCode(200)
  @Header('Cache-Control', 'no-store')
  @UseGuards(ThrottlerGuard)
  @Throttle({ default: { limit: 5, ttl: 60_000 } })
  async pair(
    @Body() dto: PairDisplayDto,
    @Req() req: Request,
    @Res({ passthrough: true }) res: Response,
  ) {
    checkDisplayOrigin(req);
    const { token, device } = await this.devices.pair(dto.kode);
    displayCookie(res, token, false, dto.isolasiSesi ? device.id : undefined);
    return device; // No credential in JSON, URL or logs.
  }
  @Get('sesi')
  @Header('Cache-Control', 'no-store')
  session(@Req() req: Request) {
    const id = req.headers['x-display-device-id'];
    return this.devices.session(cookieToken(req.headers.cookie, id), id);
  }
  @Post('putuskan')
  @HttpCode(200)
  @Header('Cache-Control', 'no-store')
  async forget(@Req() req: Request, @Res({ passthrough: true }) res: Response) {
    checkDisplayOrigin(req);
    const id = req.headers['x-display-device-id'];
    const result = await this.devices.forget(cookieToken(req.headers.cookie, id), id);
    displayCookie(res, '', true, typeof id === 'string' ? id : undefined);
    return result;
  }
}
