import { IsInt, IsISO8601, IsUUID, Matches, Min } from 'class-validator';

// Zona eksplisit mencegah reinterpretasi waktu oleh runtime/server.
export const POLA_WAKTU_OFFSET = /(?:Z|[+-](?:0\d|1[0-4]):[0-5]\d)$/;

export class CreateSlotPraktikDto {
  @IsUUID()
  jadwalPraktikId!: string;

  @IsISO8601({ strict: true })
  @Matches(POLA_WAKTU_OFFSET, { message: 'mulaiPada harus menyertakan zona waktu eksplisit' })
  mulaiPada!: string;

  @IsISO8601({ strict: true })
  @Matches(POLA_WAKTU_OFFSET, { message: 'selesaiPada harus menyertakan zona waktu eksplisit' })
  selesaiPada!: string;

  @IsInt()
  @Min(1)
  kapasitas!: number;
}
