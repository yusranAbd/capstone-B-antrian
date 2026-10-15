Panduan Kontribusi dan Menjalankan QueueB Hospital di Laptop Anggota Tim
Status: Draf panduan untuk pengembang/anggota kelompok, disusun berdasarkan struktur proyek yang diketahui. Sebelum digabungkan ke GitHub, Codex wajib memverifikasi nama layanan Docker Compose, script package.json, nama variabel konfigurasi Flutter, port API, dan cara membuat akun ADMIN/PETUGAS pada checkout main terbaru. Jangan menganggap nilai contoh sebagai konfigurasi resmi apabila tidak cocok dengan source code.

1. Tujuan dan skenario
Panduan ini membantu anggota kelompok menjalankan QueueB Hospital untuk mencoba alur pasien, petugas, admin, dan display. Antarmuka yang digunakan saat ini adalah Flutter; backend menggunakan NestJS + Prisma + PostgreSQL.
Ada dua cara menjalankan:
1. Mode A — Mandiri: setiap anggota menjalankan database, API, dan Flutter sendiri di laptopnya. Cocok untuk coding dan pengujian terisolasi.
2. Mode B — Satu server lokal/LAN (lebih praktis untuk demo bersama): satu laptop menjadi host database, API, dan Flutter Web; laptop anggota lain mengakses alamat IP host melalui browser. Mereka tidak perlu menyalakan PostgreSQL/API masing-masing.
Jangan menggunakan database E2E capstone_antrean_test untuk demo. Database demo/development menggunakan database tersendiri, misalnya capstone_antrean. Jangan mengirim .env, dump database, token, atau kredensial lewat Git.

2. Persiapan aplikasi
Di Windows, pasang aplikasi berikut sebelum clone repository:
- Git untuk mengambil source code.
- Node.js 24 atau lebih baru dan npm untuk backend (sesuaikan dengan engines di apps/api/package.json).
- Docker Desktop yang sudah menjalankan Docker Engine, untuk PostgreSQL melalui compose.yml jika tersedia.
- Flutter SDK, Chrome, dan VS Code (opsional) untuk aplikasi Flutter.
Buka PowerShell, lalu periksa:
git --version
node --version
npm --version
docker --version
docker compose version
flutter doctor
flutter devices
Jika sebuah perintah belum dikenali, perbaiki instalasi/PATH sebelum melanjutkan. Pastikan Flutter mendeteksi Chrome (web).
3. Mengambil repository
Di PowerShell:
cd D:\WorkSpace   # Ganti dengan folder kerja masing-masing
git clone https://github.com/yusranAbd/capstone-b-antrian.git
cd capstone-b-antrian
git switch main
git pull --ff-only origin main
git status --short
Jika repository bersifat private, anggota harus mendapat akses GitHub terlebih dahulu. Pada checkout awal, git status --short idealnya kosong.
Struktur yang relevan:
capstone-b-antrian/
├── apps/
│   ├── api/       # Backend NestJS
│   └── client/    # Frontend Flutter (cek pubspec.yaml)
├── docs/backend/  # Dokumentasi integrasi API
└── compose.yml    # Layanan Docker (jika tersedia pada main terbaru)
Jika folder Flutter aktual berbeda, ikuti hasil pengecekan di repository, bukan membuat proyek baru.

