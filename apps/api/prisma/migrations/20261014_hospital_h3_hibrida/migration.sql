-- H3.2: penambahan enum ADITIF; tidak mengubah record layanan existing.
-- Aktifkan layanan HIBRIDA secara eksplisit hanya setelah H3.3/H3.4 lulus.
ALTER TYPE "mode_reservasi" ADD VALUE IF NOT EXISTS 'HIBRIDA';
