import { Injectable } from '@nestjs/common';
import { ThrottlerGuard } from '@nestjs/throttler';
import type { AuthenticatedUser } from '../auth.types';

@Injectable()
export class ProfileThrottleGuard extends ThrottlerGuard {
  protected getTracker(req: Record<string, unknown>): Promise<string> {
    const user = req.user as AuthenticatedUser | undefined;
    return user ? Promise.resolve(`profile:${user.id}`) : super.getTracker(req);
  }
}
