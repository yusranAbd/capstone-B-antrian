import { Module } from '@nestjs/common';
import { APP_INTERCEPTOR } from '@nestjs/core';

import { AuthModule } from '../auth/auth.module';
import { PrismaModule } from '../prisma/prisma.module';
import { RealtimeGateway } from './realtime.gateway';
import { DisplayRealtimeGateway } from './display-realtime.gateway';
import { DisplayRealtimeAccessService } from './display-realtime-access.service';
import { RealtimeBroadcastService } from './realtime-broadcast.service';
import { RealtimeRoomAccessService } from './realtime-room-access.service';
import { PatientRealtimeGateway } from './patient-realtime.gateway';
import { PatientInvalidationInterceptor } from './patient-invalidation.interceptor';

@Module({
  imports: [AuthModule, PrismaModule],
  providers: [
    RealtimeGateway,
    RealtimeRoomAccessService,
    DisplayRealtimeGateway,
    DisplayRealtimeAccessService,
    RealtimeBroadcastService,
    PatientRealtimeGateway,
    { provide: APP_INTERCEPTOR, useClass: PatientInvalidationInterceptor },
  ],
  exports: [RealtimeBroadcastService],
})
export class RealtimeModule {}
