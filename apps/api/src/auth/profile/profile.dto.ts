import { Transform } from 'class-transformer';
import { IsByteLength, IsString, MaxLength, MinLength } from 'class-validator';

export class UpdateOwnProfileDto {
  @Transform(({ value }: { value: unknown }) =>
    typeof value === 'string' ? value.trim() : value,
  )
  @IsString()
  @MinLength(3)
  @MaxLength(150)
  nama!: string;
}

export class ChangeOwnPasswordDto {
  @IsString()
  @MinLength(1)
  @MaxLength(1024)
  kataSandiLama!: string;

  @IsString()
  @MinLength(8)
  @MaxLength(72)
  @IsByteLength(8, 72)
  kataSandiBaru!: string;
}
