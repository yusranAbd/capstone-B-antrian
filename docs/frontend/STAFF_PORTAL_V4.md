# Portal PETUGAS V4

Workbench operasional mengikuti referensi yang disetujui: header satu baris dengan pemilih ruang penugasan dan akses langsung ke profil; dokter terjadwal; daftar pasien terpadu dominan di kiri; panel pelayanan navy di kanan; pemindai QR otomatis dibuka melalui FloatingActionButton.extended di kanan bawah. Statistik atas, informasi header berulang, panel Tiket diterima/dilewati dan formulir UUID pemulihan tidak dirender. Desain role lain dipertahankan.

## Sumber data dan perilaku

- Penugasan dan pilihan ruang: GET /penugasan-petugas existing. Refresh mempertahankan ruang pilihan bila masih sah.
- Dokter: GET /jadwal-praktik existing berdasarkan layanan/tanggal, disaring lagi terhadap loket dan tanggal snapshot. Nama, spesialisasi, foto dan jam berasal dari response. Semua sesi relevan dapat dibaca pada panel yang terbatas tingginya. Foto memakai ProfessionalDoctorAvatar existing dengan decoding/cache bounded dan fallback. Tidak ada klaim kehadiran aktual.
- Daftar: field daftarPasien pada GET /queue/snapshot, bukan cache event SKIP. MENUNGGU mempertahankan ranking server; SKIP/CHECK_IN ditambahkan untuk tindak lanjut. Nama adalah identitas minimal dari pemilik tiket, tanpa usia/jenis kelamin/keluhan rekaan.
- Tabel memakai lima row per halaman lokal dan pencarian nomor/nama pada data dimuat. Backend mempertahankan 100 row menunggu legacy dan 100 tindak lanjut per batch. Kontrol batch tindak lanjut hanya muncul jika diperlukan; batch di luar 100 pertama tetap dapat dipulihkan tanpa UUID. Filter dipertahankan saat refresh/tindakan; REQUEUE memperbarui row berdasarkan ID dan hasil REST, tanpa duplikasi.
- Aksi menu sesuai status/flag: Detail tiket; Kembalikan ke Antrean pada DILEWATI loket asal; Masuk Antrean pada CHECK_IN yang relevan. CALL memilih server, tidak memilih row yang difilter. Semua endpoint transisi existing tetap digunakan.
- QR kamera dan deduplikasi frame existing dipertahankan. Tombol mengambang Pindai QR membuka dialog kamera dan hanya memanggil POST /check-in/auto-antrean. Panel bawah dan input payload manual dihapus sesuai revisi 28 Oktober 2026. CHECK_IN legacy tetap dapat dipulihkan dari row; tidak ada tahap ENQUEUE kedua untuk QR baru. Hasil scan tetap tampil dalam dialog. Lihat [QA FAB pemindai](STAFF_SCAN_FAB.md).
- Realtime /queue, join layanan, invalidasi dan reconnect tetap memicu snapshot. Polling/resume/disposal existing dipertahankan. Hasil jadwal terlambat tidak dapat mengganti ruang baru. Penolakan 401/403 mengosongkan cache nama pasien, jadwal dan hasil scan; gangguan jaringan tidak mengarang keberhasilan tindakan.

## Backend minimum

