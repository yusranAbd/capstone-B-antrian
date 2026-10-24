import { Controller, Get, Header, Param, StreamableFile } from '@nestjs/common';
import { DoctorPhotoService } from './doctor-photo.service';

// Only professional, explicitly referenced rasters are public. No static directory
// mount, bearer token in URL, account avatar, or filesystem path is exposed.
@Controller('media/dokter')
export class DoctorMediaController {
  constructor(private readonly photos: DoctorPhotoService) {}

  @Get(':filename')
  @Header('X-Content-Type-Options', 'nosniff')
  @Header('Content-Security-Policy', "default-src 'none'; sandbox")
  @Header('Cache-Control', 'no-cache')
  async read(@Param('filename') filename: string) {
    return new StreamableFile(await this.photos.read(filename), {
      type: 'image/webp',
      disposition: 'inline',
    });
  }
}
