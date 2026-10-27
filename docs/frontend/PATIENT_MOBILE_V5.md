# Patient Mobile V5 — compact UI & navigation

Acuan: [QueueB Compact & Professional UI/UX Design System](QUEUEB_UI_UX_GUIDELINES.md), dengan kebutuhan mobile V5 terbaru. Platform: Flutter Android/Web Mobile. Tidak ada perubahan backend/API, database/migration, JWT/RBAC, Queue Engine, atau transport realtime.

## Perubahan

- Header pasien tetap berisi identitas/sapaan serta tombol aktivitas tiket existing. Avatar/nama tidak lagi membuka Profil; tidak ada duplikasi avatar atau notifikasi buatan. Role lain tetap memakai header existing.
- Judul “Bagaimana kabar Anda hari ini?” menjadi 20 logical px semibold. Search dan jarak vertikal lebih ringkas.
- Kunjungan Terdekat: solid navy/teks putih, foto profesional atau fallback existing, nama maksimal dua baris, spesialisasi, status backend, poli/ruang, nomor antrean menonjol, tanggal/jam dan dua tombol existing. Tanpa ilustrasi/pattern, minHeight/fixedHeight, atau data dokter/jadwal buatan. Section hilang bila tidak ada kunjungan valid mendatang; walk-in tanpa dokter tetap menampilkan data poli/tiket yang tersedia.
- Reservasi Saya mempertahankan proyeksi appointment + walk-in, search/filter/status, pembatalan DIPESAN melalui server dan tiga jalur pembuatan existing. Avatar 40px, spacing dan heading lebih compact. Filter/controller/scroll reservasi dipertahankan oleh IndexedStack saat berpindah tab.
- FAB dipindahkan ke `Scaffold.floatingActionButton` dengan `FloatingActionButtonLocation.endFloat`. Extended FAB teal solid, ikon tambah putih, shadow ringan; tanpa Stack/Positioned/container putih penuh. List memiliki bottom padding 96 sehingga baris terakhir dapat digulir melewati FAB.
- Tiket Saya memakai ListView.builder dan PatientTicketCard reusable. Nomor/status menjadi header; poli, tanggal, dokter/ruang/slot yang tersedia menjadi baris fakta. Tanggal memakai format Indonesia; jam memakai konfigurasi timezone operasional Asia/Jakarta, bukan raw timestamp. Tint berdasarkan status backend (dipesan biru, aktif teal, dilewati amber, dibatalkan merah muda, selesai netral).
- Satu tombol utama “Lihat Tiket / QR” membuka dialog tiket existing. Aksi QR eksplisit pada Beranda tetap langsung menerbitkan QR; tombol tiket/detail mempertahankan alur penerbitan existing. Status/tanggal diverifikasi ulang lewat GET tiket. QR hanya diterbitkan DIPESAN pada hari pelayanan, kedaluwarsa existing dan tanpa auto-renew/payload statis runtime. Selesai/dibatalkan hanya membuka informasi historis. Pembatalan tersedia pada Reservasi Saya.
- Navigasi tepat lima tujuan: Beranda, Reservasi, Tiket Saya, Janji Temu, Profil. Height 60 + SafeArea, label 10px, ikon 21px. Riwayat kunjungan existing tetap tersedia melalui shortcut; tab Profil menggunakan UserProfilePage existing, tanpa halaman/endpoint baru. Logout tetap di Profil. Callback kembali ke pasien hanya dipakai saat embedding; default role lain tidak berubah.
- Tema PatientMobileV5 hanya membatasi ukuran komponen pasien (tombol minimum 44px). Tema ADMIN/PETUGAS/DOKTER/Display tidak diperkecil atau dirombak.

## Pengujian dan bukti

[JSON Chrome](patient-v5-browser-qa.json) · [Artefak ARM64](patient-v5-apk-qa.json).

- Chrome release 156.0.8078.48 + Playwright, API/Socket.IO **fixture sintetis** pada server lokal. Screenshot merupakan render nyata Flutter, bukan gambar generatif atau screenshot dari data production. Tidak ada database yang diakses/diubah oleh QA.
- Browser: lima tujuan dan profil, header tanpa akses profil, varian appointment/walk-in Beranda, QR tiket benar, pembatalan server, booking dokter, walk-in, slot terdekat nyata dari fixture, realtime/reconnect dan reload/login ulang. Semua 10 skenario PASS, nol error runtime. Viewport 320×568, 360×800, 375×812, 390×844, 412×915 serta 768×1024 tidak memiliki root horizontal overflow.
- Widget V5: lima ukuran ponsel pada text scale 1.0/1.5, navigasi/profil/QR, list lazy, histori tanpa QR aktif, filter tetap tersimpan, card terakhir di atas FAB, dan form profil di atas keyboard 320×568. 12/12 PASS.
- Pengujian sesi existing memeriksa restore/login ulang/rotasi/logout. Kebijakan Web memory-only existing dipertahankan (reload membutuhkan login); Android tetap memakai secure persistence existing. Ini bukan klaim menutup paksa/membuka aplikasi pada HP fisik.
- Format: 13 file diperiksa, 0 berubah. Flutter analyze: 0 issue. Seluruh Flutter test: **485 PASS, 1 SKIP** (4 menit 2 detik). Satu tes live opsional membutuhkan backend fixture terisolasi dan tetap SKIP. Tes lokal mencakup satu tambahan DOKTER milik pengguna yang tidak disertakan commit ini; CI memakai source committed secara mandiri.
- Build Web JavaScript release berhasil; peringatan WASM dry-run TTS/Socket.IO existing tetap ada. Tidak mengklaim dukungan build WASM.
- APK release ARM64: 31.880.265 byte (30,4 MiB), ZIP hanya memuat ABI arm64-v8a. Build QA memakai API `http://10.0.2.2:3000/api/v1` untuk emulator dan signing debug existing pada release; bukan paket distribusi store. Untuk HP fisik gunakan build dengan URL LAN/HTTPS backend yang dapat dijangkau. Tidak ada uji Android fisik yang diklaim.
- Gradle memberi peringatan plugin flutter_tts masih memakai Kotlin Gradle Plugin lama untuk kompatibilitas Flutter mendatang. Tidak di-upgrade dalam pekerjaan UI ini. Log akhir build tetap sukses.

