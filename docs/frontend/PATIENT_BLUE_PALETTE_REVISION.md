# Revisi login dan palet pasien — 28 Oktober 2026

Permintaan pengguna: kembalikan login seperti sebelum Final Experience dan gunakan perpaduan warna referensi biru/periwinkle, lavender muda, cyan dan putih. Tidak menggunakan panduan desain pihak ketiga.

- Login kembali kartu terpusat (baseline f8baef8), maksimum 420, tanpa editorial kiri; responsif dan dapat scroll ketika keyboard/text scale membutuhkan ruang.
- Primary #4C60CC, hero #4169D5, cyan #007CA8, background #F2F5FF, card #FFFFFF, soft #EEF1FF, ink #172544 dan muted #52617A. Biru aksi dibuat cukup gelap agar teks putih terbaca; warna referensi diadaptasikan, bukan menyalin data/desainnya.
- Warna tiket, kalender, tab, dialog dan profil mengalir melalui tema pasien existing. Status tetap berasal dari backend dengan label/ikon, tidak hanya warna.
- Ikon launcher/favicon/PWA geometris dan manifest mengikuti palet baru. Branding QueueB in-app tetap dipertahankan.
- Struktur pasien, agenda, lima navigasi, focus-scroll, QR, booking, login, session dan realtime tidak diubah. Backend/database dan UI role operasional tidak disentuh.

## Validasi aktual

- Format lima file Dart: 0 perubahan tersisa. Analyze: 0 issues.
- Seluruh Flutter test lokal: **497 PASS, 1 SKIP existing**. Termasuk satu tes DOKTER lokal pengguna yang tidak di-commit; live database integration opsional tetap skip tanpa fixture.
- Build Web release dan APK release split ARM64: **PASS**. APK 31,879,297 byte, masih paket QA dengan endpoint HTTPS placeholder `.invalid` dan debug signing existing. Bukan artefak distribusi publik; tidak mengklaim tes perangkat fisik.
- Chrome release: **16 skenario PASS**, `errors=[]`, pada 320x568, 360x800, 375x812, 390x844, 412x915, 768x1024, 1366x768 dan 1920x1080. Tidak ada horizontal overflow/runtime error. Widget tests memeriksa layout login centered, resize, keyboard/text scale, serta kontras teks/status minimal 4.5:1.
- Booking appointment/walk-in, pembatalan, QR sesuai tiket, save profil, logout/login, reload dan realtime/reconnect tetap lulus dengan fixture HTTP/Socket.IO terisolasi, tanpa menulis database.
- 28 file lokal pengguna dibandingkan checksum: identik. Tidak ada perubahan backend/schema/migration/dependency.

Bukti adalah render Flutter aktual dengan identitas sintetis, bukan mockup. [Laporan browser](images/blue-palette/qa.json). Blocker produksi pada PUBLIC_RELEASE_READINESS.md tetap berlaku.

| Tampilan | Screenshot |
|---|---|
| Login desktop | [1366x768](images/blue-palette/login-1366.png) |
| Login mobile | [390x844](images/blue-palette/login-390.png), [320x568](images/blue-palette/login-320.png) |
| Beranda/kunjungan | [390x844](images/blue-palette/after-home-appointment-390.png), [320x568](images/blue-palette/after-home-appointment-320.png) |
| Tiket Saya | [390x844](images/blue-palette/after-tickets-390.png) |
| Reservasi | [390x844](images/blue-palette/after-reservations-390.png) |
| Profil | [390x844](images/blue-palette/after-profile-390.png) |
