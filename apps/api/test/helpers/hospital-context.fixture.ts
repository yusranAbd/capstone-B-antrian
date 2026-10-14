import type { KonteksSlotHospital } from '../../src/hospital/hospital-context';

/** Fixture sintetis: slot sudah berakhir, sesi masih berlangsung pada tanggal tiket. */
export function buatKonteksJanjiUji(
  layananId: string,
  loketId: string,
  tanggal: string,
) {
  const jam = (value: string) => new Date(`${tanggal}T${value}:00Z`);
  const slotPraktik: KonteksSlotHospital = {
    aktif: true,
    mulaiPada: jam('02:00'),
    selesaiPada: jam('02:20'),
    jadwalPraktik: {
      aktif: true,
      tanggal: jam('00:00'),
      loketId,
      mulaiPada: jam('01:00'),
      selesaiPada: jam('04:00'),
      loket: { aktif: true, layananId },
      dokterLayanan: {
        aktif: true,
        layananId,
        dokter: { aktif: true },
        layanan: { aktif: true },
      },
    },
  };
  return { slotPraktik };
}