Proyeksi nama/check-in/status baru hanya pada snapshot PETUGAS yang terotorisasi, dalam transaksi baca existing; Cache-Control no-store. Tambahan query halaman baca bersifat opsional dan additive. Foto nullable ditambahkan pada metadata dokter GET jadwal existing. Tidak ada perubahan Queue Engine, state machine, kapasitas, slot/FIFO, Socket.IO payload, Public Display, schema atau migration. Lihat [kontrak API final](../backend/API_INTEGRATION_GUIDE.md#portal-petugas-v4--proyeksi-operasional-aditif).

## Bukti QA

Validasi source final pada 27 Oktober 2026:

| Pemeriksaan | Hasil |
|---|---|
| Backend unit | 679 PASS, 46 suite |
| Seluruh backend E2E | 386 PASS, 31 suite |
| Integritas database test | 13 record baseline identik; 0 hilang, berubah, atau fixture tersisa |
| NestJS typecheck, lint, build | PASS |
| Dart format / Flutter analyze | PASS; 82 file format tidak berubah, 0 issue |
| Seluruh Flutter test | 369 PASS, 1 live integration opsional SKIP karena fixture live tidak diberikan |
| Regresi khusus V4 | 14 PASS, termasuk pagination >100, pencabutan akses, lifecycle dan respons jadwal terlambat |
| Flutter Web release | PASS (JavaScript); dry-run WASM masih melaporkan keterbatasan dependency existing |
| Chrome release + Socket.IO | PASS pada keenam viewport; 8 skenario, 0 page error |

 Runner Chrome berada di apps/client/tool/browser-staff-v4.cjs; memakai release Flutter nyata, HTTP fixture sintetis, serta server/client Socket.IO nyata pada loopback. Bukan login akun development dan bukan pengganti uji backend NestJS/database.

Backend NestJS diuji melalui seluruh E2E di **127.0.0.1:5433/capstone_antrean_test** dengan validasi target, fingerprint seluruh baseline sebelum/sesudah, dan cleanup hanya fixture test milik suite. Cakupan termasuk QR otomatis, CALL/RECALL/SKIP/REQUEUE/START/COMPLETE, scope antarrole/poliklinik, Hospital/hibrida, Public Display dan monitoring dokter. Kamera/perangkat fisik tidak diuji; unit scanner menguji frame QR, deduplikasi dan lifecycle. Jangan mengklaim pemindaian kamera fisik dari fixture Chrome.

Chrome menilai keenam viewport: 1366x768, 1440x900, 1920x1080, 768x1024, 375x812, 390x844. Desktop dengan tiga pasien memperlihatkan seluruh kontrol utama dan tanpa scroll halaman (juga diukur dari scroll extent Flutter). Mobile memakai scroll vertikal agar semua aksi tetap dapat diakses; daftar dan panel multi-jadwal memakai area scroll/pagination terbatas. Tidak ada horizontal overflow.

Baseline Chrome memakai artefak release V3 existing; source PETUGAS pada artefak itu sama dengan baseline main sebelum pekerjaan ini. Screenshot setelahnya berasal dari build V4 final. Seluruh nama/data pada bukti merupakan fixture sintetis. Capture widget tambahan digunakan untuk regresi, bukan diklaim browser/perangkat fisik.

- [Sebelum desktop](images/staff-v4/before-1366x768.png) · [Sebelum mobile](images/staff-v4/before-390x844.png)
- [Sesudah desktop](images/staff-v4/after-1366x768.png) · [Sesudah tablet](images/staff-v4/after-768x1024.png) · [Sesudah mobile](images/staff-v4/after-390x844.png)
- [JSON hasil Chrome](staff-v4-browser-qa.json)

Seluruh file lokal/backup pengguna tetap di checkout utama; implementasi dibuat di branch terisolasi. Setelah PR di-merge, checkout yang menjalankan Flutter/API perlu disinkronkan dan proses direstart. Server pengguna localhost:5173 tidak diganti oleh runner QA.

## File perubahan

- Flutter produksi: apps/client/lib/src/app.dart, queue.dart, staff_ui.dart, staff_v4.dart.
- Flutter regresi: apps/client/test/staff_v4_test.dart, staff_dashboard_v3_test.dart, ui_test.dart, one_scan_qr_test.dart, login_ui_test.dart, session_test.dart.
- Backend produksi: apps/api/src/queue/queue-operational-snapshot.ts, queue-snapshot.types.ts, queue.controller.ts, queue.service.ts; apps/api/src/jadwal-praktik/jadwal-praktik.service.ts.
- Backend regresi: apps/api/src/queue/queue-operational-snapshot.spec.ts, queue.snapshot.spec.ts; apps/api/test/queue-snapshot.e2e-spec.ts.
- QA/dokumentasi: apps/client/tool/browser-staff-v4.cjs, docs/backend/API_INTEGRATION_GUIDE.md, dokumen ini, staff-v4-browser-qa.json dan lima screenshot dalam images/staff-v4/.

## Menjalankan ulang Chrome QA

Dari root repository, gunakan dependensi QA existing di apps/client/tool (npm ci --prefix apps/client/tool) dan dependensi API (socket.io). Build release terlebih dahulu dengan API_BASE_URL=http://localhost:3000/api/v1 dan SERVICE_TIME_ZONE=Asia/Jakarta. Runner menyesuaikan alamat API pada response JavaScript yang disajikan oleh server fixture; tidak menulis ulang build di disk.

Pada PowerShell, tetapkan NODE_PATH ke direktori absolut apps/client/tool/node_modules dan apps/api/node_modules, dipisahkan titik koma. Tetapkan QUEUEB_CANVASKIT_DIR ke direktori bin/cache/flutter_web_sdk/canvaskit milik Flutter SDK dan QUEUEB_ROBOTO_FILE ke bin/cache/artifacts/material_fonts/roboto-regular.ttf. Chrome harus tersedia.

```powershell
node -e "require('./apps/client/tool/browser-staff-v4.cjs')({build:'apps/client/build/web',output:'tmp/staff-v4-browser',engineRoot:process.env.QUEUEB_CANVASKIT_DIR,fontFile:process.env.QUEUEB_ROBOTO_FILE}).then(r=>console.log(JSON.stringify(r))).catch(e=>{console.error(e.message);process.exitCode=1})"
```

Runner memakai port loopback dinamis dan menutup browser/server setelah selesai. File output gagal harus ditinjau sebelum dibagikan. Mode baseline=true hanya untuk capture V3, bukan bukti acceptance V4.
