# Public Display Monitor V3

Satu monitor untuk satu poliklinik. Baseline `ba44b38` mencakup PR #67; aset WebP, tema cached, pemisahan clock dari snapshot, dan pelepasan resource TTS tetap dipertahankan. Tidak ada perubahan pairing, autentikasi, Queue Engine, database atau migration.

## Tampilan

- Header branding QueueB, poliklinik, tanggal/jam dan koneksi.
- Panggilan aktif menjadi fokus: nomor besar, nama sesuai kebijakan server, poliklinik dan ruang/loket.
- Daftar menunggu mengikuti urutan snapshot, total sebenarnya, kapasitas baris adaptif dan indikator sisa. Tidak ada permukaan scroll.
- Ringkasan ruang memakai strip kartu; jika terlalu banyak, berpindah halaman otomatis setiap 12 detik. Tidak ada timer rebuild jika hanya satu halaman.
- Footer pengumuman, status audio, aktivasi suara, fullscreen, refresh dan ganti perangkat tetap tersedia. Loading, data kosong, reconnect dan akses ditolak dibedakan.
- Monitor 1280×720, 1366×768 dan 1920×1080 memakai tinggi/lebar viewport. Lebar di bawah 900 atau tinggi di bawah 500 menjadi pratinjau monitor 16:9 berskala, bukan layout ponsel untuk penggunaan TV.

## Privasi dan TTS

Detail kontrak dan konfigurasi berada di [Bagian 25 panduan API](../backend/API_INTEGRATION_GUIDE.md#25-public-display-monitor-v3-v16). Nama lengkap hanya diberikan oleh server dengan dua konfigurasi eksplisit; default disamarkan, tersedia juga tanpa nama. Browser tidak memiliki sakelar untuk membuka nama lengkap. Tidak ada field identitas/medis tambahan atau token pada URL/log.

Teks layar identik dengan TTS: `Panggilan nomor antrean A, nol nol dua atas nama Yusran A., silakan menuju ke Poliklinik Anak, terima kasih.` Nomor tiket tetap A-002 pada kartu. Tidak ada chime pada baseline; TTS platform existing dipertahankan. Suara memerlukan interaksi pengguna dan engine id-ID. Jika tidak tersedia, pengumuman visual tetap berfungsi. CALL/RECALL memakai `peristiwaId`; reconnect, refresh, render ulang dan tick jam tidak memutar ulang ucapan.

## Validasi

Hasil lokal 26 Oktober 2026:

| Pemeriksaan | Hasil |
|---|---|
| Backend unit | 669 PASS, 44 suite |
| E2E snapshot/socket/pairing | 22 PASS |
| E2E selector/hibrida/snapshot/broadcast/QR/booking/reservasi | 126 PASS |
| Flutter seluruh role | 347 PASS, 1 live fixture opsional SKIP |
| Flutter analyze dan format | PASS, tanpa issue/perubahan format |
| Backend lint, type check, NestJS build | PASS |
| Flutter Web release | PASS |

Baseline database test pada kedua kelompok E2E: 13 record awal, 0 berubah/hilang, 0 fixture tersisa. Build Web JavaScript berhasil; dry-run WASM tetap memperingatkan interop pada dependency flutter_tts/socket_io_common existing. Tidak mengklaim dukungan build WASM baru.

 Fixture gambar/test adalah **data sintetis QA**, bukan pasien sebenarnya. Gambar dirender langsung oleh Flutter menggunakan font Roboto dan MaterialIcons; bukan hasil generatif.

- Tes layout: nol/satu/30 menunggu di ketiga resolusi, nama panjang, no Scrollable/no overflow, status START/COMPLETE dan room paging.
- Regresi pairing/token dicabut, audio tidak tersedia/error, deduplikasi CALL/RECALL dan reconnect.
- E2E memakai `127.0.0.1:5433/capstone_antrean_test`, baseline 13 record; hanya fixture unik milik tes yang dibersihkan. Tidak ada koneksi DB development untuk penulisan.
- Pembatalan DIPESAN existing tidak memengaruhi daftar MENUNGGU. Tidak ditambah aturan bisnis pembatalan baru.

### Reproduksi

```powershell
cd apps/client
flutter analyze
dart format --output=none --set-exit-if-changed .
flutter test
flutter build web --release
# Screenshot opsional dari fixture widget:
$env:QUEUEB_CAPTURE_DIR='<folder output absolut>'
$env:QUEUEB_FONT_DIR='<Flutter SDK>/bin/cache/artifacts/material_fonts'
flutter test test/display_v3_test.dart
```

Unit backend: `npm test -- --runInBand`, lint `npm run lint`, type check `npx tsc --noEmit`, build `npm run build`. E2E Display/snapshot/pairing serta selector/QR/booking memakai runner `test/run-admin-delete.cjs` setelah target database test divalidasi. Jangan menunjuk runner E2E ke development/production.

### Sebelum

![Public Display V2](images/public-display-v2-720p.png)

### Sesudah (fixture QA)

![Monitor V3 1366×768](images/public-display-v3/monitor-1366x768.png)

![Monitor V3 1920×1080](images/public-display-v3/monitor-1920x1080.png)

## Pemasangan dan batas verifikasi

Deploy backend dan Web dari commit yang sama agar nama/list tersedia. Setelah pairing, klik Aktifkan Suara lalu Layar Penuh; fullscreen mengikuti dukungan browser/platform. Jangan menggunakan query token. Konfigurasi nama server adalah keputusan fasilitas, tidak diaktifkan otomatis pada development/production oleh PR ini.

Pengujian otomatis audio memakai engine/mock platform: tersedianya suara id-ID dan bunyi dari speaker TV fisik tetap harus dicek saat pemasangan. Socket.IO tetap best effort dengan REST polling 15 detik; multi-instance memerlukan infrastruktur distribusi existing yang sesuai. Tidak ada klaim uji speaker atau monitor fisik.
