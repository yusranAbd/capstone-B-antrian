/*
  Warnings:

  - A unique constraint covering the columns `[layanan_id,tanggal_antrean,urutan_masuk_antrean]` on the table `tiket_antrean` will be added. If there are existing duplicate values, this will fail.

*/
-- AlterTable
ALTER TABLE "tiket_antrean" ADD COLUMN     "masuk_antrean_pada" TIMESTAMPTZ(6),
ADD COLUMN     "urutan_masuk_antrean" INTEGER;

-- AlterTable
ALTER TABLE "urutan_antrean_harian" ADD COLUMN     "urutan_masuk_terakhir" INTEGER NOT NULL DEFAULT 0;

-- CreateIndex
CREATE INDEX "idx_tiket_fifo" ON "tiket_antrean"("layanan_id", "tanggal_antrean", "status", "urutan_masuk_antrean");

-- CreateIndex
CREATE UNIQUE INDEX "uq_tiket_urutan_masuk" ON "tiket_antrean"("layanan_id", "tanggal_antrean", "urutan_masuk_antrean");
