# Milestone 1 — Stabilisasi Hospital Queue Selector H3.3

Tanggal verifikasi: 14 Oktober 2026.
Status: seluruh pemeriksaan checkpoint H3.3 lulus; siap commit setelah konfirmasi. Milestone 2 belum dimulai.

## Lingkup dan keputusan yang disetujui

- Perbaiki TS1355 tanpa mengubah nilai status pada respons.
- Pertahankan jalur FIFO existing untuk ANTREAN_HARIAN.
- Gunakan selector dan pembacaan kandidat yang sama pada CALL, daftar menunggu, dan REST snapshot Hospital.
- Akhir slot merupakan estimasi konsultasi, bukan kedaluwarsa hak pasien yang masih MENUNGGU. Slot mendatang tetap tidak layak CALL.
- Verifikasi akhir bersyarat: appointment tetap dibatasi tanggal pelayanan, ruang yang ditetapkan, tanggal sesi yang sesuai tiket, dan interval sesi praktik [mulaiPada, selesaiPada). Batas ini tidak diterapkan ulang pada COMPLETE untuk pelayanan yang sudah dimulai.
- Persetujuan Project Lead: REQUEUE mempertahankan prioritas slot, tetapi waktu prioritas diganti dengan waktu REQUEUE terbaru. Tiket yang belum pernah REQUEUE tetap memakai waktu CHECK_IN.
- Persetujuan pengujian: cleanup hanya untuk fixture unik yang dibuat tes di capstone_antrean_test pada PostgreSQL lokal port 5433.
- Tidak menetapkan toleransi keterlambatan atau fairness numerik.

## Perubahan teknis

| File | Perubahan |
|---|---|
| apps/api/src/queue/queue.service.ts | Ganti dua const assertion enum yang tidak valid dengan literal MENUNGGU; baca audit REQUEUE terbaru, tanggal tiket dan konteks waktu/tanggal sesi melalui select Hospital bersama; gunakan tipe kandidat selector untuk snapshot |
| apps/api/src/queue/hospital-queue-selector.ts | Hapus kedaluwarsa berdasarkan akhir slot; batasi appointment pada tanggal dan interval sesi yang sesuai; gunakan audit REQUEUE terbaru sebagai waktu prioritas dan CHECK_IN sebagai fallback |
| apps/api/src/queue/hospital-queue-selector.spec.ts | Regresi slot berakhir, batas awal/akhir sesi, tanggal sesi, prioritas slot, REQUEUE appointment/walk-in, serta fallback CHECK_IN |
| apps/api/src/queue/queue.service.spec.ts | Verifikasi CALL/daftar menunggu memakai audit yang sama dan tetap melayani appointment setelah akhir slot; nyatakan mode harian pada fixture CALL |
| apps/api/src/queue/queue.snapshot.spec.ts | Verifikasi snapshot setelah akhir slot, pengurutan REQUEUE, tidak bocornya audit, dan kontrak harian |
| apps/api/test/hospital-selector.e2e-spec.ts | Validasi koneksi aktual sebelum fixture; counter REQUEUE; regresi mode harian, akhir slot pada kedua mode Hospital, REQUEUE appointment/walk-in dan REQUEUE berulang; penolakan tanggal/ruang/sesi yang tidak relevan; COMPLETE setelah akhir sesi |

Perubahan queue-snapshot.types.ts yang sudah ada sebelum Milestone 1 dipertahankan; file tersebut tidak diedit dalam milestone ini.

## Algoritma Hospital

Urutan kandidat:

1. Appointment yang layak, kemudian walk-in yang layak pada HIBRIDA, kemudian kandidat yang belum/tidak layak.
2. Untuk appointment, awal slot lebih dini didahulukan.
3. Waktu audit REQUEUE terbaru; jika belum pernah REQUEUE, gunakan checkInPada.
4. urutanMasukAntrean, kemudian ID sebagai penentu urutan deterministik.

Kelayakan appointment memerlukan CHECK_IN, slot/sesi/relasi/dokter aktif, ruang yang sesuai, slot yang sudah dimulai, tanggal sesi sama dengan tanggal tiket, dan mulaiPada sesi <= sekarang < selesaiPada sesi. Query layanan pada ketiga jalur tetap membatasi tiket ke tanggal pelayanan saat ini menurut SERVICE_TIME_ZONE. Akhir slot tidak menolak kandidat selama sesi masih relevan. Konsistensi Hospital yang lebih lengkap pada booking/CHECK_IN/ENQUEUE tetap termasuk lingkup Milestone 2.

Audit REQUEUE diambil dengan filter tipe REQUEUE, urutan terjadiPada descending, dan batas satu per tiket. Audit hanya digunakan secara internal, tidak dikirim pada respons.

Untuk ANTREAN_HARIAN, query existing tetap memakai urutanMasukAntrean ASC lalu ID ASC. Waktu CHECK_IN dan audit REQUEUE Hospital tidak mengganti FIFO harian.

## Dampak kontrak API

