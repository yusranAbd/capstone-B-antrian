# QueueB Hospital — H1 Desain Schema Final untuk Review & Rencana Migrasi Aman

**Tanggal:** 13 Oktober 2026  
**Basis:** `schema(5).prisma`, 275 baris, 11 model existing, PostgreSQL + Prisma 7  
**Kebijakan disetujui:** slot konsultasi yang sudah dimulai → slot lebih awal → FIFO waktu masuk antrean  
**Status:** **final rancangan H1, BELUM diterapkan ke database**. Draf schema dan SQL harus diuji secara lokal sebelum menjadi migrasi yang disetujui.

## 1. Keputusan arsitektur yang terkunci

- Dokter adalah **master data**, bukan pengguna terautentikasi: `PeranPengguna` tetap `USER`, `PETUGAS`, `ADMIN`.
- `Layanan` tetap menjadi poli/layanan; `Loket` merepresentasikan loket atau ruang; `JadwalLayanan` adalah jam operasional POLI.
- `JadwalPraktik` adalah sesi dokter pada tanggal konkret. `SlotPraktik` mengelola jam dan kapasitas konsultasi.
- `JanjiTemu` berhubungan satu-ke-satu dengan `TiketAntrean` dan banyak-ke-satu dengan `SlotPraktik`; status tiket hanya berada di `TiketAntrean.status`.
- Pasien tetap paling banyak **1 tiket non-DIBATALKAN per poli dan tanggal** untuk MVP, walaupun dokter/slot berlainan. Kebijakan ini melestarikan aturan `/reservasi` existing.
- Nomor antrean (`nomorUrut`) dan counter `UrutanAntreanHarian` tetap per poli/tanggal. Urutan FIFO (`urutanMasukAntrean`) juga per poli/tanggal, tetapi **CALL harus membatasi kandidat ke dokter/sesi sesuai ruang** dan memilahnya menurut slot.
- Slot adalah estimasi periode konsultasi, **bukan janji waktu dipanggil persis**. Tidak ada auto-SKIP; PETUGAS melakukan SKIP/REQUEUE manual mengikuti alur Queue Engine lama.
- UI dan API lama harus tetap berjalan selama rollout; layanan `ANTREAN_HARIAN` tidak berubah.

## 2. Diffs minimal dibanding schema asli

**Tetap:** semua 11 model, semua field existing, generator, datasource, enums lama dan index unik lama.

**Aditif:**

1. Enum `ModeReservasi` (`ANTREAN_HARIAN`, `JANJI_TEMU_DOKTER`).
2. Kolom `Layanan.modeReservasi` NOT NULL default `ANTREAN_HARIAN`.
3. Lima model `Dokter`, `DokterLayanan`, `JadwalPraktik`, `SlotPraktik`, `JanjiTemu`.
4. Relasi balik di `Layanan`, `Loket`, `TiketAntrean`; tidak memindahkan atau mengganti kolom tiket.

**Jumlah target: 16 model**. Jangan menambah role `DOKTER` atau membuat akun dokter di fase ini.

## 3. Kunci dan indeks

| Entitas | Constraint utama | Maksud |
|---|---|---|
| `Dokter` | `kode` UNIQUE | Identitas internal dokter; hindari NIK atau data sensitif |
| `DokterLayanan` | (`dokterId`, `layananId`) UNIQUE | Dokter tidak didaftarkan dua kali pada poli sama |
| `JadwalPraktik` | (`dokterLayananId`, `mulaiPada`) UNIQUE | Mencegah sesi duplikat berawal sama, **bukan jaminan tanpa overlap** |
| `SlotPraktik` | (`jadwalPraktikId`, `mulaiPada`) UNIQUE | Awal slot tidak duplikat pada sesi sama |
| `JanjiTemu` | `tiketId` UNIQUE | Tiap tiket paling banyak satu janji temu |
| `TiketAntrean` | index & UNIQUE existing tetap | Kompatibilitas FIFO per poli/tanggal |

**CHECK SQL yang perlu ditambahkan pada migration review:** `selesaiPada > mulaiPada` untuk sesi dan slot, `kapasitas >= 1` untuk slot. Lihat `sql/CHECK_CONSTRAINTS_H1_REVIEW.sql`. Prisma schema saja tidak menegakkan semua aturan lintas tabel.

## 4. Invariant wajib di service saat H2/H3