4. MODE A — Menjalankan semua komponen di laptop masing-masing
4.1 Jalankan PostgreSQL
Di root repository, periksa layanan dalam compose.yml:
docker compose config --services
Identifikasi nama layanan PostgreSQL dari daftar tersebut. Kemudian jalankan hanya layanan database yang benar:
docker compose up -d <NAMA_SERVICE_POSTGRES>
docker compose ps
Ganti <NAMA_SERVICE_POSTGRES> berdasarkan keluaran perintah sebelumnya (jangan ketik tanda </> secara literal). Pastikan PostgreSQL sehat/berjalan. Konfigurasi proyek sebelumnya menggunakan port host 5433, tetapi cek pemetaan port aktual di compose.yml.
Jangan menggunakan docker compose down -v: opsi tersebut dapat menghapus volume berisi data database.
4.2 Konfigurasi environment backend
Backend proyek membaca environment dari root .env. Cari berkas template terlebih dahulu:
Get-ChildItem -Force -Name .env*
Get-ChildItem .\apps\api -Force -Name .env*
Jika template root tersedia, salin secara lokal, contohnya:
Copy-Item .env.example .env
Sesuaikan nama template dengan file yang benar-benar ada. Jika tidak ada template, minta contoh nama variabel (tanpa nilainya) kepada Project Lead; jangan menyalin kredensial pribadi. Konfigurasi biasanya mencakup URL PostgreSQL, JWT secrets, origin frontend, dan port server. Semua nilainya wajib menyesuaikan kode aktual.
Untuk MODE A, DATABASE_URL harus menunjuk ke PostgreSQL lokal milik anggota, bukan database orang lain. Format ilustrasi:
DATABASE_URL="postgresql://<PENGGUNA>:<PASSWORD>@127.0.0.1:5433/capstone_antrean?schema=public"
Nilai kredensial, nama DB, port, serta variabel lain harus dicocokkan dengan compose.yml, prisma.config.ts, dan template resmi. Jangan menempelkan password atau secret ke screenshot/issue.
4.3 Instal dan jalankan API
Buka Terminal 1 dari root:
cd apps\api
npm ci
npx prisma generate --schema prisma/schema.prisma
npx prisma migrate status --schema prisma/schema.prisma
Pastikan output Prisma mengarah ke database development lokal yang memang dipilih. Untuk database lokal baru/kosong yang sudah diverifikasi, terapkan migration existing:
npx prisma migrate deploy --schema prisma/schema.prisma
Jangan memakai prisma migrate reset atau prisma db push. Untuk database yang sudah memiliki data, diskusikan perubahan migration dengan Project Lead sebelum menjalankan deploy.
Periksa script yang tersedia, lalu jalankan API:
npm run
npm run start:dev
start:dev adalah script NestJS yang umum digunakan; Codex harus memastikan memang tersedia. Port API perlu diperiksa dari environment dan kode, biasanya 3000 tetapi jangan berasumsi. Jika port API adalah 3000, contoh pemeriksaan health:
Invoke-RestMethod http://127.0.0.1:3000/api/v1/health
Jika gagal, periksa pesan di Terminal 1, DATABASE_URL, port API, dan port database sebelum melanjutkan.
4.4 Jalankan Flutter Web
Buka Terminal 2 dari root repository:
cd apps\client
flutter pub get
flutter devices
flutter run -d chrome --web-port 5173
Penting: URL API yang digunakan Flutter harus cocok dengan API di Terminal 1. Nama setting-nya (.env, config Dart, atau --dart-define) harus ditemukan dalam source Flutter terlebih dahulu; jangan membuat variabel fiktif. Jika aplikasi menggunakan --dart-define, gunakan nama key yang benar-benar dibaca oleh kode, misalnya dalam bentuk umum:
flutter run -d chrome --web-port 5173 --dart-define=NAMA_KEY_AKTUAL=URL_API_AKTUAL
Jangan menjalankan contoh NAMA_KEY_AKTUAL apa adanya.
Buka http://localhost:5173 jika browser tidak terbuka otomatis. Pastikan login dan pengambilan daftar layanan dapat terhubung ke API.
4.5 Akun pengujian
- USER/pasien: dapat menggunakan registrasi normal apabila API mengizinkan.
- ADMIN/PETUGAS: minta akun demo yang diprovisikan secara sah oleh Project Lead; tidak ada password default yang didokumentasikan atau boleh ditebak.
- Display: ikuti mekanisme token perangkat yang sudah tersedia pada backend; jangan membagikan token di repo.
5. MODE B — Satu laptop sebagai server lokal untuk seluruh kelompok
Disarankan untuk presentasi/UAT bersama dalam satu jaringan Wi-Fi/LAN. Hanya laptop HOST yang menjalankan PostgreSQL, backend, dan Flutter Web. Anggota lain cukup memakai browser.
5.1 Siapkan HOST
Di laptop HOST, selesaikan Mode A terlebih dahulu. Pastikan login dan dashboard sudah berjalan lokal.
Cari alamat IP lokal host:
ipconfig
Catat IPv4 adaptor yang sedang digunakan, misalnya 192.168.1.10 (contoh, bukan alamat perangkat yang pasti). Semua laptop harus terhubung ke Wi-Fi/LAN yang sama.
5.2 Jalankan Flutter Web agar bisa diakses LAN
Di laptop HOST, jalankan sebagai web-server yang menerima koneksi LAN:
cd apps\client
flutter run -d web-server --web-hostname 0.0.0.0 --web-port 5173
Jika port 5173 terpakai, tutup sesi sebelumnya. Browser anggota membuka:
http://192.168.1.10:5173
Ganti IP contoh dengan IPv4 laptop HOST.
5.3 Pastikan API bisa diakses dari laptop anggota
- Backend harus mendengarkan interface LAN (0.0.0.0 atau alamat host), bukan terbatas ke 127.0.0.1.
- Browser anggota tidak boleh memanggil API http://localhost:3000: localhost menunjuk ke laptop anggota sendiri.
- URL API di build/config Flutter yang disajikan HOST harus mengarah ke http://IP_HOST:PORT_API, menggunakan key/format yang benar dari source code.
- CORS backend perlu mengizinkan origin spesifik Flutter Web http://IP_HOST:5173; jangan menonaktifkan seluruh proteksi CORS asal-asalan.
- Pada Windows Defender Firewall, izinkan port Web dan API hanya untuk jaringan Private jika diperlukan. Jangan buka port database 5433 ke LAN apabila tidak dibutuhkan.
Coba dari laptop anggota (misal API di port 3000):
Test-NetConnection 192.168.1.10 -Port 3000
Test-NetConnection 192.168.1.10 -Port 5173
Jika keduanya dapat diakses, buka halaman web dari browser anggota lalu login menggunakan akun demo sesuai role.
Keamanan: Mode LAN ini untuk demonstrasi/pengujian internal, bukan hosting publik. Jangan membuka port melalui router, port forwarding internet, atau menyalin database/akun produksi.

