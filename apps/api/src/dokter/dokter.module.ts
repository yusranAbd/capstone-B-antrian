import { Module } from '@nestjs/common';

import { AuthModule } from '../auth/auth.module';
import { PrismaModule } from '../prisma/prisma.module';
import { DokterController } from './dokter.controller';
import { DokterService } from './dokter.service';

@Module({
  imports: [PrismaModule, AuthModule],
  controllers: [DokterController],
  providers: [DokterService],
  exports: [DokterService],
})
export class DokterModule {}
