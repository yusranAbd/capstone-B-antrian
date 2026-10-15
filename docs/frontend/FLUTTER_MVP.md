# QueueB Hospital — Flutter MVP

Fondasi frontend tunggal berada di `apps/client`: ADMIN, PETUGAS, USER dan Public Display memakai Flutter/Dart. Flutter Web untuk operasional/display; Android untuk pasien, dengan UI pasien juga tersedia pada Web. Backend tetap pada kontrak `docs/backend/API_INTEGRATION_GUIDE.md` v1.2, tanpa endpoint atau migration tambahan.

## Struktur dan menjalankan

- `lib/src/api.dart`: REST, Bearer JWT, validasi `/auth/me`, refresh token rotasi single-flight dan logout.
- `config.dart`: alamat API serta kalender/instant menurut `SERVICE_TIME_ZONE` (default Asia/Jakarta).
- `app.dart`: login, registrasi USER, profil/ID akun dan pemisahan navigasi role.
- `admin.dart` / `admin_schema.dart`: master poli, dokter, relasi dokter–poli, ruang, jam/kuota, sesi, slot dan penugasan.
- `queue.dart`: Check-In QR/kamera, ENQUEUE, CALL, RECALL, SKIP, REQUEUE, START, COMPLETE dan snapshot.
- `patient.dart`: katalog, jadwal, slot, booking, walk-in, pembatalan appointment DIPESAN, tiket/QR dan polling status.
- `display.dart` / `realtime.dart`: token perangkat, snapshot publik, Socket.IO, suara Indonesia, deduplikasi audit dan fetch dirty.

SDK yang diverifikasi: Flutter 3.47.5 / Dart 3.13.4. Jalankan dari `apps/client`:

```powershell
flutter pub get
flutter run -d chrome --web-hostname localhost --web-port 5173 --dart-define=API_BASE_URL=http://localhost:3000/api/v1 --dart-define=SERVICE_TIME_ZONE=Asia/Jakarta
```

Origin Web harus diizinkan pada konfigurasi backend `CORS_ALLOWED_ORIGINS`. `localhost` dan `127.0.0.1` berbeda. Gunakan zona yang sama dengan backend; zona perangkat tidak menentukan tanggal pelayanan. Kalender DATE dan jam TIME dari Prisma tidak dikonversi sebagai instant.

Android emulator:

```powershell
flutter run -d <id-emulator> --dart-define=API_BASE_URL=http://10.0.2.2:3000/api/v1 --dart-define=SERVICE_TIME_ZONE=Asia/Jakarta
flutter build apk --debug --dart-define=API_BASE_URL=http://10.0.2.2:3000/api/v1
```

Perangkat fisik memakai alamat backend yang dapat dijangkau perangkat. HTTP lokal hanya diizinkan manifest debug; release memerlukan HTTPS. Kamera Web memerlukan origin aman (HTTPS atau localhost) dan izin pengguna. Menolak kamera tetap memungkinkan input payload QR. QR tidak boleh disimpan dalam log/analytics.

Build Web untuk hosting:

```powershell
flutter build web --release --no-web-resources-cdn --dart-define=API_BASE_URL=https://api.example.org/api/v1 --dart-define=SERVICE_TIME_ZONE=Asia/Jakarta
```

Host direktori `build/web` pada origin yang diizinkan backend, termasuk WebSocket `/socket.io`. `API_BASE_URL` dan zona adalah konfigurasi publik, bukan tempat token/kata sandi. Token akun/perangkat tidak dimasukkan pada dart-define, URL atau repository.

## Alur integrasi

1. ADMIN membuat poli beserta mode, jam/kuota dan ruang; menyediakan penugasan akun PETUGAS existing. Akun ADMIN/PETUGAS serta perangkat display tetap diprovision oleh pengelola server: belum ada API CRUD akun/perangkat.
2. Untuk appointment, hubungkan dokter ke poli, buat sesi bertanggal dan slot. Form mengirim ID relasi dokterLayanan, waktu berzona dan kapasitas integer. Mode poli hanya saat create; PATCH slot tidak mengirim parent sesi.
3. USER memilih dokter/poli/tanggal/sesi/slot tersedia lalu booking, atau walk-in pada mode harian/hibrida. Backend menentukan kapasitas akhir. Tiket milik sendiri tersedia pada Tiket Saya; ID appointment untuk pembatalan berbeda dari ID tiket untuk QR.
4. USER menerbitkan QR pada hari pelayanan. QR baru menggantikan sebelumnya, hanya sekali pakai selama 600 detik. Tampilan menghapus QR setelah expired/status berubah dan menyinkronkan status setiap 10 detik.
5. PETUGAS memilih penugasan aktif hari ini, Check-In lalu Masuk Antrean. CALL dipilih server. Tombol lanjut mengikuti status aktual snapshot, termasuk beberapa tiket aktif jika ada. Nomor/urutan tidak disusun ulang klien.
6. Hasil Check-In dan SKIP disimpan sementara di memori sesi/ruang/hari untuk ENQUEUE/REQUEUE. Setelah reload, petugas dapat memakai ID tiket sah dari rujukan operasional; belum ada endpoint daftar global CHECK_IN/DILEWATI. Tidak ada cache QR, identitas pasien atau endpoint rekaan.
7. Antrean memakai `/queue` auth token dan ACK `queue:join`; display memakai `/display` auth token perangkat + layananId dan `display:ready`. Reconnect/token rotasi membuat koneksi baru. Snapshot disegarkan setelah event, reconnect, resume dan setiap 15 detik karena kelayakan slot dapat berubah tanpa event.
8. Public Display hanya merender snapshot publik. Suara memerlukan tombol aktivasi, menggunakan teks/bahasa backend dan audit peristiwaId; baseline historis tidak dibacakan, CALL/RECALL baru dideduplikasi, suara lama dihentikan sebelum suara berikutnya.

