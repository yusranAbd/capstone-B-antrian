# PETUGAS — tombol pindai QR mengambang

Revisi 28 Oktober 2026 menghapus panel QR Check-in Otomatis di bawah dashboard beserta input payload manual. Akses kamera memakai `Scaffold.floatingActionButton` dan `FloatingActionButton.extended` berlabel **Pindai QR**, di kanan bawah. Dialog kamera, validasi QR, deduplikasi frame dan POST `/check-in/auto-antrean` tetap existing. Keberhasilan hanya ditampilkan setelah server mengembalikan MENUNGGU; snapshot dimuat ulang setelah tindakan.

Tombol tidak muncul tanpa penugasan aktif, dan tidak bisa ditekan saat memuat/memproses atau saat snapshot belum tersedia/akses ditolak. Daftar mempunyai padding bawah 88 logical px agar bagian terakhir dapat digulir melewati tombol; ruang yang tadinya dipakai panel QR dialokasikan kembali ke daftar dan pelayanan. Hasil scan tetap terlihat dalam dialog. Penolakan kamera memberikan petunjuk izin kamera dan membuka ulang pemindai, tanpa mengarahkan pengguna ke input manual yang sudah dihapus.

Tidak ada perubahan API, autentikasi, RBAC, Queue Engine, database, migration, atau portal role lain.

## Validasi

- Dart format dan Flutter analyze: PASS, 0 issue.
- Regresi PETUGAS/scanner/UI: 67 PASS.
- Seluruh Flutter test: 516 PASS, 1 tes live opsional SKIP tanpa fixture live.
- Widget responsive: 1280×640, 1280×720, 1366×768, 1440×900, 1920×1080, 768×1024, 320×740, 375×812, 414×896; tanpa RenderFlex overflow.
- Regresi mencakup FAB membuka/menutup/membuka ulang pemindai, input manual tidak dirender, QR tidak valid tidak mengirim request, callback scan mengirim satu operasi check-in+enqueue dan memperbarui snapshot, deduplikasi frame, kegagalan/offline, serta CALL/RECALL/SKIP/REQUEUE/START/COMPLETE, pagination dan pergantian ruang.

Unit integrasi callback bukan bukti kamera fisik. Kamera Android/perangkat fisik tidak diuji pada pekerjaan ini.

- Flutter Web release: PASS, JavaScript; peringatan WASM dry-run dari dependency existing tetap di luar perubahan ini.
- Chrome release nyata: PASS di sembilan viewport di atas; 0 page error. Video kamera virtual berisi QR sintetis dibaca decoder mobile_scanner asli; satu POST check-in+enqueue, frame berulang tidak mengirim ulang. CALL/RECALL/START/COMPLETE, SKIP/REQUEUE, pencarian, isolasi ruang, reconnect/REST refresh dan profil/logout juga PASS.
- Data HTTP/Socket.IO dan video QR adalah fixture sintetis. Tidak ada data development yang ditulis. QA memuat aset decoder pinned 3.1.3 identik melalui cdn.jsdelivr.net karena host Fastly default paket tidak terjangkau di lingkungan QA; source/runtime scanner aplikasi tidak diganti. Instalasi tetap membutuhkan izin kamera dan akses aset decoder existing.

[Screenshot desktop](images/staff-scan-fab/staff-1366x768.png) · [Laptop 1280×720](images/staff-scan-fab/staff-1280x720.png) · [Mobile](images/staff-scan-fab/staff-375x812.png) · [Scan berhasil](images/staff-scan-fab/scan-dialog.png) · [Laporan Chrome](images/staff-scan-fab/report.json).

Runner: `apps/client/tool/browser-staff-v4.cjs` dengan `compact: true` dan opsi `cameraVideo` menunjuk video Y4M QR sintetis `SQ1.` diikuti 43 karakter A, sesuai fixture runner. Tanpa video, runner memeriksa petunjuk kamera tidak tersedia. Jangan memakai token atau QR pengguna nyata sebagai fixture.
