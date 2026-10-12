import { Module } from '@nestjs/common';

import { AuthModule } from '../auth/auth.module';
import { PrismaModule } from '../prisma/prisma.module';
import { RealtimeGateway } from './realtime.gateway';
import { RealtimeRoomAccessService } from './realtime-room-access.service';

@Module({
  imports: [AuthModule, PrismaModule],
  providers: [RealtimeGateway, RealtimeRoomAccessService],
})
export class RealtimeModule {}
