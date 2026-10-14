import {
  IsInt,
  IsEnum,
  IsOptional,
  IsString,
  Matches,
  Max,
  MaxLength,
  Min,
  MinLength,
  ValidateIf,
} from 'class-validator';
import { ModeReservasi } from '../../generated/prisma/client';

export class CreateLayananDto {
  @ValidateIf((_, value: unknown) => value !== undefined)
  @IsEnum(ModeReservasi)
  modeReservasi?: ModeReservasi;

  @IsString()
  @Matches(/^[A-Z0-9]{2,20}$/, {
    message: 'Kode harus terdiri dari 2-20 karakter huruf kapital atau angka',
  })
  kode!: string;

  @IsString()
  @MinLength(3)
  @MaxLength(150)
  @Matches(/\S/, {
    message: 'Nama layanan tidak boleh kosong',
  })
  nama!: string;

  @IsOptional()
  @IsString()
  @MaxLength(1000)
  deskripsi?: string | null;

  @IsString()
  @Matches(/^[A-Z]{1,5}$/, {
    message: 'Prefix antrean harus terdiri dari 1-5 huruf kapital',
  })
  prefixAntrean!: string;

  @IsInt()
  @Min(1)
  @Max(240)
  durasiDasarMenit!: number;
}
