import { DisplayErrorFilter } from './display-error.filter';
import {
  Controller,
  UseFilters,
  Get,
  Header,
  Headers,
  Param,
  ParseUUIDPipe,
} from '@nestjs/common';

import { cookieToken } from './display-cookie';
import { DisplayService } from './display.service';

/**
 * Akses khusus perangkat display. Bukan endpoint pengguna atau admin.
 * Token rahasia dikirim lewat header, bukan URL, dan hanya mengizinkan baca.
 */
@Controller('display')
@UseFilters(DisplayErrorFilter)
export class DisplayController {
  constructor(private readonly displayService: DisplayService) {}

  @Get(':layananId/snapshot')
  @Header('Cache-Control', 'no-store')
  snapshot(
    @Param('layananId', new ParseUUIDPipe({ version: '4' })) layananId: string,
    @Headers('x-display-token') token: string | undefined,
    @Headers('cookie') cookie?: string,
    @Headers('x-display-device-id') deviceId?: string,
  ) {
    return this.displayService.snapshot(layananId, token ?? cookieToken(cookie, deviceId), deviceId);
  }
}
