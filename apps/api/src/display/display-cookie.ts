import { ForbiddenException } from '@nestjs/common';
import type { Request, Response } from 'express';

export const DISPLAY_COOKIE = 'queueb_display';
export const DISPLAY_SESSION_MS = 30 * 24 * 60 * 60 * 1000;
const DEVICE_ID = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
/** A public selector is not a credential. Never fall back to another device cookie. */
export function displayCookieName(deviceId?: unknown): string | undefined {
  if (deviceId === undefined) return DISPLAY_COOKIE;
  return typeof deviceId === 'string' && DEVICE_ID.test(deviceId)
    ? DISPLAY_COOKIE + '_' + deviceId.toLowerCase() : undefined;
}
export function cookieToken(cookie: string | undefined, deviceId?: unknown): string | undefined {
  const name = displayCookieName(deviceId);
  if (!name) return undefined;
  const values = cookie
    ?.split(';')
    .map((v) => v.trim())
    .filter((v) => v.startsWith(`${name}=`));
  if (values?.length !== 1) return undefined;
  const value = values[0].slice(name.length + 1);
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
  deviceId?: string,
): void {
  const name = displayCookieName(deviceId);
  if (!name) throw new ForbiddenException('Identitas perangkat display tidak valid');
  res.cookie(name, value, {
    httpOnly: true,
    secure: process.env.NODE_ENV === 'production',
    sameSite: 'strict',
    path: '/',
    maxAge: clear ? 0 : DISPLAY_SESSION_MS,
  });
}
