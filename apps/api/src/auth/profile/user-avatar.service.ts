import {
  ConflictException,
  Inject,
  Injectable,
  Logger,
  NotFoundException,
  ServiceUnavailableException,
} from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { mkdir, readFile, unlink, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { normalizeProfileImage } from '../../media/profile-image';
import { Prisma } from '../../generated/prisma/client';
import { PrismaService } from '../../prisma/prisma.service';

export const USER_AVATAR_ROOT = 'USER_AVATAR_ROOT';
export const MAX_USER_AVATAR_BYTES = 2 * 1024 * 1024;
const PREFIX = '/media/avatar/';
const FILE_NAME =
  /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.webp$/;

@Injectable()
export class UserAvatarService {
  private readonly logger = new Logger('UserAvatarAudit');
  constructor(
    private readonly prisma: PrismaService,
    @Inject(USER_AVATAR_ROOT) private readonly root: string,
  ) {}

  normalize(input?: Buffer): Promise<Buffer> {
    return normalizeProfileImage(input);
  }

  async upload(id: string, input: Buffer | undefined, actorId: string) {
    const image = await this.normalize(input);
    const filename = `${randomUUID()}.webp`;
    const ref = PREFIX + filename;
    try {
      await mkdir(this.root, { recursive: true });
      await writeFile(join(this.root, filename), image, {
        flag: 'wx',
        mode: 0o600,
      });
    } catch {
      throw new ServiceUnavailableException(
        'Penyimpanan foto belum tersedia. Coba lagi nanti',
      );
    }
    try {
      const result = await this.replace(id, ref);
      await this.removeUnreferenced(result.previous);
      this.audit('GANTI_AVATAR', id, actorId);
      return { id, avatarProfil: ref };
    } catch (error) {
      // A lost commit response must not remove a file that the DB now references.
      await this.removeUnreferenced(ref);
      throw error;
    }
  }

  async remove(id: string, actorId: string) {
    const result = await this.replace(id, null);
    await this.removeUnreferenced(result.previous);
    this.audit('HAPUS_AVATAR', id, actorId);
    return { id, avatarProfil: null };
  }

  private async replace(id: string, ref: string | null) {
    try {
      return await this.prisma.$transaction(
        async (tx) => {
          await tx.$executeRaw`SET LOCAL lock_timeout = '5s'`;
          const found = await tx.$queryRaw<
            Array<{ avatar_profil: string | null }>
          >`
          SELECT avatar_profil FROM pengguna WHERE id = ${id}::uuid FOR UPDATE`;
          if (!found.length)
            throw new NotFoundException('Pengguna tidak ditemukan');
          await tx.pengguna.update({
            where: { id },
            data: { avatarProfil: ref },
          });
          return { previous: found[0].avatar_profil };
        },
        { timeout: 10000 },
      );
    } catch (error) {
      if (
        error instanceof Prisma.PrismaClientKnownRequestError &&
        ['P2034', 'P2028'].includes(error.code)
      )
        throw new ConflictException(
          'Profil sedang berubah. Muat ulang sebelum mencoba lagi',
        );
      throw error;
    }
  }

  private async removeUnreferenced(ref: string | null) {
    if (!ref?.startsWith(PREFIX)) return;
    const filename = ref.slice(PREFIX.length);
    if (!FILE_NAME.test(filename)) return;
    try {
      if (await this.prisma.pengguna.count({ where: { avatarProfil: ref } }))
        return;
      await unlink(join(this.root, filename));
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code !== 'ENOENT')
        this.logger.warn(
          'Pembersihan foto tertunda; referensi database tetap menjadi sumber kebenaran',
        );
    }
  }

  async readOwn(id: string) {
    const user = await this.prisma.pengguna.findUnique({
      where: { id },
      select: { avatarProfil: true },
    });
    const filename = user?.avatarProfil?.slice(PREFIX.length) ?? '';
    if (!FILE_NAME.test(filename))
      throw new NotFoundException('Foto tidak ditemukan');
    if (
      !(await this.prisma.pengguna.count({
        where: { id, avatarProfil: PREFIX + filename },
      }))
    )
      throw new NotFoundException('Foto tidak ditemukan');
    try {
      return await readFile(join(this.root, filename));
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code === 'ENOENT')
        throw new NotFoundException('Foto tidak ditemukan');
      throw new ServiceUnavailableException('Foto belum dapat dimuat');
    }
  }

  private audit(aksi: string, penggunaId: string, aktorId: string) {
    this.logger.log(
      JSON.stringify({
        aksi,
        penggunaId,
        aktorId,
        terjadiPada: new Date().toISOString(),
      }),
    );
  }
}
