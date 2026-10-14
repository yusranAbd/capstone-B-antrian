import { IsBoolean, IsInt, IsISO8601, Matches, Min, ValidateIf } from 'class-validator';
import { POLA_WAKTU_OFFSET } from './create-slot-praktik.dto';

export class UpdateSlotPraktikDto {
  // ValidateIf menjaga null tidak dianggap sebagai field opsional yang valid.
  @ValidateIf((_, value: unknown) => value !== undefined)
  @IsISO8601({ strict: true })
  @Matches(POLA_WAKTU_OFFSET)
  mulaiPada?: string;

  @ValidateIf((_, value: unknown) => value !== undefined)
  @IsISO8601({ strict: true })
  @Matches(POLA_WAKTU_OFFSET)
  selesaiPada?: string;

  @ValidateIf((_, value: unknown) => value !== undefined)
  @IsInt()
  @Min(1)
  kapasitas?: number;

  @ValidateIf((_, value: unknown) => value !== undefined)
  @IsBoolean()
  aktif?: boolean;
}
