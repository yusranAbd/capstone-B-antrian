import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { PrismaModule } from '../prisma/prisma.module';
import { JadwalPraktikController } from './jadwal-praktik.controller';
import { JadwalPraktikService } from './jadwal-praktik.service';

@Module({
  imports: [PrismaModule, AuthModule],
  controllers: [JadwalPraktikController],
  providers: [JadwalPraktikService],
  exports: [JadwalPraktikService],
})
export class JadwalPraktikModule {}
