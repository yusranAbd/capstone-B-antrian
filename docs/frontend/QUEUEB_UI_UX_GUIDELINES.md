# QueueB Hospital — Compact & Professional UI/UX Design System

Panduan mandiri untuk Flutter QueueB Hospital. Ini menjadi acuan seluruh penyempurnaan visual berikutnya. Kebutuhan pengguna, keselamatan operasional, aksesibilitas dan kontrak aplikasi lebih utama daripada mengejar kepadatan atau dekorasi.

## Prinsip

**Simple, clean, compact, functional, consistent, responsive, accessible, performance-conscious.**

1. Dahulukan informasi dan tindakan yang dibutuhkan role. Satu halaman tidak perlu menampilkan semua fitur sekaligus.
2. Kurangi padding kosong dan tinggi minimum tanpa fungsi, bukan mengecilkan semua teks. Angka antrean aktif dan QR memiliki kebutuhan ukuran tersendiri.
3. Setiap nilai berasal dari API/state aktual; loading/tidak tersedia menggunakan penjelasan atau tanda —, bukan nol/estimasi palsu.
4. Gunakan komponen existing, radius dan spacing yang konsisten. Hindari ilustrasi generatif, ornamen, gradient atau bayangan baru tanpa fungsi. Aset branding existing tidak dihapus.
5. Gunakan tema per role; jangan mengubah tema dasar untuk memadatkan satu portal.
6. Ukuran di bawah adalah **logical pixels Flutter**, bukan piksel fisik. Hormati text scaling, SafeArea, keyboard dan zoom; jangan mematikan scaling untuk menyembunyikan overflow.

## Fondasi existing

| Fondasi | Sumber | Penggunaan |
|---|---|---|
| Palet/tema dasar | `apps/client/lib/src/mobile_ui.dart`, `QueueBStyle` | Branding dan komponen umum |
| ADMIN | `admin_ui.dart`, `AdminStyle`, `AdminTable`, `AdminRowActions` | Tabel/form operasional |
| PETUGAS | `staff_ui.dart`, `staff_v4.dart` | Daftar antrean, aksi pelayanan, One-Scan |
| DOKTER | `doctor_visual.dart`, `DoctorStyle` | Monitoring read-only |
| PASIEN | `patient_ui.dart`, `patient_home.dart`, `user_profile.dart` | Mobile, booking, tiket/QR/profil |
| Public Display | `display_board.dart`, `display.dart` | Monitor TV dan TTS |
| Container umum | `widgets.dart` (`Section`), `mobile_ui.dart` (`AppCard`, `EmptyState`) | Konten terstruktur, tanpa memaksakan tinggi tetap |

Tidak ada framework/dependency baru. Theme dasar tetap cached. `QueueBStyle.operationalTextTheme` adalah skala khusus portal operasional; bukan pengganti seluruh tema aplikasi. Override per role yang sudah proporsional tetap boleh dipertahankan.

<a id="pasien-dan-login-ruang-tenang"></a>

### Palet bersama seluruh portal: Biru Periwinkle

Revisi pengguna 28 Oktober 2026 mengganti palet Ruang Tenang dengan perpaduan biru/periwinkle, lavender muda, cyan dan putih dari referensi pengguna. Layout login dikembalikan ke kartu terpusat sebelum Final Experience (baseline f8baef8), tanpa panel editorial di kiri. Struktur compact pasien, lima navigasi, booking dan QR tetap dipertahankan. Perluasan persetujuan 28 Oktober 2026 menerapkan palet yang sama ke ADMIN, PETUGAS, DOKTER dan Public Display. Acuan warna bersama adalah `queueb_palette.dart`; tema tiap role tetap memiliki skala font/layout sendiri. `patient_design.dart` tetap menjadi tema khusus pasien. [QA seluruh portal](ALL_PORTALS_BLUE_PALETTE.md). [Catatan revisi](PATIENT_BLUE_PALETTE_REVISION.md). Laporan Final Experience sebelumnya merupakan riwayat, bukan palet aktif.

