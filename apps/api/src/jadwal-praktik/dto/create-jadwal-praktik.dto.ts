import { IsISO8601, IsString, IsUUID, Matches } from 'class-validator';

// Harus mencantumkan offset zona waktu atau Z agar instan tidak ambigu.
export const POLA_WAKTU_BERZONA = /(?:Z|[+-](?:0\d|1[0-4]):[0-5]\d)$/;
export const POLA_TANGGAL = /^\d{4}-(?:0[1-9]|1[0-2])-(?:0[1-9]|[12]\d|3[01])$/;

export class CreateJadwalPraktikDto {
  @IsUUID('4')
  dokterLayananId!: string;

  @IsUUID('4')
  loketId!: string;

  @IsString()
  @Matches(POLA_TANGGAL, { message: 'tanggal harus YYYY-MM-DD' })
  tanggal!: string;

  @IsISO8601({ strict: true })
  @Matches(POLA_WAKTU_BERZONA, { message: 'mulaiPada wajib menyertakan offset atau Z' })
  mulaiPada!: string;

  @IsISO8601({ strict: true })
  @Matches(POLA_WAKTU_BERZONA, { message: 'selesaiPada wajib menyertakan offset atau Z' })
  selesaiPada!: string;
}
