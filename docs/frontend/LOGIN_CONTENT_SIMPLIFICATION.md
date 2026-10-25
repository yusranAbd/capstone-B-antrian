# Penyederhanaan konten login

Revisi mengikuti anotasi pengguna: pengantar yang ditandai hitam dihapus, dan ringkasan layanan yang ditandai merah dipindahkan ke atas pada desktop.

- Mobile/tablet: branding langsung diikuti form; headline dan paragraf promosi tidak lagi tampil.
- Laptop/desktop: headline, paragraf pengantar, dan tiga manfaat lama dihapus. Kartu **Layanan digital rumah sakit** dipindahkan ke bawah branding di kiri ilustrasi dokter, tanpa duplikasi kartu di bawah.
- Form, kontrol autentikasi, validasi, registrasi, tombol Public Display, ukuran kartu form, ilustrasi, dan breakpoint desktop existing dipertahankan.
- Backend, database, autentikasi/RBAC, dan dashboard role tidak berubah.

## QA aktual

- Format: PASS pada dua file Dart berubah.
- Flutter analyze: PASS, tanpa issue.
- Regresi `login_ui_test.dart` + `session_test.dart`: **49/49 PASS**. Mencakup validasi, navigasi registrasi/display, redirect empat role, logout, pemulihan sesi, input saat resize, teks besar dan keyboard.
- Lebar UI diuji: 320, 360, 375, 390, 414, 500, 768, 1024, 1366, 1440, dan 1920 px.
- Flutter Web release: PASS.
- Browser: screenshot laptop 1366×768 dan mobile 390×844, pengantar hilang, kartu layanan hanya pada desktop dan berada di bagian atas; registrasi → kembali login PASS; tidak ada error JavaScript.
- QA visual menggunakan build sementara, tanpa akun/fixture atau perubahan database.

## Screenshot

- [Laptop](images/login-simplified/01-laptop.jpg)
- [Mobile](images/login-simplified/02-mobile.jpg)

Server pengguna `localhost:5173` dijalankan menggunakan `flutter run` dan tidak dihentikan/diganti. Untuk melihat revisi source pada server tersebut, lakukan hot restart dengan **R** pada terminal Flutter, lalu muat ulang browser jika diperlukan. Preview sementara QA telah ditutup.
