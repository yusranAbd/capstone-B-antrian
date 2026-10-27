# QueueB Hospital - public release readiness review

Scope: pemeriksaan source frontend dan konfigurasi packaging existing pada Final Experience. Tidak ada deployment, perubahan database, key produksi, role, backend atau layanan berbayar. Database development sintetis tidak boleh digunakan sebagai database publik.

## Siap pada implementasi / QA terisolasi

- UI pasien memakai data API, tidak menambahkan rating, dokter, kapasitas, estimasi atau kunjungan fiktif ke runtime.
- Status server, guard booking/cancel, QR dinamis, timer expiry, single-submit dan realtime existing dipertahankan. Detail teknis QR ada di ekspander milik pasien sendiri, bukan log.
- Message mentah respons 5xx disanitasi di QueueApi; status HTTP dan perilaku recovery tetap ada, tanpa retry POST otomatis. Pesan 4xx validasi domain tidak disembunyikan.
- Web memakai MemorySessionStore, bukan localStorage bearer token. Android memakai FlutterSecureStorage dengan namespace terpisah per API_BASE_URL; logout/tombstone dan pembersihan cached UI dipertahankan. Ini bukti kode/tes, bukan audit perangkat keras.
- Tidak ada log print/debugPrint baru atau kredensial runtime yang ditambahkan. Screenshot dan fixture pengujian memakai identitas sintetis; tidak boleh dipresentasikan sebagai akun publik nyata.
- Kebijakan Public Display backend tetap default SAMAR. Mode LENGKAP memerlukan DISPLAY_PATIENT_NAME_MODE=LENGKAP sekaligus DISPLAY_FULL_NAMES_APPROVED=true. Tidak diubah pada pekerjaan ini.
- Android main manifest existing memakai INTERNET dan CAMERA (fitur scanner bersama, camera hardware optional), allowBackup=false dan aturan ekstraksi session existing. Tidak ada permission baru ditambahkan.
- Script `apps/client/tool/build-public.ps1` menolak HTTP, localhost/loopback/private, domain placeholder, kredensial/query/fragment dan base path salah sebelum packaging Web. Lima kasus validasi lokal diperiksa; script tidak melakukan deployment. Validasi URL bukan validasi DNS/TLS atau keamanan backend.

## Perlu validasi lingkungan nyata

- API staging/production, CORS origin, HTTPS/TLS, cookie HttpOnly/SameSite/Secure per perangkat, Socket.IO lewat reverse proxy dan reconnect pada jaringan nyata.
- Scope tiket/pasien, RBAC dan isolasi data antar-akun dengan API staging serta audit server. Tes widget/fixture tidak membuktikan keamanan endpoint produksi.
- Lifecycle login Android, secure storage/Keystore pada perangkat representatif, text scale dan pembaca layar, kamera QR, TTS TV serta background/foreground nyata.
- CDN/engine/font loading, CSP/hosting cache/service worker, koneksi lambat, performa RAM total renderer dan sesi panjang. JS heap dari satu run bukan bukti tidak ada leak.
- Storage foto persisten, backup/restore yang diuji, monitoring, logging terkontrol, kebijakan privasi/penggunaan data nyata dan prosedur operasional tim.

## Blocker sebelum rilis publik

1. Belum ada URL backend produksi terverifikasi pada scope ini. AppConfig development masih mempunyai fallback localhost; jangan memakai build default sebagai artefak publik. Pipeline publik wajib memakai URL HTTPS eksplisit dan guard build-public, serta scan artefaknya. Build QA lokal tetap terpisah.
2. Android release existing masih memakai debug signing. Dibutuhkan keystore distribusi resmi, pengelolaan rahasia di luar Git, versioning dan verifikasi paket/store. Tidak membuat atau mengekspor keystore di pekerjaan UI ini.
3. Database development berisi data sintetis. Diperlukan database dan proses operasional produksi tersendiri dengan persetujuan pemilik; tidak ada reset/copy/publikasi database development.
4. Uji staging lintas akun, validasi perangkat Android representatif dan konfigurasi keamanan deployment belum dapat dinyatakan selesai hanya dari build dan browser fixture.

## Build publik yang disengaja

```powershell
# URL harus milik backend produksi yang sudah diverifikasi; jangan salin placeholder.
./apps/client/tool/build-public.ps1 -ApiBaseUrl $ProductionApiUrl -ValidateOnly
./apps/client/tool/build-public.ps1 -ApiBaseUrl $ProductionApiUrl
```

Script menghasilkan build/web-public di apps/client dan tidak mengunggahnya. Untuk QA perbandingan visual digunakan Web release dengan API lokal yang dialihkan ke fixture, bukan build publik. Artefak konfigurasi HTTPS placeholder jika dibuat hanya untuk memeriksa substitusi build, tidak boleh didistribusikan.

## Batas pengujian Android

AVD existing dijalankan dalam mode read-only tanpa snapshot-save. Boot berhasil, tetapi layanan Window Manager melaporkan Broken pipe dan lingkungan sangat melambat. Instance QA milik tugas ini dihentikan; tidak menghapus AVD atau mengubah data persistennya. Tidak mengklaim smoke UI emulator atau perangkat fisik PASS. Build APK ARM64 dan pemeriksaan manifest dilaporkan terpisah setelah selesai.

## Bukti paket final

- Web release final PASS; fallback localhost tetap untuk QA. Guard build publik wajib setelah URL nyata tersedia. Build HTTPS placeholder terpisah juga berhasil, **bukan distribusi publik**; `.invalid` sengaja ditolak guard.
- APK ARM64 final PASS, 31,879,385 byte (sekitar 30.4 MiB). Endpoint `.invalid` dan debug signing membuat paket **QA saja**.
- `aapt dump badging`: package `id.queueb.queueb_client`, min SDK 24, target SDK 36, native-code arm64-v8a; tidak ada flag application-debuggable.
- `apksigner verify --print-certs` lulus; certificate `CN=Android Debug, O=Android, C=US`. Signature valid bukan signing distribusi resmi.
- Permission final: INTERNET, CAMERA, ACCESS_NETWORK_STATE dan DYNAMIC_RECEIVER_NOT_EXPORTED internal aplikasi. Tidak ada penambahan permission pada source manifest oleh tugas ini.
- Warning Gradle kompatibilitas Built-in Kotlin pada plugin flutter_tts existing; build tetap berhasil. Upgrade dependency perlu validasi terpisah.
- Tes Flutter dan QA Chrome final lulus; [laporan desain dan 42 screenshot](FINAL_EXPERIENCE_DESIGN.md). UI emulator/perangkat fisik belum dinyatakan lulus.
