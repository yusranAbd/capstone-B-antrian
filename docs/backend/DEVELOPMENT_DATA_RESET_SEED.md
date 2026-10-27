# Dataset pengujian development QueueB — 27 Oktober 2026

Seluruh identitas adalah sintetis. Nama/gelar tidak menyatakan identitas, izin praktik, pendidikan, atau pengalaman tenaga medis nyata. Tidak ada NIK, nomor telepon, diagnosis, atau rekam medis yang dibuat. Foto memakai avatar fallback. Struktur database, migration historis, Queue Engine, RBAC dan frontend tidak diubah.

## Hasil aktivasi

- Target tunggal: `127.0.0.1:5433/capstone_antrean`, schema `public`, PostgreSQL 18.
- Backup custom PostgreSQL penuh di luar Git, checksum SHA-256, inventaris 17 tabel dan decoding seluruh arsip lulus. Ini verifikasi offline; tidak melakukan restore ke database mana pun.
- Reset pukul **10:05:30 WIT** menghapus **439 record**. Satu record ADMIN utama tetap identik seluruh kolomnya, termasuk hash kata sandi. Delapan record migration tidak berubah. Semua sesi lama dihapus dan login ADMIN dengan kredensial lama dikonfirmasi berhasil oleh Project Lead.
- Seluruh ID data operasional lama tidak ditemukan lagi; 22 foreign key valid tanpa orphan.

| Modul | Jumlah |
|---|---:|
| Poliklinik | 5 |
| Profil dokter / akun DOKTER | 10 / 10 |
| Ruang/loket | 7 |
| Jam/kapasitas mingguan | 30 |
| Jadwal praktik | 155 |
| Slot konsultasi | 1.425 |
| Akun PETUGAS | 8: 7 aktif, 1 nonaktif |
| Penugasan loket | 7 |
| Akun pasien USER | 40 |
| Appointment / walk-in | 30 / 13 |
| Perangkat display | 5 |
| Peristiwa/audit antrean | 73 |

Poliklinik: Anak, Penyakit Dalam, Mata, Bedah Umum, Saraf. Anak/Penyakit Dalam/Saraf memakai HIBRIDA, Mata JANJI_TEMU_DOKTER, Bedah Umum ANTREAN_HARIAN. Anak dan Penyakit Dalam memiliki dua ruang. Gelar spesialis mengikuti Sp.A, Sp.PD, Sp.M, Sp.B, Sp.N.

Jam layanan Senin–Sabtu 07:00–17:00 WIB, kapasitas 80 per poli/hari. Jadwal dokter bervariasi pagi/siang selama **27 Oktober–30 November 2026**, tanpa hari Minggu. Sesi aktif pagi tanggal awal memungkinkan uji antrean langsung. Slot 20 menit, kapasitas 2; tersedia satu contoh slot penuh dan banyak slot yang masih dapat dipesan. Tidak ada booking melebihi kapasitas.

Distribusi 43 tiket: DIPESAN 27, CHECK_IN 1, MENUNGGU 6, DIPANGGIL 1, DILAYANI 1, SELESAI 2, DILEWATI 1, DIBATALKAN 4. CHECK_IN dibuat melalui jalur legacy; lainnya melalui QR One-Scan/QueueService. CALL, RECALL, SKIP, REQUEUE, START, COMPLETE dan pembatalan appointment memakai service existing. REQUEUE menghasilkan satu tiket MENUNGGU, tanpa tiket/nomor baru. Dua pelayanan selesai terjadi pada waktu nyata tanggal 27 Oktober; tidak ada penyelesaian pada tanggal mendatang atau clock palsu.

Riwayat kunjungan bersumber dari tiket SELESAI, bukan tabel/fitur klinis baru. `notifikasi` tetap kosong karena backend existing belum memiliki workflow penulis notifikasi persisten; tidak mengarang fitur tambahan. Upload lama tidak dihapus dari storage, agar file pengguna/backup tetap terlindungi.

## Perintah eksplisit

Jalankan dari root repository. Harus tersedia dependensi `apps/api`, build NestJS terbaru, Git, serta PostgreSQL 18 command-line tools. `npm run db:seed` lama tetap tersedia untuk kebutuhan lamanya dan **bukan** perintah dataset ini.

```powershell
Set-Location apps/api
npm run build
Set-Location ../..

# Isi UUID ADMIN utama dari pemeriksaan read-only, jangan menebak akun.
$adminId = '<UUID_ADMIN_UTAMA>'
$batch = 'D:/QueueB-Backups/development-reset/<BATCH_BARU>'
New-Item -ItemType Directory -Path $batch
$identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
icacls $batch /inheritance:r /grant:r ($identity + ':(OI)(CI)F') 'SYSTEM:(OI)(CI)F'

node apps/api/tool/development-data.cjs preview "--admin-id=$adminId"
node apps/api/tool/development-data.cjs backup "--admin-id=$adminId" "--output=$batch"

# Gunakan checkpoint JSON yang baru dicetak backup, maksimum satu jam.
$checkpoint = '<PATH_ABSOLUT_CHECKPOINT_JSON>'
node apps/api/tool/development-data.cjs reset "--admin-id=$adminId" "--checkpoint=$checkpoint" --confirm=RESET-capstone_antrean --maintenance=acknowledged
node apps/api/tool/development-data.cjs seed "--admin-id=$adminId" "--output=$batch"
node apps/api/tool/development-data.cjs verify "--admin-id=$adminId" "--output=$batch"

# API lokal harus aktif. Hanya login dan GET; tidak mengubah booking/antrean.
node apps/api/tool/development-data.cjs smoke "--admin-id=$adminId" "--output=$batch"
```

