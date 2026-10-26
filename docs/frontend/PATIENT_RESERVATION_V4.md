# Patient Reservation V4

Tab **Pendaftaran** kini menjadi **Reservasi Saya**, memakai identitas pengguna dan empat tujuan navigasi existing. Beranda, Tiket Saya, Janji Temu, role lain dan Public Display tetap memakai implementasinya. Tidak ada perubahan backend, endpoint, autentikasi, Queue Engine, schema atau migration.

## Implementasi

- Reservasi digabung berdasarkan **ID tiket** dari GET /tiket/saya dan GET /janji-temu. Status tiket terbaru menang atas salinan tiket di appointment. Tidak ada asumsi ID appointment sama dengan ID tiket.
- Card appointment memakai dokter/jadwal/slot historis API, dengan foto profesional dari katalog dokter jika tersedia. Card walk-in hanya memakai poliklinik, tanggal dan nomor tiket; tidak mengarang dokter, slot, umur atau rating.
- Reservasi mendatang didahulukan menurut tanggal/waktu, lalu riwayat terbaru. Search menerima dokter, spesialisasi, poliklinik, nomor dan tanggal (ISO atau label Indonesia). Filter Semua/Dipesan/Selesai/Dibatalkan tidak mengubah label CHECK_IN, MENUNGGU, DIPANGGIL, DILAYANI atau DILEWATI. Jika API kelak memberikan status appointment terpisah, labelnya tampil terpisah dari status operasional tiket.
- Pembatalan hanya tersedia untuk appointment bertiket DIPESAN. Dialog dan busy guard mencegah double-submit. POST /janji-temu/:appointmentId/batalkan existing tetap sumber keputusan. Setelah sukses atau konflik status 409, daftar dibaca ulang; tidak ada pembatalan optimistis. Filter dipertahankan dan pesan hasil digulirkan ke area terlihat.
- **Walk-in tidak diberi tombol batal** karena backend existing belum menyediakan pembatalan USER untuk jenis itu. Tidak menambahkan endpoint atau menyamakan walk-in dengan appointment.
- Buka Tiket memakai ID tiket dan dialog QR existing. QR hanya diterbitkan bila status/tanggal memenuhi kontrak existing; tiket selesai/dibatalkan membuka detail tanpa QR aktif. Tidak ada retry POST booking otomatis.
- FAB membuka bottom sheet dengan drag handle dan tiga pilihan langsung, tanpa tombol lanjut tambahan. Cari Dokter memakai katalog relasi aktif; Pilih Poliklinik memakai mode layanan existing; Jadwal Terdekat membaca slot aktual, aktif, tersedia dan belum mulai, diurutkan berdasarkan waktu.
- Sesi yang sudah berakhir tidak ditawarkan sebagai jadwal mendatang. Pembacaan slot memakai batch maksimum empat request bersamaan. Tanggal, sesi dan slot dibaca ulang melalui workflow booking existing sebelum konfirmasi; slot yang menjadi penuh tidak terpilih dan tidak dapat dikonfirmasi.
- Riwayat memakai ListView.builder dengan area FAB terpisah dari viewport daftar, sehingga tombol tidak menutupi isi kartu. Pilihan dokter/slot dibatasi sepuluh kartu per halaman lokal. Avatar profesional memakai thumbnail decoding/cache/fallback existing; tidak ada aset atau dependency baru. Controller pencarian/scroll dibersihkan saat dispose.
- Socket /patient, polling, reconnect, invalidasi REST dan kebijakan sesi existing tetap digunakan (Web memory-only, Android secure storage). Event bukan sumber status UI. Hasil pembacaan slot terlambat dibuang setelah pengguna berpindah alur.

## Validasi

Validasi source final pada 27 Oktober 2026:

| Pemeriksaan | Hasil aktual |
|---|---|
| Dart format | 84 file diperiksa, 0 perubahan format |
| Flutter analyze | PASS, 0 issue |
| Seluruh Flutter test | 387 PASS, 1 tes live opsional SKIP karena fixture live tidak diberikan |
| Khusus Reservation V4 | 18 PASS |
| Flutter Web release JavaScript | PASS |
| APK release per ABI | PASS: armeabi-v7a, arm64-v8a, x86_64 |
| APK arm64-v8a | 31.880.245 byte (sekitar 30,4 MiB) |
| APK armeabi-v7a / x86_64 | 27.897.509 / 34.354.227 byte |
| Chrome 155 release | PASS, 7 skenario, 4 viewport, 0 page error |

Browser memverifikasi QR melalui ID tiket yang benar, pembatalan terkonfirmasi server, appointment dan walk-in yang benar-benar menambah data fixture, pemilihan slot aktual, reconnect yang memicu REST baru, serta reload dan login ulang sesuai kebijakan Web memory-only. Resolusi: 360x800, 390x844, 412x915, 768x1024. Widget regression juga memeriksa geometri bahwa viewport daftar berakhir sebelum FAB, bukan sekadar menambah padding pada kartu terakhir.

