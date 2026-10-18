import { IsDateString, IsOptional, IsUUID, Matches } from 'class-validator';
export class PortalTanggalDto {
  @IsOptional()
  @IsDateString({ strict: true })
  @Matches(/^\d{4}-\d{2}-\d{2}$/)
  tanggal?: string;
}
export class PortalSnapshotDto {
  @IsUUID('4')
  jadwalPraktikId!: string;
}
