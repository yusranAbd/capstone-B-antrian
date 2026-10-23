# ADMIN Compact Redesign

## Lingkup

Revisi visual Flutter Web ADMIN dari `origin/main` (`470c73c`, PR #56). Sidebar menyediakan sembilan tautan langsung, tetap dapat diciutkan. Tidak ada kategori/accordion navigasi. Pengelompokan data di dalam modul tetap tersedia agar slot dan jadwal dimuat seperlunya.

- Header 58 px; sidebar 216 px atau 64 px saat diciutkan; padding halaman 16 px.
- Sapaan, tanggal dan zona waktu tetap tersedia; banner dekoratif besar dihilangkan.
- KPI mempertahankan hitungan katalog API existing, tanpa statistik baru atau estimasi.
- Tabel default menggunakan heading 44 px dan baris 44–48 px, dengan tinggi adaptif saat teks diperbesar. Pagination, sorting, tooltip teks lengkap dan scroll horizontal dipertahankan.
- Pencarian/filter dan tombol tambah/muat ulang berada pada toolbar responsif. Filter yang banyak membungkus ke baris berikutnya.
- Aksi dokter menggunakan tombol edit dan ikon ber-tooltip untuk nonaktifkan, akun dokter dan hubungan poliklinik. Sel aksi tidak membungkus agar kontrol tidak terpotong.
- Modal jadwal praktik maksimum 840 px, dengan padding lebih ringkas; date picker, time picker dan validasi tidak berubah.
- Manajemen Display menggunakan satu tabel berkolom poliklinik. Aktivasi/rotasi, reaktivasi, konfirmasi dan pencabutan akses tetap memakai mekanisme existing. Status aktif tetap berarti izin akses, bukan status koneksi.
- Bulk jam/kapasitas, CRUD seluruh modul dan batas kewenangan tidak berubah.

Tidak ada perubahan backend, schema, migration, kontrak API, autentikasi, Socket.IO, UI DOKTER/PETUGAS/USER/Public Display. Seluruh perubahan tema terikat pada ADMIN.

## Validasi

- `dart format lib test --output=none --set-exit-if-changed`: 56 berkas, 0 perubahan.
- `flutter analyze --no-pub`: PASS, tidak ada issue.
- `flutter test --no-pub --reporter expanded`: 246 PASS, 1 SKIP existing. Tes live hanya dijalankan dengan runner dan database test tervalidasi; tidak dijalankan pada pekerjaan visual ini.
- `flutter build web --no-pub`: PASS (`build/web`). Dependency existing `flutter_tts` dan `socket_io_common` masih memberi temuan Wasm dry-run; build JavaScript selesai.
- `git diff --check`: PASS.

Regresi baru memverifikasi akses seluruh aksi dokter setelah pencarian, aktivasi/rotasi dan pencabutan perangkat melalui endpoint existing, serta peningkatan tinggi baris saat text scaling diperbesar.

QA browser menggunakan build source final dengan HTTP fixture sintetis lokal: empat poliklinik, lima dokter, empat ruang dan lima sesi. Ini menguji presentasi/navigasi tanpa menulis ke database. Fixture bukan data produk dan tidak disertakan pada entrypoint produksi. Tes widget memakai MockClient untuk memverifikasi request CRUD/validasi dan regresi peran lain; laporan ini tidak mengklaim pengujian mutasi pada server development.

Pemeriksaan browser meliputi sembilan menu, sidebar terbuka/ciut, tabel dan toolbar, modal jadwal, serta pemuatan bertahap slot. Tes mencakup filter/pagination ratusan jadwal, bulk jadwal, date/time picker, CRUD modul, akun dokter dan aktivasi/rotasi/pencabutan perangkat.

## Screenshot sebelum/sesudah

Data screenshot sintetis sama pada kedua build, tanpa kredensial atau data pribadi. Sebelum: baseline main; sesudah: source final pada branch ini. Ukuran berkas gambar diverifikasi sesuai viewport. Screenshot slot menampilkan grup tertutup; pemuatan dan aksi slot diverifikasi melalui tes widget.

| Halaman | Sebelum 1366×768 | Sesudah 1366×768 | Sebelum 1440×900 | Sesudah 1440×900 |
|---|---|---|---|---|
| Dashboard | [Lihat](images/admin-compact/before/dashboard-1366.jpg) | [Lihat](images/admin-compact/after/dashboard-1366.jpg) | [Lihat](images/admin-compact/before/dashboard-1440.jpg) | [Lihat](images/admin-compact/after/dashboard-1440.jpg) |
| Poliklinik | [Lihat](images/admin-compact/before/poliklinik-1366.jpg) | [Lihat](images/admin-compact/after/poliklinik-1366.jpg) | [Lihat](images/admin-compact/before/poliklinik-1440.jpg) | [Lihat](images/admin-compact/after/poliklinik-1440.jpg) |
| Dokter | [Lihat](images/admin-compact/before/dokter-1366.jpg) | [Lihat](images/admin-compact/after/dokter-1366.jpg) | [Lihat](images/admin-compact/before/dokter-1440.jpg) | [Lihat](images/admin-compact/after/dokter-1440.jpg) |
| Jadwal praktik | [Lihat](images/admin-compact/before/jadwal-1366.jpg) | [Lihat](images/admin-compact/after/jadwal-1366.jpg) | [Lihat](images/admin-compact/before/jadwal-1440.jpg) | [Lihat](images/admin-compact/after/jadwal-1440.jpg) |
| Slot konsultasi | [Lihat](images/admin-compact/before/slot-1366.jpg) | [Lihat](images/admin-compact/after/slot-1366.jpg) | [Lihat](images/admin-compact/before/slot-1440.jpg) | [Lihat](images/admin-compact/after/slot-1440.jpg) |
| Manajemen Display | [Lihat](images/admin-compact/before/display-1366.jpg) | [Lihat](images/admin-compact/after/display-1366.jpg) | [Lihat](images/admin-compact/before/display-1440.jpg) | [Lihat](images/admin-compact/after/display-1440.jpg) |

Tambahan: [modal jadwal](images/admin-compact/after/jadwal-modal-1366.jpg), [tablet 768×1024](images/admin-compact/after/dashboard-tablet-768.jpg).

### Dampak pada laptop

Pada fixture empat poliklinik di 1366×768, tabel dashboard beserta pagination terlihat pada viewport awal. Sebelumnya tabel dimulai di bagian bawah viewport dan sebagian baris memerlukan scroll. Seluruh sembilan menu kini terlihat tanpa membuka kategori. Daftar panjang tetap menggunakan pagination dan scroll untuk menjaga keterbacaan.

## Berkas implementasi

- `apps/client/lib/src/admin_navigation.dart`: navigasi langsung.
- `apps/client/lib/src/admin_ui.dart`: tema dan tabel ADMIN.
- `apps/client/lib/src/app.dart`: tinggi header/branding ADMIN.
- `apps/client/lib/src/admin_dashboard.dart`: ringkasan compact.
- `apps/client/lib/src/admin.dart`: shell, toolbar dan editor umum.
- `apps/client/lib/src/admin_data.dart`: toolbar, tabel, kelompok dan aksi.
- `apps/client/lib/src/admin_schedules.dart`: daftar/bulk jadwal compact.
- `apps/client/lib/src/admin_practice_form.dart`: proporsi modal.
- `apps/client/lib/src/admin_display.dart`: tabel perangkat.
- Tes terkait: `admin_optimization_test.dart`, `admin_practice_form_test.dart`, `admin_visual_refresh_test.dart`, `display_pairing_test.dart`, `ui_test.dart`.

## Batas dan perlindungan pekerjaan

Lebar tabel bisa melebihi viewport saat data/ukuran teks panjang; scroll horizontal disengaja agar kontrol tidak dipotong. Tidak ada pagination server baru. Build Web JavaScript tetap dipakai; dukungan Wasm dependency existing tidak termasuk pekerjaan ini.

Implementasi berada pada worktree terpisah dari pekerjaan lokal pengguna, termasuk revisi DOKTER yang belum dikomit. Hash 51 berkas existing diverifikasi tanpa perubahan. Tidak ada file `.env`, backup, entrypoint QA atau artefak build yang dimasukkan ke commit. PR ditujukan ke main tanpa auto-merge.
