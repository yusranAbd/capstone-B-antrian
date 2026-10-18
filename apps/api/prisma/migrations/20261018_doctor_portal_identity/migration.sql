-- Perluasan aditif: dokter existing tetap tidak memiliki akun (NULL).
ALTER TYPE "peran_pengguna" ADD VALUE 'DOKTER';
ALTER TABLE "dokter" ADD COLUMN "pengguna_id" UUID;
CREATE UNIQUE INDEX "dokter_pengguna_id_key" ON "dokter"("pengguna_id");
ALTER TABLE "dokter" ADD CONSTRAINT "dokter_pengguna_id_fkey"
  FOREIGN KEY ("pengguna_id") REFERENCES "pengguna"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
