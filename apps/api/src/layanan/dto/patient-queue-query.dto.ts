import { Transform } from 'class-transformer';
import {
  ArrayMaxSize,
  ArrayMinSize,
  ArrayUnique,
  IsArray,
  IsDateString,
  IsOptional,
  IsUUID,
  Matches,
} from 'class-validator';

export class PatientQueueQueryDto {
  @IsOptional()
  @IsDateString({ strict: true })
  @Matches(/^(?!0000)\d{4}-\d{2}-\d{2}$/)
  tanggal?: string;

  @IsOptional()
  @Transform(({ value }: { value: unknown }) =>
    typeof value === 'string' ? value.split(',') : value,
  )
  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(100)
  @ArrayUnique()
  @IsUUID('4', { each: true })
  layananId?: string[];
}

export function validPatientQueueDate(value: unknown): value is string {
  if (typeof value !== 'string' || !/^(?!0000)\d{4}-\d{2}-\d{2}$/.test(value))
    return false;
  const date = new Date(value + 'T00:00:00.000Z');
  return (
    Number.isFinite(date.getTime()) && date.toISOString().slice(0, 10) === value
  );
}
