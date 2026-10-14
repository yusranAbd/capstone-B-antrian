import { IsUUID } from 'class-validator';

export class CariSlotPraktikDto {
  // Batasi daftar per jadwal supaya endpoint tidak mengembalikan seluruh data rumah sakit.
  @IsUUID()
  jadwalPraktikId!: string;
}
