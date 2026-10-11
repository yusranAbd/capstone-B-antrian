import { IsUUID } from 'class-validator';

export class PanggilBerikutnyaDto {
  @IsUUID('4', {
    message: 'loketId harus berupa UUID yang valid',
  })
  loketId!: string;
}
