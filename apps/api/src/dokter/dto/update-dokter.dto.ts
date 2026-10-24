import {
  IsBoolean,
  IsOptional,
  IsString,
  Matches,
  MaxLength,
  MinLength,
  ValidateIf,
} from 'class-validator';

export class UpdateDokterDto {
  @ValidateIf((_, value: unknown) => value !== undefined)
  @IsString()
  @Matches(/^[A-Z0-9-]{2,30}$/)
  kode?: string;

  @ValidateIf((_, value: unknown) => value !== undefined)
  @IsString()
  @MinLength(3)
  @MaxLength(150)
  @Matches(/\S/)
  nama?: string;

  @IsOptional()
  @IsString()
  @MaxLength(150)
  spesialisasi?: string | null;

  @IsOptional()
  @IsString()
  @MaxLength(1500)
  tentangDokter?: string | null;

  @ValidateIf((_, value: unknown) => value !== undefined)
  @IsBoolean()
  aktif?: boolean;
}
