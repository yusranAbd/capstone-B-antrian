# Patient Home V7 — kartu layanan dan navigasi saat scroll

Tanggal: 30 Oktober 2026 (Asia/Jayapura). Baseline aktual `7c2f8b046d0345d283218b3b82169a185ea118c7` pada `main`, sama dengan origin/main saat preflight. Implementasi mengikuti permintaan Patient Home V7, gambar **Minimalist Healthcare Queue Dashboard**, [panduan UI QueueB](QUEUEB_UI_UX_GUIDELINES.md), [kontrak API](../backend/API_INTEGRATION_GUIDE.md), [ownership pasien](PATIENT_STATE_MANAGEMENT_STAGE3.md), [router](GO_ROUTER_MIGRATION_R1_R3.md), dan [motion V1](QUEUEB_MOTION_SYSTEM_V1.md). Permintaan V7 menggantikan keputusan identitas inline Home V6 untuk empat area yang diminta saja.

## 1. Desain kartu dan delta

Daftar **Beranda → Ambil Antrean** memakai kartu putih radius 20, border lembut, shadow ringan, badge ikon 48, judul/deskripsi, chevron, bentuk geometris transparan, dan panel informasi dua kolom. Tidak memakai aset gambar atau dependency baru. Deskripsi katalog dipakai bila tersedia; fallback menjelaskan kategori layanan.

Seluruh permukaan merupakan satu aksi InkWell. Header maupun panel mengarah ke pemilihan layanan/tanggal existing, tanpa POST booking atau penerbitan QR. Tidak ada tombol Pantau Live/Ambil Antrean di dalam kartu. Fokus keyboard memakai outline kontras 2px. Semantics menyatukan nama, deskripsi, nomor pribadi/fallback, ketersediaan statistik dan aksi memilih layanan.

Search bar, pertanyaan sapaan di bawah AppBar, Kunjungan Terdekat, kartu/detail tiket, mode Janji Temu, booking, QR, profil, visual lima bottom tabs, tema global dan portal lain dipertahankan. Komponen header V6 lama tetap tersedia untuk kompatibilitas, tetapi tidak dirender dalam Home aktual.

## 2. Kategori dan aksen

Kategori berasal dari kode katalog eksplisit, karena kontrak layanan belum menyediakan field kategori. Nama bebas bukan penentu.

| Kode                                    | Aksen                 | Ink yang lebih gelap  | Ikon Material              |
| --------------------------------------- | --------------------- | --------------------- | -------------------------- |
| PENDAFTARAN / REGISTRASI / ADMINISTRASI | `#10B981`             | `#047857`             | assignment_outlined        |
| APOTEK / APOTIK                         | `#3B82F6`             | `#1D4ED8`             | medication_outlined        |
| UMUM / POLI_UMUM / POLIKLINIK_UMUM      | `#8B5CF6`             | `#6D28D9`             | medical_services_outlined  |
| GIGI / POLI_GIGI / POLIKLINIK_GIGI      | `#F59E0B`             | `#92400E`             | health_and_safety_outlined |
| Lainnya                                 | PatientDesign.primary | PatientDesign.primary | local_hospital_outlined    |

Palet empat kategori mengikuti referensi; tinta gelap menjaga keterbacaan di permukaan tinted. Mapping umum/gigi tersedia di komponen presentasi tanpa memperluas eligibility Ambil Antrean: filter V6 tetap hanya layanan pendukung aktif dengan mode ANTREAN_HARIAN/HIBRIDA. Poliklinik tetap berada di penjelajahan Janji Temu existing.

## 3. Sumber nomor dan statistik

Nomor pribadi berasal dari snapshot `/tiket/saya` pada PatientRepository existing. Pemilihan memerlukan ID tiket dan nomor tidak kosong, layanan cocok, tanggal pelayanan hari ini dari AppConfig (`Asia/Jakarta`), identitas login tersedia, serta status DIPESAN/CHECK_IN/MENUNGGU/DIPANGGIL/DILAYANI/DILEWATI. Jika proyeksi mengandung penggunaId, nilainya harus cocok; bila field tersebut tidak ada, ownership mengikuti kontrak endpoint terautentikasi `/tiket/saya`.

