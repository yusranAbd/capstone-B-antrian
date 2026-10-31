# Patient Home V8 — Realistic Ticket UI & Navigation

Tanggal: 31 Oktober 2026, WIT. Baseline source `434a8c006f60dfa3bb7b4b37462eae367bd870e5`.

Status implementasi: **selesai; seluruh gate lokal PASS**. Identitas commit dan hasil CI exact SHA disampaikan pada receipt penutupan dan jawaban akhir, setelah push. Tidak ada deployment publik.

## Tujuan dan perbandingan visual

Acuan utama adalah screenshot pengguna **QueueB Healthcare Queue App.png**, bersama arahan V8 yang secara eksplisit menggantikan desain Beranda dan lima menu publik sebelumnya. Scope hanya Home, navigasi dan tujuan Riwayat/Informasi PASIEN. Tema global, ADMIN, PETUGAS, DOKTER dan Public Display tidak didesain ulang.

| V7 | V8 |
|---|---|
| AppBar sapaan/nama | Branding QueueB existing di kiri, notifikasi/avatar di kanan; sapaan/nama di greeting |
| Heading/search biasa | Greeting dengan visual gedung halus dan search putih rounded |
| Kunjungan blue-filled dengan QR langsung | Compact white visit; detail tetap membuka dialog tiket existing, QR diterbitkan lewat aksi eksplisit di detail |
| Kartu layanan rounded, panel statistik | Kartu kertas native, empat cutout, perforasi dan stub kanan |
| Lima menu publik | Empat menu Beranda/Riwayat/Informasi/Profil; route legacy tetap |

Logo tetap `QueueBBrand(compact: true)`, bukan identitas baru yang digambar ulang dari screenshot. Visual gedung adalah asset repository existing `assets/illustrations/patient_hospital.png`, bukan foto fasilitas yang diklaim nyata atau screenshot penuh. Asset sudah tracked; `pubspec.yaml` hanya menambahkan registrasi satu asset ini. Tidak ada dependency baru, perubahan lockfile, unduhan atau gambar generatif baru.

## Header, sapaan, search dan kunjungan

`PatientHomeAppBarV8` memakai branding existing, tombol Notifikasi dan `AccountAvatar` akun aktif. Tidak ada badge unread palsu: data notifikasi belum tersedia, sehingga dialog menjelaskan keterbatasan dan mengarahkan pasien ke Riwayat. Avatar tetap membuka Profil existing. Header dibatasi maxWidth 680 dan tingginya mengikuti text scaling.

`PatientHomeWelcomeV8` membaca nama authenticated dari owner existing, menampilkan sapaan berdasarkan jam perangkat ketika widget dibangun, tanpa polling/timer baru. Nama panjang dapat membungkus hingga tiga baris dengan semantics teks utuh. Gambar gedung di kanan memakai opacity .24, excluded semantics/pointer, decode dibatasi cacheWidth 640. Placeholder search menjadi **Cari layanan, poli, atau informasi...**; callback/query/filter layanan/dokter existing tidak diubah.

Sapaan dan AppBar mendengarkan QueueApi existing secara lokal agar perubahan nama profil pada ID akun yang sama langsung terlihat. Tes awal membuktikan nama sempat tertahan sebelum binding lokal ini diperbaiki; tes final memeriksa nama baru, identitas owner yang sama dan nol GET tambahan. Perubahan antrean hanya membangun ulang kartu, bukan greeting.

`PatientHomeVisitV8` memakai selector `nearestHomeTicket` existing serta relasi appointment dari private snapshot. Kartu putih berisi kalender, layanan, tanggal/waktu dan status reservasi aktual. TIME slot tetap diformat melalui AppConfig zona pelayanan. Loading, gagal dimuat dan tidak ada kunjungan dibedakan. Aksi **Lihat Detail** tidak menerbitkan QR otomatis. Dialog `_TicketDialog`, validasi hari/status, ownership, deduplikasi dan QR expiry tetap existing. Saat penerbitan manual berjalan, semantics indikator menyebut **Memuat QR check-in**, bukan Memuat tiket.

## Bentuk tiket dan perforasi

`PatientServiceTicketV8` memakai `PatientTicketClipper` dan `PhysicalShape` sebagai satu kontur kertas untuk shadow/clip/hit testing. RRect radius 16 dikurangi empat lingkaran radius 7: tengah sisi kiri/kanan, serta ujung atas/bawah garis perforasi pada batas stub. Cutout merupakan lubang nyata, bukan lingkaran warna background yang menutupi isi.

