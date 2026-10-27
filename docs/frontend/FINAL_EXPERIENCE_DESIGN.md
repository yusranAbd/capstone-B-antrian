# QueueB Hospital - Final Experience / Ruang Tenang

> Riwayat 27 Oktober 2026. Palet dan komposisi login telah direvisi pada [28 Oktober 2026](PATIENT_BLUE_PALETTE_REVISION.md); gunakan panduan QueueB terbaru untuk implementasi aktif.

## Product review dan keputusan

Dua pendekatan dievaluasi sebelum implementasi:

| Arah | Kekuatan | Trade-off | Keputusan |
|---|---|---|---|
| Editorial biru/cobalt, putih dingin, garis tegas | Familiar, kuat untuk orientasi informasi | Terlalu dekat dengan karakter lama; berpotensi terasa seperti dashboard administratif | Tidak dipilih |
| Ruang Tenang: ivory, plum, terracotta dan status sage/amber | Hangat, tenang, berbeda, menjaga fokus pasien; dapat dibangun dengan Flutter native | Kontras, fokus, seluruh dialog dan warna status harus ditata ulang secara konsisten | Dipilih |

Masalah baseline: banyak hardcoded teal terlepas dari tema, status berwarna serupa, kartu tiket memiliki hirarki datar, agenda berupa blok tanggal/UUID teknis, profil menempatkan menu vertikal panjang di atas form, serta login hanya berupa satu card generik. Tema di dalam PatientPage juga belum cukup untuk menangkap warna pada modal yang memakai context State; scope USER kini dipasang di root.

