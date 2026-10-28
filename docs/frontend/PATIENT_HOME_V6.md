# Beranda Pasien V6

Revisi 28 Oktober 2026, mengikuti referensi dua mode pengguna dan pedoman QueueB mandiri.

## Perubahan

- Satu identitas QueueB, sapaan dan nama login di konten Beranda; tidak ada avatar berulang atau notifikasi yang belum didukung.
- Greeting 20 logical px, pencarian compact, kunjungan terdekat solid teal gelap. Kartu adaptif dua area; pada layar sempit/teks besar menjadi vertikal. Foto dokter hanya bila profil terkait tersedia, tidak menambahkan dokter/slot untuk walk-in.
- Ambil Antrean sebagai default: layanan aktif ANTREAN_HARIAN/HIBRIDA dari API. Janji Temu: chip poli aktif JANJI_TEMU_DOKTER/HIBRIDA dan dokter berelasi aktif. Data tak dikenal tidak diterjemahkan menjadi kanal baru.
- Pencarian mengikuti mode, termasuk nama/spesialisasi dokter terkait pada walk-in. Semua filter poli berasal dari katalog API; dokter multi-poli dicari melalui relasi yang cocok.
- Daftar lazy melalui SliverList.builder, tidak dibatasi tiga dokter. Kontrol, search dan mode bertahan saat berganti tab. Lima navigasi dan perilaku focus-scroll tetap.
- Kartu layanan membuka selectService existing dengan kanal walk-in eksplisit (termasuk HIBRIDA). Kartu dokter membuka chooseDoctor/detail existing. Konfirmasi, validasi tanggal/kuota/slot dan POST tetap dimiliki PatientPage; tidak ada workflow booking kedua.
- Satu PatientUpdates dan RefreshGate existing. Invalidation Socket.IO memicu REST milik pasien; snapshot tiket terbaru mengungguli salinan appointment. Koneksi putus ditandai sambil mempertahankan data terakhir, tanpa mengklaim tetap realtime.
- Detail tiket read-only; tombol QR mengambil status aktual lalu meminta penerbitan dinamis existing jika sah. Tidak ada QR statis/token tersimpan dalam Beranda.

## Batas perubahan

Tidak ada perubahan backend, database, migration, Queue Engine, RBAC, pairing Public Display maupun layout role operasional. Akses seluruh fitur pasien tetap melalui lima menu dan alur reservasi existing. Pintasan Beranda lama diganti dua mode, bukan menghapus fungsi booking/riwayat.

## QA

Tool `browser-reservation-v4.cjs` dengan opsi `homeV6` memakai HTTP/Socket.IO sintetis pada server loopback; tidak membaca kredensial atau menulis database development. Fixture bukan data runtime aplikasi. Pengujian widget menutup validasi mode, pencarian, aksesibilitas, konfirmasi, QR dan pemulihan API.

| Pemeriksaan | Hasil |
|---|---|
| Format file terkait | 0 perubahan pada pemeriksaan akhir |
| Flutter analyze | 0 issue |
| Seluruh Flutter test lokal | 508 PASS, 1 SKIP |
| Regresi V6 dan sesi terarah | 32 PASS |
| Web release | PASS; hash build yang diuji tercantum di laporan browser |
| APK release ARM64 split | PASS, 30.5 MiB; arsip native hanya arm64-v8a |
| Responsive widget | 320×568, 360×800, 375×812, 390×844, 412×915; skala teks 1.5 dan kontrol V6 skala 2 |
| Chrome release | Dua mode, search, filter, detail dokter, masuk layanan tanpa POST otomatis, detail tiket dan QR dinamis |
| Mutasi dan realtime browser terisolasi | Appointment/walk-in, pembatalan, CHECK_IN, MENUNGGU, DIPANGGIL, DILEWATI, REQUEUE ke MENUNGGU, DILAYANI, SELESAI, reconnect dan login ulang |

Satu skip adalah live integration existing tanpa fixture live (`live_integration_test.dart`), bukan hasil PASS. Total lokal mencakup satu test revisi compact Dokter milik pengguna yang tetap tidak dimasukkan ke commit ini. QA browser menggunakan kontrak HTTP dan Socket.IO sintetis, bukan klaim end-to-end terhadap database NestJS nyata.

## Screenshot aktual

Render Flutter release di Chrome, bukan mockup. Nama, poli, slot dan tiket pada bukti ini merupakan fixture terisolasi. Runtime aplikasi tetap memakai API yang dikonfigurasi.

- [Ambil Antrean 390×844](images/patient-home-v6/home-walk-in-390.png)
- [Janji Temu 390×844](images/patient-home-v6/home-appointment-390.png)
- [Tanpa kunjungan](images/patient-home-v6/home-without-visit-390.png)
- [Dengan kunjungan appointment](images/patient-home-v6/home-with-visit-390.png)
- [Filter dokter](images/patient-home-v6/home-filtered-doctors-390.png)
- [Ambil Antrean 320×568](images/patient-home-v6/home-walk-in-320.png)
- [Janji Temu 320×568](images/patient-home-v6/home-appointment-320.png)
- [QR diterbitkan melalui workflow tiket](images/patient-home-v6/home-live-qr-390.png)
- [Laporan browser dan hash build](images/patient-home-v6/qa.json)

Dibanding referensi, notifikasi dan QR dekoratif di kartu sengaja tidak ditampilkan: notifikasi belum didukung, sedangkan QR harus diperoleh secara sah saat diminta. Layanan Administrasi/Apotek tidak dibuat. Ruang kosong setelah daftar pendek dibiarkan sebagai kanvas, tidak diisi data atau kartu buatan. Pada 320×568, konten panjang tetap scroll wajar dan navigasi dapat kembali melalui scroll ke atas.

## Batas validasi dan distribusi

Tidak ada klaim pengujian Android fisik. APK ARM64 adalah validasi kompilasi QA dengan URL reserved `https://api.queueb.invalid/api/v1`; tidak untuk distribusi ke pasien. Signing release existing masih memakai debug key. Gunakan URL backend terverifikasi dan signing resmi sebelum distribusi. Warning existing `flutter_tts`/Socket.IO untuk Wasm dan Kotlin tidak diselesaikan dengan upgrade dependency di luar scope.

Build APK awal bersamaan dengan tes gagal karena generated Android plugin registrant memuat `integration_test` yang tidak ada pada classpath release. Build berurutan setelah tes dan Web selesai berhasil tanpa mengubah source Android, dependency atau menjalankan clean. Jalankan build/test Flutter berurutan pada checkout yang sama untuk menghindari benturan artefak yang dibuat SDK.

## Reproduksi

Dari `apps/client`: `flutter analyze`, `flutter test`, `flutter build web --release`, kemudian `flutter build apk --release --split-per-abi --target-platform android-arm64 --dart-define=API_BASE_URL=https://api.queueb.invalid/api/v1` (QA saja), secara berurutan.

Untuk QA Chrome panggil modul `apps/client/tool/browser-reservation-v4.cjs` dengan `{ build: 'apps/client/build/web', output: 'tmp/patient-v6-browser', patientV5: true, homeV6: true, engineRoot, fontFile }`. `engineRoot` menunjuk cache `flutter_web_sdk/canvaskit` SDK dan `fontFile` menunjuk Roboto lokal SDK. Modul mengembalikan Promise laporan. Resolusi Node membutuhkan tooling Playwright existing dan Socket.IO dari dependency API; tidak menambah dependency runtime Flutter. Server memilih port loopback sementara, mengisolasi URL API hanya pada respons file build di memori, lalu menutup browser/server setelah selesai. Source dan build di disk tidak diubah oleh QA.