`_TicketPerforation` menggambar garis vertikal dash 4/gap 4 dan border lembut pada kontur yang sama. Shadow elevation 3, focus 5; tidak ada blur filter/backdrop, gambar tiket raster, tumpukan kertas atau loop animation. Focus border tetap jelas. InkWell existing hanya mempunyai satu onTap dan highlight callback PressMotion; chevron bukan tombol kedua.

Main section memakai ikon, nama layanan, jam operasional/fallback petugas, nomor pribadi dan currently-serving yang terpisah. Stub memakai tint lembut, ikon pengguna, angka **total check-in hari pelayanan**, label Antrean dan chevron. Tooltip dan semantics menjelaskan definisi **Total check-in hari ini**; tidak menggantinya dengan jumlah menunggu atau selisih nomor.

## Warna dan responsivitas

Palet lokal V8: primary/pendaftaran biru `#0968D8`, apotek teal `#087C70`, kasir oranye `#B95420`, laboratorium coral `#B55149`, radiologi ungu `#7952B5`, rekam medis emerald `#087F64`. Permukaan utama putih, stub tint sekitar 7%, ikon sekitar 12%; tidak ada perubahan warna/typography global portal lain.

Home maxWidth 680; list tetap lazy, urutan enam kode prioritas dan alias existing dipertahankan tanpa membuat katalog runtime. Stub sekitar 23% lebar, dibatasi 76–108 logical px. Pada text scale besar dua field nomor beralih ke susunan vertikal; teks/nomor panjang membungkus, bukan diperkecil global. Row content/stub memakai intrinsic height pada kartu layanan yang terbatas, bukan pada daftar antrean panjang; transform/value animation tidak mengubah owner halaman per frame. Biaya render harus dinilai melalui QA/profiling aktual, bukan dianggap otomatis 60 FPS.

QA widget lulus pada lebar 320/360/390/430/768/1366 dan text scale 1.0/1.3/1.5/2.0 untuk kartu, termasuk nama layanan panjang, nomor panjang dan metadata unavailable. Header/kunjungan/navbar diuji terpisah pada lebar 320/360/390/430 dengan scale 1.3/1.5/2.0 dan nama akun panjang. Nama petugas nyata tidak diuji karena kontrak USER tidak menyediakannya. Label navbar mengikuti kebijakan native NavigationBar existing; tidak ada override yang mematikan text scaling global. Aksi detail memakai Flexible agar label tetap dapat membungkus pada teks besar.

## Binding data dan batas kontrak

| Elemen | Sumber/aturan |
|---|---|
| Nomor Antreanmu | `homeServiceTicket` terhadap `/tiket/saya`, ID layanan/hari/account aktif; bukan row antrean pasien lain |
| Sedang dilayani | Read model V7.1 `sedangDilayani[]`, collection per loket; tidak menganggap CALL sebagai START |
| Angka stub | `checkedInTotal` / `totalCheckIn` authoritative dari `/layanan/antrean` |
| Freshness | PatientQueueView existing; offline mempertahankan data terakhir dengan keterangan, null bukan nol |
| Jam | GET `/jadwal-layanan` existing untuk USER, layanan aktif/hari yang cocok; DB TIME diambil sebagai wall clock, tidak digeser zona lagi |
| Nama petugas | **Belum tersedia bagi USER** pada kontrak existing; tidak membaca endpoint penugasan terlarang dan tidak menyalin nama contoh screenshot |

PatientRepository/OverviewCubit existing tetap satu owner. Katalog ditambah **satu GET `/jadwal-layanan`** pada initial/catalog reconcile, bukan request per card. PatientSnapshot menambah getter read-only serviceHours. Error jam opsional dicatat terpisah sehingga kunjungan/tiket valid tetap bisa dibaca; Informasi memberi pesan dan refresh eksplisit. Tidak ada repository/Cubit/socket kedua, local total++, perubahan check-in/booking/Queue Engine/API/RBAC atau schema/migration.

Jam kosong yang sudah terverifikasi menjadi **Tidak ada jadwal hari ini**; error/belum tersedia menjadi **Jam belum tersedia**. Matching schedule dengan format jam invalid tidak diperlakukan sebagai jadwal kosong yang sah. Subtitle petugas memakai fallback jujur. Ini batas data yang disengaja; tidak memalsukan employee assignment agar sama dengan gambar.

## Empat menu dan migrasi route

