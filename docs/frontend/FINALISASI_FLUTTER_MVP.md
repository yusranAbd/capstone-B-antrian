# Finalisasi demo Flutter MVP — 15 Oktober 2026

Basis `main`: `b3c1d09` (sudah memuat merge PR #39). Branch: `codex/flutter-demo-finalisasi`. Proyek tetap satu Flutter di `apps/client`; layout, warna, navigasi dan kontrak API existing dipertahankan. Tidak ada perubahan backend, schema atau migration.

## Perbaikan yang terbukti

1. Input tanggal manual sebelum hari ini/di luar batas kalender menyebabkan assertion `showDatePicker` dan kalender gagal terbuka. `initialServiceDate` sekarang memilih tanggal awal dalam batas kalender existing; nilai pendaftaran tidak diubah otomatis. Regresi mencakup tanggal lampau, terlalu jauh dan teks tidak valid.
2. Aktivasi TTS yang melempar error tetap membalik tombol menjadi suara aktif; error asinkron dari mesin juga tidak ditangani. Status audio kini bergantung pada keberhasilan aktivasi, callback error mematikannya, dan error suara tidak hilang saat snapshot diperbarui. Bahasa `id-ID` diperiksa sebelum sintesis agar tidak diam-diam memakai voice lain. Penghentian pengumuman lama saat RECALL/mute tetap diperbolehkan.

Kedua kasus direproduksi dengan tes gagal sebelum perbaikan, lalu lulus setelahnya. Tidak ada kebijakan antrean, toleransi waktu atau fairness baru.

## Hasil aktual

| Pemeriksaan | Hasil |
|---|---|
| Flutter unit/widget | **30/30 PASS**, termasuk 4 regresi baru; tes live terpisah tetap SKIP pada suite default |
| Analyzer / format / diff check | **PASS**, analyzer tanpa temuan |
| Build Web release, resource lokal | **PASS** |
| Build APK debug, konfigurasi emulator `10.0.2.2:3000` | **PASS** |
| Demo UI ADMIN | **PASS**: perubahan poli fixture, pembuatan dokter, relasi poli, ruang, sesi, slot dan perubahan penugasan melalui API nyata |
| Demo UI USER | **PASS**: katalog dokter/jadwal/slot, appointment dan walk-in dengan dua akun, penerbitan QR, kedua status akhir SELESAI tampil pada Tiket Saya |
| Demo UI PETUGAS | **PASS**: scan QR → CHECK_IN → ENQUEUE → CALL → RECALL → SKIP → REQUEUE → CALL → START → COMPLETE, kedua tiket selesai |
| Display / Socket.IO | **PASS**: dua pasien MENUNGGU, perubahan panggilan/status dan kembali nol menunggu; seluruh snapshot pada run final HTTP 200 |
| Decoder kamera Web | **PASS**: QR dari USER dikodekan ke video kamera virtual, dipindai `mobile_scanner` asli; CHECK_IN backend membuktikan identitas tiket yang sama |
| Penolakan kamera | **PASS**: simulasi `NotAllowedError`, pesan fallback tampil dan dialog dapat ditutup; bukan bukti penolakan OS fisik |
| Kamera fisik laptop | **PASS membuka stream 640×480**, semua track dihentikan tanpa merekam gambar; belum menguji QR optik dari layar/lembar fisik |
| Dispatch TTS / deduplikasi | **PASS pada Web Speech test double terpisah**: aktivasi + 4 pengumuman CALL/RECALL dalam `id-ID`; refresh saat masih DIPANGGIL tidak membacakan ulang audit yang sama |
| TTS native Edge headless | Hanya 3 voice `en-US`; **tidak ada `id-ID`**. Aplikasi mempertahankan audio nonaktif dan fallback visual. Suara Indonesia yang terdengar dari speaker **belum diverifikasi** |
| Android runtime | **Belum diuji**: `flutter devices`/ADB tidak menemukan perangkat dan `flutter emulators` tidak menemukan emulator. Build APK tidak dianggap bukti runtime fisik |

SDK lokal: Flutter 3.47.5 / Dart 3.13.4; browser Edge 155.0.4283.45. Screenshot dan ringkasan JSON run final ada di `apps/client/build/web/demo-*`, diabaikan Git. Browser uji menggunakan kontrol, scroll dan keyboard Flutter yang nyata; API dan clock tidak di-mock. Hanya mesin Web Speech untuk verifikasi dispatch memakai test double, pada halaman terpisah dari probe native.

## Keamanan data pengujian

Runner `node apps/client/tool/run-live.cjs --demo-browser` memvalidasi `127.0.0.1:5433/capstone_antrean_test` pada PostgreSQL dan provider Prisma sebelum fixture. Akun/perangkat bootstrap unik; master tambahan dibuat lewat UI pada poli fixture. Cleanup mencakup dokter tambahan milik run tersebut dan seluruh relasi/tiket/audit fixture, tanpa reset atau migration. Video QR sementara dihapus setelah browser ditutup; kredensial tidak ditulis ke Git/log.

Fingerprint 16 tabel run final: **13 record existing, 0 hilang, 0 berubah, 0 record baru tersisa**. Percobaan pada perangkat/media sibuk sempat menghasilkan timeout transaksi baca; run final berurutan setelah build selesai berhasil tanpa perubahan backend.

## Berkas dan kesiapan demo

- `lib/src/config.dart`, `patient.dart`, `display.dart`: dua perbaikan di atas.
- `test/ui_test.dart`: regresi kalender, kegagalan aktivasi, bahasa tidak tersedia dan kegagalan TTS asinkron.
- `tool/browser-demo.cjs`, `browser-smoke.cjs`, `run-live.cjs`, `package*.json`: skenario UI lengkap, fixture video QR, probe kamera/TTS, timeout pengujian dan cleanup. Dependency QR hanya tooling QA; tidak ada aplikasi JavaScript baru.
- `apps/client/README.md`, dokumen ini dan [DEMO_FLUTTER.md](DEMO_FLUTTER.md): panduan demo dan batas verifikasi.

**Web siap untuk demonstrasi alur visual end-to-end.** Untuk demo bersuara gunakan browser/perangkat dengan voice Indonesia dan cek speaker sebelum presentasi. APK debug tersedia untuk dipasang; host API harus disesuaikan untuk telepon fisik sesuai panduan, lalu lakukan smoke runtime pada perangkat tersebut.

Pekerjaan React/Vite lokal, perubahan root terkaitnya, backup, schema review dan file SQL tetap dipertahankan serta dikecualikan dari commit. Tidak ada auto-merge.
