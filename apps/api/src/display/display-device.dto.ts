import { IsString, IsUUID, Length, Matches } from 'class-validator';
export class CreateDisplayDeviceDto {
  @IsUUID('4') layananId: string;
  @IsString() @Length(3, 100) @Matches(/\S/) nama: string;
}
export class PairDisplayDto {
  @IsString() @Matches(/^\d{12}$/) kode: string;
}

export class UpdateDisplayDeviceDto {
  @IsString() @Length(3, 100) @Matches(/\S/) nama: string;
}
