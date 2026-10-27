# Portal pasien - header minimal dan focus scroll

Acuan: QUEUEB_UI_UX_GUIDELINES.md. Penyempurnaan lanjutan Patient Mobile V5, hanya Flutter PASIEN. Tidak ada perubahan API, backend, database, Queue Engine, auth, QR, realtime atau layout role lain.

## Perilaku

- Beranda hanya memiliki ikon Aktivitas tiket existing pada header 48px. Sapaan, avatar, nama pengguna dan logo tidak ditampilkan di header pasien.
- Reservasi, Tiket Saya dan Janji Temu tidak memiliki header bersama. Profil memakai judul/refresh di dalam konten yang ikut scroll; identitas dan logout tetap tersedia di halaman Profil existing.
- Scroll vertikal pengguna ke bawah menyembunyikan header Beranda dan navigasi bawah dengan fade/size transition 180ms. Scroll naik menampilkannya kembali 220ms; ruang layout dilepas, bukan menyisakan strip kosong. Scroll ke atas halaman juga memunculkan kontrol. Jika perluasan viewport membuat konten muat seluruhnya, bar otomatis dipulihkan agar tidak terjebak tanpa navigasi.
- Lima menu dan FAB existing tetap dipertahankan. Pergantian tab/tahap booking mengembalikan navigasi; filter, list dan state tidak dibuang saat animasi.
- Scroll horizontal filter dan dialog tidak memicu mode fokus. Native mengabaikan jumpTo/ensureVisible programatik; Web juga membaca update scroll karena Flutter semantics memetakan scroll DOM ke jumpTo. Gerakan kecil kurang dari 8 logical px tidak membalik animasi.
- Accessible navigation native menjaga kontrol terlihat, termasuk jika preferensi diaktifkan setelah kontrol tersembunyi. Reduced motion menonaktifkan transisi. main.dart existing selalu mengaktifkan semantics Web, sehingga accessibleNavigation tidak dapat dipakai untuk mematikan animasi Web secara global. Semantics tetap aktif; aksi aksesibel "Tampilkan navigasi pasien" dan fokus keyboard pada bar dapat menampilkan ulang kontrol.
- Shell memakai satu AnimationController yang di-dispose, tanpa timer/polling/listener tambahan per list. Body menjadi child AnimatedBuilder sehingga isi tidak dibangun ulang pada setiap frame animasi.

## Validasi

- Seluruh suite Flutter lokal: **491 PASS, 1 SKIP**. Termasuk revisi DOKTER lokal pengguna yang tidak masuk commit.
- Tes tambahan: hide/reveal pada seluruh lima tab di 320x568 dan 390x844, header hanya notifikasi di Beranda, navigasi 5 tujuan, programmatic/horizontal scroll, frame transisi antara, reduced motion, aksesibilitas dan disposal. Tes shell final 4/4 PASS termasuk toggle aksesibilitas di tengah sesi.
- Flutter analyze: 0 issue. Format file berubah bersih. Build Web release dan ARM64 diverifikasi terpisah; tidak mengklaim uji HP fisik.
- QA Chrome memakai render Flutter release dan fixture API/Socket.IO sintetis, tanpa database development atau kredensial nyata. Semantics existing tetap aktif. Chrome menguji scroll wheel turun/naik dan memakai label aksesibel untuk regresi booking, pembatalan, QR, profil, reconnect dan login ulang. Percobaan awal yang belum menyembunyikan bar dicatat sebagai kegagalan dan diperbaiki, bukan dianggap PASS.

## Bukti visual

[Laporan Chrome final](patient-focus-scroll-qa.json): seluruh 12 state PASS, 0 error runtime. Viewport 320x568, 360x800, 375x812, 390x844, 412x915 dan 768x1024 tanpa root horizontal overflow. Widget test juga memeriksa text scale 1.5. Scroll wheel diperiksa pada Beranda, Reservasi dan Profil 390/320 serta Tiket Saya 320; daftar Janji Temu fixture yang pendek tetap menampilkan navigasi. Tes widget memakai daftar panjang untuk memeriksa scroll pada seluruh lima tab.

| Halaman | Awal | Saat scroll turun |
|---|---|---|
| Beranda 390 | [Lihat](images/patient-focus-scroll/after-home-390.png) | [Lihat](images/patient-focus-scroll/scrolled-home-390.png) |
| Reservasi 390 | [Lihat](images/patient-focus-scroll/after-reservations-390.png) | [Lihat](images/patient-focus-scroll/scrolled-reservations-390.png) |
| Tiket Saya 320 | [Lihat](images/patient-focus-scroll/after-tickets-320.png) | [Lihat](images/patient-focus-scroll/scrolled-tickets-320.png) |
| Profil 390 | [Lihat](images/patient-focus-scroll/after-profile-390.png) | [Lihat](images/patient-focus-scroll/scrolled-profile-390.png) |

[Janji Temu 390](images/patient-focus-scroll/after-appointments-390.png). Perbandingan sebelum revisi ada pada screenshot Patient Mobile V5. Foto/identitas hanya ada dalam konten Profil, bukan header aplikasi. Gambar memakai fixture QA sintetis.

SHA-256 main.dart.js final: `e0198124ec74866c1d75e49b8629cc184f374e7d2bc2918e4c41ab44ff14353d`. Build Web release JavaScript memakai --no-wasm-dry-run; tidak mengklaim dukungan WASM. APK ARM64 memakai konfigurasi API emulator 10.0.2.2 dan signing debug release QA existing; bukan distribusi store. Tidak ada uji perangkat Android fisik.

## File utama

- patient_scroll_shell.dart: chrome pasien yang mengikuti scroll.
- patient.dart: memakai shell untuk seluruh tab/tahap pasien, tanpa identitas Beranda fallback.
- app.dart: header USER hanya notifikasi; role lain tetap existing.
- user_profile.dart: judul/refresh berada di dalam konten jika di-embed sebagai tab pasien; route profil role lain tidak berubah.
- Tes pasien dan runner browser: regresi header, navigasi dan fokus scroll.

Seluruh 28 file lokal awal dipertahankan dengan checksum identik. Workflow langsung main mengikuti otorisasi pengguna.

APK ARM64 final: 31.880.265 byte (30,4 MiB), SHA-256 `d3b35bc2d1ce0ed0447ba3755d318a0932620f5ab00be55c6a441c0bc04d791e`.
