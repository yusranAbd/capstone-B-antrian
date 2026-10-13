import { IsUUID } from 'class-validator';

export class HubungkanDokterLayananDto {
  @IsUUID('4')
  layananId!: string;
}
