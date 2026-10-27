# ADMIN Portal V4.1

Penyempurnaan ini hanya mencakup UI ADMIN. Backend, kontrak API, RBAC, Queue Engine, schema/migration dan portal role lain tidak diubah.

## Empat perubahan

1. Seluruh tabel/row manajemen memakai AdminRowActions: tombol compact **Aksi ˅**, menu berikon, dan warna merah untuk tindakan berbahaya. Berlaku pada Poliklinik, Dokter, Ruang & Loket, Jam & Kapasitas, Jadwal Praktik, Slot Konsultasi, Akun Petugas, Penugasan Loket dan Manajemen Display.
2. Rentang Dari/Sampai tanggal pada daftar Jadwal Praktik dan Slot Konsultasi dihilangkan beserta state/controller dan validasi filternya. Filter tersebut sebelumnya lokal; tidak ada parameter API tanggal baru yang ditambahkan/dihapus. Search, status, poliklinik, dokter, Tambah dan Muat ulang tetap tersedia. Date picker/form tambah/edit serta validasi sesi/kapasitas tidak diubah.
3. Subtitle literal Zona pelayanan dihapus. Konfigurasi serviceTimeZone, konversi penyimpanan/tampilan waktu, serta informasi zona pada form tanggal/waktu tetap dipertahankan.
4. Navbar ADMIN setinggi 52px hanya berisi branding dan logout. Nama/role/avatar administrator tidak dirender di navbar. Profil Saya tersedia sebagai utility di bawah sembilan tujuan navigasi existing, termasuk pada sidebar collapsed dan sheet navigasi mobile. Bukan tujuan manajemen kesepuluh.

## Pelestarian fungsi

- Callback edit, nonaktifkan, hapus permanen, relasi dokter, provisioning akun, rotasi/reaktivasi display tetap milik controller existing. Dialog konfirmasi dan respons server (termasuk 403/404/409) tidak diubah.
- Aksi dokter untuk Hubungkan poliklinik dan Buat/Lihat akun login dipindahkan dari kolom metadata ke menu yang sama. Status profil dan status akun tetap dibedakan.
- Akun PETUGAS hanya memiliki aktivasi/nonaktivasi existing; tidak ditambahkan edit/hapus yang tidak didukung API. Data nonaktif umum dapat diedit melalui form existing; tidak mengarang endpoint Aktifkan baru. Display memakai reaktivasi resmi existing, dibatasi status poliklinik seperti sebelumnya.
- Popup dirender pada overlay Navigator, sehingga tidak terpotong clip tabel. Identitas item berupa objek aksi immutable, bukan indeks yang dapat bergeser saat data berubah. Busy-state baru juga memblokir pilihan menu yang sudah telanjur terbuka. Regresi khusus menguji dua kondisi tersebut.
- Pagination, horizontal scrolling tabel, filter aktif setelah mutasi, lazy expansion slot dan thumbnail dokter dipertahankan. Tidak ada dependency atau aset baru.

## QA

Chrome 155 pada build Web release: **5 kelompok pemeriksaan PASS, 4 viewport PASS, 0 error browser**. Terverifikasi menu seluruh modul, edit dokter pada setiap viewport, penghapusan filter tanggal daftar, edit/nonaktifkan/hapus fixture dengan pencarian tetap aktif, serta profil dan logout. Artefak JavaScript yang diuji memiliki SHA-256 `ae49e75e8877125711a9f3e8175651fe394b847e8ae6de40ca406dd9acc7d2f9`.

Format dan analyze lulus. Dua belas tes baru mencakup menu semua modul, callback existing, larangan aksi akun yang tidak didukung, header/profil/logout pada empat viewport, serta race UI menu. Suite Flutter final dijalankan ulang setelah penyesuaian ekspektasi akses profil pada viewport compact: **399 PASS, 1 SKIP, 0 gagal** (4 menit 29 detik). Tes yang dilewati adalah integrasi backend live yang memerlukan runner/database test terisolasi; task UI ini tidak menulis database. Seluruh suite juga menjadi gate CI pada commit main ini.