| Token bersama | HEX | Fungsi |
|---|---|---|
| Primary periwinkle | #4C60CC | Aksi utama, tab aktif, fokus |
| Hero blue | #4169D5 | Kunjungan terdekat, teks putih |
| Cyan | #007CA8 | Aksen sekunder berfungsi |
| Background lavender | #F2F5FF | Kanvas aplikasi |
| Paper | #FFFFFF | Card, form, dialog |
| Ink | #172544 | Informasi utama |
| Muted | #52617A | Metadata/caption dengan kontras |
| Border | #D9E1F2 | Pemisah, outline halus |
| Soft periwinkle | #EEF1FF | Pilihan/permukaan pendukung |
| Success | #2B674B | Dilayani/selesai |
| Waiting | #825400 | Check-in/menunggu |
| Danger | #A43946 | Dibatalkan/error |

Status tetap mengikuti API; `PatientDesign.statusInk/statusSurface/statusIcon` memisahkan DIPESAN, MENUNGGU, DIPANGGIL, DILAYANI, DILEWATI, SELESAI dan DIBATALKAN dengan label + ikon + warna. Teks normal pasangan tersebut diuji minimal 4.5:1. Jangan memperlakukan urutan warna sebagai algoritma antrean.

Font Material bawaan (Roboto pada Android), tanpa font/dependency/ilustrasi baru. Ikon launcher/favicon/PWA template diganti ekspor geometris QueueB; branding in-app existing dipertahankan. Heading mobile 20–22, judul card 14–16, body 14, fakta 13, caption 11–12 dengan kontras memadai; target sentuh 44–48. Nomor tiket 30–34 dan QR mempunyai skala tersendiri. Card mengikuti isi; tipografi tidak diperkecil menggunakan FittedBox untuk memaksa muat. Spacing 4/8/12/16/24, radius input/tombol 14 dan card 20–24, elevation ringan.

Lima navigasi pasien dan focus-scroll existing dipertahankan. Pada Beranda V6, branding dan sapaan tampil sekali di dalam konten yang ikut scroll; tanpa avatar, notifikasi backlog atau app bar kedua. Halaman lain tidak mendapat identitas tambahan. Agenda hanya memfilter tanggal appointment nyata, tiket memakai proyeksi terbaru, dan informasi teknis QR tidak mendominasi tampilan. Semua modal/picker menangkap tema dari scope USER di root, bukan mengubah theme global. Shared components membaca marker pasien untuk variasi komponen; seluruh role kini mengambil warna dasar yang sama dari QueueBPalette.

### Beranda pasien V6 — dua mode

Beranda memakai tab **Ambil Antrean** (default) dan **Janji Temu** melalui TabBar/TabBarView native, mendukung ketukan, swipe sentuh kiri–kanan dan drag mouse pada Web. Tab tetap terlihat setelah header digulir. Header, pencarian dan kunjungan terdekat tetap bersama; pilihan tab/filter dan posisi scroll per daftar dipertahankan melalui state/PageStorage existing. Chip poli memiliki gestur horizontal sendiri agar menggulir chip tidak memindahkan tab. Daftar tetap memakai sliver builder, tanpa fixed height untuk seluruh kartu. Kartu dokter menggunakan kembali PatientHomeDoctor sebelum V6: foto, spesialisasi/poli, jadwal aktual dan Detail Dokter. Lima tujuan bottom navigation tidak diganti.

Aksen Beranda kembali memakai palet periwinkle bersama: primary #4C60CC, hero #4169D5, soft #EEF1FF, background #F2F5FF dan putih. Kartu kunjungan dipulihkan ke komposisi sebelum V6 (baseline de56b16), dengan identitas dokter, badge status, nomor antrean dan fakta kunjungan. Nama/status/tanggal/ruang/nomor berasal dari proyeksi REST existing; kartu hilang seluruhnya bila tidak ada kunjungan relevan. QR berupa aksi untuk workflow penerbitan existing, bukan gambar QR dekoratif pada kartu.

