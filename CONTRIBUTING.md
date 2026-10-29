# QueueB Hospital — Panduan Instalasi Lokal dan Development

Ditulis 29 Oktober 2026 berdasarkan inspeksi source pada `main`, baseline `2babd1860b9b80426ecfffaf408b7bd7a24d9110`. Perintah dalam panduan ini **belum dijalankan sebagai bagian penulisan dokumentasi**. Versi yang disebut terverifikasi merujuk konfigurasi/lockfile dan laporan proyek, bukan pengujian ulang pada laptop tujuan.

## 1. Pendahuluan

QueueB Hospital mengelola reservasi, tiket/QR, antrean pelayanan, pemantauan dokter, dan pengumuman ruang tunggu. Lima portal berada dalam satu aplikasi Flutter:

| Portal | Pengguna dan fungsi |
|---|---|
| ADMIN | Master poliklinik, dokter, ruang/loket, jadwal, slot, akun petugas, penugasan, dan perangkat display |
| PASIEN | Akun backend berperan `USER`; melihat katalog, reservasi/appointment, tiket, QR, dan riwayat |
| PETUGAS | Operasional loket sesuai penugasan yang aktif |
| DOKTER | Monitoring dan pembacaan jadwal/appointment milik dokter yang ditautkan ke akun |
| PUBLIC DISPLAY | Monitor layanan memakai sesi perangkat tersendiri; tidak login sebagai akun ADMIN/PETUGAS |

Flutter Web melayani browser; Flutter Android melayani perangkat/emulator. NestJS menyediakan REST dengan prefix `/api/v1` dan Socket.IO pada origin backend yang sama. PostgreSQL menyimpan data; Prisma mengakses database. Event realtime memicu rekonsiliasi data melalui REST, bukan menggantikan sumber kebenaran backend.

Panduan ini untuk **laptop baru dengan database kosong dan data sintetis**. Contoh folder tujuan adalah `C:\Workspaces\capstone-B-antrian`. Ganti folder tersebut secara konsisten jika memilih lokasi lain.

**Batas penting:** database development existing `127.0.0.1:5433/capstone_antrean` bukan target instruksi instalasi ini. Jangan menyalin `.env`, kredensial, dump pasien, atau volume database dari komputer pengembang lama. Contoh instalasi baru memakai `127.0.0.1:5434/queueb_local_new` agar targetnya berbeda. Database uji otomatis dibahas terpisah pada Bagian 11.

README root masih menyebut aplikasi React `apps/web` dan placeholder Flutter. Itu berbeda dari source `apps/client` saat ini. Untuk kelima portal di panduan ini, gunakan **`apps/client`**, bukan `apps/web`. `apps/api/README.md` juga masih berisi petunjuk starter Nest generik; script dan konfigurasi aktual menjadi acuan di bawah.

## 2. Persyaratan Sistem

### 2.1 Tools dan versi

