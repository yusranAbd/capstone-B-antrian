import { createHash } from 'node:crypto';
import { ConflictException, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { Test } from '@nestjs/testing';
import { PeranPengguna } from '../generated/prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { UsersService } from '../users/users.service';
import { AuthService } from './auth.service';
import { PasswordService } from './password.service';

// ==========================================
// DATA PENGGUNA UNTUK PENGUJIAN
// ==========================================

const penggunaUji = {
  id: 'ec8a387e-f186-4324-8c6a-faec174ce55c',
  nama: 'Pengguna Uji',
  email: 'user@test.local',
  kataSandiHash: 'hash-password-uji',
  peran: PeranPengguna.USER,
  aktif: true,
};

// ==========================================
// MOCK DEPENDENCY
// ==========================================

const buatUsersMock = () => ({
  findByEmail: jest.fn(),
  findById: jest.fn(),
  create: jest.fn(),
});

const buatPasswordMock = () => ({
  hash: jest.fn(),
  verify: jest.fn(),
});

const buatJwtMock = () => ({
  signAsync: jest.fn(),
  verifyAsync: jest.fn(),
});

const buatPrismaMock = () => {
  const mock = {
    $executeRaw: jest.fn(),
    $queryRaw: jest.fn().mockResolvedValue([{ id: penggunaUji.id }]),
    dokter: { findFirst: jest.fn() },
    sesiPengguna: {
      create: jest.fn(),
      findUnique: jest.fn(),
      update: jest.fn(),
      updateMany: jest.fn(),
    },
  };
  return {
    ...mock,
    $transaction: jest.fn((fn: (tx: typeof mock) => unknown) => fn(mock)),
  };
};

const hashToken = (token: string): string =>
  createHash('sha256').update(token).digest('hex');

// ==========================================
// AUTH SERVICE TEST
// ==========================================

describe('AuthService', () => {
  let service: AuthService;

  let usersMock: ReturnType<typeof buatUsersMock>;
  let passwordMock: ReturnType<typeof buatPasswordMock>;
  let jwtMock: ReturnType<typeof buatJwtMock>;
  let prismaMock: ReturnType<typeof buatPrismaMock>;

  it('menolak login DOKTER tanpa profil aktif sebelum sesi dibuat', async () => {
    usersMock.findByEmail.mockResolvedValue({
      ...penggunaUji,
      peran: PeranPengguna.DOKTER,
    });
    passwordMock.verify.mockResolvedValue(true);
    prismaMock.dokter.findFirst.mockResolvedValue(null);
    await expect(
      service.login({ email: penggunaUji.email, kataSandi: 'Rahasia123!' }),
    ).rejects.toThrow(UnauthorizedException);
    expect(prismaMock.sesiPengguna.create).not.toHaveBeenCalled();
  });

  it('memakai rotasi dan sesi existing saat login DOKTER bertaut profil aktif', async () => {
    usersMock.findByEmail.mockResolvedValue({
      ...penggunaUji,
      peran: PeranPengguna.DOKTER,
    });
    passwordMock.verify.mockResolvedValue(true);
    prismaMock.dokter.findFirst.mockResolvedValue({ id: 'dokter' });
    jwtMock.signAsync.mockResolvedValue('token');
    const result = await service.login({
      email: penggunaUji.email,
      kataSandi: 'Rahasia123!',
    });
    expect(result.user.peran).toBe('DOKTER');
    expect(prismaMock.sesiPengguna.create).toHaveBeenCalledTimes(1);
  });

  beforeEach(async () => {
    usersMock = buatUsersMock();
    passwordMock = buatPasswordMock();
    jwtMock = buatJwtMock();
    prismaMock = buatPrismaMock();

    const konfigurasi: Record<string, string> = {
      JWT_ACCESS_SECRET: 'access-secret-untuk-testing',
      JWT_REFRESH_SECRET: 'refresh-secret-untuk-testing',
      JWT_ACCESS_EXPIRES_IN: '15m',
      JWT_REFRESH_EXPIRES_IN: '7d',
    };

    const configMock = {
      getOrThrow: jest.fn((key: string): string => {
        const value = konfigurasi[key];

        if (!value) {
          throw new Error(`Konfigurasi tidak tersedia: ${key}`);
        }

        return value;
      }),
    };

    const moduleRef = await Test.createTestingModule({
      providers: [
        AuthService,
        {
          provide: UsersService,
          useValue: usersMock,
        },
        {
          provide: PasswordService,
          useValue: passwordMock,
        },
        {
          provide: JwtService,
          useValue: jwtMock,
        },
        {
          provide: ConfigService,
          useValue: configMock,
        },
        {
          provide: PrismaService,
          useValue: prismaMock,
        },
      ],
    }).compile();

    service = moduleRef.get<AuthService>(AuthService);
  });

  // ========================================
  // 1. REGISTRASI
  // ========================================

  describe('Registrasi', () => {
    it('berhasil membuat pengguna dengan password hash', async () => {
      usersMock.findByEmail.mockResolvedValue(null);

      passwordMock.hash.mockResolvedValue('hash-password-uji');

      usersMock.create.mockResolvedValue(penggunaUji);

      const hasil = await service.register({
        nama: 'Pengguna Uji',
        email: 'USER@TEST.LOCAL',
        kataSandi: 'Rahasia123!',
      });

      expect(hasil).toEqual({
        id: penggunaUji.id,
        nama: penggunaUji.nama,
        email: penggunaUji.email,
        peran: PeranPengguna.USER,
      });

      expect(passwordMock.hash).toHaveBeenCalledWith('Rahasia123!');

      expect(usersMock.create).toHaveBeenCalledWith({
        nama: 'Pengguna Uji',
        email: 'user@test.local',
        kataSandiHash: 'hash-password-uji',
      });

      expect(hasil).not.toHaveProperty('kataSandiHash');
    });

    it('menolak registrasi email yang sudah digunakan', async () => {
      usersMock.findByEmail.mockResolvedValue(penggunaUji);

      await expect(
        service.register({
          nama: 'Pengguna Uji',
          email: 'user@test.local',
          kataSandi: 'Rahasia123!',
        }),
      ).rejects.toThrow(ConflictException);

      expect(usersMock.create).not.toHaveBeenCalled();
    });
  });

  // ========================================
  // 2. LOGIN
  // ========================================

  describe('Login', () => {
    it('berhasil login dan membuat sesi pengguna', async () => {
      usersMock.findByEmail.mockResolvedValue(penggunaUji);

      passwordMock.verify.mockResolvedValue(true);

      jwtMock.signAsync
        .mockResolvedValueOnce('access-token-uji')
        .mockResolvedValueOnce('refresh-token-uji');

      const hasil = await service.login({
        email: 'user@test.local',
        kataSandi: 'Rahasia123!',
        namaPerangkat: 'Postman Windows',
      });

      expect(hasil.accessToken).toBe('access-token-uji');

      expect(hasil.refreshToken).toBe('refresh-token-uji');

      expect(hasil.user.peran).toBe(PeranPengguna.USER);

      expect(prismaMock.sesiPengguna.create).toHaveBeenCalledWith({
        data: expect.objectContaining({
          penggunaId: penggunaUji.id,
          namaPerangkat: 'Postman Windows',
          tokenRefreshHash: hashToken('refresh-token-uji'),
        }),
      });
    });

    it('menolak login dengan password salah', async () => {
      usersMock.findByEmail.mockResolvedValue(penggunaUji);

      passwordMock.verify.mockResolvedValue(false);

      await expect(
        service.login({
          email: 'user@test.local',
          kataSandi: 'PasswordSalah123!',
        }),
      ).rejects.toThrow(UnauthorizedException);

      expect(prismaMock.sesiPengguna.create).not.toHaveBeenCalled();
    });

    it('menolak login pengguna tidak aktif', async () => {
      usersMock.findByEmail.mockResolvedValue({
        ...penggunaUji,
        aktif: false,
      });

      await expect(
        service.login({
          email: 'user@test.local',
          kataSandi: 'Rahasia123!',
        }),
      ).rejects.toThrow(UnauthorizedException);

      expect(passwordMock.verify).not.toHaveBeenCalled();
    });
  });

  // ========================================
  // 3. REFRESH TOKEN
  // ========================================

  describe('Refresh Token', () => {
    it('menolak refresh token dari sesi yang dicabut', async () => {
      jwtMock.verifyAsync.mockResolvedValue({
        sub: penggunaUji.id,
        sid: 'session-uji',
        type: 'refresh',
        jti: 'jti-sesi-dicabut',
      });

      prismaMock.sesiPengguna.findUnique.mockResolvedValue({
        id: 'session-uji',
        penggunaId: penggunaUji.id,
        dicabutPada: new Date(),
        kedaluwarsaPada: new Date(Date.now() + 60_000),
        tokenRefreshHash: hashToken('refresh-token-lama'),
      });

      await expect(
        service.refresh({
          refreshToken: 'refresh-token-lama',
        }),
      ).rejects.toThrow(UnauthorizedException);

      expect(jwtMock.signAsync).not.toHaveBeenCalled();

      expect(prismaMock.sesiPengguna.updateMany).not.toHaveBeenCalled();
    });

    it('menolak refresh token yang tidak valid', async () => {
      jwtMock.verifyAsync.mockRejectedValue(new Error('Invalid signature'));

      await expect(
        service.refresh({
          refreshToken: 'token-tidak-valid',
        }),
      ).rejects.toThrow(UnauthorizedException);

      expect(prismaMock.sesiPengguna.updateMany).not.toHaveBeenCalled();
    });

    it('hanya mengizinkan satu rotasi dari dua request bersamaan', async () => {
      const refreshTokenLama = 'refresh-token-lama';

      const hashLama = hashToken(refreshTokenLama);

      let hashAktif = hashLama;
      let nomorToken = 0;

      // Token lama dianggap valid secara kriptografis.
      jwtMock.verifyAsync.mockResolvedValue({
        sub: penggunaUji.id,
        sid: 'session-uji',
        type: 'refresh',
        jti: 'jti-lama',
      });

      // Kedua request membaca sesi yang sama.
      prismaMock.sesiPengguna.findUnique.mockImplementation(async () => ({
        id: 'session-uji',
        penggunaId: penggunaUji.id,
        dicabutPada: null,
        kedaluwarsaPada: new Date(Date.now() + 60_000),
        tokenRefreshHash: hashLama,
      }));

      usersMock.findById.mockResolvedValue(penggunaUji);

      // Simulasi pembuatan JWT baru.
      jwtMock.signAsync.mockImplementation(
        async (payload: { type?: string; jti?: string }) => {
          nomorToken += 1;

          if (payload.type === 'refresh') {
            return `refresh-baru-${nomorToken}`;
          }

          return `access-baru-${nomorToken}`;
        },
      );

      // Simulasi atomic compare-and-swap.
      prismaMock.sesiPengguna.updateMany.mockImplementation(
        async (args: {
          where: {
            tokenRefreshHash: string;
          };
          data: {
            tokenRefreshHash: string;
          };
        }) => {
          if (args.where.tokenRefreshHash !== hashAktif) {
            return { count: 0 };
          }

          hashAktif = args.data.tokenRefreshHash;

          return { count: 1 };
        },
      );

      // Dua request menggunakan refresh token yang sama.
      const hasil = await Promise.allSettled([
        service.refresh({
          refreshToken: refreshTokenLama,
        }),
        service.refresh({
          refreshToken: refreshTokenLama,
        }),
      ]);

      const berhasil = hasil.filter((item) => item.status === 'fulfilled');

      const ditolak = hasil.filter((item) => item.status === 'rejected');

      expect(berhasil).toHaveLength(1);
      expect(ditolak).toHaveLength(1);

      expect(prismaMock.sesiPengguna.updateMany).toHaveBeenCalledTimes(2);

      // Memastikan refresh token memiliki jti unik.
      const refreshPayloads = jwtMock.signAsync.mock.calls
        .map(
          (call) =>
            call[0] as {
              type?: string;
              jti?: string;
            },
        )
        .filter((payload) => payload.type === 'refresh');

      expect(refreshPayloads).toHaveLength(2);

      expect(refreshPayloads[0].jti).toBeDefined();
      expect(refreshPayloads[1].jti).toBeDefined();

      expect(refreshPayloads[0].jti).not.toBe(refreshPayloads[1].jti);
    });
  });

  // ========================================
  // 4. LOGOUT
  // ========================================

  describe('Logout', () => {
    it('berhasil mencabut sesi pengguna', async () => {
      const refreshToken = 'refresh-token-uji';

      jwtMock.verifyAsync.mockResolvedValue({
        sub: penggunaUji.id,
        sid: 'session-uji',
        type: 'refresh',
        jti: 'jti-logout-uji',
      });

      prismaMock.sesiPengguna.findUnique.mockResolvedValue({
        id: 'session-uji',
        penggunaId: penggunaUji.id,
        tokenRefreshHash: hashToken(refreshToken),
        dicabutPada: null,
      });

      const hasil = await service.logout({
        refreshToken,
      });

      expect(hasil).toEqual({
        message: 'Logout berhasil',
      });

      expect(prismaMock.sesiPengguna.update).toHaveBeenCalledWith({
        where: {
          id: 'session-uji',
        },
        data: {
          dicabutPada: expect.any(Date),
        },
      });
    });
  });
});