Revisi pengguna memisahkan kategori tampilan dari mode booking. Ambil Antrean hanya untuk layanan pendukung dengan kode PENDAFTARAN, REGISTRASI, ADMINISTRASI, APOTEK atau APOTIK yang aktif dan mendukung ANTREAN_HARIAN/HIBRIDA. Seluruh poliklinik tampil di penjelajahan Janji Temu, termasuk poli ANTREAN_HARIAN; label dan aksi tetap mengikuti mode server, sehingga poli harian tidak dipaksa menjadi appointment. Karena API belum memiliki field kategori, daftar kode eksplisit merupakan konvensi presentasi, bukan data katalog hardcoded. Nilai mode tidak dikenal tidak diasumsikan dapat dipesan. Jangan menampilkan kuota tersedia atau estimasi dari keberadaan layanan saja. Klik membuka formulir/detail existing; mutasi tetap membutuhkan konfirmasi. [Implementasi dan QA V6](PATIENT_HOME_V6.md).

### Warna dan visual operasional

`QueueBStyle` mempertahankan nama alias existing (`teal`, `darkTeal`, `navy`, `mint`) demi kompatibilitas source, tetapi nilainya kini mengacu pada primary biru, ink dan soft dari QueueBPalette. Jangan menganggap nama legacy tersebut sebagai instruksi memakai teal lama. ADMIN memakai background/soft/cyan yang sama. Panel aksi PETUGAS dan live DOKTER memakai console #1D3270 sampai #314DA3 dengan teks putih/#E6EDFF; Public Display memakai hero #4169D5. Ukuran/font/grid tidak diubah. Status success/warning/danger operasional tetap memiliki warna semantik existing; jangan menggantinya dengan satu warna dekoratif.

- Warna status selalu didampingi label/ikon, tidak menjadi satu-satunya pembeda.
- Teks biasa target kontras minimal 4.5:1; teks besar dan kontrol bermakna minimal 3:1. Periksa kombinasi nyata, bukan menganggap seluruh warna token otomatis memenuhi semua konteks.
- Radius existing: operasional umumnya 14–16; pasien/card dasar 16–20; input 10–14. Pertahankan radius antar komponen sejenis, jangan memaksakan satu radius untuk seluruh role.
- Elevation rendah, border halus; hindari tumpukan bayangan tebal. Fokus keyboard harus terlihat.

### Spacing

Skala praktis: 4, 8, 12, 16, 20, 24. Token reusable: `smallSpace=8`, `mediumSpace=12`, `space=16`. Jadikan 8/12 gap komponen, 12/16 padding card, dan 16–24 margin luar desktop. Gunakan 16 margin horizontal mobile; pada 320px boleh 12 bila konten/touch target membutuhkan ruang. Jangan menetapkan tinggi card demi menyamakan tampilan bila isi berbeda.

## Skala portal operasional — ADMIN, PETUGAS, DOKTER

| Elemen | Baseline |
|---|---|
| Heading halaman | 18–22, semibold/bold |
| Heading section | 15–17 |
| Judul card | 14–16 |
| Body | 13–14 |
| Teks tabel/list | 12–14 |
| Metadata/timestamp/helper | 11–12, kontras cukup |
| Input/button | 13–14 |
| Header | 52–60; token baseline 56 |
| Baris tabel sederhana | 40–48, bertambah bila multiline/text scaling |
| Padding card | 12–16 |
| Gap | 8–12 |
| Margin halaman | 16–24 |

Statistik penting dapat lebih besar dari body bila membantu pemindaian cepat. Font 11–12 tidak dipakai untuk instruksi kritis atau pesan error panjang. Override operasional existing seperti metadata PETUGAS 11 dan label 12 boleh dipertahankan jika terbaca dan diuji; jangan mengubah semua angka hanya demi seragam.

`operationalTextTheme` menetapkan headline 20/22, title 14/15/17, body 12/13/14 dan label 11/12/13. Ini mencegah fallback headline Material 24–32 masuk ke card operasional. Ukuran eksplisit pada halaman lama tidak otomatis berubah; koreksi per halaman setelah ada bukti proporsi bermasalah.

### Dokter ADMIN dan agenda praktik