Kartu dengan tiket sah berlabel **Nomor Antreanmu** dan **Data tiket**. Tiket terminal, tanggal/layanan/owner berbeda atau nomor kosong tidak dipakai. Tanpa tiket, tampil **Nomor antrean — / Belum ada tiket**.

Respons layanan saat ini adalah katalog, bukan snapshot antrean global. Snapshot overview pasien juga tidak menyediakan total harian, jumlah menunggu, atau nomor panggilan global. Karena itu kanan menampilkan **Total hari ini — / Belum tersedia**; tidak menganggap field bebas/angka contoh sebagai kontrak baru. Tidak memanggil queue staff atau capability Public Display. Tidak ada data dummy, hitungan dari selisih nomor, atau label Live. Socket pasien existing tidak menjamin freshness statistik global yang memang tidak dipasok.

## 4. Urutan Pendaftaran

Setelah filter/pencarian V6, lakukan stable move layanan berkode PENDAFTARAN ke awal. Jika kode utama tidak ada, gunakan alias registrasi/administrasi pertama yang benar-benar ada. Semua item lain mempertahankan urutan relatif dari respons. Tidak memutasi input, membuat layanan palsu, mengubah sort backend atau mengubah daftar Janji Temu.

## 5. AppBar personal

Home menampilkan `Selamat datang,` dan `QueueApi.user.nama`, fallback `Pasien` jika kosong. Nama panjang ellipsis satu baris; tinggi mengikuti text scaling. Branding/judul lama di header Home diganti, tanpa menghapus aset branding atau mengubah portal lain. ListenableBuilder pada identitas existing memperbarui nama saat akun berubah; tidak ada request profil tambahan untuk sapaan.

## 6. Bell dan avatar

Bell ada di kanan tanpa badge palsu. Fitur notifikasi pasien belum tersedia; ketukan membuka dialog **Notifikasi belum tersedia. Periksa status terbaru melalui Tiket Saya.** dengan tombol Tutup, bukan route/module baru. Avatar menggunakan AccountAvatar existing (cache foto milik akun aktif atau initial), tooltip **Profil pasien**, dan route `/patient/profile` existing. Tidak ada halaman profil kedua, perubahan auth, upload atau cache avatar baru.

## 7. Penanganan arah scroll

PatientScrollShell tetap menjadi owner presentasi lokal. NotificationListener menanggapi arah vertikal dari scroll pengguna. Hysteresis 12 logical pixels mencegah gerak 1–2px membalik visibility. Perubahan arah mereset akumulasi. Home hanya menerima nested list dengan PageStorageKey `home-walk-in-list` / `home-appointment-list`; horizontal swipe/strip dan nested list lain diabaikan.

Pada Web dengan Semantics aktif, scroll DOM diterjemahkan Flutter menjadi jumpTo. Bridge conditional `dart:js_interop` mengamati input wheel/touch/keyboard **isTrusted** tanpa menghentikan event atau mengubah DOM. Scroll update harus mengikuti arah input dalam jendela 450ms, atau merupakan drag/user scroll Flutter. Programmatic jump tanpa input tidak menyembunyikan navigasi. Listener dibuang saat shell dispose; native memakai stub tanpa listener browser. Tidak menambah paket web.

Bagian atas, halaman yang muat tanpa scroll, atau perubahan pageKey/tab mengembalikan kontrol. Notifikasi horizontal, dialog/noncurrent route, snapshot BLoC dan animasi router tidak menjadi sumber hide. Terdapat custom semantics action **Tampilkan navigasi pasien**; kebijakan accessibleNavigation native mempertahankan kontrol tetap terlihat.

## 8. Animasi dan reduced motion

Controller existing menggunakan 220ms untuk kedua arah, easeOutCubic saat tampil dan easeInOutCubic saat sembunyi. SizeTransition melepaskan ruang layout; ClipRect/SlideTransition mengarahkan header ke atas dan navbar ke bawah, dengan fade ringan. Tidak ada loop, bounce, page transition, blur, atau animasi seluruh daftar.

