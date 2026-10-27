# Perluasan palet biru ke seluruh portal — 28 Oktober 2026

Permintaan pengguna memperluas palet periwinkle/cyan/lavender/putih pasien ke ADMIN, PETUGAS, DOKTER dan Public Display. Layout, ukuran, kontrak, role dan alur operasional dipertahankan.

- `QueueBPalette` menjadi sumber warna bersama; alias lama tetap tersedia agar tidak memerlukan perubahan kontrak widget.
- ADMIN: sidebar, header, tabel, kartu, filter/form mengikuti background lavender, paper putih dan aksi periwinkle.
- PETUGAS: header/list/QR mengikuti palet bersama; panel pelayanan memakai biru gelap untuk teks operasional yang kontras.
- DOKTER: canvas/card/live panel mengikuti palet baru. Revisi compact lokal yang sudah ada dipertahankan; commit tugas hanya membawa perubahan token warna, tidak membawa layout lokal.
- Public Display: panel nomor panggilan biru, daftar putih, pengumuman lavender. Privasi nama, pagination, TTS, pairing multi-monitor dan reconnect tidak berubah.
- PASIEN/login tetap memakai revisi yang telah disetujui. Login tetap kartu terpusat.

## Validasi aktual

- Flutter analyze: **0 issues**; format 11 berkas/varian source: **0 perubahan**.
- Seluruh Flutter test lokal: **500 PASS, 1 SKIP existing**. Termasuk satu tes DOKTER privat pengguna yang tidak di-commit; skip live integration memerlukan fixture database tervalidasi.
- Tes khusus: tema semua role berbagi palet tanpa mengubah ukuran font; foreground/background kontras minimal 4.5:1; panel Display dan pelayanan PETUGAS mengambil warna yang sesuai.
- Build Web release: PASS. Build APK release split ARM64: PASS. APK masih QA dengan endpoint `.invalid` dan debug signing existing; tidak diuji pada perangkat Android fisik dan bukan paket distribusi publik.
- Chrome 156.0.8078.48 release: ADMIN, DOKTER dan DISPLAY pada 1280x720, 1366x768 dan 1920x1080; tidak ada horizontal overflow atau runtime error. Display tanpa scroll, nomor panggilan aktual fixture, status menunggu/dilewati dan pairing UI tervalidasi.
- PETUGAS: 9 viewport (termasuk 1280x720, 1366x768, 1440x900, 1920x1080 dan mobile), 9 skenario PASS: search, SKIP/REQUEUE tanpa duplikasi, CALL/RECALL/START/COMPLETE, One-Scan/manual enqueue, isolasi ruang, reconnect dan profil/logout.
- PASIEN: 8 viewport 320x568 sampai 1920x1080, 16 skenario PASS: booking dokter/walk-in, pembatalan, QR sesuai tiket, lima navigasi, profil, login ulang dan realtime/reconnect.

Browser memakai aplikasi release nyata dengan fixture HTTP/Socket.IO sintetis. Ini bukti rendering/interaksi frontend, bukan uji E2E backend, keamanan pairing produksi, suara TTS nyata atau bukti bebas memory leak. Mekanisme keamanan, pagination, TTS dan Queue Engine tidak diubah. Tidak ada perubahan backend/database/migration/API/dependency runtime.

27 file lokal pengguna identik checksum; perubahan pada Doctor Visual terbatas token/import warna dan dapat dibalik tepat ke byte baseline lokal. Commit memakai varian HEAD + patch warna saja, sehingga revisi compact lokal DOKTER tidak ikut ter-commit. Screenshot/build lokal mencakup revisi compact tersebut; layout main dapat berbeda, paletnya sama.

### Screenshot aktual (fixture sintetis)

| Portal | Bukti |
|---|---|
| ADMIN | [1366x768](images/all-portals-blue/admin-1366.png) |
| PETUGAS | [1366x768](images/all-portals-blue/petugas-1366.png) |
| DOKTER | [1366x768](images/all-portals-blue/dokter-1366.png) |
| Public Display | [1280x720](images/all-portals-blue/display-1280.png), [1366x768](images/all-portals-blue/display-1366.png), [1920x1080](images/all-portals-blue/display-1920.png) |
| PASIEN | [390x844](images/all-portals-blue/pasien-390.png) |
| Login | [1366x768](images/all-portals-blue/login-1366.png) |

Laporan mentah: [role render](images/all-portals-blue/roles-qa.json), [PETUGAS](images/all-portals-blue/petugas-qa.json), [PASIEN](images/all-portals-blue/pasien-qa.json).

### Reproduksi render role

Tooling QA lokal memerlukan Node, Chrome, @playwright/test dan socket.io pada NODE_PATH; tidak menambah dependency Flutter. Setelah build Web release, panggil modul `apps/client/tool/browser-portal-palette.cjs` dengan argumen `build`, `output`, `engineRoot` (SDK bin/cache/flutter_web_sdk/canvaskit) dan `fontFile` (SDK bin/cache/artifacts/material_fonts/roboto-regular.ttf). Modul menjalankan loopback HTTP/Socket.IO fixture, tidak membaca kredensial atau menghubungi database. Font/engine memakai SDK lokal; response JS yang disajikan dialihkan ke fixture tanpa mengubah artefak di disk. `browser-staff-v4.cjs` dan `browser-reservation-v4.cjs` mempertahankan regresi flow lengkap existing.


Build Web main JS SHA-256: `3d5bab17cf9bcf9160b3561b00ef9ea9629416d4e0a82208d46e0074c917948b`.