- `DokterLayanan` aktif, dokter aktif dan layanan aktif ketika membuat slot atau booking.
- `JadwalPraktik.loketId` harus berada pada poli yang sama dengan `DokterLayanan.layananId`; loket aktif.
- Tanggal sesi `tanggal` konsisten dengan `mulaiPada` pada `SERVICE_TIME_ZONE` dan jam layanan poli; jangan memakai tanggal UTC mentah untuk tanggal pelayanan.
- Slot memiliki rentang waktu valid dan sepenuhnya berada di dalam sesi dokter; tidak tumpang tindih secara tidak sah.
- Dokter tidak dijadwalkan pada dua tempat dalam waktu tumpang tindih, termasuk dua poli berlainan; ruang tidak melayani dua sesi bersamaan. Gunakan **penguncian baris dokter dan loket** dalam transaksi pembuatan/ubah sesi, lalu cek overlap; pertimbangkan PostgreSQL exclusion constraint untuk ruang pada fase hardening.
- Tiket janji temu harus mempunyai `layananId`, `tanggalAntrean`, `penggunaId` selaras dengan slot dan identitas JWT.
- Booking dibatasi kuota slot dan kuota `JadwalLayanan.kapasitasHarian`; cek duplikasi pasien/poli/tanggal dan `StatusTiket` yang bukan `DIBATALKAN`.
- Jangan langsung mengubah `Layanan.modeReservasi` lewat PATCH biasa tanpa validasi apakah dokter/sesi/slot & kontrak API H2/H3 sudah siap.

## 5. Mekanisme booking anti-overbooking (kontrak implementasi H2)

Dalam **satu** `prisma.$transaction` dengan `isolationLevel: Serializable`:

1. Ambil identitas USER dari JWT; kunci baris slot dengan PostgreSQL `SELECT ... FOR UPDATE` memakai `tx.$queryRaw` terparameterisasi, bukan interpolasi string.
2. Validasi slot aktif, sesi aktif, dokter-layanan aktif, layanan dan loket aktif, tanggal dan waktu pelayanan.
3. Hitung janji temu pada slot yang tiketnya `status <> DIBATALKAN`; jika jumlah `>= kapasitas` → HTTP 409.
4. Hitung reservasi lain pasien pada layanan/tanggal dan cek kuota harian (mekanisme counter aman dari existing service tetap dipakai).
5. Alokasikan nomor tiket per poli/hari secara atomik, buat `TiketAntrean` `DIPESAN`, kemudian `JanjiTemu` ke slot, masih dalam transaksi yang sama.
6. Commit; retry **terbatas** pada serialization failure `P2034`. Uji 20+ permintaan paralel untuk 1 slot berkapasitas 1: tepat satu reservasi berhasil.

**Kunci booking, pembatalan, dan penjadwalan ulang pada domain slot yang sama** agar kuota selalu konsisten. Jangan menggunakan hitung kuota di frontend sebagai sumber kebenaran. Untuk MVP, cancellation/reschedule ditunda sampai endpoint dan transaksi serupa dibuat; jangan menampilkan tombol yang belum ada.

## 6. Aturan CALL: slot lalu FIFO, bukan sebaliknya

Aturan *target H3* (belum ada pada QueueService di `main`):

1. Validasi PETUGAS aktif, penugasan loket aktif, poli dan jadwal poli aktif; tentukan `JadwalPraktik` aktif untuk loket dan waktu kini (`mulaiPada <= sekarang < selesaiPada`) serta tanggal pelayanan lokal.
2. Calon tiket hanya `MENUNGGU`, telah check-in, memiliki `JanjiTemu`, slot aktif yang berhubungan dengan **sesi/dokter pada loket** itu, dan `SlotPraktik.mulaiPada <= sekarang`.
3. Urut calon tiket dengan `slot.mulaiPada ASC`, lalu `tiket.urutanMasukAntrean ASC`, lalu `tiket.id ASC`. Pilih satu secara atomik; tidak pernah mengambil slot mendatang.
4. Pertahankan guard satu tiket aktif per loket, audit peristiwa, `versi`, dan isolasi `Serializable`. RECALL/SKIP/REQUEUE/START/COMPLETE ikut memvalidasi konsistensi dokter-sesi-ruang tanpa mengganti `nomorAntrean`.
5. Jika tidak ada pasien yang memenuhi syarat, API mengembalikan kondisi antrean kosong/belum tersedia dengan kode error yang didokumentasikan; **jangan otomatis memanggil pasien slot mendatang**.
6. Untuk `ANTREAN_HARIAN`, algoritma FIFO lama tetap utuh.

**Implikasi snapshot:** pemisahan daftar per dokter/ruang serta urutan eligible. Jangan membocorkan nama pasien, diagnosis atau informasi medis di Public Display.

## 7. Strategi migrasi expand → deploy → activate

### H1-A: Persiapan aman (sebelum schema berubah)

- Sinkronkan `main` pasca PR #30, buat branch `feature/hospital-appointment-schema` dari `main`, jangan mengubah branch utama langsung.
- Backup PostgreSQL **development/staging**; pastikan prosedur restore diuji, catat migration history; jangan pernah membagikan `DATABASE_URL`/credential.
- Jalankan SQL *read-only* `PREFLIGHT_H1_READ_ONLY.sql` pada database yang tepat. Periksa data duplikat aktif pasien/poli/tanggal dan keadaan constraint existing.
- Pastikan uji lokal 593 unit/E2E, lint dan build sebagai **baseline sebelumnya**; sebelum merge H1 tetap harus dijalankan ulang.

