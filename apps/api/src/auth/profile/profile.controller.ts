import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  Patch,
  Post,
  Res,
  UploadedFile,
  UseGuards,
  UseInterceptors,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { Throttle } from '@nestjs/throttler';
import type { Response } from 'express';
import type { AuthenticatedUser } from '../auth.types';
import { CurrentUser } from '../decorators/current-user.decorator';
import { JwtAuthGuard } from '../guards/jwt-auth.guard';
import { ChangeOwnPasswordDto, UpdateOwnProfileDto } from './profile.dto';
import { ProfileService } from './profile.service';
import { ProfileThrottleGuard } from './profile-throttle.guard';
import {
  UserAvatarService,
  MAX_USER_AVATAR_BYTES,
} from './user-avatar.service';

@Controller('auth/me')
@UseGuards(JwtAuthGuard)
export class ProfileController {
  constructor(
    private readonly profile: ProfileService,
    private readonly avatar: UserAvatarService,
  ) {}
  @Patch()
  update(
    @CurrentUser() user: AuthenticatedUser,
    @Body() dto: UpdateOwnProfileDto,
  ) {
    return this.profile.update(user.id, dto);
  }

  @Post('avatar')
  @UseGuards(ProfileThrottleGuard)
  @Throttle({ default: { limit: 10, ttl: 60000 } })
  @UseInterceptors(
    FileInterceptor('foto', {
      limits: {
        fileSize: MAX_USER_AVATAR_BYTES,
        files: 1,
        fields: 0,
        parts: 1,
      },
    }),
  )
  upload(
    @CurrentUser() user: AuthenticatedUser,
    @UploadedFile() file?: { buffer: Buffer },
  ) {
    return this.avatar.upload(user.id, file?.buffer, user.id);
  }

  @Delete('avatar')
  remove(@CurrentUser() user: AuthenticatedUser) {
    return this.avatar.remove(user.id, user.id);
  }

  @Get('avatar')
  async readAvatar(
    @CurrentUser() user: AuthenticatedUser,
    @Res() res: Response,
  ) {
    const bytes = await this.avatar.readOwn(user.id);
    res.set({
      'Content-Type': 'image/webp',
      'X-Content-Type-Options': 'nosniff',
      'Cache-Control': 'private, no-store',
      'Content-Security-Policy': "default-src 'none'",
    });
    res.send(bytes);
  }

  @Post('password')
  @HttpCode(200)
  @UseGuards(ProfileThrottleGuard)
  @Throttle({ default: { limit: 5, ttl: 60000 } })
  password(
    @CurrentUser() user: AuthenticatedUser,
    @Body() dto: ChangeOwnPasswordDto,
  ) {
    return this.profile.changePassword(user.id, dto);
  }
}
