-- CreateEnum
CREATE TYPE "mode_reservasi" AS ENUM ('ANTREAN_HARIAN', 'JANJI_TEMU_DOKTER');

-- AlterTable
ALTER TABLE "layanan" ADD COLUMN     "mode_reservasi" "mode_reservasi" NOT NULL DEFAULT 'ANTREAN_HARIAN';

-- CreateTable
CREATE TABLE "dokter" (
    "id" UUID NOT NULL,
    "kode" VARCHAR(30) NOT NULL,
    "nama" VARCHAR(150) NOT NULL,
    "spesialisasi" VARCHAR(150),
    "aktif" BOOLEAN NOT NULL DEFAULT true,
    "dibuat_pada" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "diperbarui_pada" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "dokter_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "dokter_layanan" (
    "id" UUID NOT NULL,
    "dokter_id" UUID NOT NULL,
    "layanan_id" UUID NOT NULL,
    "aktif" BOOLEAN NOT NULL DEFAULT true,

    CONSTRAINT "dokter_layanan_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "jadwal_praktik" (
    "id" UUID NOT NULL,
    "dokter_layanan_id" UUID NOT NULL,
    "loket_id" UUID NOT NULL,
    "tanggal" DATE NOT NULL,
    "mulai_pada" TIMESTAMPTZ(6) NOT NULL,
    "selesai_pada" TIMESTAMPTZ(6) NOT NULL,
    "aktif" BOOLEAN NOT NULL DEFAULT true,
    "dibuat_pada" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "jadwal_praktik_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "slot_praktik" (
    "id" UUID NOT NULL,
    "jadwal_praktik_id" UUID NOT NULL,
    "mulai_pada" TIMESTAMPTZ(6) NOT NULL,
    "selesai_pada" TIMESTAMPTZ(6) NOT NULL,
    "kapasitas" INTEGER NOT NULL DEFAULT 1,
    "aktif" BOOLEAN NOT NULL DEFAULT true,

    CONSTRAINT "slot_praktik_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "janji_temu" (
    "id" UUID NOT NULL,
    "tiket_id" UUID NOT NULL,
    "slot_praktik_id" UUID NOT NULL,
    "dibuat_pada" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "diperbarui_pada" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "janji_temu_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "dokter_kode_key" ON "dokter"("kode");

-- CreateIndex
CREATE INDEX "dokter_layanan_layanan_id_aktif_idx" ON "dokter_layanan"("layanan_id", "aktif");

-- CreateIndex
CREATE UNIQUE INDEX "dokter_layanan_dokter_id_layanan_id_key" ON "dokter_layanan"("dokter_id", "layanan_id");

-- CreateIndex
CREATE INDEX "jadwal_praktik_loket_id_tanggal_aktif_idx" ON "jadwal_praktik"("loket_id", "tanggal", "aktif");

-- CreateIndex
CREATE INDEX "jadwal_praktik_dokter_layanan_id_tanggal_aktif_idx" ON "jadwal_praktik"("dokter_layanan_id", "tanggal", "aktif");

-- CreateIndex
CREATE UNIQUE INDEX "jadwal_praktik_dokter_layanan_id_mulai_pada_key" ON "jadwal_praktik"("dokter_layanan_id", "mulai_pada");

-- CreateIndex
CREATE INDEX "slot_praktik_jadwal_praktik_id_aktif_mulai_pada_idx" ON "slot_praktik"("jadwal_praktik_id", "aktif", "mulai_pada");

-- CreateIndex
CREATE UNIQUE INDEX "slot_praktik_jadwal_praktik_id_mulai_pada_key" ON "slot_praktik"("jadwal_praktik_id", "mulai_pada");

-- CreateIndex
CREATE UNIQUE INDEX "janji_temu_tiket_id_key" ON "janji_temu"("tiket_id");

-- CreateIndex
CREATE INDEX "janji_temu_slot_praktik_id_idx" ON "janji_temu"("slot_praktik_id");

-- AddForeignKey
ALTER TABLE "dokter_layanan" ADD CONSTRAINT "dokter_layanan_dokter_id_fkey" FOREIGN KEY ("dokter_id") REFERENCES "dokter"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "dokter_layanan" ADD CONSTRAINT "dokter_layanan_layanan_id_fkey" FOREIGN KEY ("layanan_id") REFERENCES "layanan"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "jadwal_praktik" ADD CONSTRAINT "jadwal_praktik_dokter_layanan_id_fkey" FOREIGN KEY ("dokter_layanan_id") REFERENCES "dokter_layanan"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "jadwal_praktik" ADD CONSTRAINT "jadwal_praktik_loket_id_fkey" FOREIGN KEY ("loket_id") REFERENCES "loket"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "slot_praktik" ADD CONSTRAINT "slot_praktik_jadwal_praktik_id_fkey" FOREIGN KEY ("jadwal_praktik_id") REFERENCES "jadwal_praktik"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "janji_temu" ADD CONSTRAINT "janji_temu_tiket_id_fkey" FOREIGN KEY ("tiket_id") REFERENCES "tiket_antrean"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "janji_temu" ADD CONSTRAINT "janji_temu_slot_praktik_id_fkey" FOREIGN KEY ("slot_praktik_id") REFERENCES "slot_praktik"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE "jadwal_praktik"
ADD CONSTRAINT "ck_jadwal_praktik_waktu"
CHECK ("selesai_pada" > "mulai_pada");

ALTER TABLE "slot_praktik"
ADD CONSTRAINT "ck_slot_praktik_waktu"
CHECK ("selesai_pada" > "mulai_pada");

ALTER TABLE "slot_praktik"
ADD CONSTRAINT "ck_slot_praktik_kapasitas"
CHECK ("kapasitas" >= 1);