`MediaQuery.disableAnimations` langsung menetapkan nilai akhir, termasuk saat tab berubah. Saat tersembunyi penuh, bar memiliki ukuran nol serta IgnorePointer, ExcludeFocus dan ExcludeSemantics. Konten tetap mounted sebagai AnimatedBuilder.child, sehingga animasi tidak membangun ulang PatientPage/provider setiap pixel.

## 9. Router, BLoC dan lifecycle

Struktur lima StatefulShell branches, path, navigator, QueueApi, PatientRepository/PatientUpdates, Cubit overview/booking/reservasi dan subscription Socket.IO tidak berubah. Visibility bukan BLoC global, route parameter, repository, API atau auth state. Alur card memanggil callback pemilihan layanan existing; konfirmasi booking dan tanggal tetap dimiliki flow sebelumnya. Tidak mengubah backend, RBAC, Queue Engine, Prisma, migrasi atau database.

## 10. Responsive dan accessibility

Widget matrix menguji lebar 320/360/390/430/768/1366 dp dan skala teks 1.0/1.3/1.5/2.0 (24 kombinasi), nama layanan/pasien serta nomor sangat panjang, tanpa RenderFlex overflow. Nomor dapat wrap maksimal dua baris/ellipsis dengan tooltip dan label Semantics penuh. Dua kolom fleksibel, tanpa mengecilkan tema atau mematikan text scaling. Ink kategori diuji kontras minimal 4.5:1 pada permukaan tinted; kategori juga dibedakan ikon dan teks.

Keyboard Tab/Enter, outline fokus, satu aksi Semantics kartu, tooltip bell/profil, kontrol tersembunyi tanpa hitbox, ruang konten bertambah, reverse scroll, gerak kecil, posisi atas, halaman pendek, accessibleNavigation, reduced motion dan disposal diuji. Pengujian screen reader/gesture bar/perangkat fisik tetap dicatat sebagai manual QA, bukan disamakan dengan widget tests.

## 11. Hasil pengujian

Evidence lokal berada di `apps/client/build/home-v7/` (diabaikan Git; tidak berisi perubahan produk).

| Gate                                          | Hasil                                                                                                                          |
| --------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| Format Dart file berubah                      | PASS                                                                                                                           |
| Regresi awal Home V3/V6/swipe, motion, scroll | 69 PASS                                                                                                                        |
| Terarah V7 + scroll shell                     | 38 PASS                                                                                                                        |
| Flutter analyze                               | PASS, no issues                                                                                                                |
| Flutter test penuh                            | 1.196 PASS, 1 live-fixture SKIP pada suite standar                                                                             |
| Tooling observer/worker                       | 8 PASS; syntax tiga script smoke PASS                                                                                          |
| Build Web release main.dart                   | PASS, JavaScript release; API QA dan timezone eksplisit                                                                        |
| Build APK debug main.dart                     | PASS; kernel main.dart + Home V7 + scroll shell, tanpa integration entrypoint                                                  |
| Browser compiled Web normal/reduced           | PASS dua context 390×844, real wheel turun/naik, jump DOM programatis, wheel 2px, Pendaftaran, Back, avatar, tab, bell, logout |
| Console, HTTP dan lifecycle browser           | 0 pageerror, 0 console error, 0 HTTP5xx, 0 POST booking/QR; tiap context 1 socket dibuat/1 ditutup                             |
| Strict backend ledger                         | PASS, tidak ada 5xx/P2028 atau transaksi pending saat finish                                                                   |
| Database setelah browser                      | PASS: fingerprint count/hash 17 tabel × 2 DB identik dengan awal; 13 record existing test utuh, 0 fixture tertinggal           |
| Protected files/dependency                    | PASS enam SHA-256 identik; pubspec.yaml/lock byte-identical                                                                    |

Build memakai API_BASE_URL `http://127.0.0.1:3001/api/v1` dan SERVICE_TIME_ZONE `Asia/Jakarta`. Browser menjalankan aplikasi terkompilasi terhadap Nest/PostgreSQL test nyata, bukan REST/socket stub. CanvasKit CDN dilayani dari salinan build lokal dengan verifikasi engine revision yang sama. Test fixture hanya pada `127.0.0.1:5433/capstone_antrean_test`, validasi target dan cleanup ID milik run; development hanya difingerprint read-only.

