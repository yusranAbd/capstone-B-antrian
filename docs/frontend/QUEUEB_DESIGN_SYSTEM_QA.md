# QueueB — laporan fondasi desain compact

## Audit dan pembersihan

Pemeriksaan mencakup source Flutter, dokumentasi frontend, instruksi proyek, file tersembunyi/config tooling, serta nama AGENTS.md/SKILL.md lokal. Tidak ditemukan skill desain khusus repository maupun kewajiban tooling yang perlu dihapus. Instalasi skill global di luar repository tidak diubah.

Komentar/skor panduan lama dihapus dari 15 file:

- `admin_doctor_profile.dart`, `admin_practice_form.dart`, `admin_ui.dart`.
- `doctor_dashboard.dart`, `doctor_visual.dart`, `doctor_professional.dart`, `doctor_schedule_ui.dart`.
- `staff_ui.dart`, `staff_v4.dart`.
- `patient_home.dart`, `patient_ui.dart`, `user_profile.dart`, `mobile_ui.dart`.
- `login_ui.dart`, `display_board.dart`.

Semua berada di `apps/client/lib/src/`. Satu paragraf penilaian desain generik dibersihkan dari `REALTIME_ADMIN_OPTIMIZATION.md`, dengan hasil pengujian dan sejarah teknis tetap utuh. Tidak ada widget/fitur/aset runtime yang dihapus. Riwayat Git, backup dan arsip tmp tidak ditulis ulang.

Acuan sekarang: [QueueB Hospital — Compact & Professional UI/UX Design System](QUEUEB_UI_UX_GUIDELINES.md). Root `AGENTS.md` dan `docs/ui-ux/README.md` menunjuk panduan ini agar pekerjaan berikutnya mengikuti aturan proyek, bukan skill eksternal.

## Dampak terarah

- `QueueBStyle.operationalTextTheme` memakai headline 20/22, title 14/15/17, body 12/13/14, label 11/12/13. Dipasang pada ADMIN/DOKTER; PETUGAS memakai baseline tersebut sambil mempertahankan override compact existing. Tema dasar pasien/TV tidak diperkecil secara global.
- Header operasional memakai token 56. Tidak mengubah branding, pilihan profil, logout, atau RBAC.
- `Section`: padding 20 → 16, gap isi 16 → 12, gap action 20 → 12/runSpacing 8. Konten panjang tetap dapat scroll dengan owner existing.
- `EmptyState`: padding vertikal 20 → 12, ikon 36 → 32, gap 12 → 8. Teks/status tetap.
- AdminTable 44–48, navbar pasien 60, touch target/input dasar 48, dan skala Public Display tetap. Ukuran hardcoded pada halaman lain tidak diubah massal.
- Tidak mengubah API, backend, database, migration, Queue Engine, auth, flow QR atau realtime. Tidak menambah dependency atau ilustrasi.

## Perlindungan pekerjaan lokal

Preflight memfingerprint 28 file lokal dalam sembilan entri Git; empat file tracked disalin byte-for-byte ke `tmp/queueb-design-baseline/` (diabaikan Git). 26 file tetap identik. Dua file DOKTER hanya mendapat penghapusan komentar dan, pada doctor_visual, wiring tema; transformasi diverifikasi persis terhadap snapshot awal.

Khusus `doctor_dashboard.dart` dan `doctor_visual.dart`, staging dilakukan dengan patch terhadap HEAD. Revisi compact layout/README/test/screenshots pengguna tidak disertakan. Backup, sql dan eksperimen apps/web tetap utuh. Tidak ada branch, PR, reset, clean atau force push.

## Validasi aktual

- Format 17 file Dart: PASS, nol perubahan tersisa.
- Flutter analyze final: PASS, tanpa issue.
- Tes fondasi: 43/43 PASS — lima portal × delapan viewport + tiga kasus Section pada text scale 1.0/1.5/2.0.
- Viewport: desktop 1280×720, 1366×768, 1440×900, 1920×1080; mobile 320×568, 360×800, 390×844, 412×915.
- Seluruh Flutter lokal: 473 PASS, 1 live fixture opsional SKIP. Angka ini termasuk satu tes DOKTER lokal pengguna yang tidak di-commit; CI memeriksa source yang benar-benar di-commit secara mandiri.
- Tes memeriksa render portal terautentikasi dengan fixture sintetis, tiket pasien, panel pelayanan, monitoring DOKTER, Public Display tanpa Scrollable, wrapping action dan cleanup. Ini bukan pengujian akun/database production atau speaker fisik.
- Build release serta QA Chrome dicatat setelah selesai pada bagian final di bawah. Tidak ada database yang dipakai/diubah untuk pekerjaan ini.

## Hasil akhir build dan Chrome

- Flutter Web release PASS (143,3 detik kompilasi). Peringatan dry-run WASM dependency TTS/Socket.IO existing tetap ada; tidak mengklaim build WASM.
- Chrome 156.0.8078.48: 9 skenario operasional PASS pada build release, 9 viewport, 0 error. Mencakup login/jadwal, search, SKIP/REQUEUE, CALL/RECALL/START/COMPLETE, One-Scan/manual, isolasi ruang, reconnect dan profil/logout.
- Browser menggunakan fixture HTTP/Socket.IO sintetis dan transport Socket.IO lokal, bukan API/database nyata. Tidak ada penulisan database. Hasil lengkap dan SHA256 artefak: [JSON browser QA](queueb-design-browser-qa.json).
- 40 tes matriks portal dan 3 tes pembesaran teks memverifikasi delapan viewport yang diminta. Tidak mengklaim pengujian speaker/kamera/perangkat fisik dari smoke UI ini.
- Scan source/dokumentasi/config staged: nol referensi panduan lama. Semua 28 file lokal awal tetap terlindungi sesuai verifikasi; dua file DOKTER hanya berubah pada komentar/wiring tema yang diizinkan.
