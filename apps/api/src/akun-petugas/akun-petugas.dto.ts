import { IsBoolean, IsEmail, IsString, Length, Matches } from 'class-validator';

export class CreateAkunPetugasDto {
  @IsString()
  @Length(3, 150)
  @Matches(/\S/)
  nama!: string;

  @IsEmail()
  @Length(3, 150)
  email!: string;

  @IsString()
  @Length(8, 72)
  kataSandi!: string;
}

export class StatusAkunPetugasDto {
  @IsBoolean()
  aktif!: boolean;
}
