# Header beranda pasien

Revisi presentasi pasien pada 25 Oktober 2026 mengikuti anotasi pengguna.

- Pada Beranda, foto/avatar P2 dan sapaan nama akun menempati header teratas menggantikan branding QueueB. Seluruh area identitas dapat ditekan untuk membuka Profil Saya.
- Sapaan tidak lagi diulang di bawah header. Ikon aktivitas tiket tetap dapat digunakan.
- Logo/komponen branding tetap tersedia di source dan halaman lain; tidak ditampilkan pada Beranda.
- Label status koneksi realtime tidak ditampilkan pada Beranda. PatientUpdates, subscription, refresh snapshot, polling fallback, dan reconnect tetap berjalan. Pesan error/loading data tetap tersedia.
- Tombol logout di header seluruh tab USER/PASIEN disembunyikan karena Keluar Akun tersedia pada Profil Saya. Header dan logout ADMIN/PETUGAS/DOKTER dipertahankan.
- Jadwal, booking, tiket, QR, dan backend/database development tidak diubah. Revisi login sebelumnya dipertahankan.

## Validasi

- 107 tes regresi beranda, login, profil/logout, QR, sesi, dan sinkronisasi pasien: PASS.
- Flutter analyze dan build Web release: PASS.
- Lebar beranda 320/360/375/390/412/414/768 px dengan nama panjang: tidak ada overflow.
- Browser dengan API nyata pada capstone_antrean_test: header identitas, akses Profil, aktivitas tiket, dan pembaruan otomatis setelah pembatalan appointment fixture terverifikasi.
- [Screenshot beranda 390×1000](images/patient-home-header/01-beranda.jpg), memakai data sementara berlabel Demo/QA.

Build QA terpisah dari proses flutter run pengguna. Untuk memperbarui localhost:5173,
gunakan hot restart **R** pada terminal Flutter. Tidak ada commit/push pada checkpoint review ini.
