import { IsBoolean, IsISO8601, ValidateIf, IsString, IsUUID, Matches } from 'class-validator';
import { POLA_TANGGAL, POLA_WAKTU_BERZONA } from './create-jadwal-praktik.dto';

export class UpdateJadwalPraktikDto {
  @ValidateIf((_dto, value: unknown) => value !== undefined)
  @IsUUID('4')
  dokterLayananId?: string;

  @ValidateIf((_dto, value: unknown) => value !== undefined)
  @IsUUID('4')
  loketId?: string;

  @ValidateIf((_dto, value: unknown) => value !== undefined)
  @IsString()
  @Matches(POLA_TANGGAL, { message: 'tanggal harus YYYY-MM-DD' })
  tanggal?: string;

  @ValidateIf((_dto, value: unknown) => value !== undefined)
  @IsISO8601({ strict: true })
  @Matches(POLA_WAKTU_BERZONA, { message: 'mulaiPada wajib menyertakan offset atau Z' })
  mulaiPada?: string;

  @ValidateIf((_dto, value: unknown) => value !== undefined)
  @IsISO8601({ strict: true })
  @Matches(POLA_WAKTU_BERZONA, { message: 'selesaiPada wajib menyertakan offset atau Z' })
  selesaiPada?: string;

  @ValidateIf((_dto, value: unknown) => value !== undefined)
  @IsBoolean()
  aktif?: boolean;
}
