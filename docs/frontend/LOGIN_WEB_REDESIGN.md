# Redesign Login QueueB Hospital (Flutter Web)

Halaman login memakai layout desktop dua kolom berdasarkan referensi Project Lead: branding, ilustrasi dokter/rumah sakit dan manfaat layanan di kiri; form login putih dan akses Public Display di kanan. Semua kontrol merupakan widget Flutter asli. Ilustrasi dekoratif dibuat dengan imagegen, tanpa identitas pasien, angka antrean, atau screenshot halaman.

## Layout dan aksesibilitas

- Lebar >=1024 px: dua kolom, kontainer terpusat dengan lebar maksimum 1440 px. Tinggi area branding mengikuti konten; form memiliki tinggi minimum pada desktop dan tetap dapat bertambah saat validasi/registrasi.
- Lebar 600–1023 px: satu kolom dengan form maksimum 560 px dan panel layanan digital di bawahnya.
- Lebar <600 px: logo dan heading ringkas, form menjadi fokus, ilustrasi desktop dan panel manfaat disembunyikan.
- Semua ukuran dapat scroll pada viewport pendek/keyboard terbuka. Isian tersimpan ketika berpindah breakpoint. Material menyediakan state hover/focus/pressed/disabled; tombol menampilkan indikator saat login berlangsung.
- Email mendukung keyboard Next; kata sandi mendukung Done/Enter, autofill dan toggle tampil/sembunyi. Pesan sesi, hasil registrasi dan error tetap tampil; notifikasi memakai live region.

## Kontrak dan batas scope

`QueueApi.login/register`, session store, token, JWT/RBAC, redirect berdasarkan role backend, logout, dan seluruh dashboard role existing dipertahankan. Tidak ada backend, database, dependency baru, route baru, atau perubahan kontrak API.

Tombol **Masuk ke Public Display** memakai callback existing ke route `/display`. Pengguna belum login dapat membuka halaman aktivasi perangkat; akses snapshot tetap membutuhkan pairing/token perangkat existing. Tidak ada data pribadi pasien ditambahkan.

Tautan lupa sandi dan tombol Google/Apple tidak ditampilkan karena alurnya belum tersedia. Registrasi tetap khusus pasien; tidak ada pilihan login cepat berdasarkan avatar/role.

## File utama

- `apps/client/lib/src/app.dart`: komposisi form baru; submit dan pemilihan role existing tetap digunakan.
- `apps/client/lib/src/login_ui.dart`: layout responsif dan token visual lokal, kartu form, branding dan panel manfaat.
- `apps/client/assets/illustrations/login_hospital.png` + `pubspec.yaml`: aset ilustrasi terpisah.
- `apps/client/test/login_ui_test.dart`: 18 regresi login baru.
- `apps/client/test/ui_test.dart`, `tool/browser-smoke.cjs`, `tool/browser-display-v2.cjs` dan `tool/browser-demo.cjs`: selaraskan label tombol Public Display pada otomasi existing.

## Validasi

- `dart format --output=none --set-exit-if-changed lib test integration_test`: 54 file, 0 perubahan.
- `flutter analyze --no-pub`: tanpa masalah.
- `flutter test --no-pub --reporter expanded`: **225 PASS, 1 conditional integration SKIP**, termasuk 18 tes login baru. Regresi mencakup sesi/token, role, logout, registrasi, antrean, Public Display dan TTS existing.
- `flutter build web --release --no-pub --no-wasm-dry-run --output build/web_login --dart-define=API_BASE_URL=http://localhost:3000/api/v1`: **PASS** (97,7 detik).
- `git diff --check` dan syntax check tiga skrip browser: lulus.
- QA browser build release: validasi login, toggle sandi, akses registrasi, layout 1440/1024/768/375 px, serta route Public Display anonim; tidak ada error runtime pada log browser. Widget test juga mencakup 320/414 px, teks 200%, keyboard pada viewport pendek, Tab/Enter, loading/error dan isian saat resize.
- Perbaikan yang ditemukan di QA: key tetap untuk field nama/email/sandi mencegah state validasi tertukar saat berganti login/registrasi; tes regresinya dijalankan.

 Tes login memakai MockClient; tes integrasi database bersyarat tidak dijalankan untuk perubahan tampilan ini. QA browser menggunakan build release standar tanpa entry point/klien API khusus.

## Panduan demo

1. Jalankan API existing dan sajikan build Web dengan `API_BASE_URL` sesuai lingkungan; tidak perlu migration.
2. Buka halaman tanpa sesi: cek layout desktop 1440/1024 px serta tablet 768 px dan ponsel 375 px.
3. Tekan Masuk dengan input kosong untuk melihat validasi. Tab dari email menuju kata sandi, cek toggle visibility, lalu login menggunakan akun existing.
4. Role dari backend menentukan dashboard ADMIN/PETUGAS/DOKTER/USER; logout kembali ke login.
5. Pilih Pasien baru? Daftar untuk registrasi pasien existing; jangan gunakan identitas pasien nyata untuk QA.
6. Dari login pilih Masuk ke Public Display. Halaman aktivasi terbuka tanpa login; pairing dan operasional TV mengikuti alur existing.

## Screenshot build release

- [Desktop 1440 px](images/login-web/01-desktop-1440.jpg)
- [Desktop 1024 px](images/login-web/02-desktop-1024.jpg)
- [Tablet 768 px](images/login-web/03-tablet-768.jpg)
- [Mobile 375 px](images/login-web/04-mobile-375.jpg)
- [Public Display tanpa login](images/login-web/05-display-anonim.jpg)

## Batas verifikasi

Tidak ada akun/password development diubah atau dibagikan. Redirect keempat role, error, loading, registrasi, sesi dan logout diuji melalui mock API dan regresi existing. Login dengan kredensial nyata dan pairing TV penuh tidak diulang karena perubahan ini hanya UI login; mekanisme tersebut tidak diubah. QA tidak menulis data database.
