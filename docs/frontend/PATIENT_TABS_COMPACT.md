# Konsistensi halaman pasien dan navigasi ringkas

Melanjutkan checkpoint header beranda dan login yang masih menunggu review.

- Beranda, Pendaftaran/Poliklinik & Dokter, detail/jadwal booking, Tiket Saya, Janji Temu, dan Riwayat menggunakan identitas pasien yang sama pada header.
- Foto/avatar dan sapaan nama akun membuka Profil Saya; aktivitas tiket tetap dapat diakses. Tidak ada branding QueueB atau tombol logout pada header USER. Logout tetap tersedia di Profil Saya.
- Label status koneksi realtime disembunyikan di seluruh tab pasien. Subscription, reconnect, refresh REST dan polling fallback tidak berubah; error/loading data tetap terlihat.
- Caption teknis Waktu pelayanan: Asia/Jakarta dihilangkan dari alur pendaftaran. Konversi timezone pelayanan serta tanggal dan jam reservasi tetap menggunakan konfigurasi existing.
- Bottom navigation memakai komponen pasien dengan tinggi 60 px, ikon 22 px, label 11 px, empat tujuan existing, dan lebar maksimal 520 px pada layar besar. Di ponsel navigasi tetap selebar layar dan mempertahankan SafeArea.
- Tidak ada perubahan backend, database development, role lain, atau alur booking/QR. Desain dan perhitungan data existing dipertahankan.

## Validasi

- Format dan Flutter analyze: PASS.
- 135 tes regresi beranda/tab, login, sesi, profil/logout, booking, QR, kalender/timezone, dan realtime: PASS.
- Lebar 320/360/375/390/412/414/500/768/1366/1920 px: header konsisten, tinggi navigasi 60 px, lebar dibatasi 520 px, tidak ada overflow.
- Build Web release dan screenshot browser menggunakan API nyata dengan fixture hanya pada capstone_antrean_test; data development tidak digunakan untuk pengujian.

Screenshot: [Pendaftaran](images/patient-tabs-compact/01-pendaftaran.jpg), [Tiket Saya](images/patient-tabs-compact/02-tiket.jpg), [Janji Temu](images/patient-tabs-compact/03-janji-temu.jpg).

Seluruh pekerjaan lokal pengguna dipertahankan dan dipisahkan dari finalisasi Git perubahan ini.
Runtime flutter run pengguna pada localhost:5173 tidak dihentikan; gunakan **R** untuk hot restart agar source terbaru tampil.