Browser memakai Flutter Web release nyata dalam Chrome dengan HTTP fixture sintetis loopback. Uji tersebut bukan autentikasi/backend NestJS live dan tidak mengakses database. CRUD fixture memverifikasi edit, nonaktifkan, hapus permanen data yang belum dipakai, serta filter pencarian yang tetap aktif. Tes existing mempertahankan pemeriksaan konfirmasi, penolakan relasi, pairing/rotasi/pencabutan display dan pengelolaan akun. Tidak ada klaim perubahan backend atau pengujian database development.

Viewport: 1366x768, 1920x1080, 768x1024, 390x844. Menu Dokter benar-benar dibuka dan modal edit dibuka/ditutup pada semua ukuran; tabel sempit mempertahankan scroll horizontal existing. Screenshot memakai data sintetis yang sama. Capture sebelum berasal dari artefak release main setelah Patient Reservation V4; source ADMIN pada baseline tersebut sama dengan awal pekerjaan ini.

- [Dokter sebelum](images/admin-v41/doctor-before-1366x768.png) / [sesudah](images/admin-v41/doctor-after-1366x768.png)
- [1920x1080](images/admin-v41/doctor-after-1920x1080.png), [tablet](images/admin-v41/doctor-after-768x1024.png), [mobile](images/admin-v41/doctor-after-390x844.png)
- [Jadwal Praktik](images/admin-v41/practice-schedules.png) / [Slot Konsultasi](images/admin-v41/consultation-slots.png)
- [Header ADMIN](images/admin-v41/header-admin.png)
- [Report browser](admin-v41-browser-qa.json)

Build yang diverifikasi adalah Web JavaScript release. Peringatan WASM dependency existing tidak ditangani di luar scope refinement ini.

## File perubahan

Produksi: apps/client/lib/src/admin_ui.dart, admin_data.dart, admin.dart, admin_navigation.dart, admin_schedules.dart, admin_staff.dart, admin_display.dart dan app.dart (hanya cabang header/akses profil ADMIN).

Regresi: admin_v41_test.dart, admin_action_helpers.dart, admin_delete_test.dart, admin_management_p0_test.dart, admin_optimization_test.dart, admin_schedules_test.dart, display_pairing_test.dart, session_test.dart dan ui_test.dart dalam apps/client/test/. Assertion mutasi/konfirmasi dipertahankan; cara membuka aksinya mengikuti dropdown baru.

QA/dokumentasi: apps/client/tool/browser-admin-v41.cjs, dokumen ini, report JSON dan delapan screenshot dalam images/admin-v41/.

## Reproduksi dan Git

Dari root repository, gunakan dependensi QA existing apps/client/tool (@playwright/test) dan Chrome. Tetapkan NODE_PATH ke direktori node_modules tooling, serta QUEUEB_CANVASKIT_DIR dan QUEUEB_ROBOTO_FILE ke cache SDK Flutter. Build Web memakai API_BASE_URL=http://localhost:3000/api/v1 dan SERVICE_TIME_ZONE=Asia/Jakarta. Runner hanya menyesuaikan URL dalam response JavaScript fixture, tanpa mengubah artefak di disk.

```powershell
node -e "require('./apps/client/tool/browser-admin-v41.cjs')({build:'apps/client/build/web',output:'tmp/admin-v41-browser',engineRoot:process.env.QUEUEB_CANVASKIT_DIR,fontFile:process.env.QUEUEB_ROBOTO_FILE}).then(r=>console.log(JSON.stringify(r))).catch(e=>{console.error(e.message);process.exitCode=1})"
```

Instruksi pengguna terbaru meminta push langsung ke main tanpa PR. Commit menggunakan push normal fast-forward, bukan force push. Checkout utama disinkronkan hanya setelah pemeriksaan konflik dengan pekerjaan lokal; tidak memakai reset, clean atau stash. Sembilan entri perubahan lokal dan backup dipertahankan. Untuk memuat source baru pada runtime development, lakukan hot restart/restart Flutter; artefak QA terisolasi tidak menimpa build lokal yang mungkin berisi revisi Dokter pengguna yang belum dikomit.