| Menu/tujuan | Branch | Domain tab existing | URL |
|---|---:|---:|---|
| Beranda | 0 | 0 | `/patient` |
| Riwayat | 1 | 2 | `/patient/reservations` |
| Informasi | 5 | 6 | `/patient/information` |
| Profil | 4 | 5 | `/patient/profile` |
| Tiket legacy (internal/deep link) | 2 | 1 | `/patient/tickets`, `/:ticketId` |
| Agenda legacy (internal/deep link) | 3 | 3 | `/patient/appointments` |

`patient_navigation.dart` memetakan empat menu ke branch secara eksplisit. Lima branch lama tetap pada indeks yang sama; hanya Informasi ditambahkan di akhir. Booking `/patient/reservations/new`, dokter `/patient/reservations/doctors/:doctorId`, detail tiket dan Motion V2 child transitions tetap. Root/session/overlay owner, navigator keys per account, redirect dan validasi URL tetap existing; policy hanya mengenali lokasi USER Informasi yang baru.

Riwayat memakai ReservationList dan proyeksi `patientReservations` existing yang menggabungkan reservasi/appointment dan tiket pribadi, termasuk kunjungan mendatang/terminal. Search/status filter/cancel/action booking existing dipertahankan. Detail serta QR tetap tersedia melalui flow yang sah. Header list menjadi Riwayat; tidak menghapus domain Tiket Saya atau Janji Temu. Fitur Janji Temu tetap pada segmented control Beranda.

Informasi adalah halaman read-only dengan katalog layanan aktif, deskripsi server, mode reservasi dan jam layanan aktual. Error/loading/empty/refresh tersedia; tidak ada CMS, berita, saran klinis atau informasi fasilitas yang dikarang. Profil, logout, avatar dan session behavior memakai halaman existing.

## Smart scroll dan Motion V2

PatientScrollShell existing tetap satu scroll/chrome owner: input vertikal pengguna, threshold 20 px, 260 ms, SafeArea, pointer/focus exclusion ketika tersembunyi. Home mode menjadi bagian pageKey restore sehingga perubahan segmented control menampilkan chrome kembali; tidak mengganti TabController atau navigation stack. Posisi scroll/query/filter tetap pada owner/PageStorage existing.

PressMotion .985/120/160 ms, ValueMotion authoritative 280 ms/highlight 600 ms, bounded ContentEntrance pertama yang terlihat, dan route transitions V2 dipakai ulang. Tidak ada animasi baru yang menambah API/socket atau replay karena duplicate snapshot. Reduced Motion mengikuti MediaQuery existing. Outgoing angka dikeluarkan dari semantics; kartu mempunyai satu action semantics dengan angka/data terbaru.

## Aksesibilitas dan pengujian bertahap

Semantics membedakan nomor pribadi, pelayanan aktif, total check-in, waiting/freshness. Tidak ada nama pasien lain. Focus keyboard/Enter, satu callback, hit testing lubang kertas, fallback unavailable dan koreksi/duplicate nilai diuji. Native navigation/icon target tetap dapat dioperasikan dengan keyboard/touch.

Evidence lokal: `apps/client/build/home-v8/` (ignored). Failed attempts dipertahankan. Tes lama diperbarui terhadap empat menu dan akses legacy melalui router; pemeriksaan jumlah POST, tiket ID, account isolation, readonly detail, expiry dan deduplikasi QR tetap. Pengujian menemukan overflow label Lihat Detail pada text scale 1.5; diperbaiki dengan Flexible, tanpa mengecilkan teks. Label QR loading juga disesuaikan terhadap aksi manual yang nyata.

## Hasil QA / build / browser

Semua gate lokal di bawah telah dijalankan dan diverifikasi:

| Gate | Hasil aktual |
|---|---|
| Format/analyze | File Dart tugas diformat; `analyze-final-r3.log` PASS tanpa issue |
| Flutter penuh | **1.335 PASS, 1 skip**, `flutter-full-r2.log`, 5 menit 43 detik |
| Tooling guard | 11 PASS / 0 FAIL |
| Home browser | PASS normal + Reduced Motion, lebar 320/360/390/430/768/1366 |
| Enam kartu | Semua membuka route booking existing; 0 booking/QR POST otomatis |
| Navigasi/chrome | Riwayat, Informasi, Profil, logout, segment Janji Temu, Back dari booking, scroll down/up, programmatic/small-scroll ignore PASS |
| Owner browser Home | Satu socket per sesi; satu closure setelah logout; 0 runtime/console error dan 0 HTTP 5xx |
| Realtime | 7/7 PASS; actual QR decoder dengan kamera Y4M terkontrol, CALL/START terpisah, duplicate/reconnect/account isolation |
| E2E akhir | **13/13 PASS**, `final-e2e-r2/browser-execution.json`, 229 detik; booking, QR pasien lewat UI, kamera petugas, enam perintah antrean, kunjungan selesai, display, reconnect/revoke |
| Routing browser | **16/16 PASS**, empat menu + legacy URLs, Back/Forward, cold link, auth/role, missing ticket, unsafe return dan malformed URL |
| Error akhir | 0 HTTP 5xx, 0 P2028, 0 pending request, 0 runtime/response-observer error; RAM bebas minimum pada run E2E 678 MiB |
| Web release | PASS, `web-preview-final.log`, 98,6 detik, source production terakhir; asset gedung terbundel |
| Android debug | PASS, `apk-debug.log`, assembleDebug 110,0 detik; APK di `build/app/outputs/flutter-apk/app-debug.apk` |
| API build | PASS untuk menjalankan harness; source backend tidak berubah |
| Integritas DB | 17 tabel × development/test = **34 fingerprint identik** terhadap baseline sebelum edit; tidak ada delta development V8 baru |

Satu skip Flutter adalah `live_integration_test.dart`, yang mensyaratkan runner/fixture tervalidasi. Ini tidak diklaim sebagai tes live yang lulus lewat `flutter test` biasa. Bukti backend nyata diperoleh dari browser Home, tujuh skenario realtime dan tiga belas skenario E2E di atas. Pengujian native Back melalui framework `handlePopRoute` dan framework-handles-Back lulus; tidak ada klaim Android Back di perangkat fisik.

Run Flutter penuh pertama: 1.329 PASS, 1 skip, 6 FAIL karena ekspektasi UI lama (empat tipe kartu V7, satu tipe greeting lama, satu subtitle lama). Tes disesuaikan ke komponen V8; assertion jumlah POST, owner, source ID, status, expiry dan keamanan sesi dipertahankan. Seluruh suite kemudian dijalankan ulang dan lulus, bukan hanya enam tes tersebut.

Run Home pertama gagal pada locator label brand, run kedua pada locator heading Informasi: Flutter mengekspos brand sebagai teks dan menggabungkan heading/deskripsi Informasi dalam group. Snapshot semantics dan screenshot membuktikan halaman benar. Locator diperbaiki tanpa perubahan production. Run ketiga (`home-r3`, `home-ledger-r3`) lulus kedua mode. Tidak menyembunyikan failed attempts.

Run E2E pertama berhenti pada locator QR: POST manual sudah mendapat 201, tetapi `qr_flutter` mengekspos label QR sebagai text semantics. Source package diperiksa; locator menerima teks atau aria-label yang sama, tanpa mengganti assertion angka/request. Run kedua lulus: detail tidak membuat QR otomatis, satu aksi menerbitkan tepat satu POST, QR tampil, lalu payload dari response UI itu dipakai kamera petugas. Tidak ada perubahan backend/timeout untuk mengatasi kegagalan ini. Semua percobaan menjaga 13 row baseline test dan menyisakan nol fixture baru.

Perintah build memakai `lib/main.dart`, `API_BASE_URL=http://127.0.0.1:3001/api/v1` dan `SERVICE_TIME_ZONE=Asia/Jakarta`. APK adalah artefak debug QA, bukan bukti instalasi/runtime perangkat atau build release produksi. Gradle dibatasi heap 2 GiB, dua worker, tanpa parallel build. Warning existing Wasm dry-run (`flutter_tts`/socket), KGP `flutter_tts` dan Java native access tetap tercatat; tidak ada upgrade dependency dalam tugas ini dan tidak ada klaim build Wasm.

### Review screenshot terhadap referensi

Screenshot compiled Web telah diperiksa secara visual, bukan hanya widget tree. Set enam layanan dan fallback awal ada di `home-r3/browser-after/home-normal-{360,390,430,1366}.png`; versi Reduced Motion juga tersedia. Data pribadi/serving berbeda ada di `realtime/home-v8-live-{360,390,430,1366}.png`. Semua path relatif terhadap evidence lokal ignored `apps/client/build/home-v8/`, tidak berisi identitas pasien development.

Header/logo existing, sapaan, gedung kanan, search putih, kunjungan putih, segment biru, empat notches, perforasi, stub tinted dan empat menu mengikuti komposisi referensi. Main/stub tidak melebar penuh di desktop: maxWidth 680. Pada screenshot realtime nomor pribadi **PEN-002**, serving **PEN-001**, stub **1** adalah hasil reservasi/check-in fixture terisolasi yang benar-benar dilakukan, bukan nilai yang disisipkan ke UI. Kedua nomor tetap terbaca dan perforasi tidak memotong isi pada empat ukuran tersebut. Screenshot awal dapat menunjukkan focus/hover tint dari pointer login; desktop memperlihatkan permukaan putih saat pointer di luar kartu.