Tiga percobaan harness awal berhenti pada selector (dua sapaan gabungan dalam AX group dan satu container scroll); semuanya dibersihkan dan diarsipkan, tanpa perubahan kode aplikasi. Selector final memakai role/group dan container Semantics scroll aktual. Satu kandidat sudah lulus lalu diulang untuk menambah hook console error; hanya run final dengan kedua mode dan hook console dihitung sebagai acceptance browser. Full Flutter suite dan build memakai source produk yang sama. Warning dry-run Wasm berasal dari plugin TTS/socket existing; hasil build yang diuji adalah JavaScript release, bukan klaim dukungan Wasm baru. APK tetap berhasil dengan warning Java native access dan kompatibilitas KGP flutter_tts existing; dependency tidak di-upgrade dalam tugas visual ini.

## 12. Screenshot

Screenshot nyata 390×844 yang sudah diperiksa:

- [Sebelum](images/patient-home-v7/before-390.png).
- [Sesudah](images/patient-home-v7/after-390.png).
- [Saat scroll turun, kedua bar tersembunyi](images/patient-home-v7/scroll-hidden-390.png).

Capture lengkap normal/reduced dan kondisi tersembunyi tetap di `apps/client/build/home-v7/browser-{before,after}/`. Semua nama/layanan dalam capture adalah fixture test, bukan data runtime hardcoded atau pasien nyata. Tidak ada QR atau data pasien development pada tiga gambar yang disertakan.

## 13. File berubah

- `apps/client/lib/src/patient_home_v7.dart`: kategori, stable order, seleksi tiket, kartu, AppBar.
- `apps/client/lib/src/patient_home_v6.dart`: wrapper kartu V7 dan urutan lokal, filter/mode existing tetap.
- `apps/client/lib/src/patient.dart`: wiring tiket/Header/bell/avatar dalam shell existing.
- `apps/client/lib/src/patient_scroll_shell.dart`: arah/hysteresis, slide/size, reduced/accessibility dan input cleanup.
- `apps/client/lib/src/patient_scroll_input{,_stub,_web}.dart`: conditional observer input Web.
- `apps/client/test/patient_home_v7_test.dart`: data, ordering, card, identity, matrix, owner/read/POST/navigation.
- `apps/client/test/patient_scroll_shell_test.dart`: perluasan regresi kedua bar.
- `apps/client/test/patient_home_v3_test.dart`: ekspektasi header inline V6 diganti AppBar V7.
- `apps/client/tool/browser-patient-home-v7.cjs`, `browser-smoke.cjs`, `run-live.cjs`: smoke browser terisolasi dan strict ledger gate.
- Dokumen ini dan screenshot QA terpilih.

## 14. Risiko dan manual QA

Total/menunggu/panggilan global membutuhkan kontrak data pasien resmi di tugas terpisah; V7 sengaja menampilkan ketiadaan data dengan jujur. Notification center juga belum ada. Jangan mengubah fallback menjadi angka atau Live hanya untuk menyerupai mockup.

Bridge Web menghubungkan trusted input dan scroll update berdekatan; uji lanjutan disarankan pada Safari/iOS, trackpad inertia dan screen reader Web karena pemetaan scroll engine/platform dapat berbeda. Wajib periksa TalkBack/VoiceOver, avatar foto nyata, gesture bar/keyboard dan Android Back di perangkat fisik sebelum rilis publik. APK debug build tidak sama dengan pengujian perangkat fisik. Tidak ada deployment pada tugas ini.

Fingerprint enam file/dokumen historis dan pubspec/lock diaudit sebelum stage; backup/untracked lama dipertahankan dan dikeluarkan dari cakupan commit. Origin/main diperiksa ulang setelah semua pengujian dan tetap pada baseline yang sama (0 ahead/0 behind). Direct-to-main commit/push mengikuti gate wajib yang sudah lulus; perubahan lama tidak ikut commit. Status CI harus diperiksa pada SHA hasil commit dan dilaporkan pada hasil akhir; dokumen ini tidak mengklaim CI sebelum push.