Hash build Web yang diuji: `c050906b41f89f0174a083b307487b76e7e4458782ff488d64c15b1649889537`. Report JSON menyimpan hash dan waktu QA. APK release final menggunakan --split-per-abi; file build tidak masuk Git. Semua sembilan entri perubahan lokal pada checkout utama tetap identik terhadap manifest/checksum awal pekerjaan ini; backup tidak disentuh.

Backend tidak diubah, sehingga tidak ada aktivasi database maupun E2E tulis database pada pekerjaan ini. Pengujian Flutter dan Chrome memakai fixture sintetis. CI NestJS existing tetap dijalankan pada PR. QA browser menggunakan release Flutter nyata di Chrome, HTTP fixture loopback dan transport Socket.IO nyata; bukan uji akun development, backend NestJS live, atau perangkat Android fisik.

Peringatan nonblocking Android existing: plugin flutter_tts masih memakai Kotlin Gradle Plugin dan perlu penyesuaian untuk Flutter mendatang; tidak menghalangi build saat ini. Tidak melakukan upgrade dependency di luar scope.

Batas dukungan build existing: Web JavaScript release; WASM dry-run masih mengeluarkan peringatan dependency flutter_tts/socket_io_common. Android release memakai signing configuration existing untuk demo. APK dikompilasi dengan API_BASE_URL=http://10.0.2.2:3000/api/v1 (emulator lokal); deployment ke perangkat/server lain memerlukan define URL sesuai lingkungan, tanpa mengganti source. Tidak ada klaim instalasi atau kamera perangkat fisik.

## Screenshot dan QA

Seluruh nama, ID tiket dan QR pada screenshot merupakan fixture sintetis.

- [Reservasi Saya 390x844](images/reservation-v4/reservations-390x844.png)
- [Bottom sheet Buat Reservasi](images/reservation-v4/create-sheet.png)
- [Pemilihan dokter](images/reservation-v4/choose-doctor.png)
- [360x800](images/reservation-v4/reservations-360x800.png) / [412x915](images/reservation-v4/reservations-412x915.png) / [tablet](images/reservation-v4/reservations-768x1024.png)
- [Hasil browser](reservation-v4-browser-qa.json)

Runner apps/client/tool/browser-reservation-v4.cjs memakai dependensi QA existing apps/client/tool (@playwright/test) serta socket.io dari apps/api. Tetapkan NODE_PATH ke kedua direktori node_modules tersebut (dipisah titik koma pada Windows). Tetapkan QUEUEB_CANVASKIT_DIR dan QUEUEB_ROBOTO_FILE ke direktori CanvasKit/file Roboto pada cache Flutter SDK. Chrome harus tersedia.

Dari root repository, setelah build Web release dengan API_BASE_URL=http://localhost:3000/api/v1 dan SERVICE_TIME_ZONE=Asia/Jakarta:

```powershell
node -e "require('./apps/client/tool/browser-reservation-v4.cjs')({build:'apps/client/build/web',output:'tmp/reservation-v4-browser',engineRoot:process.env.QUEUEB_CANVASKIT_DIR,fontFile:process.env.QUEUEB_ROBOTO_FILE}).then(r=>console.log(JSON.stringify(r))).catch(e=>{console.error(e.message);process.exitCode=1})"
```

Runner memakai port dinamis, menyesuaikan alamat API hanya pada response JavaScript fixture (tanpa mengubah artefak di disk), dan menutup browser/server. Report gagal ditinjau dahulu sebelum dibagikan. Server pengguna localhost:5173 tidak diubah selama QA. Untuk aktivasi, gunakan checkout hasil merge lalu restart Flutter/Web dan muat ulang browser.

## File perubahan

- apps/client/lib/src/patient.dart: integrasi tab, pembatalan, pilihan jalur, pembacaan slot dan navigasi ke workflow existing.
- apps/client/lib/src/patient_reservations.dart: proyeksi reservasi, kartu, filter/search, daftar lazy, bottom sheet dan pilihan dokter.
- apps/client/test/patient_reservations_test.dart: regresi alur baru, status, concurrency UI, slot penuh/berakhir, foto dan daftar panjang.
- apps/client/test/patient_home_v3_test.dart dan ui_test.dart: penyesuaian ekspektasi tab Pendaftaran dan dialog pembatalan yang disetujui; alur lain tetap diuji.
- apps/client/tool/browser-reservation-v4.cjs: QA browser sintetis.
- Dokumen ini, report JSON dan screenshot di images/reservation-v4/.
