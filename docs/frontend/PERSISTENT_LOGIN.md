# Persistent login Android dan pemulihan sesi

17 Oktober 2026. Scope: autentikasi Flutter existing. Tidak mengubah backend, kontrak REST, database, migration, API_BASE_URL, dashboard atau desain pasien. PR ini berbasis main setelah PR #43.

## Penyebab

`QueueApi` sebelumnya hanya menyimpan access/refresh token di field memori. `main()` langsung membuat client baru tanpa membaca sesi tersimpan. Selain itu setiap kegagalan refresh, termasuk timeout/offline, memanggil `clearSession()`. Menutup proses membuang token, dan gangguan jaringan dapat mengakhiri sesi terlalu dini.

## Implementasi

- Android memakai `flutter_secure_storage` **11.2.0**, konfigurasi standar RSA OAEP untuk pembungkus kunci dan AES-GCM untuk nilai, melalui Android Keystore. `resetOnError: false` mencegah penghapusan otomatis ketika pembacaan secure storage gagal. Tidak memaksakan biometrik atau menyimpan password. Konfigurasi mengikuti [dokumentasi paket resmi](https://pub.dev/documentation/flutter_secure_storage/11.2.0/flutter_secure_storage/AndroidOptions-class.html).
- Satu envelope JSON memuat versi, API base, access token dan refresh token; tidak ada password, profil atau role yang di-cache. Key terpisah per API base mencegah token development diteruskan ke environment lain. Pasangan ditulis dalam satu operasi plugin; tidak memisahkan penulisan access/refresh. Tidak mengklaim transaksi atomik antara database backend dan perangkat.
- `SessionStore` dapat diganti fake. Factory main memilih Android secure store hanya pada Android native; Web dan platform lain memakai memori. Implementasi Web dari dependency tidak dipakai untuk menyimpan token. Tidak menambahkan localStorage, sessionStorage, SharedPreferences biasa atau cookie.
- Backup Android dinonaktifkan; aturan Android 12+ mengecualikan shared preferences dari cloud/device transfer, termasuk ciphertext/kunci konfigurasi plugin. Tidak menyalin kredensial ke backup proyek.
- Startup menampilkan loading sambil membaca penyimpanan dan memanggil `GET /auth/me`. Identitas/role baru dibuka setelah respons backend sah; tidak menavigasi dari klaim JWT atau role yang di-cache. `401` memicu satu refresh, menyimpan pasangan baru, lalu mengulang GET sekali. USER/PETUGAS/ADMIN memakai routing existing.
- Refresh single-flight mencakup HTTP dan penyimpanan. Penulisan/penghapusan serial dan generation guard mencegah login, respons GET atau rotasi terlambat memulihkan sesi yang sudah logout. Listener realtime diberi token baru setelah penyimpanan selesai; koneksi lama dibuang sesuai mekanisme existing.
- Offline/timeout/5xx mempertahankan token dan menampilkan gate koneksi dengan Coba lagi/Hapus sesi. Tidak membuka dashboard offline dengan role cache. Tidak ada loop retry refresh otomatis; retry pemulihan eksplisit memvalidasi lagi. Kegagalan simpan hasil rotasi mempertahankan pasangan baru di memori agar dapat disimpan ulang tanpa mengonsumsi refresh dua kali.
- Penolakan autentikasi (400/401/403 pada alur auth), profil tanpa role yang didukung, atau penolakan GET setelah retry menghapus sesi. Error domain 403 di endpoint lain tidak otomatis menghapus login. Data/envelope rusak dibersihkan; error akses secure storage menampilkan retry tanpa mengasumsikan data kosong.
- Logout mengosongkan identitas/token memori, menutup halaman/dialog sensitif dan socket, lalu menghapus secure record **sebelum** request logout server. Tombstone tanpa token mencegah pemulihan bila delete gagal setelah tombstone berhasil. Jika penulisan tombstone gagal, delete dicoba. Bila keduanya gagal, UI memperlihatkan kegagalan cleanup dan tetap mencoba pencabutan server. Tidak mengklaim cleanup lokal berhasil jika OS menolaknya.
- Logout bersamaan rotasi menunggu respons yang sudah berjalan untuk mencabut refresh pengganti, tanpa menyimpannya kembali. Gangguan server logout tetap menghapus lokal dan memberi informasi bahwa pencabutan server belum terkonfirmasi. Membuka ulang setelah cleanup sukses tidak memulihkan sesi tersebut.

Kontrak backend yang dipakai: POST `/auth/login`, POST `/auth/refresh` dengan `refreshToken`, GET `/auth/me` dengan Bearer, POST `/auth/logout` dengan refresh terbaru. Refresh memakai compare-and-swap hash sesi dan mengonsumsi token lama. Tidak ada kebutuhan perubahan backend.

## Pengujian dan batas bukti

Pengujian fake membuat `QueueApi` baru dari store yang sama untuk meniru proses aplikasi baru; mencakup token valid, refresh/rotasi, penolakan sesi, offline/503, single-flight, read/write/delete failure, race logout, role, koneksi pasien dan penutupan dialog tiket. Adapter secure storage diuji dengan mock platform serta kegagalan tombstone/delete. Tidak ada token/password dicetak; diagnostik storage yang mungkin sensitif diganti pesan umum.

QA browser menjalankan Flutter Web release dengan respons HTTP terkontrol untuk tiga role. Memeriksa `/auth/me`, satu refresh, logout yang gagal server, reload tetap login, dan localStorage/sessionStorage kosong. Semua request API dicegat; tidak menulis database atau menjalankan backend/migration. Ini regresi shared authentication Web, bukan bukti Android Keystore fisik.

Perangkat Android tidak tersedia dan pengguna menyetujui melanjutkan tanpa perangkat fisik. Force-stop/relaunch pada Android asli belum diuji pada task ini. Build APK dan tes abstraction tidak menggantikan smoke test perangkat.

Jika proses mati setelah server mengonsumsi refresh tetapi sebelum pasangan pengganti diterima/tersimpan, backend existing tidak menyediakan replay/idempotent recovery. Token dipertahankan saat gangguan, tetapi penolakan token lama pada validasi berikutnya dapat memerlukan login ulang. Ini batas kontrak rotasi, bukan alasan menghapus sesi langsung ketika offline. Kehilangan Keystore, uninstall/clear app data, revokasi atau kedaluwarsa refresh juga membutuhkan login sah kembali.

## Menjalankan pemeriksaan

```powershell
# apps/client
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test --reporter expanded
flutter build web --release --no-web-resources-cdn --no-wasm-dry-run --dart-define=API_BASE_URL=http://127.0.0.1:3001/api/v1

# root, tanpa database/backend
node apps/client/tool/browser-auth-session.cjs

# apps/client, artefak untuk penggunaan development normal
flutter build web --release --no-web-resources-cdn --no-wasm-dry-run --dart-define=API_BASE_URL=http://localhost:3000/api/v1
flutter build apk --debug --dart-define=API_BASE_URL=http://127.0.0.1:3000/api/v1
```

Smoke perangkat berikutnya: login → tunggu profil tampil → force-stop → buka ulang → pastikan role pulih tanpa form login → ulangi saat offline → sambungkan dan Coba lagi → logout → force-stop/buka ulang → pastikan form login. Gunakan akun uji milik sendiri dan endpoint yang disetujui; jangan menghapus data aplikasi untuk meniru force-stop.

## Hasil akhir

| Pemeriksaan | Hasil aktual |
| --- | --- |
| Flutter unit/widget | **100 PASS**, termasuk **26 regresi baru**; satu tes live database umum SKIP karena task ini tidak menulis database |
| Flutter analyze | **PASS**, tanpa temuan |
| Dart format | **PASS**, 25 file, tidak ada perubahan |
| Web release | **PASS**, build QA API 3001 dan artefak development API localhost:3000 |
| APK Android debug | **PASS**, artefak terbaru `apps/client/build/app/outputs/flutter-apk/app-debug.apk`, API USB `127.0.0.1:3000`; build diulang setelah koreksi logout terakhir |
| Web auth ADMIN/PETUGAS/USER | **PASS**, HTTP terkontrol, satu refresh, warning logout 503, reload meminta login, storage browser kosong |
| Android registrasi/backup | **PASS**, generated registrant memuat plugin Secure Storage; merged manifest memuat tiga pengaturan backup yang diminta |
| Backend / database / migration | **Tidak diubah**, tidak menjalankan tes yang menulis database |
| Android fisik | **Tidak dijalankan**, sesuai persetujuan melanjutkan tanpa perangkat |

Bukti Web tersanitasi: [persistent-login-web-qa.json](persistent-login-web-qa.json). Build mencatat peringatan existing native access JDK dan Kotlin Gradle Plugin pada `flutter_tts`; tidak dilakukan upgrade dependency lain di luar penambahan secure storage dan transitive dependency-nya.

## File utama

- `apps/client/lib/src/session_store.dart`: abstraction, envelope, Android Keystore dan factory platform.
- `apps/client/lib/src/api.dart`: restore, persistence, refresh/error/logout dan pengendalian race.
- `apps/client/lib/main.dart`, `lib/src/app.dart`: startup/gate, pesan sesi dan batas navigasi sensitif.
- `apps/client/android/app/src/main/AndroidManifest.xml`, `res/xml/session_backup_rules.xml`: backup protection.
- `apps/client/pubspec.yaml`, `pubspec.lock`: dependency terkunci dan transitive dependency plugin.
- `apps/client/test/session_test.dart`, `tool/browser-auth-session.cjs`: regresi auth/storage/Web.
- README client, panduan MVP dan laporan ini: perilaku terbaru dan batas verifikasi.
