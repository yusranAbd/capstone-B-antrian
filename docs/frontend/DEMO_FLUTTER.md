# Panduan demo QueueB Hospital — Flutter

Gunakan satu source `apps/client`, Backend MVP existing, dan kontrak `docs/backend/API_INTEGRATION_GUIDE.md`. UI tidak didesain ulang. Panduan ini melengkapi `CONTRIBUTING.md` dengan nama konfigurasi Flutter yang benar-benar tersedia.

## Sebelum presentasi

1. Jalankan PostgreSQL/API existing pada database demo yang disetujui pengelola. Jangan reset/menghapus data atau mengubah migration untuk menyiapkan demo.
2. Siapkan akun ADMIN, PETUGAS dan **dua USER berbeda**. Akun operasional/perangkat display diprovision pengelola server; USER dapat registrasi. Satu USER hanya boleh memiliki satu tiket non-batal per poli/hari, termasuk tiket yang sudah selesai.
3. Siapkan ID layanan dan token perangkat display secara privat. Jangan taruh token di URL, dart-define, slide, source, screenshot atau Git.
4. Samakan `SERVICE_TIME_ZONE` Flutter dan backend. Default **Asia/Jakarta**, bukan zona jam laptop. Jadwal, slot, tanggal pelayanan dan penugasan harus berada pada tanggal pelayanan yang sama.
5. Jalankan Web dari `apps/client`:

```powershell
flutter pub get
flutter run -d chrome --web-hostname localhost --web-port 5173 --dart-define=API_BASE_URL=http://localhost:3000/api/v1 --dart-define=SERVICE_TIME_ZONE=Asia/Jakarta
```

Backend harus mengizinkan origin `http://localhost:5173`. Jika menggunakan `127.0.0.1`, samakan host di origin dan API; kedua host tidak identik bagi browser. Buka sesi browser/profil terpisah untuk ADMIN, PETUGAS, kedua USER dan display karena setiap tab menyimpan sesi hanya di memorinya. Reload meminta login/token ulang.

## Urutan demonstrasi

| Aktor | Tindakan | Hasil yang diperiksa |
|---|---|---|
| ADMIN | Buat poli HIBRIDA, jam layanan hari ini dan kuota, ruang/loket | Poli menerima walk-in serta appointment; ruang terkait poli yang sama |
| ADMIN | Buat dokter, Hubungkan poliklinik, buat jadwal praktik pada ruang dan tanggal demo | Dokter aktif, relasi aktif, sesi berada dalam jam layanan |
| ADMIN | Buat slot yang **belum mulai** dengan kapasitas tersedia | Slot berada dalam sesi; pasien harus booking sebelum slot mulai |
| ADMIN | Penugasan petugas memakai ID akun dari profil PETUGAS | Penugasan aktif mencakup hari demo dan ruang sesi; satu petugas tidak diberi penugasan tumpang tindih |
| USER A | Pilih poli → Walk-in → Reservasi → Tiket Saya | Tiket DIPESAN dan nomor antrean dari backend |
| USER B | Pilih poli → dokter → Lihat jadwal dokter → Lihat slot → pilih slot tersedia → Booking | Appointment berbeda dari tiket; dokter, ruang dan waktu tampil pada detail tiket |
| USER A/B | Lihat tiket / QR → Terbitkan QR | QR pada hari pelayanan, berlaku 600 detik, sekali pakai; QR baru menggantikan QR lama |
| PETUGAS | Pilih ruang → Pindai kamera atau tempel payload → Check-In | Status CHECK_IN; belum masuk daftar menunggu |
| PETUGAS | Masuk Antrean untuk kedua tiket | Status MENUNGGU; snapshot/display diperbarui |
| Display | Buka Public Display, masukkan token perangkat dan ID poli, Aktifkan suara | Realtime terhubung; tombol suara tidak mengaku aktif jika mesin gagal |
| PETUGAS | Setelah sesi/slot mulai, Panggil berikutnya | Backend memilih kandidat; nomor dan ruang muncul pada display |
| PETUGAS | Panggil Ulang → Lewati → Antre Ulang → Panggil berikutnya | RECALL mengumumkan kembali; REQUEUE mendapat prioritas waktu baru menurut backend |
| PETUGAS | Mulai Pelayanan → Selesaikan Pelayanan; ulangi untuk tiket kedua | Kedua tiket SELESAI, ruang siap melayani, display mengikuti keadaan server |
| USER A/B | Muat ulang tiket | Kedua status menjadi SELESAI |

