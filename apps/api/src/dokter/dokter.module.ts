import { Module } from '@nestjs/common';

import { AuthModule } from '../auth/auth.module';
import { PrismaModule } from '../prisma/prisma.module';
import { DokterController } from './dokter.controller';
import { DokterService } from './dokter.service';
import { resolve } from 'node:path';
import { DoctorMediaController } from './doctor-media.controller';
import { DOCTOR_MEDIA_ROOT, DoctorPhotoService } from './doctor-photo.service';

@Module({
  imports: [PrismaModule, AuthModule],
  controllers: [DokterController, DoctorMediaController],
  providers: [
    DokterService,
    DoctorPhotoService,
    {
      provide: DOCTOR_MEDIA_ROOT,
      useFactory: () =>
        resolve(process.env.DOCTOR_MEDIA_DIR?.trim() || '.queueb-media/dokter'),
    },
  ],
  exports: [DokterService],
})
export class DokterModule {}
