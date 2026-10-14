import { IsUUID } from 'class-validator';

export class CreateJanjiTemuDto {
  @IsUUID()
  slotPraktikId!: string;
}
