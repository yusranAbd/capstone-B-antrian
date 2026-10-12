import { Module } from '@nestjs/common';

import { DisplayController } from '../display/display.controller';
import { DisplayService } from '../display/display.service';
import { PrismaModule } from '../prisma/prisma.module';
import { RealtimeModule } from '../realtime/realtime.module';
import { QueueController } from './queue.controller';
import { QueueService } from './queue.service';

@Module({
  imports: [PrismaModule, RealtimeModule],
  controllers: [QueueController, DisplayController],
  providers: [QueueService, DisplayService],
  exports: [QueueService],
})
export class QueueModule {}