Siapkan booking beberapa menit sebelum giliran demonstrasi. Slot yang sudah berakhir tidak otomatis membatalkan pasien selama sesi masih sah. Appointment MENUNGGU setelah sesi berakhir tidak dapat diselesaikan dengan mutasi rekaan; ini batas HOSP-OPS-01 existing. Jangan memakai PATCH sesi berisi slot sebagai jalan pintas.

## Kamera, suara dan jaringan

- Kamera Web membutuhkan **HTTPS atau localhost** dan izin kamera. `http://IP_LAN:5173` biasanya tidak menyediakan akses kamera; gunakan HTTPS yang sah atau PETUGAS pada localhost. Input payload merupakan fallback existing, bukan pemindaian kamera.
- Aktifkan suara dengan tombol pada display. Pastikan speaker tidak mute dan mesin browser menyediakan bahasa `id-ID`. Jika bahasa tidak tersedia atau mesin menolak/menyampaikan error, aplikasi tetap/kembali ke mode suara nonaktif dan pengumuman visual tetap bekerja. Gunakan browser/perangkat yang memiliki voice Indonesia; jangan mengganti bahasa secara diam-diam. Verifikasi suara terdengar sebelum mulai; pengujian sintesis API tidak membuktikan volume speaker fisik.
- Berikan waktu snapshot/event tiba sebelum tindakan berikutnya; gunakan Muat ulang bila koneksi sempat terputus. Event bersifat best effort, REST tetap sumber kebenaran.
- Jika request mutasi timeout, baca ulang tiket/snapshot sebelum mengulang agar tidak menganggap transaksi pasti gagal.
- Jangan menampilkan payload QR, token atau kata sandi pada layar presentasi yang direkam. Gunakan akun/data demo, bukan identitas pasien nyata.

## Android

Gunakan perangkat Android yang tersambung dan tampil di `flutter devices`, lalu:

```powershell
# Emulator: localhost API laptop dapat dijangkau melalui 10.0.2.2.
flutter run -d <id-perangkat> --dart-define=API_BASE_URL=http://10.0.2.2:3000/api/v1 --dart-define=SERVICE_TIME_ZONE=Asia/Jakarta
# Perangkat fisik: ganti IP contoh dengan IPv4 host API yang terjangkau pada LAN.
flutter build apk --debug --dart-define=API_BASE_URL=http://192.168.1.10:3000/api/v1 --dart-define=SERVICE_TIME_ZONE=Asia/Jakarta
```

Pasang `build/app/outputs/flutter-apk/app-debug.apk` pada perangkat demo sesuai prosedur pemilik perangkat. Jangan memakai `localhost`/`10.0.2.2` sebagai host API pada telepon fisik. HTTP diizinkan pada build debug saja; release membutuhkan HTTPS dan penandatanganan tersendiri. Tidak ada backend/schema yang harus diubah untuk menggunakan APK.

## Pemeriksaan otomatis

```powershell
# Dari apps/client
flutter analyze
flutter test
dart format --output=none --set-exit-if-changed .
flutter build web --release --no-web-resources-cdn --dart-define=API_BASE_URL=http://127.0.0.1:3001/api/v1
flutter build apk --debug --dart-define=API_BASE_URL=http://10.0.2.2:3000/api/v1
# Setelah build selesai, dari root repository
npm ci --prefix apps/client/tool
node apps/client/tool/run-live.cjs --demo-browser
```

Runner hanya memakai `127.0.0.1:5433/capstone_antrean_test` setelah validasi PG dan provider Prisma. Akun, poli dan perangkat fixture dibuat unik; tindakan aplikasi menggunakan API existing. Hanya fixture milik tes yang dibersihkan dan fingerprint data existing diperiksa. Tidak ada reset, migration atau credential fixture yang ditulis ke Git. Video kamera virtual sementara dihapus setelah tes. Hasil/screenshot ada di `apps/client/build/web`, yang diabaikan Git.

Kamera virtual pada tes berisi QR yang baru diterbitkan USER dan melewati decoder `mobile_scanner` asli. Pengujian pembukaan kamera fisik hanya membaca status track/resolusi lalu menghentikannya; tidak merekam foto/video orang. Hasil kamera fisik dan suara mesin harus dibaca sesuai laporan aktual, bukan disamakan dengan pengujian Android fisik.