### H1-B: Hasilkan migrasi (review, bukan langsung apply)

- Tempatkan `schema.hospital.H1.REVIEW.prisma` pada `apps/api/prisma` untuk pemeriksaan; **jangan mengganti file asli tanpa diff/review**.
- Jalankan `npx prisma validate --schema prisma/schema.hospital.H1.REVIEW.prisma` dari `apps/api` pada instalasi dependency resmi proyek.
- Setelah disetujui, salin perubahan aditif ke `prisma/schema.prisma`. Pada **database dev terisolasi** yang sudah di-backup, jalankan `npx prisma migrate dev --create-only --name hospital_h1_expand` untuk menghasilkan SQL migrasi. Catatan: migrate dev dapat menjalankan/mengecek migrasi existing dan membutuhkan shadow database; jangan jalankan pada database bersama/produksi.
- Review SQL: hanya `CREATE TYPE`, `ALTER TABLE layanan ADD COLUMN mode_reservasi ... DEFAULT 'ANTREAN_HARIAN'`, `CREATE TABLE` baru, index, FK, dan CHECK yang disepakati. **Tidak boleh ada DROP/RENAME kolom lama**.
- Tambahkan CHECK PostgreSQL ke migration SQL yang dihasilkan lalu uji pada database dev dan staging, termasuk `prisma migrate status` serta pemeriksaan data lama.

### H1-C: Deploy kompatibel & observasi

- Deploy schema tanpa mengubah mode layanan existing; default semuanya `ANTREAN_HARIAN`.
- Jalankan ulang semua pengujian serta pengujian migrasi data existing (reservasi lama, QR 10 menit, CHECK_IN, FIFO, publik display, login).
- Seed poli/dokter/sesi/slot **hanya** pada development/staging. Hindari contoh identitas pasien nyata.

### H2/H3: Implementasi perilaku baru dan aktivasi

- Implementasi Doctor & Appointment CRUD serta booking atomik; blokir endpoint lama `/reservasi` untuk layanan mode dokter.
- Implementasi CALL prioritas slot, otorisasi loket serta snapshot/display khusus dokter; tambah E2E konkurensi.
- Setelah semua berjalan, aktifkan `JANJI_TEMU_DOKTER` **per poli**, dengan admin action yang terkontrol; lakukan smoke test nyata. Baru kemudian integrasi UI Flutter/Web.

### Produksi dan rollback

- Saat deploy produksi nanti gunakan migration SQL yang telah direview melalui proses rilis (`prisma migrate deploy`), dengan backup, maintenance window jika perlu, dan perencanaan lock untuk skala tabel sebenarnya. Jangan `prisma db push` atau `migrate reset` di produksi.
- **Rollback aplikasi:** selama kolom baru punya default dan alur lama masih kompatibel, kembalikan aplikasi/flag ke mode `ANTREAN_HARIAN` terlebih dulu. Setelah ada booking dokter, rollback tidak sesederhana membuang tabel; lebih aman roll-forward atau restore yang terencana.
- Empat temuan *high* dependency Prisma dan kebutuhan hardening reverse proxy tetap menjadi risiko produksi terbuka, terpisah dari keberhasilan migrasi skema.

## 8. Acceptance criteria / gate sebelum commit H1

- [ ] Schema diverifikasi oleh `prisma validate` pada environment proyek.
- [ ] SQL migrasi generated telah direview; **0 DROP existing, 0 rename**, termasuk Foreign Key.
- [ ] CHECK waktu dan kapasitas ditambahkan dan diperiksa.
- [ ] Backup DB dev/staging serta smoke-test restore tersedia.
- [ ] Migration berhasil pada DB dev dengan data lama; seed, CRUD & regression tidak rusak.
- [ ] Unit/E2E existing **dijalankan ulang** (baseline 593 test, bukan klaim tes baru).
- [ ] Konsistensi aplikasi lama setelah deploy mode harian terbukti.
- [ ] Kebijakan CALL & slot dicatat di API guide serta rencana uji H2/H3.

## 9. Batasan/risiko yang tidak ditutup pada H1

- Desain schema **tidak otomatis** menjamin kapasitas slot, tanggal lintas tabel, overlap semua sesi dokter, dan FIFO; H2/H3 perlu transaksi dan pengujian.
- Constraint `@@unique` tidak melarang jadwal overlap interval; SQL PostgreSQL `EXCLUDE` opsional untuk ruang, service mengunci dokter+loket agar konkurensi konsisten.
- Pembatalan dan reschedule baru boleh diaktifkan setelah transaksi dan kebijakan kuota lengkap.
- Public Display sekarang dikelompokkan menurut layanan; penambahan label dokter tidak boleh dianggap sudah ada sebelum implementasi H3.