Perbedaan yang disengaja: logo tetap identitas QueueB repository; gedung memakai asset existing alih-alih foto contoh; petugas belum tersedia; tanggal, jam, jumlah layanan, status dan nomor mengikuti server. Kunjungan walk-in hanya menyebut tanggal jika tidak ada slot waktu; tidak menambahkan 09.00 dari gambar. Antrean stub berarti total check-in hari pelayanan, sehingga boleh berbeda dari nomor pribadi/serving/jumlah menunggu.

### Batas pengukuran performa

Profil browser 1.200 ms berbasis requestAnimationFrame di sekitar aksi, bukan Flutter raster timeline atau benchmark lintas perangkat. Run Home lulus secara fungsional tetapi masih menunjukkan jank: normal idle p95 16,7 ms, scroll p95 33,4 ms/max 49,9 ms, card route p95 33,4 ms/max 133,3 ms. Reduced Motion mengurangi efek; tidak menjamin menghapus semua delay host. Realtime authoritative check-in pada run ini p95 16,8 ms/max 16,9 ms. Tidak menyatakan stabil 60 FPS, tidak menyimpulkan state management sebagai satu-satunya penyebab, dan tidak membandingkan performa V7/V8 tanpa benchmark setara.

Browser memakai fresh headless Playwright dengan app compiled, server localhost test dan fixture unik guarded `127.0.0.1:5433/capstone_antrean_test`. Tidak mengendalikan existing Chrome. Tidak ada seed/reset/migration atau mutation development. Kamera/Web Speech terkontrol bukan bukti perangkat fisik. Build/Chrome/regresi berat dijalankan serial pada host RAM 8 GiB.

## Git, integritas dan risiko tersisa

Baseline Git `main` sinkron origin pada `434a8c0`; preflight fetch akhir tetap 0 ahead / 0 behind. 30 status entries historis disimpan sebelum edit dan tetap terjaga. Enam file historis dilindungi: README, doctor_dashboard, doctor_visual, doctor_visual_refresh_test, LOCAL_INSTALLATION_GUIDE, GO_ROUTER_MIGRATION_AUDIT_R0. Keenam hash dan lockfile tetap identik. Pubspec diverifikasi persis sama dengan baseline setelah satu baris registrasi asset existing dikeluarkan dari perbandingan; dependency tidak berubah. Manifest tugas berisi 41 file presentation, routing, shared catalog read, tes, browser tooling dan dokumentasi; tidak ada path backend.

Baseline read-only 17 tabel × dua database diambil sebelum source diubah. Checkpoint setelah Home, realtime dan E2E akhir semuanya identik, termasuk sesi. Tidak ada delta V8 baru yang membutuhkan pengecualian. Pengecualian sesi Motion V2 tidak dianggap berlaku untuk delta baru. Sesi/audit historis dan historicalStrict=FAIL tidak diubah atau dinyatakan terselesaikan oleh CI.

Penutupan Git mengikuti otorisasi pengguna: stage 41 path manifest secara eksplisit setelah gate lokal, audit staged diff/path/credential, satu commit bahasa Indonesia dan fast-forward push ke origin/main. Backup, credential, dump, evidence ignored dan perubahan historis tidak masuk. Tidak ada force push, branch/worktree/PR atau deployment. CI workflow `CI` (Flutter Checks + NestJS Checks) harus diverifikasi terhadap **SHA commit yang benar-benar didorong**, bukan run sebelumnya. Identitas commit dapat dilihat pada riwayat file ini; receipt `apps/client/build/home-v8/closure.json` dan jawaban akhir memuat SHA/run URL aktual sesudah push. Nilai rahasia tidak dicetak ke laporan.

Risiko/batas tersisa: nama petugas tidak tersedia dalam kontrak USER; asset gedung adalah ilustrasi existing; raster Android/perangkat fisik/screen reader belum diuji; jank browser dan warning plugin existing tetap terbuka. Native API/calendar/QR/business logic di luar perubahan presentation ini tetap existing. Regresi lokal memakai workspace beserta perubahan historis terlindungi; CI menguji tree commit yang dipush. Hasil visual/performa, integritas dan CI harus dibaca sesuai batas tersebut.
