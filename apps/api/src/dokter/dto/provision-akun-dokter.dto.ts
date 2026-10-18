import {
  IsEmail,
  IsNotEmpty,
  IsString,
  IsUUID,
  Length,
  ValidateIf,
} from 'class-validator';

/** Pilih salah satu: tautkan akun DOKTER existing, atau buat akun baru. */
export class ProvisionAkunDokterDto {
  @ValidateIf((o) => o.penggunaId !== undefined || o.email === undefined)
  @IsUUID('4')
  penggunaId?: string;

  @ValidateIf((o) => o.email !== undefined || o.penggunaId === undefined)
  @IsEmail()
  @Length(3, 150)
  email?: string;

  @ValidateIf((o) => o.kataSandi !== undefined || o.penggunaId === undefined)
  @IsString()
  @IsNotEmpty()
  @Length(8, 72)
  kataSandi?: string;
}
