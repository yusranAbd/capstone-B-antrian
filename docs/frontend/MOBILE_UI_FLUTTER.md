# Mobile UI QueueB Hospital

Implementasi pada `apps/client`, branch `feature/flutter-mobile-ui-redesign`, dari main `538769d` (PR #40). Referensi presentation board dipakai untuk susunan dan identitas visual, bukan penambahan fitur backend.

## Layar dan fondasi

1. **Welcome / Masuk / Daftar**: identitas QueueB, ilustrasi rumah sakit yang digambar dengan Flutter, formulir autentikasi JWT existing, validasi dan penanganan error. Registrasi tetap USER saja.
2. **Beranda pasien**: nama dari sesi login, banner, empat akses cepat, janji temu mendatang berdasarkan data milik pengguna. Bottom navigation: Beranda, Pendaftaran, Tiket Saya, Janji Temu.
3. **Poliklinik dan dokter**: pencarian nama, filter kanal, kartu poli dan dokter terhubung. Pilihan form existing dipertahankan untuk aksesibilitas. Ketersediaan dokter diketahui melalui jadwal/slot, bukan klaim pada kartu.
4. **Booking**: ringkasan dokter, tanggal pelayanan menurut `SERVICE_TIME_ZONE`, kalender dan pilihan tujuh hari, sesi/ruang serta slot dari API. Kapasitas dan `tersedia` tetap otoritatif dari backend. Booking memerlukan konfirmasi.
5. **Tiket / QR**: nomor besar, status aktual, informasi poli/tanggal serta dokter/ruang/slot untuk appointment. QR terbit pada hari pelayanan, sekali pakai, kedaluwarsa 600 detik; polling dan tombol refresh tetap tersedia. Pembatalan hanya appointment DIPESAN.
6. **Petugas**: identitas petugas dan ruang, status koneksi realtime, kamera atau input payload QR, Check-In terpisah dari Masuk Antrean, tiket aktif dan kontrol sesuai state, receipt sementara, pemulihan ID sah dan daftar menunggu menurut urutan server.

`lib/src/mobile_ui.dart` menyimpan token warna, tema Material 3, branding, ilustrasi serta kartu/status/empty state reusable. Tema teal dibatasi pada autentikasi, USER dan PETUGAS. ADMIN Web dan Public Display tetap memakai tema/layout sebelumnya; API client, konfigurasi dan layanan Socket.IO tidak diubah.

File implementasi: `lib/src/app.dart` (autentikasi/role), `patient.dart` (empat tujuan navigasi pasien dan QR), `queue.dart` (panel petugas) serta `mobile_ui.dart` (komponen). Regresi ada di `test/ui_test.dart`; instrumentasi perangkat di `integration_test/mobile_flow_test.dart`. Harness `tool/android-demo.cjs`, `run-live.cjs`, `browser-demo.cjs` dan `browser-smoke.cjs` mengikuti navigasi baru. `pubspec.yaml`/lock hanya menambah SDK `integration_test` sebagai dependency pengujian.

Tidak ada data rating/ulasan, estimasi antrean palsu, foto dokter rekaan, social login, forgot password, reschedule, endpoint atau schema baru. Akses Public Display menjelaskan kebutuhan token perangkat pengelola; pasien tetap melihat status pribadi lewat Tiket Saya.

## Menjalankan

Gunakan instruksi konfigurasi pada [README Flutter](../../apps/client/README.md) dan [panduan demo](DEMO_FLUTTER.md). `API_BASE_URL` dan `SERVICE_TIME_ZONE` tetap diberikan melalui `--dart-define`. Backend mengikuti [API Integration Guide](../backend/API_INTEGRATION_GUIDE.md).

## QA yang dapat diulang

```powershell
cd apps/client
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter build web --release --no-web-resources-cdn --dart-define=API_BASE_URL=http://127.0.0.1:3001/api/v1
flutter build apk --debug --dart-define=API_BASE_URL=http://10.0.2.2:3000/api/v1
```

Dari root repository, setelah backend compiled dan PostgreSQL test lokal tersedia:

```powershell
node apps/client/tool/run-live.cjs --demo-browser
$env:FLUTTER_ANDROID_DEVICE='<id-adb>'
$env:ADB_PATH='C:\Users\hp\AppData\Local\Android\sdk\platform-tools\adb.exe'
node apps/client/tool/run-live.cjs --android
```

Harness memvalidasi `127.0.0.1:5433/capstone_antrean_test`, membuat fixture unik dan membersihkan fixture tersebut saja, lalu membandingkan fingerprint data yang sudah ada. Tidak ada reset, migrasi atau akses database development utama.

Harness Android memakai `adb reverse` pada port 3001/3002 yang belum digunakan. Port 3002 adalah server loopback khusus instrumentasi untuk kredensial fixture sementara dan penerimaan screenshot; tidak masuk APK aplikasi normal maupun backend. Pemetaan milik tes dilepas saat selesai. Izin kamera diberikan khusus aplikasi QueueB untuk QA perangkat.

Screenshot hasil perangkat disimpan lokal dalam `apps/client/build/android-screenshots/`; log, credential fixture, APK dan build tidak di-stage. QR pada screenshot adalah fixture test yang dibersihkan, bukan tiket pasien nyata.

Nama screenshot yang akan dihasilkan bila instrumentasi perangkat selesai: `01-login.png`, `02-beranda.png`, `03-poliklinik-dokter.png`, `04-booking-slot.png`, `05-tiket-qr.png`, dan `06-petugas.png`. Screenshot browser mobile berawalan `mobile-` di `apps/client/build/web/` merupakan artefak berbeda; jangan menyebutnya sebagai screenshot Android.

## Hasil verifikasi

Verifikasi pada 17 Oktober 2026:

- **48/48 unit/widget PASS**; satu tes live REST terpisah SKIP secara default. Regresi mencakup login/registrasi, navigasi, loading/offline dan coba ulang, empty state, tujuh status tiket, kartu dokter, slot tidak tersedia, pembatalan, seluruh aksi petugas, kalender serta Public Display/TTS existing.
- Layout USER dan PETUGAS diuji pada lebar **320, 375, 414 dan 768 piksel** tanpa overflow. QR dibatasi oleh lebar konten dialog.
- Format Dart dan analyzer **PASS**, tanpa temuan.
- Web release dengan resource lokal **PASS**. Wasm bukan target build ini; dependency TTS/Socket.IO masih memberi peringatan kompatibilitas dry run Wasm.
- APK debug aplikasi normal (`lib/main.dart`, bukan entrypoint tes) **PASS**. Artefak: `apps/client/build/app/outputs/flutter-apk/app-debug.apk`. Build ini memakai `API_BASE_URL=http://127.0.0.1:3000/api/v1` untuk koneksi USB lokal; setelah perangkat tersambung stabil, gunakan `adb -s <id-adb> reverse tcp:3000 tcp:3000`. Emulator/LAN memerlukan alamat API yang sesuai dan build ulang dengan `--dart-define` seperti contoh di atas.
- **Skenario browser lengkap PASS** pada build final: CRUD ADMIN (poli, dokter, relasi, ruang, sesi, slot, penugasan), dua USER (appointment dan walk-in hingga tiket/QR), semua aksi PETUGAS sampai kedua tiket SELESAI, snapshot Socket.IO/Public Display dan deduplikasi pengumuman. Kamera laptop membuka stream 640×480; decode QR nyata memakai video QR fixture pada kamera virtual browser, serta penolakan izin diuji terpisah. Ini bukan klaim scan QR fisik Android.
- Voice native browser `id-ID` tersedia dan callback sintesis berhasil diamati. Logika deduplikasi juga lulus pada halaman dengan Web Speech test double yang dinyatakan terpisah dari mesin native.
- Run akhir Display memperoleh **23 snapshot HTTP 200 dan satu HTTP 500** dengan `Prisma P2028` (batas transaksi 5000 ms, tercatat 6143 ms). UI pulih melalui refresh berikutnya dan kedua alur selesai. Penyebab performa perlu diperiksa pada lingkungan target; tidak disimpulkan sebagai bug logika backend atau diubah pada scope redesign.
- Setiap run memvalidasi database test dan fingerprint **13 record existing: 0 hilang, 0 berubah; 0 fixture baru tersisa** setelah cleanup.
- APK instrumentasi Android berhasil dibangun dan sempat dipasang pada **2410CRP4CG / Android 16**. **Alur Android dan screenshot fisik belum dapat dinyatakan lulus**: koneksi USB berulang kali terputus dan satu pemasangan ulang ditolak dengan `INSTALL_FAILED_USER_RESTRICTED`. Tidak ada screenshot Android yang diklaim dari artefak browser.

Percobaan awal harness Android juga menemukan penggunaan `Response.ok` sebagai fungsi; sudah dikoreksi menjadi properti Fetch. Harness login ulang sebelum menyiapkan slot setelah build, serta menggulir widget yang dibangun secara lazy. Ini perubahan tooling QA, bukan perubahan autentikasi atau backend.

Overflow kartu akses cepat pada layar sempit diperbaiki dengan tinggi konten yang fleksibel. Tahap booking menyembunyikan pemilih poli/dokter yang berulang; navigasi baru mengembalikan posisi gulir saat berpindah halaman. Refresh status tiket yang berhasil membersihkan error sebelumnya. Respons jadwal lama dibatalkan secara logis ketika tanggal pilihan berubah.

Riwayat hasil sebelum redesign tetap berada pada [finalisasi MVP sebelumnya](FINALISASI_FLUTTER_MVP.md). Lihat checklist/status Pull Request untuk verifikasi CI terhadap commit akhir.

## Batas existing

- Token hanya di memori; reload memerlukan login kembali.
- Public Display memerlukan provisioning token perangkat dan voice `id-ID` untuk suara.
- Kamera Web memerlukan HTTPS/localhost dan izin perangkat; input payload QR tetap tersedia.
- Tidak ada endpoint global receipt CHECK_IN/DILEWATI; daftar sementara dan pemulihan ID tetap dipertahankan.
- Resolusi manual HOSP-OPS-01 tetap di luar scope.
- `flutter_tts` masih menerapkan Kotlin Gradle Plugin lama; build saat ini berhasil, tetapi upgrade dependency diperlukan sebelum berpindah ke Flutter yang mewajibkan Built-in Kotlin. Tidak dilakukan upgrade di luar scope redesign ini.
