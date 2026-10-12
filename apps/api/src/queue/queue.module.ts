import { Module } from '@nestjs/common';

import { PrismaModule } from '../prisma/prisma.module';
import { RealtimeModule } from '../realtime/realtime.module';
import { QueueController } from './queue.controller';
import { QueueService } from './queue.service';

@Module({
  imports: [PrismaModule, RealtimeModule],
  controllers: [QueueController],
  providers: [QueueService],
  exports: [QueueService],
})
export class QueueModule {}
