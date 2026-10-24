import { BadRequestException, PayloadTooLargeException } from '@nestjs/common';
import sharp from 'sharp';
export const MAX_PROFILE_PHOTO_BYTES = 2 * 1024 * 1024;
export async function normalizeProfileImage(input?: Buffer): Promise<Buffer> {
  if (!input?.length)
    throw new BadRequestException('Pilih foto JPEG, PNG atau WebP');
  if (input.length > MAX_PROFILE_PHOTO_BYTES)
    throw new PayloadTooLargeException('Ukuran foto maksimal 2 MB');
  const jpeg = input[0] === 0xff && input[1] === 0xd8 && input[2] === 0xff;
  const png = input
    .subarray(0, 8)
    .equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]));
  const webp =
    input.subarray(0, 4).toString() === 'RIFF' &&
    input.subarray(8, 12).toString() === 'WEBP';
  if (!jpeg && !png && !webp)
    throw new BadRequestException('Format foto harus JPEG, PNG atau WebP');
  try {
    const image = sharp(input, {
      limitInputPixels: 16_000_000,
      failOn: 'warning',
    });
    const metadata = await image.metadata();
    if (
      !['jpeg', 'png', 'webp'].includes(metadata.format ?? '') ||
      (metadata.pages ?? 1) !== 1
    )
      throw new Error('Unsupported image');
    // Decode all pixels, strip metadata and any appended payload, then store a
    // single normalized raster. Never serve the original bytes or filename.
    return await image
      .rotate()
      .resize(640, 640, { fit: 'inside', withoutEnlargement: true })
      .webp({ quality: 85 })
      .toBuffer();
  } catch {
    throw new BadRequestException(
      'Isi foto tidak valid. Gunakan JPEG, PNG atau WebP statis (maksimal 16 juta piksel)',
    );
  }
}
