import { IsOptional, IsString, IsUUID, Matches } from 'class-validator';
import { POLA_TANGGAL } from './create-jadwal-praktik.dto';

export class CariJadwalPraktikDto {
  @IsOptional()
  @IsUUID('4')
  dokterId?: string;

  @IsOptional()
  @IsUUID('4')
  layananId?: string;

  @IsOptional()
  @IsString()
  @Matches(POLA_TANGGAL, { message: 'tanggal harus YYYY-MM-DD' })
  tanggal?: string;
}
