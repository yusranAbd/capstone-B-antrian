# flutter_animate — pilot micro-interactions PASIEN

## 1. Executive summary

Pilot terarah pada Portal PASIEN, berdasarkan panduan UI QueueB. Tidak mengubah struktur UI, theme, typography, business logic, BLoC/repository, QueueApi/SessionStore, go_router, API/RBAC/Queue Engine, schema atau data development. `responsive_framework` masih ditunda dan tidak termasuk scope.

Baseline Git: `89d64a06dde013fd3fb5839747adc9d24a81f2ca`, main sinkron saat preflight. Empat file historis, R0/setup, backup dan untracked lama dipertahankan. Git mengikuti otorisasi direct-to-main setelah semua gate lokal lulus; hasil commit/push dan CI untuk SHA final dilaporkan pada penyerahan.

## 2. Dependency

Direct pin `flutter_animate: 4.5.2`; pub get berhasil. Hanya satu transitive baru: `flutter_shaders 0.1.5`. go_router 18.1.1, intl 0.20.3 dan seluruh dependency existing tetap. SDK lokal tetap Flutter 3.47.5/Dart 3.13.4; tanpa override, pub upgrade massal, library animasi tambahan atau perubahan tooling Android/Gradle/Kotlin/Java/TTS.

API diperiksa melalui source package terpasang dan [dokumentasi flutter_animate 4.5.2](https://pub.dev/packages/flutter_animate/versions/4.5.2). flutter_shaders merupakan transitive; pilot tidak memakai ShaderEffect, blur, shimmer, repeat atau animasi halaman global.

## 3. Lokasi penerapan

- `lib/src/patient.dart`: notice sukses pada header Tiket Saya, tujuan existing setelah `booking.submit` dikonfirmasi. MobileNotice/SelectableText, isi pesan, status, rekonsiliasi dan navigasi existing dipertahankan.
- `lib/src/patient.dart`: label Tanggal praktik pada panel pilihan jadwal. Input, kalender, slot, tombol dan PopScope tidak dibungkus animasi.
- `lib/src/patient_motion.dart`: helper khusus pasien dengan token presentasi sekali pakai; bukan auth/state manager atau service navigasi.

## 4. Alasan pemilihan dan audit ringkas

PatientScrollShell sudah memakai AnimationController native 220ms/180ms untuk chrome scroll dengan reduced-motion handling. ReservationList juga memiliki scroll-to-top 180ms ketika notice berubah. TabBar/TabBarView Home dan navigasi Material existing dipertahankan; tidak mengganti atau menumpuk animasi pada komponen tersebut. Pencarian terarah pada patient*.dart tidak menemukan AnimatedContainer/Opacity/Switcher/Size/TweenAnimationBuilder tambahan pada dua elemen pilot.

Notice sukses dipilih karena sudah ada dan hanya ditetapkan setelah hasil submit sah. Label tanggal merupakan teks pendukung non-interaktif; animasinya tidak memindahkan input atau menunda konfirmasi.

## 5. Efek dan durasi

Kedua elemen memakai fade 0,88→1 dan translasi vertikal 3→0 logical pixels secara paralel, 200ms, Curves.easeOut. Tidak looping. Opacity awal tidak nol agar informasi tetap terlihat; kontras komposit teks/notice pada paper dan background diuji minimal 4,5:1. Margin/spacing, ukuran layout, warna token dan target sentuh existing tidak berubah.

## 6. Accessibility/reduced motion

`MediaQuery.disableAnimationsOf(context)` mengembalikan child langsung, tanpa Animate/controller dan tanpa menunda informasi. Preferensi yang berubah saat playback juga menghentikan motion; mengaktifkannya lagi tidak memutar event lama. Tidak ada ExcludeSemantics atau label yang dihapus. SelectableText existing tetap tersedia. Tes mencakup semantics, fokus dan input serta empat ukuran mobile/empat desktop dengan text scale 1,5. Ini tidak menggantikan verifikasi screen reader/perangkat fisik.

## 7. Lifecycle dan state/navigation safety

PatientMotionOnce hanya menyimpan bool consumed, tanpa ID, nomor tiket, payload QR atau data pasien. Key Animate adalah identitas objek token tersebut, bukan ID pasien. Token sukses dibuat hanya setelah submit berhasil dan pemeriksaan mounted/repository.active existing; snapshot/rebuild biasa tidak membuat token baru. Teks pembatalan/error tidak memakai entrance sukses.

TickerMode.valuesOf(context).enabled menunda konsumsi event pada branch offstage. Jika meninggalkan branch saat motion, visual diselesaikan langsung; remount/tab return memakai event consumed sehingga tidak replay. Label memakai token per flow booking; perubahan pilihan/draft tidak dibuat ulang oleh motion.

Tidak ada controller manual/onPlay/onComplete/listen callback yang memanggil API/navigasi. Controller internal library ditutup saat Animate unmount. Tidak mengubah provider keys, repository/feed, Cubit, route, busy guard atau retry. Tes menghitung owner dan request sebelum/sesudah rebuild; satu explicit booking tetap satu POST.

## 8. Test coverage dan hasil

25 tes pilot mencakup timing finite/rebuild, remount, reduced motion dan semantics, offstage, disposal, new event, kontras, delapan viewport/input focus, success pending→confirmed, failure/timeout, no duplicate POST/owner, tab switch, logout saat motion, session eviction sebelum respons, draft dan native Back policy melalui widget binding. Dua tes tambahan membandingkan label/value/hint semantics MobileNotice asli dengan versi beranimasi pada pertengahan/akhir playback dan reduced motion; nilainya tetap sama dengan baseline.

Test clock mem-flush zero-delay autoplay library dengan `pump(Duration.zero)` sebelum mengukur 200ms; tidak menambahkan delay runtime. SemanticsHandle test ditutup eksplisit. Analyze awal mengidentifikasi API TickerMode.of deprecated dan tiga kondisi test tanpa braces; diperbaiki, tanpa mematikan lint/assertion.

| Gate lokal | Hasil aktual |
| --- | --- |
| `flutter pub get` | PASS; dua package baru, pin lama tetap |
| Format tiga file Dart terkait | PASS |
| `flutter analyze` | PASS, tanpa issue (run final 76,3 detik) |
| Tes pilot | 25 PASS (13 detik) |
| `flutter test` lengkap | 1.116 PASS, 1 live-fixture SKIP pada perintah standar (5 menit 50 detik) |
| Web release | PASS (153,1 detik) |
| APK debug, entrypoint `lib/main.dart` | PASS (127,7 detik) |

Tes lengkap mencakup regresi Home V6, lima tab, booking/reservasi/QR, routing dan kebijakan Back existing. Tes pilot menambahkan pemeriksaan Back melalui widget binding; emulator/perangkat Android tidak dijalankan ulang dalam pilot ini. Build tetap mengeluarkan peringatan existing Wasm/plugin dan migrasi Built-in Kotlin; tidak mengubah SDK/plugin/toolchain untuk menutup peringatan tersebut.

## 9. Build size comparison

Baseline historis dalam brief tidak dipakai sebagai pembanding utama. Web release dan APK debug main.dart dibangun ulang sebelum pubspec/source diubah, lalu setelah perubahan dengan SDK/mode/defines identik: API_BASE_URL=http://127.0.0.1:3001/api/v1, SERVICE_TIME_ZONE=Asia/Jakarta. Build lokal menyertakan perubahan dokter historis yang dilindungi pada kedua sisi; file itu tidak ikut commit pilot.

| Ukuran (byte) | Sebelum | Sesudah | Selisih |
| --- | ---: | ---: | ---: |
| Direktori output Web release | 51.222.340 | 51.230.272 | +7.932 |
| `main.dart.js` | 5.505.157 | 5.511.454 | +6.297 |
| APK debug `main.dart` | 259.043.720 | 259.596.141 | +552.421 |

Source produksi `lib/` bertambah dari 110 menjadi 111 file, 26.861 menjadi 26.959 baris setelah normalisasi LF: dua file produksi terdampak, +98 LOC bersih. Tes/harness/dokumentasi dicatat terpisah dari LOC produksi. Ukuran direktori Web memakai seluruh isi direktori dengan metode sama pada kedua sisi; screenshot pilot disimpan di luar `build/web`. Selisih mencakup implementasi pilot dan dependency/assets hasil build, bukan estimasi ukuran library saja.

Tidak mengklaim zero overhead, peningkatan FPS atau memori; tidak melakukan profiling FPS/RAM aplikasi atau benchmark kompleks.

## 10. Risiko dan batas pengujian

Smoke Chrome headless dengan NestJS/PostgreSQL/Socket.IO nyata PASS pada dua context berurutan: normal dan reduced motion, masing-masing viewport 390×844. Keduanya memverifikasi login, pemilihan poli/walk-in, tidak ada POST reservasi sebelum konfirmasi, respons booking 201/status DIPESAN, tombol tiket/QR tetap tersedia, lima tab, guard logout `login?from=/patient/profile`, satu POST booking dan nol POST QR. Satu koneksi Socket.IO per context tetap satu sepanjang flow dan ditutup saat logout; nol pageerror/HTTP5xx. QR tidak diterbitkan oleh smoke ini; regresi QR existing tercakup tes Flutter lengkap.

Screenshot kedua mode diperiksa: notice sukses terbaca, status/tiket dan lima tab tetap terlihat, tanpa clipping teks. Tidak memakai screenshot untuk mengklaim peningkatan FPS atau pembacaan screen reader. Pada engine Web lokal, SelectableText yang belum fokus muncul sebagai textarea disabled dengan value DOM kosong meskipun teks tampil pada canvas. Harness memeriksa permukaannya dan mengambil screenshot untuk review teks; kesetaraan label/value/hint semantics komponen asli dibuktikan di tes Flutter. Pembacaan screen reader browser/perangkat fisik tetap belum diverifikasi.

Sembilan percobaan awal harness belum lulus, meliputi readiness engine, label Email yang berubah saat fokus, kapitalisasi label tiket, representasi DOM SelectableText, dan expected URL logout yang belum memasukkan parameter guard. Investigasi memakai probe tanpa login, source engine/helper existing dan screenshot; tidak mengubah source autentikasi/router/backend atau menghapus assertion transaksi. Semua percobaan tetap diverifikasi cleanup dan fingerprint. Run final memakai helper input existing, readiness engine terpisah, pemeriksaan screenshot/semantics yang sesuai levelnya, dan expected URL sesuai guard existing.

Tidak mengulang seluruh backend destructive E2E untuk perubahan presentasi ini. Fixture HTTP widget palsu tidak menyentuh DB. Smoke memakai harness existing yang memvalidasi target PostgreSQL `127.0.0.1:5433/capstone_antrean_test`, fixture unik dan cleanup. Pada setiap percobaan/final, 13 record domain existing tidak hilang/berubah dan nol fixture tersisa. Fingerprint read-only 17 tabel per database (`capstone_antrean` dan `capstone_antrean_test`) identik sebelum/sesudah dan antar-run; development tidak dipakai mutasi. Ledger final tidak mengandung HTTP5xx/P2028 dan pendingAtFinish=0. Mode `--patient-motion --browser` menjalankan flow terarah; strict ledger juga menjadi gate exit runner ketika diagnostics diaktifkan.

## 11. Rekomendasi

Pertimbangkan hanya feedback non-kritis sejenis setelah evaluasi pilot/manual. Tidak mengaktifkan motion pada ADMIN/PETUGAS/DOKTER/Public Display dalam tugas ini. Nomor antrean, QR, snapshot realtime, indikator error dan TTS bukan sasaran rollout otomatis. Tidak ada roadmap redesign seluruh UI; responsive_framework tetap ditunda.

File stage dibatasi pada dependency/lockfile, dua file produksi pasien, tes pilot, tiga file harness terkait dan laporan ini. Fingerprint SHA-256 empat file historis serta dokumen setup/R0 yang sudah ada diperiksa kembali; tidak ikut commit. Bukti lokal tersanitasi tersimpan di `apps/client/build/animate-pilot` (diabaikan Git), termasuk log analyze/tes/build, ukuran sebelum/sesudah, summary browser dan hasil cleanup/fingerprint; `protected-before.json` dan `protected-after.json` menyimpan fingerprint lengkap enam file tersebut. APK juga diperiksa memiliki kernel entrypoint main.dart dan pilot, tanpa entrypoint integration test. Screenshot tidak ikut commit.
