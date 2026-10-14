import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { PrismaModule } from '../prisma/prisma.module';
import { SlotPraktikController } from './slot-praktik.controller';
import { SlotPraktikService } from './slot-praktik.service';

@Module({
  imports: [PrismaModule, AuthModule],
  controllers: [SlotPraktikController],
  providers: [SlotPraktikService],
  exports: [SlotPraktikService],
})
export class SlotPraktikModule {}