## Screenshot sebelum/sesudah

Fixture utama sama untuk perbandingan: kunjungan walk-in aktif, appointment dan riwayat. Varian appointment tambahan hanya memindahkan walk-in fixture ke status selesai sementara pada server QA agar card appointment dapat diperiksa; bukan perubahan logika aplikasi.

### 390×844

| Halaman | Sebelum | Sesudah |
|---|---|---|
| Beranda | [Lihat](images/patient-v5/before-home-390.png) | [Lihat](images/patient-v5/after-home-390.png) |
| Reservasi | [Lihat](images/patient-v5/before-reservations-390.png) | [Lihat](images/patient-v5/after-reservations-390.png) |
| Tiket Saya | [Lihat](images/patient-v5/before-tickets-390.png) | [Lihat](images/patient-v5/after-tickets-390.png) |
| Janji Temu | [Lihat](images/patient-v5/before-appointments-390.png) | [Lihat](images/patient-v5/after-appointments-390.png) |
| Profil | [Lihat](images/patient-v5/before-profile-390.png) | [Lihat](images/patient-v5/after-profile-390.png) |

### 320×568

| Halaman | Sebelum | Sesudah |
|---|---|---|
| Beranda | [Lihat](images/patient-v5/before-home-320.png) | [Lihat](images/patient-v5/after-home-320.png) |
| Reservasi | [Lihat](images/patient-v5/before-reservations-320.png) | [Lihat](images/patient-v5/after-reservations-320.png) |
| Tiket Saya | [Lihat](images/patient-v5/before-tickets-320.png) | [Lihat](images/patient-v5/after-tickets-320.png) |
| Janji Temu | [Lihat](images/patient-v5/before-appointments-320.png) | [Lihat](images/patient-v5/after-appointments-320.png) |
| Profil | [Lihat](images/patient-v5/before-profile-320.png) | [Lihat](images/patient-v5/after-profile-320.png) |

Varian card appointment: [390×844](images/patient-v5/after-home-appointment-390.png) · [320×568](images/patient-v5/after-home-appointment-320.png). Foto memakai fallback karena fixture tidak mempunyai fotoProfil; aplikasi tetap membaca foto aktual melalui komponen existing bila tersedia. Tampilan beradaptasi terhadap referensi mobile dalam percakapan; tidak memasukkan rating, pengalaman, atau nomor estimasi fiktif.

## Reproduksi

```powershell
cd apps/client
flutter analyze
flutter test
flutter build web --release --dart-define=API_BASE_URL=http://localhost:3000/api/v1 --dart-define=SERVICE_TIME_ZONE=Asia/Jakarta
flutter build apk --release --target-platform android-arm64 --split-per-abi --dart-define=API_BASE_URL=http://10.0.2.2:3000/api/v1 --dart-define=SERVICE_TIME_ZONE=Asia/Jakarta
```

Runner browser `apps/client/tool/browser-reservation-v4.cjs` memakai opsi patientV5:true dengan build/output/engineRoot/fontFile. Kontrak lama tetap dapat dijalankan untuk build baseline lewat patientV5:false. Token/kode QA tidak ditulis ke dokumentasi; binary APK, profil browser dan file tmp tidak di-commit.

File produksi utama: patient.dart, patient_home.dart, patient_ui.dart, patient_reservations.dart, patient_mobile_v5.dart, app.dart (hanya callback USER), user_profile.dart (opsi embedding). Tes menyesuaikan label navigasi/status visual tanpa mengurangi assertion aturan booking, QR, autentikasi atau role.

28 file lokal awal tetap identik terhadap manifest hash, termasuk revisi DOKTER, README, screenshots dan backup pengguna. Git langsung main tanpa branch/worktree/PR, tanpa force/reset/clean. Server development pengguna tidak dihentikan/diganti; untuk localhost:5173 lakukan hot restart (R) dan refresh untuk menampilkan source terbaru.
