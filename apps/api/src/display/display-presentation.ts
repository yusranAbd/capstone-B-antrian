/** Kebijakan operator server. Browser/perangkat tidak boleh menaikkan izin nama. */
export function modeNamaDisplay(): 'SAMAR' | 'LENGKAP' | 'TANPA_NAMA' {
  if (process.env.DISPLAY_PATIENT_NAME_MODE === 'TANPA_NAMA')
    return 'TANPA_NAMA';
  return process.env.DISPLAY_PATIENT_NAME_MODE === 'LENGKAP' &&
    process.env.DISPLAY_FULL_NAMES_APPROVED === 'true'
    ? 'LENGKAP'
    : 'SAMAR';
}

export function namaPublikDisplay(
  nama: string | null | undefined,
): string | null {
  if (modeNamaDisplay() === 'TANPA_NAMA') return null;
  const bagian =
    nama
      ?.replace(/[\p{Cc}\p{Cf}]/gu, ' ')
      .trim()
      .split(/\s+/u)
      .filter(Boolean) ?? [];
  if (!bagian.length) return null;
  if (modeNamaDisplay() === 'LENGKAP') return bagian.join(' ');
  if (bagian.length === 1) return `${Array.from(bagian[0])[0]}.`;
  return `${bagian[0]} ${bagian
    .slice(1)
    .map((b) => `${Array.from(b)[0]}.`)
    .join(' ')}`;
}

export function teksPanggilanDisplay(
  nomor: string,
  nama: string | null,
  poli: string,
): string {
  // Ejaan digit mempertahankan angka nol di depan. Teks layar identik dengan TTS.
  const digit = [
    'nol',
    'satu',
    'dua',
    'tiga',
    'empat',
    'lima',
    'enam',
    'tujuh',
    'delapan',
    'sembilan',
  ];
  const pelafalan = nomor
    .replace(/([A-Za-z]+)/g, (s) => s.split('').join(' '))
    .replace(/-/g, ', ')
    .replace(/\d/g, (d) => `${digit[Number(d)]} `)
    .trim()
    .replace(/\s+/g, ' ');
  return `Panggilan nomor antrean ${pelafalan}${nama ? ` atas nama ${nama}` : ''}, silakan menuju ke ${poli}, terima kasih.`;
}
