import { IsUUID } from 'class-validator';

export class MasukAntreanDto {
  @IsUUID('4', {
    message: 'loketId harus berupa UUID yang valid',
  })
  loketId!: string;
}