| Tool | Acuan versi/kompatibilitas | Unduhan atau dokumentasi resmi |
|---|---|---|
| Git | Tidak ada minimum yang dipin repository; gunakan Git for Windows yang didukung | [Git for Windows](https://git-scm.com/install/windows) |
| VS Code | Opsional sebagai editor utama; tidak ada versi yang dipin | [VS Code](https://code.visualstudio.com/download) |
| Flutter SDK | Acuan proyek **3.47.5**; lockfile mensyaratkan Flutter **>=3.47.0** | [Instalasi manual Flutter](https://docs.flutter.dev/install/manual), [arsip SDK](https://docs.flutter.dev/install/archive) |
| Dart SDK | Bundel Flutter; `pubspec.yaml`/lockfile mensyaratkan **>=3.13.4 <4.0.0**, acuan **3.13.4** | Tidak perlu memasang Dart terpisah untuk aplikasi ini |
| Node.js | Gunakan **24.x >=24.15.0**, mengikuti major CI dan engine dependency terkunci; tidak ada `engines` di package root API | [Node.js](https://nodejs.org/en/download), pilih major 24 bila situs menampilkan major lain |
| npm | Package manager backend; `package-lock.json` format 3 dan CI memakai `npm ci`; versi npm persis tidak dipin | Disertakan installer Node.js; tidak perlu pnpm/yarn untuk alur ini |
| PostgreSQL | **18**, mengikuti image `postgres:18-alpine` di `compose.yml`; minimum lintas versi tidak ditetapkan proyek | [PostgreSQL Windows](https://www.postgresql.org/download/windows/) |
| Chrome | Browser pengembangan Web; versi persis tidak dipin | [Google Chrome](https://www.google.com/chrome/) |
| Android Studio + Android SDK | Diperlukan untuk Android; pilih versi yang mendukung AGP **9.1.0** | [Instalasi Android Studio](https://developer.android.com/studio/install) |
| Java/JDK | AGP 9.1 memerlukan JDK **17** minimum; source Java/Kotlin menargetkan 17. Gunakan JDK/JBR kompatibel yang terdeteksi Flutter | [Kompatibilitas AGP 9.1](https://developer.android.com/build/releases/agp-9-1-0-release-notes) |
| Gradle/Kotlin | Wrapper repo **Gradle 9.3.1**, plugin Kotlin **2.4.0**; tidak perlu memasang Gradle global | File `apps/client/android/settings.gradle.kts` dan `gradle/wrapper/gradle-wrapper.properties` |
| Docker Desktop | **Opsional**, hanya bila PostgreSQL dipilih lewat container; tidak wajib untuk instalasi PostgreSQL native | [Docker Desktop Windows](https://docs.docker.com/desktop/setup/install/windows-install/) |

Catatan Node: Prisma terkunci pada **7.10.0**, NestJS core pada **12.1.2**. Walaupun sebagian dependency menerima Node 20/22, `@angular-devkit/core` terkunci mensyaratkan `^22.22.3 || ^24.15.0 || >=26.0.0`. Node 24 yang terlalu lama dapat gagal memenuhi keseluruhan toolchain. Jangan mengganti lockfile untuk mengatasi salah versi Node.

`compileSdk`, `targetSdk`, `minSdk`, dan `ndkVersion` Android didelegasikan ke Flutter SDK pada `build.gradle.kts`; angka persisnya **PERLU DIKONFIGURASI** mengikuti SDK Flutter yang dipilih dan kebutuhan plugin. Jangan menebak minimum Android atau mengubah Gradle untuk instalasi awal.

### 2.2 Kapasitas dan platform

Target panduan: Windows 10/11 64-bit + PowerShell. Windows 11 yang masih didukung lebih sesuai untuk laptop baru; periksa dukungan Windows masing-masing versi Android Studio/Docker yang diunduh. Tidak ada minimum RAM/storage resmi QueueB dalam repository.

Rekomendasi perencanaan, **bukan syarat aplikasi yang telah diukur**: RAM 16 GB atau lebih; pertimbangkan 24–32 GB jika emulator, Docker, IDE, dan Gradle digunakan bersamaan; sediakan sekitar 50 GB ruang SSD untuk SDK, cache, system image, dan build. Virtualisasi diperlukan untuk pilihan emulator/Docker tertentu. `android/gradle.properties` saat ini mengizinkan heap Gradle hingga 8 GB; hindari menjalankan seluruh build dan E2E bersamaan pada host terbatas.

CI menjalankan Flutter/Nest di Ubuntu, sehingga toolchain non-Windows didukung pada tingkat CI. Path Windows, `Get-NetTCPConnection`, dan langkah installer di sini tidak langsung berlaku pada Linux/macOS; ikuti installer resmi platform tersebut. Pengembangan iOS tidak termasuk panduan ini.

## 3. Instalasi Tools

### 3.1 Git dan VS Code

1. Instal Git for Windows dan izinkan Git tersedia pada PATH.
2. Instal VS Code; opsi **Add to PATH** memudahkan perintah `code`.
3. Buka VS Code → Extensions → pasang ekstensi **Flutter** dari penerbit Dart Code; ekstensi Dart menjadi pendampingnya.
4. Buka PowerShell baru setelah mengubah PATH.

**Direktori: folder pengguna, belum perlu clone.**

```powershell
Set-Location $env:USERPROFILE
git --version
code --version
```

### 3.2 Flutter dan PATH

Unduh Flutter sesuai acuan Bagian 2, lalu ekstrak misalnya ke `C:\Development\flutter`. Hindari folder yang memerlukan hak administrator untuk ditulis. Tambahkan `C:\Development\flutter\bin` melalui **Environment Variables → User variables → Path**. Buka terminal baru.

Untuk PATH sementara pada terminal saat ini saja:

**Direktori: folder pengguna.**

```powershell
Set-Location $env:USERPROFILE
$env:Path = "C:\Development\flutter\bin;$env:Path"
Get-Command flutter, dart
flutter --version
dart --version
flutter doctor -v
```

Pastikan Dart yang terdeteksi berasal dari bundel Flutter yang dipilih. Jangan memakai Flutter lama yang kebetulan lebih dulu ditemukan di PATH.

### 3.3 Android Studio/SDK — wajib hanya untuk Android

1. Instal Android Studio dan selesaikan setup Android SDK.
2. Di **SDK Manager**, sediakan SDK Platform sesuai Flutter, Build Tools, Platform Tools, dan Android SDK Command-line Tools. Pasang NDK sesuai versi yang diminta Flutter bila build memerlukannya.
3. Untuk emulator, pasang Android Emulator dan buat AVD melalui **Device Manager**, dengan system image yang sesuai arsitektur host. Aktifkan dukungan virtualisasi bila diperlukan.
4. Flutter dapat menggunakan JDK/JBR Android Studio. Periksa lokasi Java pada `flutter doctor -v`; jangan menurunkan versi AGP/Gradle/Kotlin untuk menyesuaikan Java lama.

**Direktori: folder pengguna. Jalur SDK berikut adalah contoh lokasi default Windows; sesuaikan bila instalasi berbeda.**

```powershell
Set-Location $env:USERPROFILE
flutter config --android-sdk "$env:LOCALAPPDATA\Android\Sdk"
flutter doctor --android-licenses
flutter doctor -v
flutter devices
```

Baca dan setujui lisensi Android sendiri. Peringatan toolchain desktop Windows tidak perlu diselesaikan bila hanya menargetkan Web/Android; bagian Android, Chrome, dan koneksi perangkat yang akan digunakan harus siap.

### 3.4 Node.js dan npm

Instal Node 24 sesuai Bagian 2 beserta npm, lalu buka PowerShell baru.

**Direktori: folder pengguna.**

```powershell
Set-Location $env:USERPROFILE
node --version
npm --version
Get-Command node, npm
```

Jika PowerShell memblokir `npm.ps1`, gunakan `npm.cmd` untuk perintah npm, dan `npx.cmd` untuk npx. Tidak perlu menonaktifkan execution policy secara global.

### 3.5 PostgreSQL atau Docker

Pilih **salah satu** cara pada Bagian 6:

- **Native:** instal PostgreSQL 18 beserta command-line tools. Pada laptop baru ini, atur instance lokal pada port **5434**; simpan password administrator PostgreSQL sendiri.
- **Container:** instal Docker Desktop dan pastikan backend Linux/WSL yang disyaratkan Docker siap. Database dibuat dari konfigurasi Compose existing, dengan nama proyek/volume khusus dan port loopback pada Bagian 6.3.

**Direktori: folder pengguna. Pilih blok sesuai metode.**

```powershell
Set-Location $env:USERPROFILE
# Native: bila bin PostgreSQL belum ada pada PATH, sesuaikan lokasi aktual.
$env:Path = "C:\Program Files\PostgreSQL\18\bin;$env:Path"
psql --version
```

```powershell
Set-Location $env:USERPROFILE
# Hanya untuk pilihan Docker; buka Docker Desktop lebih dahulu.
docker --version
docker compose version
```

## 4. Clone Repository

Pastikan akun GitHub memiliki akses bila repository privat. Gunakan autentikasi GitHub yang sah melalui credential manager/SSH/PAT sesuai kebijakan tim; jangan menaruh token dalam URL clone atau dokumen.

**Direktori awal: `C:\`; hasil clone: `C:\Workspaces\capstone-B-antrian`.**

```powershell
Set-Location C:\
New-Item -ItemType Directory -Path C:\Workspaces -Force | Out-Null
Set-Location C:\Workspaces
git clone --branch main https://github.com/yusranAbd/capstone-b-antrian.git
Set-Location C:\Workspaces\capstone-B-antrian
git branch --show-current
git log -1 --oneline
git status -sb
Get-ChildItem
code .
```

Branch yang diharapkan adalah `main`. Acuan panduan ini `2babd18`; `main` dapat memiliki commit lebih baru ketika panduan dibaca. Periksa perubahan konfigurasi bila HEAD berbeda. Jika folder target sudah berisi pekerjaan lain, berhenti dan pilih folder kosong; jangan menghapus/reset pekerjaan tersebut.

## 5. Struktur Project

```text
capstone-B-antrian/
├── .env.example                  Template environment, belum memuat semua opsi
├── .env                          Dibuat lokal di laptop tujuan; diabaikan Git
├── compose.yml                   Service PostgreSQL 18 dan volume persisten
├── apps/
│   ├── api/
│   │   ├── package.json          Script npm backend
│   │   ├── package-lock.json     Dependency backend terkunci
│   │   ├── prisma.config.ts      URL dari ../../.env; konfigurasi migrate/seed
│   │   ├── prisma/
│   │   │   ├── schema.prisma
│   │   │   ├── migrations/       Delapan direktori migration pada baseline
│   │   │   └── seed.ts           Seed master, bukan akun awal
│   │   ├── src/                  NestJS, REST, JWT/RBAC dan Socket.IO
│   │   ├── test/                 Integrasi/e2e; perlu database test terpisah
│   │   └── tool/                 Tool maintenance khusus, bukan installer
│   └── client/
│       ├── pubspec.yaml / pubspec.lock
│       ├── lib/                  Lima portal Flutter dan entry point main.dart
│       ├── android/ / web/       Konfigurasi platform
│       ├── test/                 Unit/widget/BLoC dan live test ber-guard
│       ├── integration_test/     Pengujian perangkat terpisah
│       └── tool/                 Runner QA browser/perangkat, bukan kebutuhan startup
├── docs/backend/API_INTEGRATION_GUIDE.md
├── docs/frontend/                Panduan alur dan hasil QA
├── docs/setup/                   Panduan ini
└── .github/workflows/ci.yml      Flutter checks dan NestJS checks
```

Prisma Client dihasilkan ke `apps/api/src/generated/prisma`, bukan diedit manual. `.dart_tool`, `node_modules`, `build`, `dist`, `.env`, dan generated client tidak perlu disalin dari laptop lama.

## 6. Konfigurasi PostgreSQL

### 6.1 Tetapkan target baru dan buat environment lokal

Target panduan:

| Parameter | Nilai contoh laptop baru |
|---|---|
| Endpoint yang diakses backend | `127.0.0.1:5434` |
| Database | `queueb_local_new` |
| Role koneksi | `queueb_local` |
| Password | **PERLU DIKONFIGURASI**, pilih rahasia baru |
| Database lama yang dilarang menjadi target | `127.0.0.1:5433/capstone_antrean` |

**Direktori: root repository laptop tujuan. Jalankan penyalinan hanya jika `.env` belum ada.**

```powershell
Set-Location C:\Workspaces\capstone-B-antrian
if (Test-Path -LiteralPath .env) { throw '.env sudah ada; periksa target, jangan ditimpa.' }
Copy-Item -LiteralPath .env.example -Destination .env
code .env
```

Isi empat variabel `POSTGRES_*` dan `DATABASE_URL` sesuai target di atas sebelum melanjutkan. Contoh lengkap dan secret JWT ada pada Bagian 7. Role/password pada connection string harus sama dengan database yang benar-benar dibuat. Password dengan `@`, `:`, `/`, `#`, `%`, dan karakter khusus lain perlu URL encoding pada `DATABASE_URL`; `POSTGRES_PASSWORD` tetap nilai aslinya. Password acak berbentuk hex memudahkan penyusunan URL.

### 6.2 Pilihan A: PostgreSQL native

Jalankan service instance PostgreSQL 18 yang baru melalui Windows **Services**. Nama service dapat berbeda menurut installer: **PERLU DIKONFIGURASI**, lihat Services atau PostgreSQL Configuration/installer. Pastikan instance itu menggunakan port 5434.

**Direktori: root repository. Koneksi berikut membuka psql interaktif; password administrator diminta, bukan ditulis dalam perintah.**

```powershell
Set-Location C:\Workspaces\capstone-B-antrian
psql -h 127.0.0.1 -p 5434 -U postgres -d postgres -W
```

**Di dalam psql, database administrasi instance baru tersebut:**

```sql
\conninfo
SELECT current_database(), current_user, inet_server_addr(), inet_server_port();
CREATE ROLE queueb_local LOGIN;
\password queueb_local
CREATE DATABASE queueb_local_new OWNER queueb_local;
\q
```

`\password` meminta password baru secara interaktif. Jika role/database sudah ada, **berhenti dan periksa kepemilikannya**; jangan menghapus atau menimpa database existing. Role `queueb_local` tidak perlu diberi superuser untuk penggunaan aplikasi lokal ini.

**Direktori: root repository. Verifikasi target dan kondisi kosong sebelum migration pertama.**

```powershell
Set-Location C:\Workspaces\capstone-B-antrian
psql -h 127.0.0.1 -p 5434 -U queueb_local -d queueb_local_new -W -c "SELECT current_database(), current_user, inet_server_port();"
psql -h 127.0.0.1 -p 5434 -U queueb_local -d queueb_local_new -W -c "SELECT count(*) AS public_tables FROM information_schema.tables WHERE table_schema='public';"
```

Nama database harus `queueb_local_new`, user `queueb_local`, dan port native 5434. Sebelum migration pertama, database yang benar-benar baru belum mempunyai tabel aplikasi. Jangan lanjut bila identitas berbeda.

### 6.3 Pilihan B: PostgreSQL dari Compose existing

Gunakan hanya jika tidak memilih A. Root `.env` harus sudah mengisi `POSTGRES_DB=queueb_local_new`, `POSTGRES_USER=queueb_local`, password baru, dan `POSTGRES_PORT=5434`.

`compose.yml` existing memakai image `postgres:18-alpine` dan volume `postgres_data`. Untuk nama proyek di bawah, volume terpisah menjadi `queueb-local-new_postgres_data`. Pastikan nama container/proyek/volume ini belum digunakan untuk data lain.

Perintah berikut memakai **`compose run` dengan port loopback eksplisit**. Menurut [referensi Docker Compose](https://docs.docker.com/reference/cli/docker/compose/run/), `run` tidak mempublikasikan `ports` service kecuali diminta; `--publish` di sini menentukan mapping sendiri. Ini menghindari mapping `compose up` existing yang tidak membatasi alamat host pada loopback. Tidak diperlukan file Compose tambahan.

**Direktori: root repository, Docker Desktop sudah berjalan. Hanya untuk pembuatan container pertama.**

```powershell
Set-Location C:\Workspaces\capstone-B-antrian
docker compose --project-name queueb-local-new run -d --name queueb-local-new-postgres --publish 127.0.0.1:5434:5432 postgres
docker ps --filter name=queueb-local-new-postgres
docker port queueb-local-new-postgres
docker exec queueb-local-new-postgres pg_isready -U queueb_local -d queueb_local_new
docker exec queueb-local-new-postgres psql -U queueb_local -d queueb_local_new -c "SELECT current_database(), current_user, inet_server_port();"
docker exec queueb-local-new-postgres psql -U queueb_local -d queueb_local_new -c "SELECT count(*) AS public_tables FROM information_schema.tables WHERE table_schema='public';"
```

Tunggu `pg_isready` menyatakan menerima koneksi. Mapping host harus `127.0.0.1:5434`; port yang dilaporkan SQL dari **dalam container** adalah 5432, dan itu normal. Nama database tetap harus `queueb_local_new`. Image menginisialisasi user/database hanya saat volume kosong; mengganti `.env` setelah volume berisi data tidak mengubah password/database existing.

Untuk pemakaian berikutnya, **jangan mengulang pembuatan container** dan jangan menggantinya dengan `compose up` yang mempunyai mapping berbeda.

**Direktori: root repository, container yang sama sudah pernah dibuat.**

```powershell
Set-Location C:\Workspaces\capstone-B-antrian
docker start queueb-local-new-postgres
docker exec queueb-local-new-postgres pg_isready -U queueb_local -d queueb_local_new
```

Jangan menghapus volume untuk memperbaiki salah password. User bootstrap image PostgreSQL merupakan pengelola instance; pembatasan privilege production adalah pekerjaan tersendiri, bukan alasan membuka database ke LAN/internet.

## 7. Konfigurasi Backend NestJS

### 7.1 Environment root

NestJS membaca `../../.env` lalu `.env` ketika dijalankan dari `apps/api`; Prisma config membaca `../../.env`. **Gunakan satu `.env` di root repository** agar backend dan CLI tidak menunjuk database berbeda. Environment yang diwarisi terminal dapat mendahului file untuk Nest/Prisma CLI; periksa dan bersihkan override lama pada terminal laptop tujuan. Jangan menampilkan URL berkredensial ke log/chat.

Isi template lokal berikut dengan nilai milik laptop tujuan. Semua nilai `GANTI_...` adalah placeholder, **bukan credential siap pakai**.

**File: `C:\Workspaces\capstone-B-antrian\.env` pada laptop tujuan, bukan file di repository pengembang existing.**

```dotenv
NODE_ENV=development
POSTGRES_DB=queueb_local_new
POSTGRES_USER=queueb_local
POSTGRES_PASSWORD=GANTI_PASSWORD_DATABASE_BARU
POSTGRES_PORT=5434
DATABASE_URL=postgresql://queueb_local:GANTI_PASSWORD_DATABASE_URL_ENCODED@127.0.0.1:5434/queueb_local_new?schema=public
API_PORT=3000
JWT_ACCESS_SECRET=GANTI_RANDOM_SECRET_ACCESS
JWT_REFRESH_SECRET=GANTI_RANDOM_SECRET_REFRESH
JWT_ACCESS_EXPIRES_IN=15m
JWT_REFRESH_EXPIRES_IN=7d
CORS_ALLOWED_ORIGINS=http://localhost:5173,http://127.0.0.1:5173
SERVICE_TIME_ZONE=Asia/Jakarta
DISPLAY_PATIENT_NAME_MODE=SAMAR
DISPLAY_FULL_NAMES_APPROVED=false
```

**Direktori: root repository. Opsional untuk membuat dua secret acak independen, setelah Node terpasang; simpan hasil hanya pada `.env` lokal.**

```powershell
Set-Location C:\Workspaces\capstone-B-antrian
node -e "const c=require('node:crypto'); console.log('JWT_ACCESS_SECRET='+c.randomBytes(32).toString('hex')); console.log('JWT_REFRESH_SECRET='+c.randomBytes(32).toString('hex'));"
```

| Variabel | Status dan perilaku yang terverifikasi |
|---|---|
| `DATABASE_URL` | Wajib; PostgreSQL URL. Ini yang dipakai Nest/Prisma, bukan `POSTGRES_DB` secara langsung |
| `JWT_ACCESS_SECRET`, `JWT_REFRESH_SECRET` | Wajib, masing-masing minimal 16 karakter dan harus berbeda; gunakan nilai acak kuat seperti contoh generator |
| `API_PORT` | Default 3000, integer 1–65535 |
| `JWT_ACCESS_EXPIRES_IN`, `JWT_REFRESH_EXPIRES_IN` | Default `15m` / `7d`; pertahankan untuk setup awal |
| `NODE_ENV` | Gunakan `development` untuk HTTP lokal; `production` mengubah persyaratan origin dan cookie Secure |
| `CORS_ALLOWED_ORIGINS` | Daftar origin dipisahkan koma, tanpa path atau trailing slash; dipakai REST dan validasi origin Socket.IO. Isi eksplisit seperti contoh; jangan memakai `*` untuk koneksi berkredensial |
| `SERVICE_TIME_ZONE` | Default dan acuan pelayanan `Asia/Jakarta`; samakan dengan Flutter, meskipun timezone laptop berbeda |
| `POSTGRES_*` | Dibaca Compose untuk inisialisasi/pemetaan port. Pada native, sesuaikan dengan user/database sebenarnya; mengubahnya tidak menggantikan pengaturan `DATABASE_URL` |
| `DISPLAY_PATIENT_NAME_MODE` | Default aman `SAMAR`; opsi source juga `TANPA_NAMA`. Setup tidak memerlukan nama lengkap |
| `DISPLAY_FULL_NAMES_APPROVED` | Nama lengkap hanya aktif bila mode `LENGKAP` dan flag tepat `true`; jangan mengaktifkan untuk smoke test |
| `DOCTOR_MEDIA_DIR`, `USER_AVATAR_DIR` | Opsional; default `.queueb-media/dokter` dan `.queueb-media/avatar`, relatif working directory backend. Lokasi harus dapat ditulis bila memakai upload |

Template `.env.example` belum mencantumkan CORS, timezone dan opsi display/media di atas; source tetap mendukungnya. Tidak ada konfigurasi SMTP, email provider, Redis, cloud storage, atau API eksternal wajib yang ditemukan untuk startup alur dasar. Email akun adalah identitas login; panduan tidak mengasumsikan pengiriman email verifikasi. Internet tetap diperlukan untuk mengunduh dependency/SDK dan resource browser yang diperlukan plugin; kemampuan offline penuh tidak dijamin.

Socket.IO tidak membutuhkan port/URL environment tambahan: memakai origin API yang sama, namespace `/queue`, `/patient`, `/doctor`, dan `/display`; jalur transport `/socket.io/`. Jangan menambahkan namespace pada `API_BASE_URL` atau menebak variabel `SOCKET_URL`.

### 7.2 Dependency dan Prisma Client

**Direktori: `apps/api`. Ini langkah instalasi pada laptop tujuan.**

```powershell
Set-Location C:\Workspaces\capstone-B-antrian\apps\api
npm ci
npx prisma generate
```

`npm ci` mengikuti lockfile; jangan menggunakan upgrade massal atau menghapus lockfile. Prisma Client dihasilkan sesuai `prisma/schema.prisma`. Tidak perlu Nest CLI atau Prisma global. Jika npx menawarkan mengunduh paket yang belum terpasang, periksa keberhasilan `npm ci` terlebih dahulu.

### 7.3 Migration — hanya database baru yang sudah diverifikasi

Sebelum menulis schema, pastikan identitas dari Bagian 6 benar dan `.env` root masih menunjuk `queueb_local_new` pada 5434. Hilangkan override `DATABASE_URL` lama pada **terminal instalasi baru ini**, sehingga CLI membaca file root yang baru diperiksa.

**Direktori: `apps/api`.**

```powershell
Set-Location C:\Workspaces\capstone-B-antrian\apps\api
Remove-Item Env:DATABASE_URL -ErrorAction SilentlyContinue
npx prisma migrate status
```

Periksa baris datasource: **database `queueb_local_new`, endpoint `127.0.0.1:5434`**. Status pending/exit nonzero dapat normal sebelum migration pertama; error autentikasi/koneksi bukan izin untuk lanjut. Jika yang tampil database lain, berhenti dan perbaiki konfigurasi.

**Direktori: `apps/api`, lanjutkan hanya setelah identitas target baru cocok.**

```powershell
Set-Location C:\Workspaces\capstone-B-antrian\apps\api
npx prisma migrate deploy
npx prisma migrate status
```

`migrate deploy` menerapkan migration yang sudah dikomit; pada baseline terdapat delapan migration. Instalasi tidak perlu membuat migration baru, shadow database, `db push`, atau reset. Jangan menerapkan instruksi ini pada database yang sudah berisi data operasional.

### 7.4 Seed master — opsional, sekali pada database baru

`npm run db:seed` menjalankan `prisma/seed.ts`: membuat/memperbarui master ADM/VRF/INF, tiga loket dan jadwal kerja Senin–Jumat 08:00–15:00. Seed **tidak membuat akun**, profil dokter, sesi praktik, atau slot konsultasi. Seed melakukan upsert dan dapat memperbarui master yang sudah ada.

**Direktori: `apps/api`, hanya target baru yang telah dimigrasi dan master-nya masih kosong.**

```powershell
Set-Location C:\Workspaces\capstone-B-antrian\apps\api
npx prisma migrate status
# Periksa lagi datasource queueb_local_new:5434 sebelum baris berikut.
npm run db:seed
```

Khusus seed ini, `dotenv` pada `seed.ts` memakai `override: true`: nilai `.env` root mengalahkan environment terminal. Karena itu mengganti `$env:DATABASE_URL` saja **tidak cukup** untuk mengarahkan seed ke target lain. Jangan memakai seed ini untuk database test/operasional dengan harapan override terminal melindunginya.

`npm run data:development` adalah tool maintenance database existing, bukan installer/bootstrap akun. Tool tersebut mengunci target `capstone_antrean:5433`, mempertahankan ADMIN yang sudah ada, dan seeder sintetisnya memiliki window tanggal 27 Oktober 2026. **Jangan gunakan tool maintenance/reset tersebut untuk setup laptop baru.**

### 7.5 Jalankan backend

**Direktori: `apps/api`, terminal backend khusus.**

```powershell
Set-Location C:\Workspaces\capstone-B-antrian\apps\api
npm run start:dev
```

Watch mode mengompilasi dan memulai backend. Biarkan terminal ini terbuka. Environment tidak ditanam pada Flutter; perubahan `.env` backend sebaiknya diikuti stop/start backend secara sadar.

**Direktori: root repository, terminal pemeriksaan terpisah.**

```powershell
Set-Location C:\Workspaces\capstone-B-antrian
Invoke-RestMethod -Uri 'http://localhost:3000/api/v1/health'
```

Respons sukses memuat `status: ok`, `service: capstone-antrean-api`, `database: connected`, dan timestamp server. Endpoint ini benar-benar menjalankan pemeriksaan Prisma ke database. Halaman root `/` bukan pengganti health check.

## 8. Konfigurasi Flutter Frontend

### 8.1 Dependency dan perangkat

**Direktori: `apps/client`.**

```powershell
Set-Location C:\Workspaces\capstone-B-antrian\apps\client
flutter pub get
flutter doctor -v
flutter devices
```

Pertahankan `pubspec.lock`. Bila dependency meminta Dart/Flutter lebih tinggi, cocokkan SDK Bagian 2; jangan menurunkan constraint untuk memaksa instalasi.

### 8.2 API base dan timezone

`lib/src/config.dart` membaca compile-time `--dart-define`:

- `API_BASE_URL`: default `http://localhost:3000/api/v1`.
- `SERVICE_TIME_ZONE`: default `Asia/Jakarta`.

URL harus HTTP(S), tanpa username/password, query, atau fragment; sertakan prefix `/api/v1`. Origin Socket.IO diturunkan otomatis dari URL tersebut. Berkas `.env` backend **tidak otomatis dibaca Flutter**. Setelah mengubah dart-define, hentikan dan jalankan/build Flutter kembali; hot reload saja tidak cukup.

| Klien | Contoh API base | Penjelasan |
|---|---|---|
| Chrome di laptop backend | `http://localhost:3000/api/v1` | Pasangkan dengan Web `http://localhost:5173` agar host konsisten |
| Android Emulator bawaan Android Studio | `http://10.0.2.2:3000/api/v1` | Alias host komputer, bukan loopback Android |
| Android fisik pada Wi-Fi/LAN sama | `http://192.168.1.20:3000/api/v1` | Contoh IP, **PERLU DIKONFIGURASI** dengan IPv4 host sebenarnya |
| Browser pada komputer/monitor LAN lain | `http://192.168.1.20:3000/api/v1` | Frontend juga memakai host LAN yang konsisten; lihat Bagian 13 |

`localhost` pada Android fisik/emulator mengarah ke perangkat itu sendiri. Alias emulator ini tidak boleh diasumsikan berlaku pada semua emulator pihak ketiga; lihat [jaringan Android Emulator](https://developer.android.com/studio/run/emulator-networking).

### 8.3 Flutter Web

**Direktori: `apps/client`, terminal frontend khusus; backend sudah sehat.**

```powershell
Set-Location C:\Workspaces\capstone-B-antrian\apps\client
flutter run -d chrome --web-hostname localhost --web-port 5173 --dart-define=API_BASE_URL=http://localhost:3000/api/v1 --dart-define=SERVICE_TIME_ZONE=Asia/Jakarta
```

Buka aplikasi pada `http://localhost:5173`. CORS harus mengizinkan origin ini secara persis. `http://127.0.0.1:5173` merupakan origin berbeda; mengganti hostname bisa memisahkan cookie/session display. Jangan mencampur Web localhost dengan API 127.0.0.1 untuk pairing awal.

### 8.4 Flutter Android

Hidupkan AVD melalui Android Studio, atau sambungkan ponsel dengan USB debugging dan setujui otorisasi perangkat. Ambil ID aktual dari `flutter devices`.

**Direktori: `apps/client`. Ganti nilai ID contoh sebelum menjalankan.**

```powershell
Set-Location C:\Workspaces\capstone-B-antrian\apps\client
flutter devices
$queuebDeviceId = 'GANTI_ID_DARI_FLUTTER_DEVICES'
flutter run -d $queuebDeviceId --dart-define=API_BASE_URL=http://10.0.2.2:3000/api/v1 --dart-define=SERVICE_TIME_ZONE=Asia/Jakarta
```

Contoh terakhir untuk emulator Android Studio. Untuk ponsel fisik, ganti API base dengan IP LAN host yang dapat dijangkau pada Bagian 13. Backend harus terjangkau dari perangkat; USB untuk menjalankan aplikasi tidak otomatis membuat `localhost` Android sama dengan PC.

Manifest debug mengizinkan cleartext HTTP dan aplikasi mendeklarasikan izin Internet/kamera. Gunakan **debug** untuk HTTP lokal; build release tidak mempunyai pengecualian HTTP debug dan memerlukan endpoint HTTPS yang sesuai. Signing release pada source masih memakai debug signing; panduan ini tidak menyiapkan distribusi production.

## 9. Menjalankan Sistem Lokal

| Urutan | Terminal/alat | Working directory | Pemeriksaan |
|---|---|---|---|
| 1 | Windows Services atau Docker Desktop | Instance/container baru Bagian 6 | PostgreSQL menerima koneksi dan target benar |
| 2 | Terminal A: `npm run start:dev` | `apps/api` | Health REST berhasil |
| 3 | Terminal B: `flutter run ...` | `apps/client` | Halaman login muncul |
| 4 | Chrome/AVD/ponsel | URL/perangkat yang dipilih | API base menunjuk host yang dapat diakses |
| 5 | Terminal C/pengamatan UI | Root repository | Health dan portal sesuai role |

**Direktori: root repository, terminal C.**

```powershell
Set-Location C:\Workspaces\capstone-B-antrian
Test-NetConnection -ComputerName localhost -Port 3000
Invoke-RestMethod -Uri 'http://localhost:3000/api/v1/health'
```

`TcpTestSucceeded` hanya memverifikasi port; respons health memastikan database dapat diakses. Katalog yang memerlukan autentikasi tidak harus bisa dibuka sebagai URL publik tanpa login. Jangan menafsirkan `401` sebagai server mati.

## 10. Setup Awal Lima Portal

Seluruh provisioning di bagian ini hanya pada **database baru laptop tujuan, berisi akun/data sintetis**. Tidak ada password ADMIN default yang terverifikasi atau script bootstrap ADMIN umum pada repository.

### 10.1 ADMIN pertama — PERLU DIKONFIGURASI oleh pengelola

Registrasi aplikasi selalu membuat peran `USER` (`UsersService.create`); body register tidak boleh ditambahi field role. Seed master tidak menghasilkan ADMIN, sedangkan tool maintenance membutuhkan ADMIN yang sudah ada. Jangan menganggap migrasi schema otomatis membuat akun.

**Prosedur bootstrap manual lokal berikut adalah langkah operator database baru, bukan endpoint peningkatan role yang disediakan aplikasi:**

1. Setelah backend/frontend siap, pilih **Pasien baru? Daftar** pada halaman login. Daftarkan identitas sintetis untuk pengelola laptop tujuan, dengan email unik dan password pilihan sendiri (8–72 karakter; nama 3–150 karakter). Registrasi existing akan membentuk password hash melalui `PasswordService` dengan bcrypt cost 12.
2. Logout dari sesi registrasi bila sudah login.
3. Pengelola yang berwenang memverifikasi ulang datasource baru dengan `migrate status`, lalu membuka Prisma Studio lokal. Jangan melakukan ini pada database operasional existing.

**Direktori: `apps/api`, terminal operator terpisah, hanya target `queueb_local_new:5434` yang sudah diperiksa.**

```powershell
Set-Location C:\Workspaces\capstone-B-antrian\apps\api
Remove-Item Env:DATABASE_URL -ErrorAction SilentlyContinue
npx prisma migrate status
# Hanya setelah target baru benar:
npx prisma studio
```

4. Di Studio, buka model `Pengguna`/tabel `pengguna`; temukan **akun sintetis yang baru didaftarkan** berdasarkan email tepat. Ubah hanya `peran` dari `USER` ke `ADMIN`, pastikan `aktif=true`, lalu simpan. Jangan mengedit `kataSandiHash`, ID, atau akun lain.
5. Tutup Studio/terminal operator dengan `Ctrl+C` setelah selesai. Studio adalah akses administrasi database; jangan mempublikasikannya ke LAN/internet.
6. Login ulang di aplikasi dengan email/password yang sama; portal ADMIN harus terbuka. Jika tim memiliki prosedur provisioning resmi lain, gunakan prosedur pengelola tersebut. Hak mengelola database/akun pertama adalah **PERLU DIKONFIGURASI**, bukan privilege yang diberikan ke pasien biasa.

Prisma CLI sudah menjadi devDependency repository; [Prisma Studio](https://www.prisma.io/docs/studio/getting-started) mendukung pembacaan/pengeditan record. Nama role/kolom di atas berasal dari schema aktual. Ini tidak memerlukan script installer baru, password plaintext pada SQL, atau perubahan RBAC backend.

### 10.2 Master ADMIN dan urutan dependensi

Pada portal ADMIN, gunakan menu administrasi/sidebar; pada layar kecil, buka **Menu administrasi**. Siapkan data secara berurutan:

1. **Poliklinik** aktif dan mode reservasi yang benar: `ANTREAN_HARIAN`, `JANJI_TEMU_DOKTER`, atau `HIBRIDA`. Mode menentukan kanal yang tersedia.
2. **Ruang & loket** aktif terkait poliklinik.
3. **Jam & kapasitas poli** untuk hari pelayanan yang akan diperiksa; kapasitas positif dan jam buka/tutup benar.
4. **Dokter** aktif dan relasi dokter–poliklinik; jangan membuat profil tanpa relasi untuk mengharapkan katalog appointment tersedia.
5. **Jadwal praktik** terkait relasi dokter–poliklinik/ruang, lalu **Slot konsultasi** di dalam sesi dengan kapasitas sesuai. Pilih tanggal yang belum lewat dan waktu pelayanan `Asia/Jakarta`.
6. **Penugasan petugas**: tab **Akun Petugas** untuk akun, tab **Penugasan Loket** untuk relasi petugas–loket yang aktif dan periode mencakup hari ini.
7. **Manajemen Display**: perangkat aktif per monitor dan poliklinik, lalu aktivasi pada 10.6.

Tidak perlu membuat booking atau menekan tombol command antrean untuk memeriksa instalasi. Master dari seed opsional adalah contoh layanan dasar; bukan dataset rumah sakit lengkap dan bukan akun siap login.

### 10.3 PASIEN (`USER`)

- Gunakan akun pasien sintetis lain melalui halaman **Daftar**; jangan memakai akun bootstrap ADMIN sebagai pasien.
- Login sebagai pasien dan buka **Beranda**, **Reservasi**, **Tiket Saya**, riwayat/profil sesuai navigasi yang tampil.
- Pastikan katalog aktif termuat. Reservasi walk-in memerlukan mode harian/hibrida dan jadwal/kuota; appointment memerlukan dokter terkait, sesi dan slot yang masih tersedia.
- Untuk smoke test instalasi, cukup buka pilihan katalog/tanggal/slot tanpa mengonfirmasi booking. Riwayat/tiket kosong pada database baru adalah hasil yang sah.
- Sesi akun Web berada di memori; reload dapat kembali ke login. Android memakai secure storage dan memvalidasi sesi melalui `/auth/me`. Ini berbeda dari cookie perangkat display.

### 10.4 PETUGAS

- ADMIN membuat akun melalui **Penugasan petugas → Akun Petugas**, dengan nama, email, password baru, lalu menyediakan **Penugasan Loket** aktif. Backend menggunakan `POST /akun-petugas` dan `/penugasan-petugas`, keduanya dibatasi ADMIN.
- Login menggunakan akun PETUGAS pada context browser/perangkat terpisah. Pilih penugasan/loket yang sesuai bila pilihan tersedia.
- Pastikan dashboard dapat membaca snapshot, nama layanan/loket benar, dan status realtime terhubung. Antrean kosong adalah normal.
- `403` bisa berarti role/penugasan/ruang tidak memenuhi syarat, bukan alasan mengganti role atau melemahkan guard. Jangan menguji CALL/RECALL/START/COMPLETE pada database yang bukan lingkungan uji.

### 10.5 DOKTER

- ADMIN membuat profil dokter aktif dan relasi polikliniknya, lalu memakai pengelolaan akun pada menu **Dokter** untuk membuat/menautkan akun.
- Kontrak yang tersedia: `POST /dokter/:id/akun`, menerima akun DOKTER existing melalui `penggunaId`, **atau** membuat akun baru dari `email` dan `kataSandi` (8–72 karakter). Ini berbeda dari registrasi pasien.
- Login sebagai DOKTER setelah akun tertaut ke profil aktif. Periksa dashboard, tanggal/jadwal, daftar appointment dan monitoring miliknya. Data kosong sebelum ada appointment adalah normal.
- Portal dokter bersifat read-only untuk antrean; tidak ada kebutuhan memberikan izin command PETUGAS ke dokter untuk melengkapi setup.

### 10.6 PUBLIC DISPLAY

1. ADMIN membuka **Manajemen Display**, membuat perangkat dengan nama dan poliklinik terkait, lalu menghasilkan kode aktivasi.
2. Buka tab/monitor baru pada aplikasi. Dari login pilih **Masuk ke Public Display**.
3. Masukkan **kode aktivasi 12 digit** yang dibuat ADMIN lalu hubungkan perangkat. Kode sekali pakai berlaku **5 menit**; jangan memakai contoh kode rekaan.
4. Pastikan identitas layanan benar dan **Realtime terhubung** muncul. Tekan **Aktifkan suara** melalui interaksi pengguna untuk mengizinkan audio; siapkan suara Indonesia di browser/OS bila belum tersedia.
5. Untuk monitor lain, buat perangkat dan kode lain. Jangan menduplikasi pairing satu perangkat untuk mewakili seluruh monitor.

Mekanisme Web existing: `POST /display/pairing` dengan isolasi sesi menghasilkan cookie backend `HttpOnly`, `SameSite=Strict`, masa sesi 30 hari; `Secure` aktif saat `NODE_ENV=production`. Cookie per perangkat bernama `queueb_display_<UUID>`. Flutter menyimpan **selector ID perangkat**, bukan credential, dalam `sessionStorage` per tab; REST memakai selector `x-display-device-id`, Socket.IO memakai identitas perangkat sesuai scope. Browser client mengirim cookie dengan credentials. Token mentah tidak ditampilkan untuk disalin atau ditempatkan pada URL/dart-define.

Gunakan frontend dan API pada hostname/site yang konsisten. CORS yang benar saja tidak mengatasi cookie yang ditolak karena beda site. Tab baru tanpa selector perlu pairing; kode yang sudah dipakai perlu diganti. Rotasi/nonaktifkan dari ADMIN mencabut sesi perangkat sasaran. Jika JWT refresh secret backend diganti, kode aktivasi lama juga dapat tidak berlaku. Jangan mengubah SameSite/menonaktifkan keamanan browser untuk memaksa pairing.

Initial load, reconnect, dan refresh manual tidak seharusnya membacakan panggilan lama. Suara aktivasi bukan bukti seluruh CALL/TTS atau speaker fisik telah diuji.

## 11. Pengujian Awal

### 11.1 Smoke test aman setelah instalasi

| Pemeriksaan | Hasil yang diharapkan |
|---|---|
| GET health | `status=ok`, `database=connected` |
| Buka Flutter | Login/registrasi tampil, tidak ada error koneksi aset/API |
| Login ADMIN | Menu administrasi tampil sesuai role |
| Login PASIEN | Katalog layanan/dokter aktif terbaca; layar tiket kosong tetap valid |
| Buka reservasi | Pilihan yang sesuai konfigurasi tersedia; **jangan submit booking untuk smoke test ini** |
| Login PETUGAS | Penugasan aktif terlihat dan snapshot loket dapat dimuat |
| Login DOKTER | Profil/jadwal/appointment miliknya dapat dibaca |
| Pairing display sintetis | Layanan/perangkat sesuai, tidak mengambil scope monitor lain |
| Realtime | Status terhubung pada portal yang menggunakan socket; tidak perlu membuat antrean untuk sekadar memverifikasi handshake |

Login/registrasi/pairing/master setup menulis data akun/sesi/konfigurasi pada **database baru**. Pengujian perubahan status antrean atau booking hanya dilakukan pada lingkungan uji yang disiapkan khusus, dengan pasien sintetis, target diverifikasi, dan fixture dibersihkan. Jangan menjalankan skenario tersebut pada database operasional.

### 11.2 Pemeriksaan Flutter dan build

**Direktori: `apps/client`; jalankan setelah dependency siap. Ini perintah untuk developer laptop tujuan, bukan hasil pengujian baru panduan ini.**

```powershell
Set-Location C:\Workspaces\capstone-B-antrian\apps\client
flutter analyze
flutter test
flutter build web --release --no-web-resources-cdn --dart-define=API_BASE_URL=http://localhost:3000/api/v1 --dart-define=SERVICE_TIME_ZONE=Asia/Jakarta
flutter build apk --debug --dart-define=API_BASE_URL=http://10.0.2.2:3000/api/v1 --dart-define=SERVICE_TIME_ZONE=Asia/Jakarta
```

`test/live_integration_test.dart` dilewati secara default tanpa fixture `FLUTTER_REAL_FIXTURE`. Jangan mengatur fixture/environment live pada terminal unit test. `integration_test/` dan runner browser/Android bukan bagian otomatis dari smoke test dasar. Web build di atas hanya menghasilkan file untuk backend HTTP lokal; hosting HTTPS dan alamat target harus dikonfigurasi ulang untuk distribusi lain.

Output utama: `apps/client/build/web/` dan `apps/client/build/app/outputs/flutter-apk/app-debug.apk`. APK emulator dengan `10.0.2.2` tidak otomatis cocok untuk ponsel fisik; build ulang memakai alamat LAN/HTTPS yang sesuai.

### 11.3 Pemeriksaan backend tanpa database nyata

Unit test memakai dependency/mocks. Untuk mencegah kesalahan target, gunakan URL dummy yang tidak bisa menjadi database development, dalam terminal testing terpisah.

**Direktori: `apps/api`, terminal unit test tersendiri.**

```powershell
Set-Location C:\Workspaces\capstone-B-antrian\apps\api
$env:DATABASE_URL = 'postgresql://invalid:invalid@127.0.0.1:1/blocked_unit_test'
npm run test -- --runInBand
npm run lint
npm run build
Remove-Item Env:DATABASE_URL
```

`pretest` menjalankan tes tooling `development-data.test.cjs`; ini tidak sama dengan menjalankan tool reset/seed. Lint aktual menggunakan oxlint type-aware. Build menghasilkan `dist`; jangan menjalankan backend pada terminal yang masih memiliki URL dummy.

### 11.4 Integrasi database — opsional, memerlukan setup tersendiri

Runner proyek mengunci penulisan test ke **`127.0.0.1:5433/capstone_antrean_test`**, bukan database development baru port 5434 dan bukan `capstone_antrean`. Karena target ini hard-coded, jangan mengubah runner agar menulis ke database aplikasi demi kemudahan.

**PERLU DIKONFIGURASI:** instance/role database test pada port 5433 di laptop tujuan, database test **baru**, kredensial test, dan migration. Pembuatan instance/role mengikuti Bagian 6 dengan nama/port khusus test; jangan menganggap server/role port 5434 otomatis tersedia pada 5433. Tidak diperlukan untuk sekadar membuka kelima portal.

Setelah operator membuktikan database test yang baru dan kosong, gunakan terminal terpisah berikut. Ganti placeholder; `migrate status` harus menampilkan nama **`capstone_antrean_test`** dan endpoint **5433** sebelum migration. **Jangan menjalankan seed master** pada blok test, karena seed meng-override URL dari `.env` root.

**Direktori: `apps/api`, terminal test terisolasi laptop tujuan.**

```powershell
Set-Location C:\Workspaces\capstone-B-antrian\apps\api
$env:DATABASE_URL = 'postgresql://GANTI_USER_TEST:GANTI_PASSWORD_TEST_URL_ENCODED@127.0.0.1:5433/capstone_antrean_test?schema=public'
npx prisma migrate status
# Hanya database test BARU dan identitas yang telah cocok:
npx prisma migrate deploy
npm run build
node test/run-doctor-portal.cjs --suite=queue-snapshot
Remove-Item Env:DATABASE_URL
```

Runner memverifikasi database/migration, membuat fixture, dan memeriksa fingerprint sesudah cleanup. Pertahankan assertion tersebut. Full suite dapat dijalankan melalui runner `--all` oleh developer yang memahami isolasi; pada host terbatas, eksekusi serial per suite lebih sesuai daripada menjalankan browser/build/database tests bersama. `npm run test:e2e` langsung bukan langkah instalasi dasar karena tidak memberikan guard luar yang sama. Jangan memakai opsi maintenance/reset atau memigrasikan otomatis database development existing untuk memenuhi tes.

## 12. Troubleshooting

| Masalah | Kemungkinan penyebab | Langkah pemeriksaan/solusi |
|---|---|---|
| `flutter`/`dart` tidak dikenali | PATH belum benar atau terminal lama | Tambahkan folder `flutter\bin` aktual, buka terminal baru, periksa `Get-Command` dari Bagian 3 |
| Dart tidak memenuhi constraint | Flutter yang aktif terlalu lama/SDK lain mendahului PATH | Cocokkan `flutter --version` dan `dart --version` dengan Bagian 2; jangan mengubah pubspec/lockfile |
| `flutter doctor` belum siap | Android SDK, command-line tools, lisensi, atau Java belum sesuai | Selesaikan komponen target yang digunakan, jalankan doctor dari direktori `apps/client`/folder pengguna; jangan mengabaikan error toolchain Android bila akan build APK |
| `node`/`npm` tidak ditemukan | Node belum terpasang/PATH belum diperbarui | Instal Node 24 kompatibel lalu buka terminal baru; npm ikut Node |
| `npm.ps1`/`npx.ps1` diblokir | Execution policy PowerShell | Gunakan `npm.cmd`/`npx.cmd`; jangan membuka policy global tanpa kebutuhan |
| `EBADENGINE` | Node 24 minor terlalu lama atau major tidak sesuai | Gunakan Node 24 >=24.15.0 dan ulangi `npm ci`; jangan regenerasi lockfile |
| PostgreSQL connection refused | Service/container berhenti, port/host salah | Periksa instance/container baru dan mapping 5434; jangan beralih ke database lama 5433 untuk mencoba-coba |
| Prisma gagal autentikasi/koneksi | `DATABASE_URL` tidak cocok, password tidak URL-encoded, terminal mewarisi URL lain | Periksa `.env` root dan override terminal tanpa mencetak secret; validasi melalui psql/migrate status pada target baru |
| Prisma Client/module belum ada | `generate` belum dijalankan atau dependency gagal | Dari `apps/api`, selesaikan `npm ci` lalu `npx prisma generate` sebelum build/start |
| Port 3000/5173 terpakai | Ada proses lain | Identifikasi PID dengan blok diagnostik di bawah; hentikan hanya proses sendiri atau pilih port baru dan sesuaikan API base/CORS |
| CORS error | Origin tidak persis cocok; localhost berbeda dari 127.0.0.1/IP LAN | Isi origin frontend lengkap tanpa path pada `CORS_ALLOWED_ORIGINS`, restart backend; jangan mengganti menjadi wildcard untuk cookie |
| Frontend tidak dapat mengakses API | Dart-define salah, prefix `/api/v1` hilang, backend belum sehat, firewall/mixed content | Uji health dari perangkat yang sesuai, cocokkan host/port; build/run ulang setelah mengubah dart-define; HTTPS frontend memerlukan API HTTPS |
| Socket.IO tidak terhubung | Origin ditolak, token/sesi tidak valid, assignment atau scope salah, jalur WebSocket terblokir | Periksa namespace sesuai role, koneksi `/socket.io/`, login/penugasan/perangkat; CORS bukan pengganti RBAC |
| Emulator gagal dengan localhost | Localhost menunjuk Android | Emulator Android Studio memakai `10.0.2.2`; ponsel memakai IP LAN host |
| APK/Gradle gagal | SDK/NDK/lisensi/Java tidak kompatibel atau host kehabisan resource | Ikuti error pertama dan doctor; pertahankan wrapper Gradle 9.3.1/AGP 9.1.0/Kotlin 2.4.0. Tutup build/emulator yang tidak dibutuhkan; jangan upgrade/downgrade toolchain massal |
| Login gagal setelah seed | Seed tidak membuat akun atau akun nonaktif/password salah | Bootstrap ADMIN baru sesuai 10.1; pasien register sebagai USER, petugas/dokter diprovision ADMIN. Tidak ada password default yang boleh ditebak |
| PETUGAS tidak punya loket/403 | Akun/penugasan/loket/poli tidak aktif atau tanggal di luar periode | ADMIN memperbaiki relasi dan periode; jangan mengubah guard/role untuk melewati pemeriksaan |
| Dokter tidak bisa login/katalog kosong | Profil dokter aktif belum tertaut atau jadwal/slot belum tersedia | Provision akun dari menu Dokter; cek relasi poli, sesi dan slot sesuai tanggal pelayanan |
| Pairing display gagal | Kode bukan 12 digit, expired/terpakai, perangkat nonaktif, beda site/cookie ditolak | Buat kode baru melalui ADMIN, cocokkan layanan dan hostname, periksa cookie HttpOnly melalui DevTools tanpa menyalin nilainya; jangan menonaktifkan SameSite |
| Tab display baru meminta aktivasi | Selector per tab belum ada | Pair perangkat/tab tersebut secara terpisah; jangan menyalin token atau mengandalkan cookie ambient perangkat lain |
| Kamera tidak tersedia | Izin ditolak, tidak ada kamera, origin HTTP LAN bukan secure context | Izinkan kamera, gunakan localhost atau HTTPS terpercaya. [getUserMedia memerlukan secure context](https://developer.mozilla.org/en-US/docs/Web/API/MediaDevices/getUserMedia); jangan memakai flag browser yang mengabaikan keamanan |
| TTS senyap | Belum ada gesture aktivasi, browser/OS mute, voice Indonesia belum tersedia | Klik Aktifkan suara, periksa volume/output/voice OS; initial load/reconnect memang senyap untuk panggilan lama |
| Ponsel/monitor LAN tidak terhubung | IP salah, jaringan guest/VPN/isolasi Wi-Fi, binding/firewall | Uji port API dari perangkat dan atur rule Private/LocalSubnet saja; jangan mematikan firewall secara keseluruhan |
| Snapshot 500/503/P2028 | Transaksi gagal/acquisition deadline atau latency host/database | Catat endpoint/waktu/error tanpa secret, periksa beban dan koneksi. Jangan menaikkan timeout atau retry POST otomatis agar tampak berhasil; perubahan backend perlu diagnosis tersendiri |

**Direktori: root repository; diagnostik read-only Windows.**

```powershell
Set-Location C:\Workspaces\capstone-B-antrian
Get-NetTCPConnection -State Listen -LocalPort 3000,5173 -ErrorAction SilentlyContinue |
    Select-Object LocalAddress, LocalPort, OwningProcess
Test-NetConnection -ComputerName localhost -Port 3000
```

Untuk memeriksa PID, gunakan Task Manager atau `Get-Process -Id <PID_YANG_DITEMUKAN>` dari direktori yang sama, dengan mengganti placeholder. Jangan menghentikan proses lain tanpa mengetahui pemiliknya. Jika port frontend dipilih selain 5173, perbarui allowlist origin; bila API bukan 3000, perbarui API base seluruh klien.

## 13. Menjalankan pada Jaringan Lokal

Gunakan jaringan Private yang dipercaya. Database tetap hanya diakses backend secara lokal; tidak ada kebutuhan membagikan port PostgreSQL kepada ponsel/TV atau membuat port forwarding internet.

### 13.1 IP, binding, dan CORS

**Direktori: root repository pada komputer host.**

```powershell
Set-Location C:\Workspaces\capstone-B-antrian
Get-NetIPConfiguration
Get-NetTCPConnection -State Listen -LocalPort 3000 -ErrorAction SilentlyContinue |
    Select-Object LocalAddress, LocalPort, OwningProcess
```

Pilih IPv4 adaptor LAN/Wi-Fi yang aktif, bukan IP VPN/loopback. Contoh berikut memakai `192.168.1.20`; **ganti dengan IP aktual**. `main.ts` menggunakan `app.listen(port)` tanpa argumen host; tidak ada variabel `API_HOST`/`HOST` yang digunakan untuk binding pada source ini. Verifikasi alamat listen dan jangkauan aktual; jangan mengarang flag npm untuk mengubah host.

Pada `.env` **laptop tujuan**, tambahkan origin frontend LAN, misalnya:

```dotenv
CORS_ALLOWED_ORIGINS=http://localhost:5173,http://127.0.0.1:5173,http://192.168.1.20:5173
```

Restart backend. Untuk menyajikan frontend development ke browser LAN:

**Direktori: `apps/client`, terminal frontend; contoh IP wajib diganti.**

```powershell
Set-Location C:\Workspaces\capstone-B-antrian\apps\client
flutter run -d web-server --web-hostname 0.0.0.0 --web-port 5173 --dart-define=API_BASE_URL=http://192.168.1.20:3000/api/v1 --dart-define=SERVICE_TIME_ZONE=Asia/Jakarta
```

Browser LAN membuka `http://192.168.1.20:5173`, bukan `0.0.0.0`. Target `web-server` adalah server development Flutter, bukan konfigurasi deployment publik. Untuk ponsel Android fisik, gunakan ID perangkat aktual dengan API base LAN yang sama pada perintah Android Bagian 8.

### 13.2 Firewall terbatas

Jika firewall memblokir akses yang memang diperlukan, izinkan aplikasi/port 3000 dan 5173 hanya pada profil **Private** dan subnet lokal. Contoh opsional berikut memerlukan PowerShell **Run as Administrator** pada laptop tujuan; pilih setelah memahami bahwa port aplikasi dapat diakses perangkat pada subnet tersebut.

**Direktori: root repository, PowerShell administrator laptop tujuan.**

```powershell
Set-Location C:\Workspaces\capstone-B-antrian
New-NetFirewallRule -DisplayName 'QueueB Local Development' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 3000,5173 -Profile Private -RemoteAddress LocalSubnet
```

Jangan menambahkan port PostgreSQL ke rule ini. Jangan mematikan firewall atau membuka router ke internet. Jika jaringan menggunakan client isolation/guest Wi-Fi, minta pengelola jaringan menyediakan konektivitas yang sesuai; rule firewall host tidak menghilangkan isolasi tersebut.

### 13.3 HTTP, HTTPS dan sesi display

- HTTP localhost pada browser laptop cocok untuk development dan kamera; HTTP pada IP LAN **bukan** secure context kamera. Gunakan HTTPS dengan sertifikat yang dipercaya perangkat untuk kamera Web di LAN; jangan melewati peringatan sertifikat atau mematikan proteksi browser.
- HTTPS frontend tidak boleh memanggil API HTTP karena mixed content. Untuk penggunaan HTTPS, **frontend, API dan WebSocket** harus tersaji dengan skema/hostname/site yang konsisten, termasuk penerusan `/socket.io/`. Hostname, sertifikat dan reverse proxy lokal tersebut **PERLU DIKONFIGURASI** oleh pengelola; repository tidak menyediakan konfigurasi HTTPS lokal siap pakai di alur ini.
- Android debug mengizinkan HTTP lokal; Android release memerlukan endpoint HTTPS yang sesuai. Memasang APK tidak otomatis menyiapkan TLS/server.
- Cookie display menggunakan `SameSite=Strict`; CORS tidak menjadikannya bisa lintas site sembarangan. Untuk monitor LAN, gunakan frontend/API pada hostname/IP host yang konsisten. Pada `NODE_ENV=production`, cookie juga `Secure`, sehingga HTTP tidak menjadi solusi yang benar.
- Public Display pada browser perlu gesture **Aktifkan suara**, kebijakan audio/voice OS, dan pairing perangkat sendiri. Kemampuan kamera/TTS pada perangkat TV/browser tertentu perlu acceptance fisik; keberhasilan Web di laptop tidak menjaminnya.

## 14. Development Workflow

1. Buka terminal database/backend/frontend sesuai Bagian 9; gunakan peran akun yang tepat pada browser context/perangkat berbeda.
2. Backend `npm run start:dev` memakai watch mode. Pada terminal Flutter, `r` untuk hot reload dan `R` untuk hot restart; perubahan dart-define memerlukan run/build ulang.
3. Jalankan analyze/unit test sebelum review. Test integrasi/browser/perangkat harus menggunakan database test terpisah dan runner guard, bukan database aplikasi.
4. Bangun Web/APK menggunakan alamat target yang sesuai; build debug, development server, dan deployment production adalah kegiatan berbeda.
5. Tinjau Git tanpa menimpa pekerjaan lokal. Dokumen ini tidak mengotorisasi commit/push otomatis.

**Direktori: root repository, sebelum menarik perubahan.**

```powershell
Set-Location C:\Workspaces\capstone-B-antrian
git status -sb
git diff --stat
# Jalankan hanya setelah memastikan pekerjaan lokal aman dan tidak tertimpa:
git pull --ff-only origin main
```

Jika pull ditolak karena perubahan lokal atau branch divergen, hentikan dan selesaikan bersama tim; jangan memakai reset, clean massal, force push, atau stash tanpa memahami pekerjaan yang harus dipertahankan. Setelah dependency/schema berubah pada commit yang ditarik, baca diff lockfile dan migration; jangan menjalankan migration otomatis pada database berisi data.

**Direktori: `apps/client`, contoh pemeriksaan rutin lokal.**

```powershell
Set-Location C:\Workspaces\capstone-B-antrian\apps\client
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
```

Backend unit/lint/build dan build Web/APK menggunakan perintah Bagian 11. CI existing memeriksa Flutter format/analyze/test serta backend generate/lint/unit/build; CI tersebut bukan pengganti integrasi database, pairing browser, atau acceptance kamera/speaker nyata.

### Menghentikan sistem

- Terminal Flutter: tekan `q` atau `Ctrl+C`.
- Terminal Nest watch: tekan `Ctrl+C`.
- Terminal Prisma Studio yang masih terbuka: tekan `Ctrl+C`.
- PostgreSQL native: stop **instance lokal baru yang tepat** melalui Windows Services bila memang tidak digunakan aplikasi lain; data tetap disimpan.

**Direktori: root repository, hanya bila memakai container baru Bagian 6.3.**

```powershell
Set-Location C:\Workspaces\capstone-B-antrian
docker stop queueb-local-new-postgres
```

Tidak perlu menghapus container/volume atau database untuk shutdown. Saat memulai lagi, gunakan `docker start` pada container yang sama sesuai Bagian 6.3.

## 15. Checklist Instalasi

- [ ] Laptop/OS dan kapasitas cukup untuk target Web/Android yang dipilih.
- [ ] Git dan editor siap; akses GitHub sah tersedia.
- [ ] Flutter/Dart sesuai constraint dan acuan proyek, PATH tidak mengambil SDK lain.
- [ ] Node 24 kompatibel dan npm dapat dijalankan.
- [ ] Untuk Android: SDK/JDK/lisensi dan perangkat/AVD terdeteksi.
- [ ] Repository `main` di-clone pada folder kosong; HEAD diperiksa.
- [ ] Metode PostgreSQL dipilih: native **atau** container terpisah.
- [ ] Database **baru** `queueb_local_new:5434`, role/password baru, dan kondisi awal diverifikasi.
- [ ] Tidak ada koneksi setup diarahkan ke development existing `capstone_antrean:5433`.
- [ ] `.env` root lokal dibuat dari template tanpa menimpa file lain; JWT berbeda dan kuat.
- [ ] `DATABASE_URL`, `POSTGRES_*`, port API, CORS, dan timezone konsisten.
- [ ] `npm ci` dan `npx prisma generate` selesai pada laptop tujuan.
- [ ] Datasource diperiksa sebelum `migrate deploy`; migration selesai tanpa reset.
- [ ] Bila seed master dipilih, hanya dijalankan pada database baru; tidak mengharapkan akun dari seed.
- [ ] Backend watch berjalan dan health menyatakan database connected.
- [ ] `flutter pub get` selesai dan frontend dapat dibuka dengan API base yang benar.
- [ ] ADMIN pertama diprovision pengelola database baru, tanpa password default/rekaan.
- [ ] Master poli/ruang/jam, dokter/relasi/sesi/slot disiapkan sesuai kebutuhan.
- [ ] Akun PETUGAS beserta penugasan aktif dan akun DOKTER tertaut tersedia.
- [ ] Pasien sintetis dapat login dan membaca katalog; tidak membuat booking operasional untuk smoke test.
- [ ] Display dipasangkan dengan perangkat/kode tersendiri; cookie/site dan realtime benar.
- [ ] Izin kamera, secure context, gesture audio dan voice dipahami.
- [ ] Bila memakai LAN: IP, binding, CORS, firewall Private/subnet dan kebutuhan HTTPS diperiksa; database tidak dibagikan.
- [ ] Analyze/unit/build dijalankan sendiri bila diperlukan; integrasi hanya pada test DB tervalidasi.
- [ ] Secret/dump/data pasien tidak masuk Git atau dibagikan pada chat/log.
- [ ] Cara stop/start diketahui tanpa menghapus data.

## 16. Catatan Keamanan

- `.env` diabaikan Git; jangan commit, menyalin secret komputer lain, atau meletakkan JWT/password/token/QR pada URL, dart-define, screenshot, analytics, maupun log bersama.
- Jangan menyalin database pasien asli untuk menjalankan laptop pribadi. Gunakan identitas dan data sintetis baru.
- Tidak ada instruksi reset database existing dalam panduan ini. Jangan memakai maintenance/reset/seeder tanggal tetap sebagai bootstrap instalasi.
- Pisahkan aplikasi development, database test, dan data operasional. Nama yang mirip bukan bukti isolasi: periksa host, port, database aktual, role, dan keadaan awal sebelum setiap migration/seed/test yang menulis.
- Pertahankan JWT/RBAC dan pemeriksaan penugasan backend. Bootstrap manual ADMIN dibatasi operator database baru; bukan fitur elevasi role untuk pengguna aplikasi.
- Jangan mengekspos PostgreSQL/Prisma Studio ke internet. Untuk LAN aplikasi, batasi firewall pada jaringan Private/subnet dan jangan membuat port forwarding publik.
- Gunakan dua JWT secret acak yang berbeda dan password database lokal baru. Jangan menganggap placeholder `.env.example` sebagai secret layak pakai.
- Cookie display HttpOnly/SameSite/Secure dan pemisahan selector per tab dipertahankan. Jangan menonaktifkan proteksi browser untuk mengatasi salah konfigurasi host/TLS.
- Default tampilan nama pasien tetap tersamar. Nama lengkap dan kebijakan pengumuman publik memerlukan keputusan pengelola, bukan kebutuhan instalasi.
- Kamera nyata, suara speaker/TV, koneksi LAN dan ketahanan sesi perlu pemeriksaan pada perangkat tujuan. Tidak ada klaim pengujian ulang runtime dari pekerjaan dokumentasi ini.

### Sumber konfigurasi repository

- [Instruksi proyek](../../AGENTS.md), [README Flutter](../../apps/client/README.md), [kontrak API](../backend/API_INTEGRATION_GUIDE.md).
- [Backend scripts](../../apps/api/package.json), [lockfile npm](../../apps/api/package-lock.json), [validasi environment](../../apps/api/src/config/env.validation.ts), [Nest ConfigModule](../../apps/api/src/app.module.ts), [startup backend](../../apps/api/src/main.ts).
- [Template environment](../../.env.example), [Compose existing](../../compose.yml), [Prisma config](../../apps/api/prisma.config.ts), [schema](../../apps/api/prisma/schema.prisma), [seed master](../../apps/api/prisma/seed.ts).
- [Flutter dependency/constraint](../../apps/client/pubspec.yaml), [lockfile Flutter](../../apps/client/pubspec.lock), [API base Flutter](../../apps/client/lib/src/config.dart), [routing/role awal](../../apps/client/lib/src/app.dart).
- [Akun USER](../../apps/api/src/users/users.service.ts), [provisioning PETUGAS](../../apps/api/src/akun-petugas/akun-petugas.controller.ts), [provisioning DOKTER](../../apps/api/src/dokter/dokter.controller.ts), [cookie display](../../apps/api/src/display/display-cookie.ts).
- [Gradle Android](../../apps/client/android/app/build.gradle.kts), [plugin Android](../../apps/client/android/settings.gradle.kts), [HTTP debug](../../apps/client/android/app/src/debug/AndroidManifest.xml), [CI](../../.github/workflows/ci.yml).

Rujukan unduhan dan perilaku tool eksternal ditautkan pada bagian terkait. Bila README lama berbeda dengan konfigurasi di atas, verifikasi source pada commit yang digunakan; jangan mengubah source/lockfile hanya untuk menyesuaikan contoh dokumentasi lama.
