import { INestApplication, ValidationPipe } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

export function configureApp(app: INestApplication): void {
  const config = app.get(ConfigService);
  const allowedOrigins = config.get<string[]>('CORS_ALLOWED_ORIGINS') ?? [];

  // Origin HTTP khusus browser. Autentikasi dan otorisasi tetap di endpoint.
  // Socket.IO memerlukan pemeriksaan origin terpisah pada kedua gateway.
  app.enableCors({ origin: allowedOrigins, credentials: true });

  app.setGlobalPrefix('api/v1');

  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true,
    }),
  );
}
