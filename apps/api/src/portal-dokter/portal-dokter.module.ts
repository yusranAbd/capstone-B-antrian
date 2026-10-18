import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { PrismaModule } from '../prisma/prisma.module';
import { PortalDokterController } from './portal-dokter.controller';
import { PortalDokterService } from './portal-dokter.service';
@Module({
  imports: [AuthModule, PrismaModule],
  controllers: [PortalDokterController],
  providers: [PortalDokterService],
})
export class PortalDokterModule {}
