# Backend MVP QueueB Hospital — kesiapan integrasi

Tanggal: 14 Oktober 2026. Branch: `feature/hospital-integrasi-h3`, base `main`.

Status: Backend MVP siap untuk integrasi Web/Flutter; kedua alur utama lulus pengujian akhir. Finalisasi Git telah diotorisasi; PR/CI aktual dilaporkan dari GitHub. Tidak ada auto-merge. Kesiapan integrasi frontend berbeda dari persetujuan deployment produksi.

## Alur yang tersedia

**Appointment:** USER membaca dokter → jadwal bertanggal → slot tersedia → booking → tiket QR → PETUGAS CHECK_IN → ENQUEUE → CALL → START → COMPLETE.

**Walk-in:** USER memilih poli → reservasi → tiket QR → PETUGAS CHECK_IN → ENQUEUE → CALL → START → COMPLETE. ANTREAN_HARIAN tetap FIFO; HIBRIDA berbagi kuota/nomor dengan appointment dan CALL walk-in memerlukan sesi dokter aktif pada ruang peminta.

ADMIN dapat menyiapkan poli, jadwal operasional, ruang, penugasan PETUGAS, dokter, relasi dokter–poli, sesi dan slot melalui endpoint existing. Register publik tetap USER; akun ADMIN/PETUGAS pertama harus diprovision oleh pengelola server. JWT/RBAC, QR sekali pakai, audit transaksi, State Machine, Socket.IO dan Public Display tetap dipertahankan.

Panduan kontrak final: [API_INTEGRATION_GUIDE.md](API_INTEGRATION_GUIDE.md), khususnya Bagian 17–18. Bagian 18 memberi urutan request, body, sumber ID, role, status dan penanganan error untuk Web/Flutter. Tidak ada pengembangan frontend.

## Perubahan setelah checkpoint Milestone 2

Milestone 2 di-commit sebagai `cc1773a`: konsistensi kapasitas, validasi Hospital, selector, metadata/filter ketidaklayakan dan timezone. Checkpoint ini lulus 568 unit dan 255 E2E; manifest 23 file dan rincian terdapat pada [laporan Milestone 2](MILESTONE_2_INTEGRASI_HOSPITAL.md).

Satu penghalang penyiapan MVP ditutup: POST /layanan sebelumnya selalu menghasilkan ANTREAN_HARIAN, sehingga poli Hospital tidak dapat disiapkan melalui API. CREATE kini menerima field opsional modeReservasi dengan nilai enum existing. Request lama tanpa field tetap menghasilkan ANTREAN_HARIAN; JANJI_TEMU_DOKTER dan HIBRIDA dapat dipilih ADMIN. Nilai null/invalid ditolak 400. GET layanan mengembalikan mode yang tersimpan. PATCH tidak membuka perubahan mode poli existing; ini menghindari pengubahan interpretasi tiket yang sudah berjalan.

Tidak ada endpoint baru, schema/migration, upgrade dependency atau perubahan database utama. Toleransi menit/fairness baru tidak ditetapkan. Suite integrasi akhir menyiapkan seluruh master operasional melalui API ADMIN dan membuktikan pembacaan katalog oleh USER sebelum booking, bukan hanya menguji booking pada fixture yang dibuat langsung melalui DB. Promosi role fixture dan fault injection tetap terbatas database test.

Manifest commit final MVP setelah Milestone 2:

| File | Perubahan |
|---|---|
| `apps/api/src/layanan/dto/create-layanan.dto.ts` | Pilihan mode enum opsional, tanpa perubahan UPDATE |
| `apps/api/src/layanan/layanan.service.ts` | Simpan mode dengan default ANTREAN_HARIAN |
| `apps/api/src/layanan/layanan.service.spec.ts` | Regresi default lama dan kedua mode Hospital |
| `apps/api/test/layanan.e2e-spec.ts` | CREATE mode Hospital, RBAC, baca USER, null/invalid dan penolakan perubahan mode |
| `apps/api/test/hospital-integrasi.e2e-spec.ts` | Penyiapan melalui API ADMIN dan pemilihan katalog USER dalam alur lengkap |
| `docs/backend/API_INTEGRATION_GUIDE.md` | Versi 1.2, kontrak mode dan urutan request integrasi |
| `docs/backend/MVP_BACKEND_FINAL.md` | Status, bukti pengujian dan batas MVP |

## Pengujian akhir

| Pemeriksaan | Hasil akhir |
|---|---|
| Unit test seluruh backend, tanpa cache | PASS — 570/570 test, 35/35 suite |
| E2E seluruh backend, tanpa cache | PASS — 258/258 test, 22/22 suite, 189,188 detik |
| Lint type-aware | PASS — exit 0, tanpa warning lint |
| Type check TypeScript noEmit | PASS — exit 0 |
| NestJS build | PASS — exit 0 |
| Whitespace/staging scope | PASS — git diff --check, staging dibatasi manifest |

E2E terarah finalisasi mode/master API telah lulus 42/42 pada tiga suite. Seluruh E2E memakai `127.0.0.1:5433/capstone_antrean_test` setelah validasi URL dan current_database. Cleanup hanya fixture unik yang dibuat tes, sesuai persetujuan. Runner lokal membandingkan fingerprint record existing pada 16 tabel; tidak mencetak kredensial, data pasien atau fingerprint.

Run akhir: 13 record existing, 0 hilang, 0 berubah dan 0 record baru tersisa setelah cleanup. Log ERROR constraint sementara merupakan fault injection pada tes rollback audit yang assertion-nya lulus; bukan kegagalan run. Database development utama tidak digunakan. Perintah QA: npm test -- --runInBand --no-cache; npm run lint; npm run build; node node_modules/typescript/bin/tsc --project tsconfig.json --noEmit --incremental false; E2E test/jest-e2e.json --runInBand --no-cache melalui runner target-tervalidasi.

