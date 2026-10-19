import { ForbiddenException } from '@nestjs/common';
import type { Request, Response } from 'express';

export const DISPLAY_COOKIE = 'queueb_display';
export const DISPLAY_SESSION_MS = 30 * 24 * 60 * 60 * 1000;
export function cookieToken(cookie: string | undefined): string | undefined {
  const values = cookie
    ?.split(';')
    .map((v) => v.trim())
    .filter((v) => v.startsWith(`${DISPLAY_COOKIE}=`));
  if (values?.length !== 1) return undefined;
  const value = values[0].slice(DISPLAY_COOKIE.length + 1);
  return /^[a-f0-9]{64}$/i.test(value) ? value : undefined;
}
export function checkDisplayOrigin(req: Request): void {
  const origin = req.headers.origin;
  if (origin === undefined) return; // Native clients do not send Origin.
  const origins =
    process.env.CORS_ALLOWED_ORIGINS?.split(',').map((v) => v.trim()) ??
    (process.env.NODE_ENV === 'production'
      ? []
      : ['http://localhost:3000', 'http://localhost:5173']);
  if (!origins.includes(origin))
    throw new ForbiddenException('Origin aktivasi display tidak diizinkan');
}
export function displayCookie(
  res: Response,
  value: string,
  clear = false,
): void {
  res.cookie(DISPLAY_COOKIE, value, {
    httpOnly: true,
    secure: process.env.NODE_ENV === 'production',
    sameSite: 'strict',
    path: '/',
    maxAge: clear ? 0 : DISPLAY_SESSION_MS,
  });
}
