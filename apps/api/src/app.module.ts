import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { ThrottlerModule } from '@nestjs/throttler';

import { AuthModule } from './auth/auth.module';
import { validateEnvironment } from './config/env.validation';
import { HealthModule } from './health/health.module';
import { LayananModule } from './layanan/layanan.module';
import { LoketModule } from './loket/loket.module';
import { JadwalLayananModule } from './jadwal-layanan/jadwal-layanan.module';
import { PenugasanPetugasModule } from './penugasan-petugas/penugasan-petugas.module';
import { ReservasiModule } from './reservasi/reservasi.module';
import { TiketModule } from './tiket/tiket.module';
import { QrModule } from './qr/qr.module';
import { CheckInModule } from './check-in/check-in.module';
import { QueueModule } from './queue/queue.module';
import { RealtimeModule } from './realtime/realtime.module';
import { DokterModule } from './dokter/dokter.module';

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
      envFilePath: ['../../.env', '.env'],
      validate: validateEnvironment,
    }),

    ThrottlerModule.forRoot([
      {
        ttl: 60_000,
        limit: 100,
      },
    ]),

    HealthModule,
    AuthModule,
    LayananModule,
    LoketModule,
    JadwalLayananModule,
    PenugasanPetugasModule,
    DokterModule,
    ReservasiModule,
    TiketModule,
    QrModule,
    CheckInModule,
    QueueModule,
    RealtimeModule,
  ],
})
export class AppModule {}
