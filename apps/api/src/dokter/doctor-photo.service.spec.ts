import {
  BadRequestException,
  NotFoundException,
  PayloadTooLargeException,
} from '@nestjs/common';
import sharp from 'sharp';
import { PrismaService } from '../prisma/prisma.service';
import { DoctorPhotoService } from './doctor-photo.service';

describe('Doctor professional photo validation', () => {
  jest.setTimeout(30000);
  const count = jest.fn();
  const service = new DoctorPhotoService(
    { dokter: { count } } as unknown as PrismaService,
    'unused-test-storage',
  );
  beforeEach(() => jest.clearAllMocks());
  it.each(['jpeg', 'png', 'webp'] as const)(
    'decodes %s and emits only a metadata-free raster',
    async (format) => {
      const original = await sharp({
        create: { width: 24, height: 30, channels: 3, background: 'teal' },
      })
        .withMetadata({ exif: { IFD0: { Artist: 'private metadata' } } })
        .toFormat(format)
        .toBuffer();
      const result = await service.normalize(
        Buffer.concat([original, Buffer.from('<script>injected</script>')]),
      );
      const meta = await sharp(result).metadata();
      expect(meta.format).toBe('webp');
      expect(meta.exif).toBeUndefined();
      expect(result.includes(Buffer.from('<script>'))).toBe(false);
    },
  );
  it('rejects oversized and missing bytes', async () => {
    await expect(
      service.normalize(Buffer.alloc(2 * 1024 * 1024 + 1)),
    ).rejects.toThrow(PayloadTooLargeException);
    await expect(service.normalize()).rejects.toThrow(BadRequestException);
  });
  it.each([
    Buffer.from('not an image'),
    Buffer.from(
      '<svg xmlns="http://www.w3.org/2000/svg" width="1" height="1"/>',
    ),
    Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0x00]),
  ])(
    'rejects scripts, SVG and corrupt files despite image-like names/signatures',
    async (input) => {
      await expect(service.normalize(input)).rejects.toThrow(
        BadRequestException,
      );
    },
  );
  it('limits decoded pixels', async () => {
    const image = await sharp({
      create: { width: 4100, height: 4100, channels: 3, background: 'white' },
    })
      .png()
      .toBuffer();
    await expect(service.normalize(image)).rejects.toThrow(BadRequestException);
  });
  it.each(['../.env', '..%2f.env', 'photo.svg', 'not-a-uuid.webp'])(
    'rejects unsafe media references without querying DB',
    async (name) => {
      await expect(service.read(name)).rejects.toThrow(NotFoundException);
      expect(count).not.toHaveBeenCalled();
    },
  );
});
