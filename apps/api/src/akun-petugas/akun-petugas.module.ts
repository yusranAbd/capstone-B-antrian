import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { PrismaModule } from '../prisma/prisma.module';
import { AkunPetugasController } from './akun-petugas.controller';
import { AkunPetugasService } from './akun-petugas.service';

@Module({
  imports: [AuthModule, PrismaModule],
  controllers: [AkunPetugasController],
  providers: [AkunPetugasService],
})
export class AkunPetugasModule {}
