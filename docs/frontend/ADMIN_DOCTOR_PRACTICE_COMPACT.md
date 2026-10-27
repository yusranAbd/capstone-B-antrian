# Dokter & Jadwal Praktik ADMIN — compact management

## Perubahan

- Dokter: baris dari maksimum 112 menjadi 64 logical px pada text scale normal. Nama dan spesialisasi/kode dikelompokkan, akun tetap terpisah dari status profil. Enam baris per halaman, pilihan jumlah baris tetap tersedia. Tidak mengubah provisioning, hubungkan poliklinik, nonaktifkan atau hapus.
- Banner alur dokter dipindahkan ke Panduan dokter pada judul; penjelasan keamanan tetap dapat dibaca melalui dialog.
- Jadwal: agenda tanggal dengan pengelompokan ruang, jam mulai/selesai menonjol, nama dokter/poli pada dua tingkat, status dan menu aksi. Enam sesi dirender per halaman. Pada desktop lebar, sesi di dalam tiap ruang disusun dua kolom; pada layar sempit/teks besar kembali satu kolom. Default memilih hari ini jika ada, tanggal mendatang terdekat, atau tanggal terakhir dari data jika semuanya lampau. Ini hanya pilihan tampilan, bukan aturan pelayanan.
- Navigasi tanggal yang memiliki data, date picker, Hari ini, Semua tanggal, search/status/poli/dokter tetap ada. Tanggal pilihan tetap dipertahankan saat filter berubah; empty state menawarkan tanggal lain/Semua tanggal.
- Toolbar dibuat proporsional agar aksi tidak jatuh ke baris sendiri pada desktop utama.
- Menu aksi bertambah ukurannya saat text scale besar; baris agenda sempit memakai Wrap agar status/aksi tidak overflow.

Tidak ada perubahan endpoint, database, migration, backend, role, Queue Engine atau portal lain. Palet biru existing dipertahankan. Seluruh pekerjaan lokal pengguna dilindungi.

## Hasil QA aktual

- Format 6 file Dart: 0 perubahan; analyze: 0 issues.
- Seluruh Flutter test lokal: **507 PASS, 1 SKIP existing**. Termasuk satu tes DOKTER privat pengguna yang tidak di-commit; live database integration opsional tetap skip tanpa fixture.
- Build Web release: **PASS**. Tidak melakukan build/perangkat Android pada tugas desktop ini.
- Chrome 156.0.8078.48, release nyata dengan 10 dokter dan 155 jadwal sintetis: **PASS**, tanpa root horizontal overflow/runtime error pada 1280x720, 1366x768, 1920x1080 dan 390x844 untuk kedua modul.
- Search dokter, akses menu aksi, ganti tanggal agenda dan Semua tanggal tetap bekerja. Semua 155 sesi dapat dijangkau; render dibatasi enam sesi per halaman.
- Tes regresi 440 sesi memverifikasi filter tetap menyaring data dan hanya enam menu/baris dibangun. Tes agenda memeriksa lima viewport, page/date navigation, handler row yang benar, source tidak termutasi, empty state dan text scale 2x.
- Batas tinggi baris Dokter normal turun dari 112 ke 64 logical px; enam baris dan header tabel aktual berukuran 428 px pada fixture Chrome. Footer pagination tetap di luar bagian tabel tersebut. Ukuran baris bertambah saat text scaling.
- Semua 28 file lokal yang dilindungi identik dengan baseline task. Tidak ada perubahan backend/database/migration/API/role. Palet lintas portal tetap dipertahankan.

Browser memakai HTTP fixture terisolasi, bukan data atau kredensial development. Tidak mengklaim E2E backend atau uji perangkat fisik. Screenshot dan build lokal mencakup revisi compact DOKTER pengguna yang sudah ada, tetapi source tersebut tidak masuk commit ini.

| Modul | Sebelum | Sesudah |
|---|---|---|
| Dokter desktop | [1366x768](images/admin-compact-management/before-doctor-1366.png) | [1366x768](images/admin-compact-management/after-doctor-1366.png) |
| Agenda praktik desktop | [1366x768](images/admin-compact-management/before-practice-1366.png) | [1366x768](images/admin-compact-management/after-practice-1366.png) |
| Dokter laptop kecil | [1280x720](images/admin-compact-management/before-doctor-1280.png) | [1280x720](images/admin-compact-management/after-doctor-1280.png) |
| Agenda laptop kecil | [1280x720](images/admin-compact-management/before-practice-1280.png) | [1280x720](images/admin-compact-management/after-practice-1280.png) |
| Dokter mobile | [390x844](images/admin-compact-management/before-doctor-390.png) | [390x844](images/admin-compact-management/after-doctor-390.png) |
| Agenda mobile | [390x844](images/admin-compact-management/before-practice-390.png) | [390x844](images/admin-compact-management/after-practice-390.png) |

Bukti: [baseline](images/admin-compact-management/before-qa.json), [final](images/admin-compact-management/after-qa.json). Runner `browser-admin-v41.cjs` memakai opsi `compactManagement:true`; `baseline:true` hanya menangkap desain lama. Tooling Node/Chrome/Playwright existing, tidak menambah dependency Flutter. Keduanya memakai dataset fixture dengan jumlah dan bentuk yang sama; ID sintetis dibuat ulang setiap run.


Web final main JS SHA-256: `d444e9cd0512a1e0ba2bf9db205057310bd46eb7320315f0408bd6223d9d024c`.
