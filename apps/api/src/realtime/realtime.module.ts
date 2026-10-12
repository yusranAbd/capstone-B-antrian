import { Module } from '@nestjs/common';

import { AuthModule } from '../auth/auth.module';
import { PrismaModule } from '../prisma/prisma.module';
import { RealtimeGateway } from './realtime.gateway';
import { DisplayRealtimeGateway } from './display-realtime.gateway';
import { DisplayRealtimeAccessService } from './display-realtime-access.service';
import { RealtimeBroadcastService } from './realtime-broadcast.service';
import { RealtimeRoomAccessService } from './realtime-room-access.service';

@Module({
  imports: [AuthModule, PrismaModule],
  providers: [
    RealtimeGateway,
    RealtimeRoomAccessService,
    DisplayRealtimeGateway,
    DisplayRealtimeAccessService,
    RealtimeBroadcastService,
  ],
  exports: [RealtimeBroadcastService],
})
export class RealtimeModule {}
