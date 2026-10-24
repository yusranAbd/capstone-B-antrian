# Perbaikan antrean harian pada Portal DOKTER

## Temuan dan reproduksi

Pemeriksaan development `127.0.0.1:5433/capstone_antrean` dilakukan dengan transaksi
READ ONLY dan koneksi Prisma `default_transaction_read_only=on`. Tidak ada login,
mutasi tiket, perubahan master, migration, atau penghapusan data development.

Pada pemeriksaan 24 Oktober 2026, dr. Sindi memiliki akun DOKTER, profil dan relasi
poli Anak aktif, serta sesi hari ini yang sedang berlangsung di Ruang Anak 1.
Poli Anak menggunakan `ANTREAN_HARIAN`. Tiket `AN-001` adalah non-appointment,
MENUNGGU, dengan urutan antrean valid dan `loketId=null`. Audit tiket mengonfirmasi
alur CHECK_IN → ENQUEUE → CALL → SKIP → REQUEUE; setelah antre ulang, tiket kembali
ke pool bersama tanpa ruang. Tidak perlu mengubah atau mengisi loket pada data itu.

| Jalur | Sumber/filter | Hasil sebelum perbaikan |
| --- | --- | --- |
| PETUGAS | `GET /queue/snapshot?loketId=…`, `QueueService.snapshotAntrean` | Menunggu dibaca per poli/tanggal, bukan loket; AN-001 terlihat |
| DOKTER | `GET /portal-dokter/antrean/snapshot?jadwalPraktikId=…`, `PortalDokterService.snapshot` | Wajib loket tiket sama, lalu hanya appointment sesi sendiri atau walk-in HIBRIDA; AN-001 tersaring |
| Realtime dokter | namespace `/doctor`, `DoctorRealtimeGateway.invalidateTicket` | Non-appointment tanpa loket langsung diabaikan; query walk-in hanya HIBRIDA |
| Flutter | `DoctorPage.load`, `DoctorDashboardData`, `DoctorQueuePanel` | Membaca jadwal sendiri yang sedang live, menggabungkan appointment dan snapshot; tidak memfilter walk-in menjadi appointment-only |

Jadi penyebab langsung berada pada scope backend yang belum mendukung harian,
bukan tautan akun dokter, pencarian tabel, atau subscription ke room PETUGAS.
Frontend `/doctor` tidak mengirim join room manual; backend menentukan penerima.
Tanggal dan waktu dibandingkan pada hari pelayanan `Asia/Jakarta`; tidak ditemukan
perbedaan timezone sebagai penyebab kasus ini.

Reproduksi E2E sebelum fix: PETUGAS melihat dua tiket MENUNGGU, DOKTER menerima
`totalMenunggu=0`; event dokter harian juga tidak terkirim. Tiga dari empat tes
reproduksi awal gagal. Seluruh fixture dibersihkan tanpa mengubah 13 record existing.

## Perubahan minimum

- Snapshot dokter memasukkan pool MENUNGGU harian non-appointment pada poli/tanggal
  sesi aktif sendiri, termasuk tiket REQUEUE tanpa loket. FIFO tetap mengikuti
  `urutanMasukAntrean`, lalu `id`; selector Hospital tidak dipakai untuk harian.
- DIPANGGIL/DILAYANI tetap harus cocok dengan ruang sesi dokter. Appointment dokter
  lain, poli/tanggal lain dan sesi tidak aktif tetap tidak dapat diakses.
- Invalidasi `/doctor` untuk harian menjangkau seluruh sesi aktif pada poli yang
  sama agar pool bersama diperbarui, termasuk setelah CALL/REQUEUE. Event tetap
  hanya invalidasi tanpa data pasien; REST snapshot mempertahankan scope ruang.
- Tidak mengubah Queue Engine, frontend production, JWT/RBAC, endpoint, schema,
  migration, desain, prioritas Hospital, atau role lain.

Perbandingan service nyata sesudah fix (read-only) pada hari pelayanan 2026-10-24:

```json
{
  "petugas": [{"nomorAntrean":"AN-001","status":"MENUNGGU"}],
  "dokter": [{"nomorAntrean":"AN-001","status":"MENUNGGU","jenisAntrean":"WALK_IN","layakDipanggil":true}]
}
```

## Cakupan berkas yang diperiksa

- `apps/api/src/queue/queue.controller.ts`, `queue.service.ts`, `hospital-queue-selector.ts`.
- `apps/api/src/portal-dokter/portal-dokter.controller.ts`, `portal-dokter.service.ts`.
- `apps/api/src/realtime/doctor-realtime.gateway.ts`, `doctor-invalidation.interceptor.ts`, `realtime-broadcast.service.ts`.
- `apps/api/src/hospital/hospital-context.ts`, `apps/api/prisma/schema.prisma`.
- `apps/client/lib/src/queue.dart`, `doctor.dart`, `doctor_dashboard.dart`, `patient_sync.dart`, `config.dart`.
- Tes Doctor Portal, Queue Engine dan kontrak API pada panduan integrasi.

## Regresi

E2E hanya memakai `127.0.0.1:5433/capstone_antrean_test`, divalidasi sebelum fixture.
Regresi baru memakai JWT, reservasi → QR → Check-In → ENQUEUE, dua dokter pada poli
yang sama, satu dokter poli lain, dan urutan enqueue yang berbeda dari check-in.
Tes meliputi FIFO, CALL/START/COMPLETE, SKIP/REQUEUE tanpa loket, invalidasi dua sesi
poli yang sama, isolasi ruang/poli, kepemilikan sesi, sesi nonaktif dan RBAC.
Suite existing Doctor Portal tetap menguji appointment/HIBRIDA serta autentikasi.
Tes Flutter tambahan membuktikan snapshot walk-in dapat dirender saat appointment
kosong dan event `/doctor` memicu pembacaan ulang REST.

- Backend: 648/648 unit test (41 suite), type check, lint, build NestJS dan format PASS.
- Seluruh E2E backend: 327/327 PASS, 28/28 suite, tanpa suite gagal. Dijalankan
  berurutan dengan proses Jest terpisah per suite untuk membatasi penggunaan memori.
- Regresi spesifik: 24/24 PASS (5 harian baru + 19 Doctor Portal existing), termasuk
  FIFO harian, REQUEUE, HIBRIDA dan pembatasan akses antarpoliklinik.
- Integritas E2E: seluruh 13 record existing identik, nol hilang/berubah dan nol
  fixture tersisa; pemeriksaan seluruh tabel publik selain metadata migration
  diulang setelah setiap suite E2E lengkap.
- Flutter: 277 PASS, satu tes live opt-in dilewati; analyzer tanpa issue.
- Tidak ada perubahan UI production. Seluruh 51 file lokal pengguna dari baseline
  awal tetap identik dan tidak ditimpa.

- Build Flutter Web release PASS; endpoint build QA tetap menggunakan API test
  `127.0.0.1:3001`, bukan mutasi database development.
- API development pada port 3000 dikelola Nest watch; health sesudah perbaikan
  mengembalikan `status=ok` dan `database=connected`.

## Batasan yang tetap berlaku

Monitoring dokter membutuhkan sesi aktif miliknya pada hari pelayanan. Dokter tanpa
sesi, sesi belum mulai/berakhir, atau profil/relasi/ruang nonaktif tetap tidak mendapat
antrean. Pasien harian yang MENUNGGU belum ditetapkan kepada dokter tertentu; pool
bersama tidak berarti pasien sedang dilayani di semua ruang. Aplikasi/API yang
masih menjalankan build lama perlu memuat build backend terbaru.