Preview hanya membaca database dan menunjukkan rencana penghapusan serta dataset. Backup memakai snapshot PostgreSQL konsisten. Reset menolak target lain, production/test, schema lain, ADMIN ambigu/nonaktif, perubahan SQL migration, tabel tak dikenal, FK bermasalah, backup kedaluwarsa/rusak, dan baseline non-sesi yang berubah. Perbedaan LF/CRLF migration diperiksa dengan checksum kedua bentuk saja; SQL semantik yang berubah tetap ditolak. Perubahan sesi normal dicatat pada jumlah penghapusan aktual.

Hentikan aktivitas tulis aplikasi selama maintenance. Reset mengunci seluruh tabel yang dikenal dan memeriksa ulang baseline **sebelum** DELETE, dalam satu transaksi, tanpa cascade, menonaktifkan constraint, truncate, drop, atau Prisma migrate reset. Kegagalan reset membatalkan transaksi tersebut; tidak melakukan restore otomatis. ADMIN dan migration diverifikasi kembali sebelum COMMIT. Sesi ADMIN juga dicabut agar tidak ada sesi lama yang bertahan.

Dataset bertanggal tetap ini memiliki guard waktu: reset/seed pertama hanya diizinkan **27 Oktober 2026 07:00–11:40 WIB**, sebelum sesi pagi berakhir, agar seluruh status live terbentuk melalui service dengan jam nyata. Di luar waktu tersebut reset ditolak sebelum penghapusan. Periode dataset berikutnya harus direncanakan ulang secara eksplisit, bukan memalsukan waktu domain. Backup/preview/verify tidak membutuhkan jendela tersebut.

Seed yang sudah lengkap dapat dijalankan ulang: hanya validasi, **no-op**, tanpa duplikasi/password baru/transisi tambahan. Jika seed terhenti parsial, skrip berhenti dan meminta review checkpoint privat; tidak menimpa, menghapus, atau mengulangi CALL/booking secara spekulatif. Gunakan direktori batch baru untuk reset baru. Jangan menghapus checkpoint sebagai cara melewati guard.

## Kredensial, display, dan keamanan

Setiap akun baru memiliki password acak independen, di-hash oleh PasswordService existing. Akun USER dibuat melalui AuthService, akun PETUGAS melalui service ADMIN, dan akun DOKTER melalui provisioning resmi. Kredensial plaintext hanya berada pada `akun-pengujian.json` dalam direktori batch eksternal dengan ACL pemilik/SYSTEM. Jangan memasukkan file tersebut, checkpoint, dump, token, atau `.env` ke Git/chat/log. Setelah presentasi, akun sintetis dapat dinonaktifkan melalui ADMIN.

Seeder bekerja offline; transaksi dan audit domain nyata tetapi tidak mengirim event WebSocket dari proses maintenance yang tidak memiliki klien. Setelah aktivasi, aplikasi membaca ulang snapshot dari API normal. Uji jaringan realtime dijalankan terpisah pada database E2E terisolasi.

Kelima display terdaftar dengan scope poli sendiri. Pairing, penolakan lintas scope/perangkat, serta rotasi A tanpa mengganggu B sudah diuji menggunakan service pairing. Pada akhir seed semua credential uji dicabut melalui rotasi; kode/token mentah tidak disimpan. ADMIN harus **Generate Kode Aktivasi baru → Ganti perangkat/aktivasi TV** untuk setiap monitor. Token/cookie perangkat lama memang tidak berlaku lagi.

## Validasi aktual

- Tujuh tes tool/safety guard berjalan pada `npm run test:data-tools` dan lifecycle `pretest` CI; tidak mengakses/menghapus database.
- Seluruh 679 unit test backend, lint, type check dan build NestJS lulus.
- 36 E2E lulus: auto-check-in, hospital-hibrida, doctor-daily-queue, display-pairing. Runner `test/run-admin-delete.cjs` memvalidasi `127.0.0.1:5433/capstone_antrean_test`; 13 record baseline test tetap utuh, 0 perubahan/hilang/sisa fixture.
- Validasi seeder: 0 konflik dokter/ruang/penugasan, 0 slot overlap/di luar sesi, 0 kapasitas terlampaui, 0 salah relasi appointment, 0 kesalahan kronologi, seluruh tanggal dalam periode, serta setiap poli memiliki ruang dan setiap dokter akun DOKTER.
- 57 akun baru aktif berhasil login; satu PETUGAS nonaktif ditolak. Snapshot lima dokter terbaca dan akses lintas poliklinik ditolak.
- HTTP API development: health 200, login USER/PETUGAS/DOKTER, profil/katalog poli-dokter-jadwal-slot, tiket/riwayat pasien, waiting/snapshot PETUGAS, serta portal/snapshot DOKTER lulus. Ketiga role memperoleh 403 pada pengelolaan akun ADMIN.
- Login ADMIN lama dikonfirmasi berhasil oleh pengguna. Tidak mengklaim tes UI Flutter/Android baru pada pekerjaan database ini.
- Eksekusi ulang seed lengkap terverifikasi no-op; tidak menulis data operasional atau mengganti kredensial.

Contoh menjalankan regresi tanpa menyentuh development:

```powershell
Set-Location apps/api
npm test -- --runInBand
node test/run-admin-delete.cjs --runTestsByPath test/auto-check-in.e2e-spec.ts test/hospital-hibrida.e2e-spec.ts test/doctor-daily-queue.e2e-spec.ts test/display-pairing.e2e-spec.ts
```

Laporan agregat tanpa identitas/credential: [DEVELOPMENT_DATA_20261027_QA.json](DEVELOPMENT_DATA_20261027_QA.json). Tidak ada migration, reset otomatis pada startup/CI/deployment, atau perubahan frontend.
