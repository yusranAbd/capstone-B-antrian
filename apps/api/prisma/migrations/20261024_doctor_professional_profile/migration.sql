-- P1 aditif: seluruh profil existing tetap valid; tidak mengubah relasi.
ALTER TABLE "dokter"
  ADD COLUMN "foto_profil" VARCHAR(200),
  ADD COLUMN "tentang_dokter" VARCHAR(1500);