6. Checklist uji coba anggota
Setelah aplikasi berjalan, minta anggota menguji:
- [ ] Halaman login Flutter Web terbuka.
- [ ] USER/pasien dapat masuk dan memilih poliklinik.
- [ ] USER dapat melihat dokter, jadwal, slot, dan membuat janji temu (pada data poli yang memang sudah dikonfigurasi).
- [ ] USER dapat mendaftar walk-in pada poli yang mengizinkannya.
- [ ] Tiket dapat dilihat, termasuk status dan proses QR sesuai tanggal pelayanan.
- [ ] PETUGAS dapat memilih ruang yang ditugaskan dan melakukan Check-In/ENQUEUE.
- [ ] PETUGAS dapat menjalankan CALL dan penyelesaian antrean.
- [ ] ADMIN dapat membuka pengelolaan dokter, poliklinik, jadwal, dan slot.
- [ ] Public Display dapat menampilkan pembaruan antrean.
Jika halaman tampil tetapi daftar kosong, periksa apakah database lokal memiliki data layanan/dokter/jadwal yang diperlukan. Jangan mengarang seed atau akun demo; tanyakan prosedur provisioning yang benar.
7. Masalah umum
Gejala	Hal yang diperiksa
git clone gagal	Hak akses repository private, koneksi dan kredensial GitHub.
docker compose gagal	Docker Desktop berjalan, nama layanan benar, port tidak bentrok.
Prisma tidak terkoneksi	DATABASE_URL, DB aktif, port 5433 dan kredensial cocok.
API jalan tetapi Flutter tidak mengambil data	Base URL API, CORS, prefix /api/v1, dan alamat localhost vs IP HOST.
Flutter tidak dikenali	Flutter SDK/PATH dan flutter doctor.
Chrome tidak muncul	flutter devices, instalasi Chrome, dukungan web Flutter.
Login ADMIN/PETUGAS gagal	Akun belum diprovisikan atau role/penugasan tidak sesuai.
QR tidak tampil	Tiket/tanggal/masa berlaku QR, bukan hanya masalah tampilan.
Laptop anggota tidak bisa membuka server	IP HOST, jaringan sama, firewall Private, dan bind server.


8. Aturan kontribusi Git kelompok
1. Ambil pembaruan dari main dengan git switch main lalu git pull --ff-only origin main.
2. Buat branch sesuai tugas, misalnya feature/perbaikan-formulir-pasien.
3. Commit hanya file yang relevan; gunakan pesan commit Bahasa Indonesia.
4. Jangan stage .env, backup, token, dump database, node_modules, atau file build.
5. Push branch dan buat Pull Request; jangan langsung commit atau force push ke main.
6. PR di-merge setelah pemeriksaan CI dan persetujuan Project Lead.
9. Menghentikan aplikasi
- Terminal API / Flutter: Ctrl+C pada masing-masing terminal.
- Database Docker saat tidak dipakai: dari root docker compose stop <NAMA_SERVICE_POSTGRES>; data volume tetap tersimpan.
- Jangan gunakan docker compose down -v.
10. Referensi internal
- docs/backend/API_INTEGRATION_GUIDE.md — kontrak endpoint dan autentikasi.
- docs/backend/MVP_BACKEND_FINAL.md — checkpoint backend MVP.
- apps/api/prisma/schema.prisma dan apps/api/prisma/migrations/ — skema dan perubahan database.
- apps/client/pubspec.yaml dan source konfigurasi Dart — kebutuhan serta URL API Flutter.
Untuk maintainer/Codex sebelum merge dokumentasi: verifikasi seluruh nama service, script, port, environment key, lokasi Flutter, provisioning database/akun, dan tambahkan perintah resmi yang telah dicoba pada clean clone. Pertahankan bagian kontribusi Git sebelumnya apabila ada.