Daftar Dokter memakai baris 64 logical px (bertambah mengikuti text scaling), identitas dan akun ringkas serta 6 baris per halaman; opsi jumlah baris dan seluruh menu aksi tetap tersedia. Bantuan alur profil/poliklinik/akun dipindahkan ke tombol Panduan dokter agar tidak menjadi banner permanen.

Jadwal Praktik memakai agenda per tanggal dan ruang, dengan 6 sesi per halaman, jam sebagai jangkar visual, pemilih tanggal, navigasi tanggal tersedia, Hari ini dan Semua tanggal. Semua tanggal tetap dapat diakses; bukan pemotongan data API. Pencarian/filter lama dan handler mutasi dipertahankan. Layar kecil/teks besar membungkus secara alami. [QA compact management](ADMIN_DOCTOR_PRACTICE_COMPACT.md).

## Skala mobile — PASIEN

| Elemen | Baseline |
|---|---|
| Heading | 18–22 |
| Judul card | 14–16 |
| Body | 14–16 |
| Caption | 12–13 bila terbaca |
| Padding horizontal | 16 |
| Gap | 8–12 |
| Target sentuh | sekitar 44–48, termasuk area hit |

Gunakan alur progresif pilih dokter/poli → jadwal → konfirmasi → tiket. QR harus utuh dengan quiet zone, dapat dibaca scanner, dan tidak diperkecil demi memuat lebih banyak konten. Tanggal, status dan lokasi harus jelas. Konten panjang boleh scroll; tombol utama jangan tertutup keyboard, navbar atau FAB. Jangan membawa font tabel desktop 12px ke seluruh body pasien.

## Standar Public Display

Public Display **tidak memakai skala dashboard desktop**. Pertahankan skala responsive di `DisplayBoard`: nomor panggilan sangat besar, nama poli/jam jelas, lokasi tujuan kuat, daftar pasien terbaca, kontras tinggi. Nomor daftar tidak boleh terpotong menjadi ellipsis; gunakan ruang kolom yang cukup dan scale-down untuk kode panjang.

- Monitor 1280×720, 1366×768, 1440×900, 1920×1080: tanpa scroll atau overflow.
- Kapasitas list mengikuti tinggi; daftar panjang memakai auto-pagination existing, bukan memperkecil semua teks atau membuat scroll.
- Empty/loading/reconnect/rejected harus dibedakan. Akses ditolak tidak mempertahankan snapshot sensitif.
- REST snapshot adalah sumber kebenaran; namespace /display, deduplikasi peristiwaId, pairing per perangkat, kebijakan nama server dan TTS existing tidak berubah karena pekerjaan visual.
- Kontrol audio/fullscreen/perangkat tidak mendominasi layar; tetap dapat ditemukan dan dioperasikan.
- Preview sempit boleh memakai skala monitor; bukan UI operasional ponsel baru. Uji speaker/id-ID di perangkat fisik sebelum pemasangan.

## Standar komponen