## Keamanan dan batas perilaku

- Role UI berasal dari `/auth/me`; backend JWT/RBAC tetap otoritas. Registrasi tidak mengirim role.
- Token hanya di memori. Menutup/reload aplikasi memerlukan login/provisioning display ulang. Logout meminta pencabutan token server dan langsung membersihkan sesi lokal.
- Refresh hanya satu request saat beberapa 401. Timeout/network error mutasi tidak diulang otomatis; UI membaca ulang data dan meminta evaluasi status. Refresh yang kehilangan respons mengakhiri sesi agar token rotasi tidak digunakan ulang secara buta.
- Form membatasi input, backend tetap memvalidasi hubungan dokter/slot/ruang/sesi/kapasitas. Error validasi dan konflik disajikan sebagai pesan backend.
- HOSP-OPS-01 masih batas backend: MENUNGGU setelah sesi berakhir tampil dengan alasan, tanpa tombol cancel/perpanjangan petugas. Tidak ada toleransi/fairness numerik tambahan.

## QA

```powershell
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
```

`core_test.dart` menguji kontrak/session/timezone/fetch/deduplikasi; `ui_test.dart` menguji login, ADMIN, PETUGAS seluruh aksi, pasien dua kanal/QR/pembatalan, display dan layout sempit. `live_integration_test.dart` dilewati secara default dan hanya dijalankan runner lokal berikut.

Untuk integration nyata, API existing harus sudah memiliki dependency/generated client/build dan database test yang migration-nya siap. Runner tidak menjalankan migration/reset. Dari root repository:

```powershell
node apps/client/tool/run-live.cjs
# Tambahan smoke browser atas build Web dengan API_BASE_URL=http://127.0.0.1:3001/api/v1:
npm ci --prefix apps/client/tool
node apps/client/tool/run-live.cjs --browser
```

Runner membaca kredensial koneksi lokal dari env tanpa mencetaknya, memaksa dan memvalidasi `127.0.0.1:5433/capstone_antrean_test` pada PG dan provider Prisma, membuat fixture unik, lalu membersihkan hanya fixture tersebut. Fingerprint 16 tabel sebelum/sesudah memastikan data existing tidak berubah dan tidak ada record baru tersisa. Credential fixture hanya lewat environment proses. Semua master/booking/QR/queue memakai API existing; akun/perangkat bootstrap sesuai provisioning server. Slot berada di masa depan saat booking; tes menunggu awal slot sah tanpa memanipulasi clock atau aturan backend.

Tool Node/Playwright hanya QA Flutter Web, bukan aplikasi JavaScript. Browser default Edge; `FLUTTER_BROWSER_CHANNEL=chrome` atau `chromium` dapat dipilih sesuai instalasi. Screenshot QA berada di `build/web` dan tidak masuk Git.

## Batas kesiapan

- Build Web menggunakan JavaScript/CanvasKit. Dependency Socket.IO/TTS saat ini memberi peringatan Wasm; mode Wasm belum diklaim siap.
- `flutter_tts` memberi peringatan migrasi Kotlin untuk SDK masa depan. Versi pada pubspec.lock telah diuji. Incremental Kotlin dimatikan karena cache Windows lintas drive; ini tidak mengubah perilaku aplikasi.
- Kamera, izin audio, kualitas suara Indonesia dan perangkat Android fisik memerlukan smoke manual. APK debug bukan APK produksi bertanda tangan.
- Persistensi login aman lintas restart, provisioning UI akun/perangkat, pagination/history dan penyempurnaan desain dapat dikerjakan kemudian sesuai kontrak/scope.
- Pekerjaan React/Vite lokal tetap dipertahankan di `apps/web`, dokumen `WEB_MVP.md` dan perubahan lokal README/CI/.gitignore; seluruhnya dikecualikan dari commit Flutter. Tidak ada proyek Flutter kedua dan tidak ada perubahan backend.

## Hasil verifikasi 14 Oktober 2026

- 26/26 tes unit/widget PASS; satu tes live sengaja SKIP pada perintah default dan dijalankan terpisah.
- 1/1 tes integrasi live PASS untuk appointment dan walk-in hingga SELESAI, QR sekali pakai, RECALL/SKIP/REQUEUE, JWT refresh serta seluruh jenis event pada dua namespace Socket.IO.
- 4/4 smoke browser Edge PASS: ADMIN, PETUGAS + realtime, pasien pada viewport sempit + Tiket Saya, Public Display + realtime.
- `flutter analyze`: No issues found; `dart format --output=none --set-exit-if-changed .`: 0 perubahan; pemeriksaan sintaks tool Node dan `git diff --cached --check`: PASS.
- Build Flutter Web release dengan resource lokal dan APK Android debug: PASS dari source final.
- Database aktual: `127.0.0.1:5433/capstone_antrean_test`. Fingerprint 16 tabel: 13 record existing, 0 hilang, 0 berubah, 0 record baru tersisa.
- Percobaan integrasi saat build paralel sempat timeout transaksi 5 detik. Verifikasi berurutan setelah build berhasil tanpa perubahan backend. Jalankan integrasi database setelah build untuk mengurangi kontensi resource lokal.