- Tidak menambah endpoint, parameter request, status HTTP, kolom, atau migration.
- Status snapshot tetap MENUNGGU; versiSkema tetap 1.
- Field Hospital yang telah ada sebelum milestone ini tetap dipertahankan: jenisAntrean, layakDipanggil, slotMulaiPada.
- layakDipanggil dapat tetap true setelah akhir slot jika persyaratan lain terpenuhi.
- Appointment di luar interval sesi atau dengan tanggal sesi yang tidak cocok memiliki layakDipanggil false dan tidak dapat di-CALL. Kontrak CALL tetap 404 jika tidak ada kandidat layak.
- Setelah REQUEUE, posisi tiket mengikuti waktu antre ulang tanpa mengganti nomorAntrean atau checkInPada asli.
- Socket.IO, audit mutasi, QR, State Machine, serta Public Display tidak diubah.

## Hasil pengujian aktual

| Pemeriksaan | Hasil |
|---|---|
| Type check: tsc --project tsconfig.json --noEmit --incremental false | Lulus, exit 0 |
| Lint: npm run lint | Lulus, exit 0 |
| NestJS build: npm run build | Lulus, exit 0 |
| Seluruh unit: npm test -- --runInBand --no-cache | 537/537 lulus, 35 suite |
| Seluruh E2E: Jest test/jest-e2e.json --runInBand --no-cache tanpa filter | 234/234 lulus, 21 suite, termasuk seluruh 17 kasus Hospital Selector |
| git diff --check | Lulus |

Tambahan dibanding baseline audit: 16 unit test dan 13 E2E H3.3. Verifikasi akhir menambahkan 5 unit dan 7 E2E dibanding hasil awal Milestone 1 (532 unit, 10 Hospital Selector). E2E Hospital mencakup kesamaan CALL/daftar/snapshot, slot mendatang, ruang lain, slot berakhir pada HIBRIDA dan JANJI_TEMU_DOKTER, REQUEUE pada dua jenis tiket, FIFO harian dengan CHECK_IN berlawanan, REQUEUE berulang, dua CALL bersamaan, batas tanggal/ruang/sesi, serta penyelesaian pelayanan setelah sesi berakhir.

DATABASE_URL E2E hanya diatur pada environment proses, tidak ditulis ke .env. Target tepat 127.0.0.1:5433/capstone_antrean_test, koneksi aktual, serta enum HIBRIDA diperiksa sebelum seluruh suite dijalankan. Cleanup dibatasi fixture milik tes. Tidak ada akses database development utama, reset, atau migration.

Seluruh regresi FIFO harian, QR, reservasi, appointment, REQUEUE, CALL, realtime dan Public Display lulus dalam run yang sama. Unit test tidak dipakai sebagai pengganti bukti build: keduanya dijalankan terpisah.

Fingerprint isi record existing pada 16 tabel disimpan hanya di memori sebelum tes dan dibandingkan sesudah tes: 13 record existing, 0 hilang, 0 berubah, 0 record baru tersisa. Tidak membuat backup atau menampilkan data/kredensial.

Log error CHECK constraint berasal dari skenario fault injection existing yang menguji rollback audit dan mengharapkan HTTP 500; seluruh tes tersebut lulus. Warning runtime yang masih muncul: experimental VM Modules dan deprecation pg untuk query serentak pada satu client. Tidak dilakukan upgrade dependency pada checkpoint ini.

## Batas dan tindak lanjut review

- Validasi kapasitas semua mode, hubungan Hospital pada CHECK_IN/ENQUEUE/CALL, timezone realtime, dan race penugasan tetap merupakan pekerjaan berikutnya.
- Prioritas slot lebih awal tetap berlaku setelah REQUEUE sesuai keputusan yang disetujui. Fairness numerik terhadap walk-in belum ditetapkan.
- Query Hospital kini membaca satu audit REQUEUE per kandidat. Pengujian ini belum mengukur performa antrean besar.
- Setelah sesi berakhir, appointment MENUNGGU tidak di-CALL melalui sesi lain. Pelayanan yang telah dimulai tetap dapat diselesaikan. Penanganan operasional pasien yang masih menunggu di akhir sesi tetap memerlukan keputusan Project Lead; tidak ada auto-SKIP, pembatalan otomatis, atau toleransi numerik.
- Finalisasi API_INTEGRATION_GUIDE.md dan audit dependency/deployment termasuk Milestone 3. Milestone 1 bukan sertifikasi kesiapan produksi.
- Tidak ada commit, push, merge, reset database, atau migration database utama.

Staging akhir diperiksa: 0 file staged; backup, .env dan artefak lokal tidak masuk staging. Migration existing tidak diubah.

Daftar file checkpoint yang direkomendasikan untuk commit setelah konfirmasi:

- apps/api/src/queue/queue.service.ts
- apps/api/src/queue/queue-snapshot.types.ts (perubahan existing sebelum Milestone 1, diperlukan feature H3.3)
- apps/api/src/queue/hospital-queue-selector.ts
- apps/api/src/queue/hospital-queue-selector.spec.ts
- apps/api/src/queue/queue.service.spec.ts
- apps/api/src/queue/queue.snapshot.spec.ts
- apps/api/test/hospital-selector.e2e-spec.ts
- docs/backend/H3_3_STABILISASI.md

Rekomendasi commit setelah konfirmasi: `fix(queue): menstabilkan pemilihan antrean hospital H3.3`.

Saat nantinya menyiapkan commit, pilih file implementasi/tes/dokumentasi secara eksplisit dan sertakan tipe snapshot existing yang diperlukan feature ini setelah direview. Jangan menggunakan penambahan seluruh workspace karena backup dan berkas untracked lain sudah ada sebelum pekerjaan ini.
