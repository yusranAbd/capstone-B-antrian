import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { PassportModule } from '@nestjs/passport';
import { PrismaModule } from '../prisma/prisma.module';
import { UsersModule } from '../users/users.module';
import { AuthController } from './auth.controller';
import { AuthService } from './auth.service';
import { JwtAuthGuard } from './guards/jwt-auth.guard';
import { RolesGuard } from './guards/roles.guard';
import { JwtStrategy } from './jwt.strategy';
import { PasswordService } from './password.service';
import { resolve } from 'node:path';
import { ProfileController } from './profile/profile.controller';
import { ProfileService } from './profile/profile.service';
import { ProfileThrottleGuard } from './profile/profile-throttle.guard';
import {
  USER_AVATAR_ROOT,
  UserAvatarService,
} from './profile/user-avatar.service';

@Module({
  imports: [
    UsersModule,
    PrismaModule,
    PassportModule.register({
      defaultStrategy: 'jwt',
    }),
    JwtModule.register({}),
  ],
  controllers: [AuthController, ProfileController],
  providers: [
    ProfileService,
    ProfileThrottleGuard,
    UserAvatarService,
    {
      provide: USER_AVATAR_ROOT,
      useFactory: () =>
        resolve(process.env.USER_AVATAR_DIR?.trim() || '.queueb-media/avatar'),
    },
    AuthService,
    PasswordService,
    JwtStrategy,
    JwtAuthGuard,
    RolesGuard,
  ],
  exports: [
    PasswordService,
    JwtAuthGuard,
    RolesGuard,
    PassportModule,
    JwtModule,
    JwtStrategy,
  ],
})
export class AuthModule {}
