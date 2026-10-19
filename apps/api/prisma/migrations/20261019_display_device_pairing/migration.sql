-- Aditif; token existing dan seluruh data perangkat tetap dipertahankan.
ALTER TABLE "perangkat_tampilan"
  ADD COLUMN "kode_aktivasi_hash" VARCHAR(64),
  ADD COLUMN "kode_berlaku_hingga" TIMESTAMPTZ(6),
  ADD COLUMN "kode_digunakan_pada" TIMESTAMPTZ(6),
  ADD COLUMN "sesi_berakhir_pada" TIMESTAMPTZ(6);
CREATE UNIQUE INDEX "perangkat_tampilan_kode_aktivasi_hash_key"
  ON "perangkat_tampilan"("kode_aktivasi_hash");