Palet dan ukuran normatif ada pada [panduan QueueB](QUEUEB_UI_UX_GUIDELINES.md#pasien-dan-login-ruang-tenang). Tidak ada skill desain eksternal, font, dependency atau ilustrasi baru. Ikon favicon/PWA/launcher template diganti dengan ekspor PNG dari SVG geometris medical cross QueueB; tidak memakai gambar generatif. Ikon Material dan foto aktual API tetap digunakan; fallback berupa ikon tanpa membuat identitas dokter palsu.

## Hasil implementasi

| Area | Perubahan produk | Perilaku yang dipertahankan |
|---|---|---|
| Login/registrasi | Ivory/paper, branding QueueB existing, cerita tiga langkah pada desktop, form natural-height pada mobile; keyboard tetap dapat scroll | JWT, validasi, autofill, role redirect, registrasi USER dan akses pairing display |
| Beranda | Eyebrow ringan; nomor kunjungan, tanggal/jam dan lokasi diatur proporsional dalam hero plum; layout bertumpuk saat layar/text besar | Pilihan kunjungan berdasarkan tiket aktual; section hilang jika kosong; walk-in tidak diberi dokter/jadwal buatan |
| Search/poli/dokter | Paper cards, indikator pilihan plum, nama/foto aktual dan caption yang terstruktur | Pencarian/filter existing dan hubungan dokter-poli |
| Detail dokter/booking | Identitas lebih tegas, bio aktual, kalender dan slot konsisten dengan tema; modal konfirmasi selaras | Kapasitas dan validitas dari API, single-submit/konflik server tetap authoritative |
| Reservasi | Info ringkas, status dengan ikon/warna berbeda, aksi berdampingan bila cukup ruang | Appointment + walk-in, search/filter, pembatalan DIPESAN melalui server, FAB standar dan bottom padding |
| Tiket/QR | Paper ticket dengan nomor/status, fakta berikon, pemisah ringan dan aksi historis berbeda; detail QR tanpa duplikasi nomor besar | QR dinamis, check status terbaru, kedaluwarsa, sekali pakai, tidak menerbitkan QR histori/di luar aturan |
| Janji Temu | Agenda waktu dengan filter tanggal ringkas dari response nyata, ListView.builder dan akses langsung tiket terkait | Tidak membuat jadwal/booking/status baru; ID tiket tetap diambil ulang lewat API |
| Profil | Identitas akun, pilihan pengaturan 2 kolom, form dan logout jelas; tanpa sidebar mobile baru | Nama/foto/password/role-info existing, private avatar dan pembersihan sesi |
| Navigasi/feedback | Lima tujuan dan focus scroll dipertahankan; modal, empty/loading, field dan tombol satu bahasa visual | Realtime, reconnect, reduced motion dan accessibility existing |

Respons 5xx tidak lagi menampilkan message/stack/database detail mentah. ApiException tetap menyimpan status HTTP; tidak menambah retry mutasi. Pesan validasi 4xx tetap dipertahankan. Tes recovery role lain diperbarui untuk memeriksa pesan aman, bukan menghilangkan assertion pemulihannya.

Profil dashboard ADMIN/PETUGAS/DOKTER dan Public Display tidak didesain ulang. Warna shared avatar/empty/notice hanya berubah saat marker tema pasien aktif; token QueueBStyle operasional tetap identik. Seluruh revisi lokal DOKTER/README/backup pengguna dipertahankan.

## QA dan bukti

Baseline adalah main f8baef8, artefak hash e0198124ec74866c1d75e49b8629cc184f374e7d2bc2918e4c41ab44ff14353d. Browser memakai fixture HTTP/Socket.IO sintetis yang sama; tidak menulis database development. Screenshot adalah render Flutter aktual, bukan mockup.

### Validasi source final (27 Oktober 2026)

- Format: 22 file Dart terkait, 0 perubahan. Analyze: **0 issues**.
- Seluruh Flutter test: **497 PASS, 1 SKIP existing** (live integration opsional memerlukan fixture database tervalidasi). Hasil lokal termasuk satu tes DOKTER pengguna yang sengaja tidak dimasukkan commit; CI menguji source tracked.
- Web release: **PASS**. APK release split ARM64: **PASS**, sekitar 30.4 MiB. APK memakai HTTPS placeholder dan debug signing, **QA saja**.
- Chrome **156.0.8078.48**, Flutter release/CanvasKit: **16 skenario PASS**, `errors=[]`. Viewport 320x568, 360x800, 375x812, 390x844, 412x915, 768x1024, 1366x768 dan 1920x1080; root scrollWidth sama dengan lebar viewport. Widget tests juga memeriksa text scale 1.5/2.0 pada komponen relevan.
- Flow: lima navigasi, focus-scroll, kunjungan appointment/walk-in, detail dokter, booking dokter, walk-in, slot terdekat aktual, pembatalan server, QR sesuai ID tiket, reconnect/invalidation Socket.IO, reload/login ulang, save profil, logout/login ulang, tiga siklus navigasi.
- QR tetap dinamis melalui endpoint existing. Payload/ID teknis ada di ekspander tertutup default; histori tidak menerima QR aktif di luar aturan existing.
- Pencarian Beranda mempunyai controller/state sendiri, bertahan saat pindah tab dan dapat dibersihkan. Pilihan poli memakai query Beranda yang sama. Regresi pencarian existing tetap lulus.
- Semua 28 file lokal terlindungi dibandingkan checksum manifest awal: **identik**. Backend, database, schema, migration dan dependency tidak diubah.

Batas: browser adalah aplikasi release nyata dengan HTTP dan transport Socket.IO sintetis pada loopback, **bukan E2E backend/live production**. Data/foto yang tidak tersedia memakai fallback ikon/info kosong. Web reload mengikuti session memory-only existing dan meminta login ulang. Persistent secure session Android diperiksa tes source; tidak mengklaim UI emulator/perangkat fisik PASS.

Locator runner Chrome diperbaiki untuk semantics Flutter yang kadang kehilangan accessible name setelah reload: tetap memilih button dengan nama atau teks tampilan yang tepat. Timeout startup engine diperbesar untuk host yang sedang build. Tidak ada retry booking/cancel otomatis atau bypass assertion domain.

### Ukuran dan resource

| Ukuran | Baseline f8baef8 | Final |
|---|---:|---:|
| Web release seluruh file | 50,923,590 byte | 50,930,493 byte |
| main.dart.js | 5,230,490 byte | 5,247,599 byte |
| APK ARM64 release | 31,880,265 byte | 31,879,385 byte |
| JS heap awal | 34.82 MiB | 37.35 MiB |
| JS heap setelah flow | 93.43 MiB | 78.24 MiB |
| JS heap siklus 1 / 2 / 3 | 91.95 / 104.37 / 99.34 MiB | 101.46 / 93.43 / 108.19 MiB |
| JS heap setelah idle 5 detik | 102.06 MiB | 108.19 MiB |
| Socket pasien aktif setiap sampel | 1 | 1 |

CDP Performance pada dua run Chrome terpisah, satu sampel per tahap, tanpa forced GC. Ini bukan RAM total browser/WASM, benchmark terkontrol atau bukti bebas leak. Heap berfluktuasi dan bertumbuh pada kedua versi; hasil **tidak mendukung klaim penurunan RAM**. Retensi sesi panjang dan renderer memory perlu profil lanjutan. Tidak ada font/dependency runtime baru, ilustrasi baru, penghilangan realtime atau perubahan cache/list pagination. Penambahan main JS sekitar 17 KB dan total Web sekitar 7 KB; APK praktis setara. Konfigurasi endpoint APK sebelum/sesudah berbeda; selisih kecil bukan klaim optimasi binary.

Bukti CDP/viewport/skenario: [baseline](images/final-experience/before-qa.json), [final](images/final-experience/after-qa.json).

### Screenshot aktual sebelum / sesudah

42 PNG identitas sintetis. Link fokus 390x844; lima halaman utama dan kunjungan juga tersedia pada 320x568. Halaman panjang tetap scroll.

| Halaman | Sebelum | Sesudah |
|---|---|---|
| Beranda | [Sebelum](images/final-experience/before-home-390.png) | [Sesudah](images/final-experience/after-home-390.png) |
| Kunjungan | [Sebelum](images/final-experience/before-home-appointment-390.png) | [Sesudah](images/final-experience/after-home-appointment-390.png) |
| Reservasi | [Sebelum](images/final-experience/before-reservations-390.png) | [Sesudah](images/final-experience/after-reservations-390.png) |
| Tiket | [Sebelum](images/final-experience/before-tickets-390.png) | [Sesudah](images/final-experience/after-tickets-390.png) |
| Janji Temu | [Sebelum](images/final-experience/before-appointments-390.png) | [Sesudah](images/final-experience/after-appointments-390.png) |
| Profil | [Sebelum](images/final-experience/before-profile-390.png) | [Sesudah](images/final-experience/after-profile-390.png) |
| Detail dokter | [Sebelum](images/final-experience/before-doctor-detail-390.png) | [Sesudah](images/final-experience/after-doctor-detail-390.png) |
| Booking | [Sebelum](images/final-experience/before-booking-390.png) | [Sesudah](images/final-experience/after-booking-390.png) |
| Konfirmasi | [Sebelum](images/final-experience/before-confirmation-390.png) | [Sesudah](images/final-experience/after-confirmation-390.png) |
| QR | [Sebelum](images/final-experience/before-correct-ticket-qr.png) | [Sesudah](images/final-experience/after-correct-ticket-qr.png) |
| Login mobile | [Sebelum](images/final-experience/before-login-390.png) | [Sesudah](images/final-experience/after-login-390.png) |
| Login desktop | [Sebelum](images/final-experience/before-login-1366.png) | [Sesudah](images/final-experience/after-login-1366.png) |
| Registrasi | [Sebelum](images/final-experience/before-register-390.png) | [Sesudah](images/final-experience/after-register-390.png) |

### Reproduksi tanpa database

Chrome, Flutter SDK, Node, `@playwright/test` 1.64.1 dan `socket.io` 4.8.x diperlukan sebagai tooling QA lokal (bukan dependency Flutter). Tooling dapat dipasang di direktori terpisah di luar repository. Set NODE_PATH ke node_modules tooling dan apps/api/node_modules. Tidak perlu membuat proyek React.

```powershell
# Dari root repo setelah flutter build web --release.
$env:FLUTTER_ROOT = 'C:/Development/flutter' # sesuaikan SDK lokal
node -e "require('./apps/client/tool/browser-reservation-v4.cjs')({build:'apps/client/build/web',output:'tmp/final-experience-recheck',patientV5:true,patientFocus:true,finalExperience:true,engineRoot:process.env.FLUTTER_ROOT+'/bin/cache/flutter_web_sdk/canvaskit',fontFile:process.env.FLUTTER_ROOT+'/bin/cache/artifacts/material_fonts/roboto-regular.ttf'}).then(r=>console.log(JSON.stringify(r))).catch(e=>{console.error(e);process.exitCode=1})"
```

Runner menyajikan release melalui loopback; hanya respons JS yang disajikan diarahkan ke fixture API, file artefak tidak dimodifikasi. Engine/font memakai SDK lokal. Baseline menggunakan salinan release f8baef8 dengan hash yang dicatat di atas. Screenshot adalah render aplikasi, bukan mockup.

Web final SHA-256: `ce69bed048d3315f54d414fc758bc4ea7c9644fe4090a2ed6f2e0a6aa07a0732`. APK final SHA-256: `396ba2e611bf0dfc0f646258dc979a2e213725e34bff073e72e72864cea5e259`.


## Kesiapan publik

Lihat [laporan rilis publik terpisah](PUBLIC_RELEASE_READINESS.md). Build release dan screenshot bukan persetujuan deployment atau bukti kesiapan data produksi.
