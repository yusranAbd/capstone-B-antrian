import { validateEnvironment } from './env.validation';

describe('validateEnvironment, konfigurasi frontend dan timezone', () => {
  const dasar: Record<string, unknown> = {
    NODE_ENV: 'test',
    DATABASE_URL: 'postgresql://test:test@localhost:5433/capstone_antrean_test',
    JWT_ACCESS_SECRET: 'contoh_access_secret_aman_12345678',
    JWT_REFRESH_SECRET: 'contoh_refresh_secret_aman_87654321',
  };

  it('menetapkan origin development dan timezone default', () => {
    const config = validateEnvironment(dasar);
    expect(config.CORS_ALLOWED_ORIGINS).toEqual([
      'http://localhost:3000',
      'http://localhost:5173',
    ]);
    expect(config.SERVICE_TIME_ZONE).toBe('Asia/Jakarta');
  });

  it('menerima origin konfigurasi serta menghapus duplikasi', () => {
    const config = validateEnvironment({
      ...dasar,
      CORS_ALLOWED_ORIGINS: 'https://queueb.example.org,https://queueb.example.org',
    });
    expect(config.CORS_ALLOWED_ORIGINS).toEqual(['https://queueb.example.org']);
  });

  it('memerlukan daftar origin eksplisit pada production', () => {
    expect(() => validateEnvironment({ ...dasar, NODE_ENV: 'production' }))
      .toThrow('CORS_ALLOWED_ORIGINS');
  });

  it.each([
    '*',
    'https://queueb.example.org/path',
    'javascript:alert(1)',
    'https://queueb.example.org,',
  ])('menolak origin tidak valid: %s', (value) => {
    expect(() => validateEnvironment({ ...dasar, CORS_ALLOWED_ORIGINS: value }))
      .toThrow('CORS_ALLOWED_ORIGINS');
  });

  it('menolak timezone tidak valid', () => {
    expect(() => validateEnvironment({ ...dasar, SERVICE_TIME_ZONE: 'Bukan/Zona' }))
      .toThrow('SERVICE_TIME_ZONE');
  });

  it('menerima timezone IANA yang sah', () => {
    const config = validateEnvironment({ ...dasar, SERVICE_TIME_ZONE: 'Asia/Jayapura' });
    expect(config.SERVICE_TIME_ZONE).toBe('Asia/Jayapura');
  });
});