Suite mencakup katalog dokter/jadwal/slot, master ADMIN, booking/walk-in, kapasitas, QR, CHECK_IN, ENQUEUE, CALL/RECALL, SKIP/REQUEUE, START/COMPLETE, FIFO harian, invalid ruang/tanggal/relasi, rollback audit, authentication, snapshot, Socket.IO dan Public Display. Booking paralel 20 request pada kapasitas satu serta CALL paralel diuji dengan assertion tiket/appointment/audit dan status hasil. Uji konkurensi baru mengisolasi integritas transaksi dengan ThrottlerStorage test; regresi throttle existing tetap dijalankan.

CI existing pada PR menjalankan pemeriksaan repository, Flutter existing bila terdeteksi, serta NestJS lint, unit dan build setelah Prisma generate. E2E PostgreSQL dijalankan lokal sesuai pembatasan Project Lead; jangan mengartikan CI hijau sebagai hasil E2E remote atau sertifikasi load produksi.

## Revisi nonkritis yang ditunda

- Resolusi manual HOSP-OPS-01/perpanjangan sesi dengan slot. MENUNGGU setelah akhir sesi tetap tercatat dan tidak dapat di-CALL normal; metadata/filter baca tersedia. Pasien DIPANGGIL/DILAYANI sebelum sesi berakhir tetap dapat menyelesaikan pelayanan. Tidak ada auto-cancel/reschedule/requeue/perpindahan hari. Penundaan disetujui Project Lead; jangan menyatakan resolusi manual sudah tersedia.
- Toleransi keterlambatan numerik, fairness lanjutan, pagination/backlog historis, idempotency key dan pengubahan mode poli existing. Jangan membuat tombol frontend untuk mutasi yang belum tersedia.
- Uji beban besar dan semua interleaving administrasi penugasan. Uji booking/CALL terarah lulus, tetapi bukan jaminan untuk seluruh skenario deployment.

## Gate deployment terpisah

Temuan dependency historis belum diaudit ulang/dimitigasi dalam finalisasi ini; tidak ada perubahan package/lockfile. Warning VM Modules Node dan deprecation query paralel pg masih terlihat pada pengujian. Jangan menyamakan warning itu dengan audit vulnerability terbaru, atau menganggap risiko keamanan produksi telah ditutup.

Sebelum deployment, pengelola perlu memastikan SERVICE_TIME_ZONE, konfigurasi rahasia server, HTTPS/reverse proxy/origin, provisioning akun/perangkat, database/migration existing, observabilitas dan topologi Socket.IO sesuai lingkungan. Tidak ada reset, migrasi utama atau perubahan data produksi yang dijalankan oleh pekerjaan ini.

## Git

Commit Milestone 2 dan commit final MVP hanya memuat source/test/dokumentasi backend dalam manifest. `.env`, `backups/`, `sql/`, `cls`, schema review dan `tmp/` berada di luar commit. PR ditujukan ke main; merge menunggu persetujuan akhir Project Lead setelah check CI aktual berhasil. Hasil push/PR/CI dilaporkan dari GitHub, bukan diasumsikan dari hasil lokal.


## Perluasan Doctor Portal D1–D4 — 18 Oktober 2026

Perluasan yang disetujui menambah role DOKTER, relasi akun–profil opsional one-to-one dan provisioning ADMIN `POST /dokter/:id/akun`. Empat GET portal memakai dokter dari JWT/account database, tidak dari parameter dokterId. Snapshot dibatasi sesi sendiri aktif pada hari pelayanan; appointment lain disembunyikan, walk-in HIBRIDA dibatasi ruang/sesi. Respons tidak memuat identitas pasien atau rahasia QR. Mutasi Queue tetap PETUGAS dan tidak diubah.

Namespace `/doctor` memakai invalidasi setelah commit, autentikasi dan revalidasi sesi/akun/profil, pembatasan tanggal/ruang/sesi. USER `/patient`, PETUGAS `/queue` dan perangkat `/display` tetap memakai kontrak existing. Perubahan katalog terbaca pada rekonsiliasi REST; tidak ada broadcast data pasien. Kontrak/prosedur deployment: API_INTEGRATION_GUIDE.md Bagian 19. Laporan QA aktual: `docs/frontend/DOCTOR_PORTAL.md`.

Migration baru `20261018_doctor_portal_identity` aditif: enum DOKTER, nullable unique dokter.pengguna_id dan FK RESTRICT. Hanya database test lokal tervalidasi yang dimigrasikan untuk QA. **Database development/produksi belum disentuh; deployment migration menunggu persetujuan Project Lead.** Tidak ada reset, perubahan migration lama, dependency baru atau penambahan domain klinis.


QA final perluasan DOKTER: 589/589 unit (37 suite), 283/283 E2E (24 suite), type check, lint dan NestJS build PASS. Seluruh E2E menggunakan database test lokal tervalidasi; 13 record existing tetap utuh dan 0 fixture tersisa. Flutter 121 tes PASS, satu live opsional SKIP; Web nyata menerima lima invalidasi dokter untuk alur QR walk-in sampai COMPLETE, dan build Web release/APK debug PASS. Fixture waktu E2E H3.3 diperbaiki agar sesi relatif tidak melintasi tanggal pelayanan ketika dijalankan dekat tengah malam UTC; selector produksi tidak diubah. Detail batas perangkat dan bukti screenshot berada pada laporan Doctor Portal.
