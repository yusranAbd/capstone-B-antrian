# QueueB Hospital — Flutter

Satu aplikasi Dart untuk ADMIN, PETUGAS, USER dan Public Display. Target: Web dan Android. Backend tetap NestJS existing dengan prefix `/api/v1`.

```powershell
flutter pub get
flutter run -d chrome --web-hostname localhost --web-port 5173 --dart-define=API_BASE_URL=http://localhost:3000/api/v1 --dart-define=SERVICE_TIME_ZONE=Asia/Jakarta
```

Gunakan origin Web yang diizinkan backend. Untuk Android emulator, API_BASE_URL memakai `http://10.0.2.2:3000/api/v1`; perangkat fisik memakai host yang dapat dijangkau. HTTP hanya tersedia pada build debug, release memakai HTTPS.

```powershell
flutter analyze
flutter test
flutter build web --release --no-web-resources-cdn --dart-define=API_BASE_URL=https://api.example.org/api/v1
flutter build apk --debug --dart-define=API_BASE_URL=http://10.0.2.2:3000/api/v1
```

Kontrak API: [API_INTEGRATION_GUIDE.md](../../docs/backend/API_INTEGRATION_GUIDE.md).
Panduan alur, QA nyata, konfigurasi dan batas MVP: [FLUTTER_MVP.md](../../docs/frontend/FLUTTER_MVP.md).
Panduan presentasi Web/Android, kamera, suara dan urutan aktor: [DEMO_FLUTTER.md](../../docs/frontend/DEMO_FLUTTER.md).
Hasil verifikasi dan batas perangkat: [FINALISASI_FLUTTER_MVP.md](../../docs/frontend/FINALISASI_FLUTTER_MVP.md).
Redesign enam layar mobile, komponen tema dan QA perangkat: [MOBILE_UI_FLUTTER.md](../../docs/frontend/MOBILE_UI_FLUTTER.md).
Perbaikan Poliklinik ADMIN, jadwal berkelompok dan input beberapa hari: [ADMIN_POLIKLINIK_JADWAL.md](../../docs/frontend/ADMIN_POLIKLINIK_JADWAL.md).
Sinkronisasi pasien lintas klien, navigasi ADMIN berkategori, hasil QA dan batas deployment: [REALTIME_ADMIN_OPTIMIZATION.md](../../docs/frontend/REALTIME_ADMIN_OPTIMIZATION.md).
Pemulihan sesi Android, Secure Storage, offline dan logout: [PERSISTENT_LOGIN.md](../../docs/frontend/PERSISTENT_LOGIN.md).
Informasi dokter, kalender praktik dari API, slot dan booking mobile: [DOCTOR_SCHEDULE_MOBILE.md](../../docs/frontend/DOCTOR_SCHEDULE_MOBILE.md).

Pasangan token akun Android disimpan melalui Android Keystore/`flutter_secure_storage`; Web dan platform lain tetap di memori. Password dan token perangkat display tidak dipersistenkan aplikasi. Startup Android memvalidasi `/auth/me` sebelum membuka halaman role. Akun operasional/perangkat display disediakan pengelola server. Jangan masukkan token/kredensial ke dart-define, URL, source atau Git. Kanal pasien `/patient` memakai JWT USER; jangan memakai room PETUGAS atau token display untuk pasien. Backend menyediakan invalidasi setelah commit; respons dan endpoint REST existing tetap dipakai.
