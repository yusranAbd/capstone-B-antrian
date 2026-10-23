import { Module } from '@nestjs/common';
import { PrismaModule } from '../prisma/prisma.module';
import { RealtimeModule } from '../realtime/realtime.module';
import { AdminDeleteController } from './admin-delete.controller';
import { AdminDeleteService } from './admin-delete.service';
@Module({
  imports: [PrismaModule, RealtimeModule],
  controllers: [AdminDeleteController],
  providers: [AdminDeleteService],
})
export class AdminDeleteModule {}
