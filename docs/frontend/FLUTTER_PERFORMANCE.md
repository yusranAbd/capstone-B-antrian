# Optimasi performa dan ukuran Flutter

## Lingkup dan batas bukti

Baseline: main setelah PR #66, commit `b634e95`. SDK Flutter 3.47.5 stable / Dart 3.13.4. Pengukuran lokal sebelum/sesudah mempertahankan perubahan dashboard dokter pengguna yang sama (tiga file belum dikomit); perubahan itu tidak masuk PR optimasi. Mesin Windows memiliki sekitar 8 GiB RAM. Semua ukuran di bawah adalah byte file atau MiB (1.048.576 byte), bukan ukuran instalasi Android atau RAM proses.

Build Web menggunakan release, API_BASE_URL `http://127.0.0.1:3001/api/v1` dan SERVICE_TIME_ZONE `Asia/Jakarta`. Build APK menggunakan konfigurasi default existing. Tidak ada koneksi atau penulisan database selama pekerjaan ini.

**Pengukuran RAM/JavaScript heap Web belum selesai.** Alat computer-use menghentikan akses Chrome karena URL tab tidak dapat diverifikasi dengan cukup yakin. Angka 600 MB dari laporan pengguna belum direproduksi. Tidak ada klaim bahwa RAM tab berkurang atau memory leak Web terbukti hilang. Uji codec native dan identitas widget di bawah bukan pengganti profiling Chrome.

## Temuan dan perubahan

