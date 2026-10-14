import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { PrismaModule } from '../prisma/prisma.module';
import { JanjiTemuController } from './janji-temu.controller';
import { JanjiTemuService } from './janji-temu.service';

@Module({
  imports: [PrismaModule, AuthModule],
  controllers: [JanjiTemuController],
  providers: [JanjiTemuService],
  exports: [JanjiTemuService],
})
export class JanjiTemuModule {}
