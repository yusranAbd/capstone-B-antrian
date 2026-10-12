export function validateEnvironment(
  config: Record<string, unknown>,
): Record<string, unknown> {
  // =========================
  // API PORT
  // =========================
  const rawApiPort = config.API_PORT ?? 3000;
  const apiPort =
    typeof rawApiPort === 'number' ? rawApiPort : Number(rawApiPort);

  if (!Number.isInteger(apiPort) || apiPort < 1 || apiPort > 65535) {
    throw new Error('API_PORT harus berupa angka antara 1 dan 65535');
  }

  // =========================
  // DATABASE
  // =========================
  const databaseUrl =
    typeof config.DATABASE_URL === 'string' ? config.DATABASE_URL.trim() : '';

  if (!databaseUrl) {
    throw new Error('DATABASE_URL wajib tersedia');
  }

  try {
    const parsedDatabaseUrl = new URL(databaseUrl);

    if (
      parsedDatabaseUrl.protocol !== 'postgresql:' &&
      parsedDatabaseUrl.protocol !== 'postgres:'
    ) {
      throw new Error();
    }
  } catch {
    throw new Error(
      'DATABASE_URL harus berupa connection string PostgreSQL yang valid',
    );
  }

  // =========================
  // JWT ACCESS SECRET
  // =========================
  const jwtAccessSecret =
    typeof config.JWT_ACCESS_SECRET === 'string'
      ? config.JWT_ACCESS_SECRET.trim()
      : '';

  if (jwtAccessSecret.length < 16) {
    throw new Error('JWT_ACCESS_SECRET minimal harus memiliki 16 karakter');
  }

  // =========================
  // JWT REFRESH SECRET
  // =========================
  const jwtRefreshSecret =
    typeof config.JWT_REFRESH_SECRET === 'string'
      ? config.JWT_REFRESH_SECRET.trim()
      : '';

  if (jwtRefreshSecret.length < 16) {
    throw new Error('JWT_REFRESH_SECRET minimal harus memiliki 16 karakter');
  }

  if (jwtAccessSecret === jwtRefreshSecret) {
    throw new Error('JWT_ACCESS_SECRET dan JWT_REFRESH_SECRET harus berbeda');
  }

  // =========================
  // JWT EXPIRATION
  // =========================
  const jwtAccessExpiresIn =
    typeof config.JWT_ACCESS_EXPIRES_IN === 'string'
      ? config.JWT_ACCESS_EXPIRES_IN.trim()
      : '15m';

  const jwtRefreshExpiresIn =
    typeof config.JWT_REFRESH_EXPIRES_IN === 'string'
      ? config.JWT_REFRESH_EXPIRES_IN.trim()
      : '7d';

  if (!jwtAccessExpiresIn) {
    throw new Error('JWT_ACCESS_EXPIRES_IN tidak boleh kosong');
  }

  if (!jwtRefreshExpiresIn) {
    throw new Error('JWT_REFRESH_EXPIRES_IN tidak boleh kosong');
  }

  // =========================
  // CORS ALLOWED ORIGINS (BROWSER REST API)
  // =========================
  const rawOrigins = config.CORS_ALLOWED_ORIGINS;
  if (rawOrigins !== undefined && typeof rawOrigins !== 'string') {
    throw new Error('CORS_ALLOWED_ORIGINS harus berisi daftar origin dipisahkan koma');
  }

  const production = config.NODE_ENV === 'production';
  const origins = rawOrigins === undefined
    ? production
      ? []
      : ['http://localhost:3000', 'http://localhost:5173']
    : rawOrigins.split(',').map((origin) => origin.trim());

  if (origins.length === 0 || origins.some((origin) => !origin)) {
    throw new Error('CORS_ALLOWED_ORIGINS wajib diisi dengan origin yang valid');
  }

  for (const origin of origins) {
    try {
      const url = new URL(origin);
      if (
        (url.protocol !== 'http:' && url.protocol !== 'https:') ||
        url.origin !== origin
      ) {
        throw new Error();
      }
    } catch {
      throw new Error(`CORS_ALLOWED_ORIGINS berisi origin tidak valid: ${origin}`);
    }
  }

  // =========================
  // TIME ZONE LAYANAN
  // =========================
  const serviceTimeZone = config.SERVICE_TIME_ZONE ?? 'Asia/Jakarta';
  if (typeof serviceTimeZone !== 'string' || !serviceTimeZone.trim()) {
    throw new Error('SERVICE_TIME_ZONE harus berupa nama timezone IANA');
  }
  try {
    new Intl.DateTimeFormat('en-US', { timeZone: serviceTimeZone });
  } catch {
    throw new Error('SERVICE_TIME_ZONE harus berupa nama timezone IANA yang valid');
  }

  // =========================
  // FINAL CONFIG
  // =========================
  return {
    ...config,

    API_PORT: apiPort,
    DATABASE_URL: databaseUrl,

    JWT_ACCESS_SECRET: jwtAccessSecret,
    JWT_REFRESH_SECRET: jwtRefreshSecret,

    JWT_ACCESS_EXPIRES_IN: jwtAccessExpiresIn,
    JWT_REFRESH_EXPIRES_IN: jwtRefreshExpiresIn,
    CORS_ALLOWED_ORIGINS: [...new Set(origins)],
    SERVICE_TIME_ZONE: serviceTimeZone,
  };
}