| Komponen | Aturan |
|---|---|
| AppBar/header | Tinggi operasional 56; brand/identitas secukupnya, nama panjang ellipsis + akses profil. Pada sempit sederhanakan isi, jangan menumpuk semua tombol. |
| Sidebar | Pertahankan item/group existing, indikator aktif jelas, label singkat. Beralih Drawer sesuai breakpoint existing; jangan menambah sidebar pada DOKTER/PETUGAS. |
| Card/Section | Padding 12–16, judul 14–17, gap konten 8–12, tinggi mengikuti isi. Gunakan Section/AppCard existing; bukan panel kosong dengan minHeight besar. |
| Tabel | 40–48 untuk baris sederhana, header 40–44, text 12–14. Izinkan tinggi adaptif untuk multiline/scaling. Pagination existing, kolom numerik selaras, status jelas. Scroll horizontal **terbatas di tabel** boleh untuk kolom yang benar-benar banyak; jangan membuat root halaman melebar. |
| Dropdown Aksi | Gunakan `AdminRowActions` existing; ikon 18–20, tooltip/label jelas, aksi berbahaya merah dan konfirmasi. Jangan menambah/menghilangkan aksi atau mengubah arti Nonaktifkan/Hapus. |
| Search | Lebar fleksibel, ikon 18–20, hint singkat sesuai field yang benar-benar dicari. Jangan menjanjikan pencarian medis/data yang tidak didukung API. |
| Filter | Dekat pencarian, Wrap/stack pada sempit, nilai pilihan terlihat. Pertahankan filter setelah refresh/mutasi bila state existing mendukung. |
| TextField/dropdown | Desktop padding horizontal 12/vertical 10; mobile tetap target nyaman. Label persisten, helper/error dapat membungkus; input kode/token tidak dicetak pada log. |
| Button | Primer untuk aksi utama, outline/text untuk sekunder. Tinggi visual desktop sekitar 36–44, target hit/touch 44–48 bila digunakan dengan sentuhan. Jangan paksa label panjang satu baris pada lebar sempit; pindahkan/stack tombol. |
| Dialog | Lebar terbatas sesuai formulir, judul/isi/action jelas. Isi panjang dapat scroll dalam viewport, tombol tidak tertutup keyboard. Pertahankan validasi dan konfirmasi. |
| Bottom sheet | Mobile: SafeArea dan inset keyboard, isi dapat scroll, tinggi berdasarkan kebutuhan. Pilihan utama jelas dan tombol tutup dapat dijangkau. |
| Status badge | Teks + warna/ikon, padat, label konsisten dengan status existing. Jangan mengubah state machine melalui label visual. |
| Avatar | Header operasional sekitar 28–36; mobile 36–48; identitas card 40–64 bila perlu. Fallback inisial/icon; jangan menganggap ilustrasi sebagai foto akun. |
| Empty state | Pesan singkat + aksi bila tersedia, ikon kecil 28–36, padding 12. Hindari ilustrasi besar atau vertical spacer berlebihan pada dashboard. |
| Loading | Indikator sesuai area data; pertahankan data valid terakhir bila kontrak mengizinkan. Hindari spinner yang mengunci seluruh layar pada refresh ringan. |
| Error/reconnect | Pesan spesifik + retry, teks membungkus, jangan hanya warna. Loading/kosong/akses ditolak dibedakan; jangan bocorkan credential/detail internal. |
| FAB | Hanya bila ada aksi primer nyata; jangan menutup baris terakhir, tombol batal, atau bottom navigation. Beri bottom inset konten yang cukup. |
| Bottom Navigation | Gunakan `PatientBottomNavigation` existing (60 ditambah SafeArea), lima tujuan pasien: Beranda, Reservasi, Tiket Saya, Janji Temu, Profil, label terbaca/ikon jelas. Jangan menaikkan navbar dasar global yang berdampak pada semua role. |

## Perbedaan lima portal

- **ADMIN:** kepadatan tabel, CRUD, search/filter/form. Informasi nama/status utama; identifier teknis tidak menjadi input manual bila ada pilihan data.
- **PETUGAS:** antrean dan aksi pelayanan adalah fokus. Panel pelayanan cukup dominan; QR One-Scan dibuka lewat FloatingActionButton.extended Pindai QR, tanpa panel bawah/input manual. Sisakan inset bawah agar FAB tidak menutupi aksi terakhir; dokter terjadwal dan status antrean tetap terlihat. Urutan/prioritas mengikuti server.
- **DOKTER:** monitoring jadwal/appointment/antrean read-only. Jangan menambahkan aksi pelayanan PETUGAS, rekam medis, atau data pasien yang tidak tersedia.
- **PASIEN:** mobile-first, navigasi sederhana, booking/reservasi/tiket/QR. Jangan mengorbankan touch target/teks demi kepadatan desktop.
- **PUBLIC DISPLAY:** informasi jarak jauh, tanpa scroll, pengumuman aktual, privasi dan keamanan perangkat.

Login memakai kartu terpusat pada desktop dan mobile sesuai revisi 28 Oktober 2026. Lebar maksimum 420, scroll ketika viewport/keyboard/text scale membutuhkannya. Tidak ada panel editorial baru. Jangan mengubahnya saat memadatkan portal operasional lain.

