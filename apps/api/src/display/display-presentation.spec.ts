import {
  modeNamaDisplay,
  namaPublikDisplay,
  teksPanggilanDisplay,
} from './display-presentation';

describe('presentasi dan kebijakan privasi monitor', () => {
  const env = { ...process.env };
  afterEach(() => {
    process.env = { ...env };
  });
  it('default tersamar; satu nama hanya inisial; data kosong tidak dibuat-buat', () => {
    delete process.env.DISPLAY_PATIENT_NAME_MODE;
    expect(modeNamaDisplay()).toBe('SAMAR');
    expect(namaPublikDisplay('  Yusran  Abdullah ')).toBe('Yusran A.');
    expect(namaPublikDisplay('Sindi')).toBe('S.');
    expect(namaPublikDisplay('  ')).toBeNull();
    expect(namaPublikDisplay(null)).toBeNull();
  });
  it('nama lengkap memerlukan dua konfigurasi server eksplisit', () => {
    process.env.DISPLAY_PATIENT_NAME_MODE = 'LENGKAP';
    delete process.env.DISPLAY_FULL_NAMES_APPROVED;
    expect(namaPublikDisplay('Yusran Abdullah')).toBe('Yusran A.');
    process.env.DISPLAY_FULL_NAMES_APPROVED = 'true';
    expect(namaPublikDisplay('Yusran Abdullah')).toBe('Yusran Abdullah');
    process.env.DISPLAY_PATIENT_NAME_MODE = 'TANPA_NAMA';
    expect(namaPublikDisplay('Yusran Abdullah')).toBeNull();
  });
  it('ucapan dan teks pengumuman identik; mempertahankan nol, fallback tanpa nama', () => {
    expect(teksPanggilanDisplay('A-002', 'Yusran A.', 'Poli Anak')).toBe(
      'Panggilan nomor antrean A, nol nol dua atas nama Yusran A., silakan menuju ke Poli Anak, terima kasih.',
    );
    expect(teksPanggilanDisplay('PD-012', null, 'Penyakit Dalam')).toBe(
      'Panggilan nomor antrean P D, nol satu dua, silakan menuju ke Penyakit Dalam, terima kasih.',
    );
  });
});
