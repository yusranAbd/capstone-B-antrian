import { IsOptional, IsString, Matches, MaxLength, MinLength } from 'class-validator';

export class CreateDokterDto {
  @IsString()
  @Matches(/^[A-Z0-9-]{2,30}$/, {
    message: 'Kode dokter harus terdiri dari 2-30 karakter huruf kapital, angka atau tanda hubung',
  })
  kode!: string;

  @IsString()
  @MinLength(3)
  @MaxLength(150)
  @Matches(/\S/, { message: 'Nama dokter tidak boleh kosong' })
  nama!: string;

  @IsOptional()
  @IsString()
  @MaxLength(150)
  spesialisasi?: string | null;
}