## Audit fondasi dan keputusan tahap ini

| Temuan | Koreksi terarah |
|---|---|
| ADMIN/DOKTER mewarisi typography Material dasar; title/headline dapat lebih besar daripada kebutuhan card | Pasang `operationalTextTheme` khusus tema operasional. PETUGAS mengambil baseline sama sambil mempertahankan override compact existing. |
| Section umum padding 20, title-body gap 16, gap action 20 | Padding 16, title-body gap 12, gap action 12/runSpacing 8. Tidak mengubah isi, callback, atau mode scroll. |
| EmptyState umum padding vertikal 20, ikon 36, gap 12 | Padding 12, ikon 32, gap 8. Pesan/aksi tetap. |
| AdminTable sudah memakai baris 44–48 dan padding tabel compact | Pertahankan; jangan mengecilkan ulang. |
| Pasien sudah memiliki navbar 60 terpisah; input/tombol dasar 48 dan padding 16 | Pertahankan; jangan ubah global demi dashboard. |
| Public Display baru selesai dipoles dan mempunyai skala sendiri | Bersihkan komentar saja; tidak mengecilkan nomor, row, kartu ruang, atau kontrol. |
| Revisi compact DOKTER lokal belum di-commit | Pertahankan; commit tugas ini hanya komentar dan wiring tema yang disetujui, tanpa membawa revisi layout lokal. |

Ini pembenahan fondasi, bukan klaim semua halaman/hardcoded style langsung seragam. Polishing selanjutnya harus berbasis masalah nyata dan memakai dokumen ini.

## Responsive, aksesibilitas dan performa

Wajib periksa desktop **1280×720, 1366×768, 1440×900, 1920×1080**; mobile **320×568, 360×800, 390×844, 412×915**. Uji text scale minimal 1.0 dan skenario teks diperbesar pada komponen yang berubah.

- Tidak ada RenderFlex overflow, tabrakan kontrol atau root horizontal overflow. Konten panjang scroll wajar; tabel dapat scroll terkontrol, TV tetap tanpa scroll.
- Gunakan Expanded/Flexible/Wrap dan constraints yang sesuai; jangan menyembunyikan error dengan clipping atau mematikan text scaling.
- Label panjang, error jaringan, empty/loading, data padat dan status aktual perlu diuji, bukan hanya screenshot ideal.
- Fokus keyboard, semantics/tooltip pada ikon, urutan navigasi dan kontras tetap jelas. Jangan hanya menggunakan hover untuk aksi penting.
- Reuse ThemeData/tokens cached. Jangan mengganti daftar berpaginasi dengan seluruh row sekaligus, memperbesar image decode tanpa perlu, atau membocorkan timer/listener/controller.
- Pertahankan coalescing REST snapshot, reconnect, deduplikasi TTS dan disposal existing. Optimasi ukuran aplikasi dan realtime tidak boleh dikorbankan untuk dekorasi.

## Workflow dan definition of done

1. Baca panduan ini, kontrak API bila relevan, dan pemilik komponen yang akan diubah.
2. Periksa Git serta pekerjaan lokal; stage hanya file/hunk terkait. Ikuti workflow Git yang disetujui pengguna, bukan membuat branch/PR/merge otomatis.
3. Jelaskan masalah ukuran yang terbukti; perubahan harus sekecil yang menyelesaikannya. Jangan mengubah API/backend/database/RBAC untuk perapihan visual.
4. Jalankan format file berubah, flutter analyze, tes layout/interaksi/regresi relevan dan build Web. Catat viewport, hasil aktual, serta batas hardware/browser yang belum diuji.
5. Periksa diff, data/screenshot sintetis dan keamanan file; jangan commit .env, profil browser, credential, backup atau perubahan lokal tak terkait.
6. Setelah push yang disetujui, periksa CI pada SHA yang tepat. Screenshot dan test tidak menggantikan pemeriksaan readability manusia.

Pemeliharaan panduan: perubahan token harus disertai alasan, scope role, dan verifikasi. Tidak memakai skor desain generik atau dependensi panduan eksternal.
