import { IsUUID, Matches } from 'class-validator';

/** Payload dari QR nota, tidak sama dengan token check-in SQ1. */
export class VerifikasiBuktiReservasiDto {
  @Matches(/^QBR1\.TK[A-F0-9]{24}$/, {
    message: 'Kode QR bukti reservasi tidak valid',
  })
  qrPayload!: string;

  @IsUUID()
  loketId!: string;
}
