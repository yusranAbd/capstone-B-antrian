# Portal PETUGAS V3

## Ruang lingkup

Redesign Flutter Web khusus PETUGAS, dari baseline `fa7a065` (main setelah PR #60).
Backend, database, JWT/RBAC, Queue Engine, namespace Socket.IO, dan UI role lain
tidak diubah. Tidak ada dependency, endpoint, atau migration baru.

## Perubahan tampilan

- Header 60 px: branding, identitas petugas, ruang/poli, realtime, profil dan logout.
- Ringkasan compact: total menunggu dari `menunggu.total`, tiket aktif ruang terpilih
  dari `loket[].tiketAktif`, serta indikator selesai dengan nilai `—` yang diberi
  keterangan karena kontrak snapshot tidak menyediakan agregat selesai.
- Desktop memakai kolom 60/40: daftar antrean dan panel pelayanan. Check-In dan
  tiket diterima/dilewati berada tepat di bawahnya. Layar sempit memakai satu kolom.
- Daftar menunggu memiliki scroll sendiri dan pencarian nomor lokal yang hanya
  menyembunyikan baris. Urutan, jenis, slot dan kelayakan tetap berasal dari server.
- Nomor aktif dan aksi mengikuti status aktual. CHECK_IN tetap terpisah dari ENQUEUE;
  tiket hasil Check-In dapat dimasukkan langsung tanpa mengetik UUID.
- Receipt sementara tetap tersedia untuk CHECK_IN/SKIP. Bagian “Pemulihan ID tiket”
  dapat dibuka setelah reload; validasi UUID dan pemeriksaan backend tetap berlaku.
- Tombol dikunci selama operasi, indikator proses dan pesan hasil tetap tersedia.
  Tidak ada transisi optimistis. Snapshot REST tetap menjadi sumber kebenaran.

## Batas kontrak existing

Snapshot menunggu dapat memuat sebagian tiket saja. Total dan jumlah baris yang
terlihat sengaja dibedakan. API tidak menyediakan riwayat receipt persisten atau
total selesai untuk halaman ini. Reload/pindah ruang mengosongkan receipt sementara;
pemulihan memerlukan ID tiket sah. Tidak ada data pribadi pasien yang ditambahkan.
Pada Web, kredensial bearer tetap hanya berada di memori sesuai implementasi
existing. Reload memerlukan login kembali sebelum pemulihan tiket; redesign ini
tidak menambahkan penyimpanan token di browser.

## Reproduksi QA

```powershell
cd apps/client
dart format --output=none --set-exit-if-changed lib/src/app.dart lib/src/queue.dart lib/src/staff_ui.dart test/staff_dashboard_v3_test.dart
flutter analyze --no-pub
flutter test --no-pub
flutter build web --release --no-pub --no-wasm-dry-run --dart-define=API_BASE_URL=http://127.0.0.1:3001/api/v1
cd ../..
node apps/client/tool/run-live.cjs --staff-v3
```

Runner memvalidasi database aktual `127.0.0.1:5433/capstone_antrean_test`, menjalankan
NestJS pada port 3001, dan memeriksa URL API dalam build Web sebelum membuka browser.
Hanya fixture unik milik run yang dibersihkan; ID dan hash record existing pada
16 tabel dibandingkan sebelum/sesudah. Tidak menyentuh database development.

Kamera diuji dengan video QR sintetis di browser dan penolakan izin kamera.
Ini bukan pengujian kamera fisik. Jam slot dan prioritas panggil memakai aturan
backend asli, tanpa pemalsuan waktu atau REST stub.

## Screenshot

- [Sebelum, 1366×768](images/staff-v3/00-sebelum-1366.png)
- [Sesudah, 1366×768](images/staff-v3/01-dashboard-1366.png)
- [Sesudah, 1440×900](images/staff-v3/02-dashboard-1440.png)
- [Sesudah, 1920×1080](images/staff-v3/03-dashboard-1920.png)
- [Check-In dan receipt](images/staff-v3/04-check-in.png)
- [Antrean aktif](images/staff-v3/05-antrean-aktif.png)
- [Pelayanan selesai / kosong](images/staff-v3/06-selesai-kosong.png)
- [Tablet](images/staff-v3/07-tablet.png)

## Hasil validasi Flutter

- `dart format`: empat file Dart terkait sudah terformat.
- `flutter analyze --no-pub`: PASS, tidak ada issue.
- `flutter test --no-pub`: 276 PASS, satu tes live opt-in dilewati.
  Termasuk regresi ADMIN, DOKTER, USER, Public Display, login/logout dan sesi.
- Delapan tes PETUGAS V3 memeriksa viewport desktop, urutan/kelayakan server,
  pencarian dan semantics, loading/conflict di desktop dan 320/375 px, serta
  pemulihan UUID tanpa mutasi untuk ID tidak valid.
- `flutter build web --release --no-pub --no-wasm-dry-run` dengan URL API test: PASS.

## Hasil QA browser nyata

`node apps/client/tool/run-live.cjs --staff-v3`: PASS.

- Memilih ruang sesuai penugasan; kamera mendekode QR walk-in, lalu Check-In dan
  ENQUEUE dilakukan terpisah untuk walk-in serta appointment.
- CALL memilih appointment pada slot yang sudah dimulai. RECALL, SKIP, pemulihan
  REQUEUE setelah reload/login ulang, START dan COMPLETE lulus. Kedua tiket SELESAI.
- 13 event `/queue` diterima. RECALL eksternal memicu pengambilan snapshot tanpa
  mutasi UI. Transport fixture diputus, status reconnect dan refresh REST pulih.
- Kamera ditolak menampilkan fallback tempel QR; logout kembali ke halaman login.
- Screenshot desktop 1366×768, 1440×900, 1920×1080 dan tablet 768×1024 ditinjau.
  Layout 320/375/414/768 px juga diperiksa dengan browser dan regresi widget.
- Tidak ada error runtime browser.
- Integritas test: 13 record existing identik, nol record hilang/berubah,
  nol fixture tersisa. Database development tidak dipakai untuk QA.

Runner existing mengeluarkan peringatan deprecation `pg` saat persiapan fixture;
ini tidak menggagalkan tes dan tidak menjadi alasan mengubah backend pada task UI.

## Berkas perubahan

- `apps/client/lib/src/queue.dart`: susunan dashboard dan presentasi loading operasi.
- `apps/client/lib/src/staff_ui.dart`: tema dan komponen visual khusus PETUGAS.
- `apps/client/lib/src/app.dart`: memasang header khusus PETUGAS dengan callback
  profil/logout existing; cabang role lain dipertahankan.
- `apps/client/test/staff_dashboard_v3_test.dart`: delapan tes regresi tambahan.
- `apps/client/tool/browser-staff-v3.cjs`: QA browser terisolasi dan screenshot.
- `apps/client/tool/browser-demo.cjs`: mengekspor generator video QR existing.
- `apps/client/tool/browser-smoke.cjs`, `apps/client/tool/run-live.cjs`: opt-in runner
  PETUGAS V3 dan pemutusan transport khusus fixture untuk tes reconnect.
- Dokumen ini dan delapan screenshot di `docs/frontend/images/staff-v3/`.

Seluruh 51 file lokal pengguna yang dicatat sebelum pekerjaan tetap dipertahankan;
perubahan tersebut tidak disertakan dalam commit redesign.
