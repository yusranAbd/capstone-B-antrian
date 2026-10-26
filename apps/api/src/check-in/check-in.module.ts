import { AutoCheckInService } from './auto-check-in.service';
import { QueueModule } from '../queue/queue.module';
import { RealtimeModule } from '../realtime/realtime.module';
import { Module } from '@nestjs/common';

import { AuthModule } from '../auth/auth.module';
import { PrismaModule } from '../prisma/prisma.module';

import { CheckInController } from './check-in.controller';
import { CheckInService } from './check-in.service';

@Module({
  imports: [AuthModule, PrismaModule, QueueModule, RealtimeModule],
  controllers: [CheckInController],
  providers: [CheckInService, AutoCheckInService],
  exports: [CheckInService],
})
export class CheckInModule {}