- APK debug mengandung engine tiga ABI, kernel Dart debug, validation library dan native barcode scanner. Pada baseline, tiga `libflutter.so` saja sekitar 112 MB sebelum overhead ZIP; kernel Dart sekitar 80 MB sebelum kompresi. Distribusi debug tidak mewakili aplikasi release; gunakan APK sesuai ABI. Lihat [pengukuran ukuran Flutter](https://docs.flutter.dev/perf/app-size) dan [build APK per ABI](https://docs.flutter.dev/deployment/android#build-an-apk).
- Lima ilustrasi sebelumnya dibundel, total 7.373 MiB. `admin_welcome.png` dan `patient_hospital.png` tidak mempunyai referensi runtime. Keduanya dikeluarkan dari pubspec, file sumber tetap tersedia.
- Login dan ilustrasi tiket dikonversi ke WebP lossless. Ukuran, alpha dan seluruh byte piksel RGBA hasil decode sama dengan PNG. Tidak ada resize/penurunan kualitas/desain; PNG sumber tetap disimpan. Ilustrasi bundled sekarang sekitar 3.05 MiB (turun 58,65%).
- Avatar profesional, avatar akun, dan preview upload dokter mendapat decode-width sesuai ukuran tampil dan DPR, menggunakan bucket yang dapat dipakai ulang. Rasio gambar dipertahankan. Web dapat mengabaikan hint decode; manfaat memori Web harus diukur terpisah. Lihat [Image Flutter](https://api.flutter.dev/flutter/widgets/Image-class.html).
- ThemeData QueueB yang immutable dipakai ulang, bukan dibuat kembali setiap akses. Warna, ukuran, ikon dan desain tidak berubah.
- Timer jam Public Display kini memperbarui ValueNotifier yang hanya membangun ulang area jam. Snapshot, kartu loket dan pemilihan antrean tidak dibangun ulang setiap detik. Refresh REST, realtime, TTS dan deduplikasi CALL/RECALL tetap berjalan.
- Callback error TTS yang menangkap state halaman dilepas saat dispose; callback platform plugin tidak lagi mempertahankan closure halaman lama.
- Semua dependency dipertahankan. Percobaan melepas cupertino_icons dibatalkan karena build menemukan referensi ikon adaptif dari framework. Tidak dilakukan upgrade dependency/scanner atau perubahan kemampuan scan offline.
- Kebijakan global ImageCache tidak diperkecil secara paksa, dan tidak ada fitur realtime atau aksesibilitas yang dimatikan.

## Hasil ukuran

Lihat `FLUTTER_PERFORMANCE_MEASUREMENTS.json` untuk byte, SHA-256, kategori APK dan perbandingan final. APK release sesudah optimasi juga memakai `--split-debug-info`; simbol disimpan di output lokal, tidak masuk Git. Ukuran file APK berbeda dari kebutuhan ruang instalasi.

| Artifact | Sebelum (MiB) | Sesudah (MiB) |
| --- | ---: | ---: |
| Web release, seluruh folder termasuk varian engine | 49.80 | 45.48 |
| APK debug | 226.19 | 176.97 |
| APK release universal | 82.17 | 73.89 |
| APK armeabi-v7a release | 30.65 | 24.87 |
| APK arm64-v8a release | 34.48 | 28.90 |
| APK x86_64 release | 36.84 | 31.26 |
| Ilustrasi bundled | 7.37 | 3.05 |

Web release turun 8,68%; APK release universal turun 10,08%; arm64 turun 16,17%. Perbandingan release mencakup aset dan flag split-debug-info, bukan hanya perubahan kode. Seluruh APK release sebelum/sesudah diperiksa untuk tiga/satu ABI yang sesuai dan struktur manifest/DEX.

APK debug baseline mengandung 47.096.357 byte ruang antar-entry ZIP yang tidak direferensikan (padding incremental build). Perubahan aset juga dapat meninggalkan ruang kosong seperti ini pada APK debug berikutnya. Sesudah membuat ulang hanya output APK debug, ukuran menjadi 185.567.998 byte. Sebagian besar penurunan debug adalah penghilangan padding lama, bukan perubahan kode. Script pengukuran membuat ulang hanya file generated di `build/app/outputs/apk/{debug,release}` sebelum packaging; source dan cache compiler tetap dipertahankan. Pengurangan padding artifact bukan bukti penghematan RAM runtime. Tidak dipakai flutter clean.

## Audit resource dan regresi

| Resource | Pemeriksaan |
| --- | --- |
| PatientUpdates / portal dokter | Socket forceNew, listener API/observer lifecycle dan timer dibersihkan saat dispose; deduplikasi event dibatasi 256 ID; fallback polling dan reconnect dipertahankan. |
| RealtimeFeed / PETUGAS / Display | Socket dispose, listener kredensial dilepas; timer polling dan SnapshotLoader dibersihkan ketika ruang/perangkat diganti atau halaman ditutup. |
| Tiket QR | Timer countdown, listener updates dan RefreshGate dibersihkan; penerbitan QR tetap eksplisit, tidak otomatis saat reconnect. |
| QueueApi | Timer refresh token dan HTTP client ditutup saat dispose; cache avatar dibatalkan pada perubahan identitas/logout. Login persisten dipertahankan. |
| Controller UI / scanner | Controller formulir, scroll dan scanner memiliki dispose. Tidak ada perubahan izin kamera atau pipeline scan. |
| Public Display | Timer jam/room deck dibatalkan, notifier clock dibuang, listener fullscreen/observer dilepas dan suara dihentikan. Callback error TTS dilepas. |
| Daftar | Tabel ADMIN sudah memakai pagination lokal; preview dokter beranda dibatasi tiga kartu. Tidak ada bukti yang membenarkan rewrite daftar atau perubahan kontrak pagination. |

- Suite Flutter: **329 PASS, 1 SKIP**, meliputi ADMIN, PETUGAS, DOKTER, PASIEN, Public Display, QR, booking, session persistence, navigasi dan realtime. Tes live dilewati karena memerlukan fixture dari `tool/run-live.cjs`; tidak dibuat fixture database baru untuk audit ini.
- Tes tambahan: 40 siklus pembuatan/dispose feed untuk USER dan 40 untuk DOKTER; sesudah tiga menit fake time dan perubahan token tidak ada socket/listener/poll tersisa atau socket baru.
- Tes clock: 60 tick memperbarui waktu sementara identitas widget snapshot menunggu tetap sama (tidak rebuild subtree antrean).
- Benchmark codec native dengan ilustrasi 1254×1254: RGBA decoded **6.290.064 → 65.536 byte** pada target 128×128. Ini pengukuran alokasi gambar uji pada codec native, bukan angka RAM total Android/Web atau pengukuran foto pengguna.
- Flutter analyze final: tanpa issue. Format, build Web release dan APK debug/release/split diperiksa. Validasi final artifact dicatat di tabel dan JSON.
- Seluruh 51 file lokal pengguna tetap identik, tidak di-stage. Backend, database, migration, autentikasi/RBAC dan Queue Engine tidak berubah.

## Reproduksi build

File perubahan: `pubspec.yaml`; `assets/illustrations/{login_hospital,patient_ticket}.webp`; `lib/src/{admin_doctor_profile,display,display_board,doctor_professional,image_sizing,login_ui,mobile_ui,patient_home,user_profile}.dart`; `test/{patient_sync,performance_resources}_test.dart`; `scripts/flutter-performance.ps1`; laporan ini dan `FLUTTER_PERFORMANCE_MEASUREMENTS.json`. Semua path Flutter berada di `apps/client/`. File sumber PNG dan pekerjaan dashboard dokter lokal dipertahankan.

Gunakan SDK dan source yang sama serta checkout terpisah untuk perbandingan. Dari root repository:

```powershell
./scripts/flutter-performance.ps1 -Label before -Flutter C:/Development/flutter/bin/flutter.bat
./scripts/flutter-performance.ps1 -Label after -Flutter C:/Development/flutter/bin/flutter.bat -SplitDebugInfo
```

Jalankan label before pada baseline dan after pada branch optimasi. Parameter ApiBaseUrl dan ServiceTimeZone harus sama di dua sisi dan sesuai lingkungan integrasi. Script menyimpan versi SDK, log, SHA-256 dan ukuran ke `tmp/flutter-performance/<label>/`; artifact hasil pengukuran sesi ini berada di `tmp/performance/{before,after}/`. Jangan memasukkan APK, simbol, log lokal, atau rahasia ke Git.

Untuk distribusi Android arm64 gunakan varian `app-arm64-v8a-release.apk`; ABI lain tetap tersedia. APK benchmark memakai endpoint default existing; untuk pemasangan pada perangkat nyata isi ApiBaseUrl dengan alamat backend yang dapat dijangkau perangkat. Signing release masih memakai konfigurasi debug existing, sehingga signing distribusi production tetap pekerjaan rilis tersendiri. Build memberi peringatan kompatibilitas Kotlin Gradle Plugin dari flutter_tts untuk Flutter mendatang; dependency tidak di-upgrade dalam optimasi ini.

## Protokol RAM Web yang masih harus dijalankan

1. Serve artifact release dengan konfigurasi backend yang sama, tanpa Flutter debug/hot reload. Catat versi Chrome, OS, viewport, DPR, ekstensi, mode cache dan role. Jalankan sebelum/sesudah bergantian di tab baru, tiga pengulangan per kondisi.
2. Chrome Task Manager: catat memory footprint renderer tab yang benar. Pisahkan dari total semua proses Chrome/GPU. Buka [Performance Monitor](https://developer.chrome.com/docs/devtools/performance-monitor): catat JS heap, DOM nodes, event listeners, CPU, layouts dan style recalculations. JS heap saja tidak mewakili engine Wasm, image/GPU atau RAM tab.
3. Ukur setelah idle 60 detik; sesudah 20 siklus berpindah halaman role; lalu pada menit 5 dan 10 saat realtime tetap aktif. Untuk Public Display sertakan CALL, RECALL, reconnect, mute/unmute dan keluar halaman. Jangan masukkan token atau data pasien dalam trace/screenshot publik.
4. Pada Memory panel ambil heap snapshot sesudah GC pada titik yang sama; bandingkan retained/detached object setelah navigasi dan logout. Grafik naik sementara sebelum GC tidak cukup membuktikan leak. Rekam Performance trace untuk frame/rendering pada navigasi dan event antrean.
5. Isi tabel dengan median dan rentang tiga run, bukan angka tunggal dari debug atau screenshot Task Manager seluruh browser.

| Metrik Web release | Sebelum | Sesudah | Status |
| --- | --- | --- | --- |
| RAM tab idle | Belum terukur | Belum terukur | Akses Chrome DevTools terhenti saat verifikasi URL |
| RAM setelah 20 siklus navigasi | Belum terukur | Belum terukur | Sama |
| Pertumbuhan RAM menit 5/10 | Belum terukur | Belum terukur | Sama |
| JS heap / DOM / event listener / frame trace | Belum terukur | Belum terukur | Sama |

Penghematan ukuran file dan pengurangan rebuild telah diverifikasi. Target penurunan RAM Web belum dapat dinyatakan tercapai sampai protokol di atas selesai.
