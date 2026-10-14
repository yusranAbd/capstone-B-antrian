# Milestone 2 — Integrasi Backend QueueB Hospital

Tanggal: 14 Oktober 2026. Branch: `feature/hospital-integrasi-h3`.
Baseline: `d5ba177` (merge PR #37, H3.3). Status: finalisasi Milestone 2 diotorisasi Project Lead; menjadi baseline Backend MVP untuk integrasi frontend.

## Hasil dan batas kesiapan

Integrasi booking/walk-in, QR, CHECK_IN, ENQUEUE dan pemanggilan Hospital telah diselaraskan tanpa endpoint mutasi baru, perubahan schema atau migration. Kuota harian berlaku pada kedua mode appointment; validasi Hospital menggunakan konteks relasi yang sama; informasi ketersediaan slot memperhitungkan kuota poli. FIFO ANTREAN_HARIAN dan pelayanan yang sudah berjalan tetap memakai State Machine existing.

Project Lead menyetujui metadata `alasanTidakLayak` dan filter baca `hanyaTidakLayak`, serta memutuskan agar resolusi manual tetap menjadi gap tanpa mutasi tambahan. Tiket appointment MENUNGGU setelah sesi berakhir tetap tercatat dan tidak diambil CALL normal. **Penanganan manual belum lengkap:** belum ada tindakan API sah untuk menutup tiket tersebut atau memperpanjang sesi yang telah berisi slot. Lihat [audit dan usulan HOSP-OPS-01](HOSP_OPS_01_GAP_DAN_USULAN.md). Instruksi final Project Lead mengizinkan gap ini ditunda ke revisi berikutnya; dua alur utama siap diintegrasikan. Deployment produksi tetap memerlukan konfigurasi lingkungan dan penilaian risiko tersendiri.

## Masalah dan perubahan teknis

| Masalah | Perubahan | Dampak |
|---|---|---|
| Booking JANJI_TEMU_DOKTER melewati kuota harian | Pemeriksaan jadwal, jam poli dan kuota harian setelah lock counter, sama dengan HIBRIDA | Jadwal nonaktif/invalid menghasilkan 400; kuota penuh 409. Semua tiket selain DIBATALKAN termasuk SELESAI tetap dihitung |
| Hubungan appointment tidak diperiksa menyeluruh ketika masuk antrean | Shared select/validator slot–sesi–dokter–relasi–poli–ruang dan tanggal/rentang; integrasi CHECK_IN/ENQUEUE/selector | Salah ruang 403; konteks Hospital invalid CHECK_IN 400, ENQUEUE 409; penolakan tidak mengonsumsi QR atau menambah counter/audit |
| Akhir slot berbeda dari akhir sesi | Slot berakhir tetap layak selama sesi berlangsung; akhir sesi menolak CALL normal dan penerimaan baru | Tidak menetapkan toleransi keterlambatan numerik atau mengubah status secara otomatis |
| Walk-in HIBRIDA membutuhkan konteks pelayanan dokter | ENQUEUE pada ruang CHECK_IN; CALL membutuhkan sesi dokter aktif pada ruang/tanggal/waktu peminta | Walk-in tetap lewat POST reservasi dan tidak dijadikan appointment |
| Informasi kelayakan pada berbagai jalur berbeda | CALL, daftar menunggu dan snapshot menggunakan selector dan pemeriksaan sesi aktif yang sama | Prioritas H3.3 tetap: slot, waktu REQUEUE terbaru atau CHECK_IN, urutan masuk, ID; harian tetap FIFO |
| Tiket setelah akhir sesi sulit dibedakan dari slot mendatang | Metadata alasan dan filter baca yang disetujui, tanpa mutasi tiket | SESI_BERAKHIR berbeda dari SLOT_BELUM_DIMULAI; filter diterapkan sebelum batas 100 |
| Konversi primitive ValidationPipe menghilangkan nilai query invalid | Hindari konversi Boolean global sebelum ParseBoolPipe dengan metadata tipe union | Nilai selain literal true/false ditolak 400; tanpa parameter default false |
| tersedia hanya memperhatikan kapasitas slot | Periksa mode, relasi, tanggal, jam poli dan kuota harian dalam RepeatableRead; cache kuota per poli/tanggal pada daftar | sisaKapasitas tetap kapasitas slot. tersedia false dapat terjadi saat sisa slot positif; bukan jaminan booking personal |
| Otorisasi Socket.IO mengasumsikan Jakarta | Gunakan SERVICE_TIME_ZONE melalui helper waktu pelayanan | Tanggal penugasan realtime mengikuti tanggal layanan REST, termasuk rollover Jayapura |

Pola transaksi Serializable, lock sesi/slot/counter, retry terbatas, update versi/status kondisional, audit aktor, QR sekali pakai dan best-effort broadcast existing dipertahankan. START/COMPLETE tidak diberi pemeriksaan baru akhir sesi yang akan menghalangi penyelesaian pasien DIPANGGIL/DILAYANI. Tidak ada perubahan Public Display, JWT/RBAC, nomor tiket atau status database.

## Kontrak API dan integrasi

Perluasan baca yang disetujui:

- `GET /queue/menunggu?loketId=<uuid-v4>&hanyaTidakLayak=true`: JWT PETUGAS dan penugasan aktif tetap wajib. Literal true/false, default false; true pada ANTREAN_HARIAN ditolak 400. Respons array maksimum 100; filter bukan pagination.
- `alasanTidakLayak` opsional pada tiket Hospital di daftar/snapshot: null jika layak, kode alasan jika belum/tidak layak. Tidak mengandung identitas pasien, QR atau data medis. Klien harus menerima kode alasan baru secara defensif.
- Detail slot menambah metadata relasi loketId/layananId/modeReservasi. Field ketersediaan existing tetap, dengan pemeriksaan yang lebih lengkap.
- Tidak ada endpoint baru; DTO mutasi, status dan versiSkema 1 tetap. Validasi yang lebih ketat dapat menolak data master tidak konsisten yang sebelumnya lolos.

[Panduan integrasi API](API_INTEGRATION_GUIDE.md), Bagian 17, mencatat 22 endpoint Hospital existing, mode, DTO, respons, status error, aturan kuota, QR, selector, timezone dan checklist API Web/Flutter. Tidak ada implementasi frontend.

Kelayakan dapat berubah karena waktu berlalu tanpa event mutasi. Klien perlu refresh snapshot pada batas waktu dan sebelum CALL. Daftar/filter tetap terbatas pada tanggal pelayanan berjalan dan scope penugasan; tiket hari lalu tidak otomatis berpindah tanggal. Tindak lanjut historis dan resolusi manual memerlukan keputusan terpisah.

## Manifest perubahan yang direkomendasikan

**23 file scope Milestone 2** (18 modifikasi tracked dan 5 file baru). Manifest finalisasi Git Milestone 2 yang diotorisasi.

| File | Tujuan |
|---|---|
| `apps/api/src/hospital/hospital-context.ts` (baru) | Select internal, validasi relasi/tanggal/jam dan helper timezone |
| `apps/api/src/check-in/check-in.service.ts` | Validasi Hospital sebelum konsumsi QR |
| `apps/api/src/check-in/check-in.service.spec.ts` | Regresi penerimaan dan penolakan konteks |
| `apps/api/src/janji-temu/janji-temu.service.ts` | Kuota kedua mode dan validasi tanggal/jam |
| `apps/api/src/janji-temu/janji-temu.service.spec.ts` | Regresi kuota dan konteks booking |
| `apps/api/src/queue/hospital-queue-selector.ts` | Alasan kelayakan dan sesi walk-in aktif |
| `apps/api/src/queue/hospital-queue-selector.spec.ts` | Regresi selector dengan relasi lengkap |
| `apps/api/src/queue/queue-snapshot.types.ts` | Metadata alasan opsional |
| `apps/api/src/queue/queue.controller.ts` | Filter baca dan parsing boolean ketat |
| `apps/api/src/queue/queue.service.ts` | ENQUEUE, filter, shared selector/sesi CALL dan snapshot |
| `apps/api/src/queue/queue.service.spec.ts` | Regresi ENQUEUE, sesi walk-in dan filter |
| `apps/api/src/queue/queue.snapshot.spec.ts` | Fixture snapshot dengan konteks Hospital |
| `apps/api/src/realtime/realtime-room-access.service.ts` | SERVICE_TIME_ZONE pada izin room |
| `apps/api/src/realtime/realtime-room-access.service.spec.ts` | Regresi tanggal pada timezone berbeda |
| `apps/api/src/slot-praktik/slot-praktik.service.ts` | Ketersediaan sesuai kuota/jadwal/konteks |
| `apps/api/src/slot-praktik/slot-praktik.service.spec.ts` | Regresi ketersediaan dan cache kuota |
| `apps/api/test/helpers/hospital-context.fixture.ts` (baru) | Fixture unit relasi Hospital lengkap |
| `apps/api/test/hospital-integrasi.e2e-spec.ts` (baru) | 21 kasus integrasi dan konkurensi |
| `apps/api/test/janji-temu.e2e-spec.ts` | Fixture dengan jadwal poli sah dan cleanup terscope |
| `apps/api/test/slot-praktik.e2e-spec.ts` | Fixture dengan mode/jadwal poli sah dan cleanup terscope |
| `docs/backend/API_INTEGRATION_GUIDE.md` | Kontrak Hospital terbaru dan checklist integrasi |
| `docs/backend/HOSP_OPS_01_GAP_DAN_USULAN.md` (baru) | Audit resolusi manual, persetujuan baca dan usulan mutasi yang belum diterapkan |
| `docs/backend/MILESTONE_2_INTEGRASI_HOSPITAL.md` (baru) | Laporan, manifest, hasil QA dan risiko |

## Verifikasi aktual

Perintah dijalankan dari apps/api kecuali runner lokal E2E. Type check, lint dan build diverifikasi masing-masing; keberhasilan unit test tidak dipakai sebagai bukti build.

| Pemeriksaan | Hasil |
|---|---|
| `npm test -- --runInBand --no-cache` | PASS — 568/568 test, 35/35 suite |
| Seluruh E2E `test/jest-e2e.json --runInBand --no-cache` | PASS — 255/255 test, 22/22 suite, 158,374 detik |
| E2E integrasi Hospital setelah koreksi query | PASS — 21/21 |
| `node node_modules/typescript/bin/tsc --project tsconfig.json --noEmit --incremental false` | PASS — exit 0 |
| `npm run lint` | PASS — exit 0, tanpa warning lint |
| `npm run build` | PASS — exit 0, NestJS build |
| `git diff --check` | PASS pada checkpoint Milestone 2 sebelum staging |

Regresi seluruh suite mencakup FIFO harian, reservasi, appointment, QR, CHECK_IN, ENQUEUE, CALL/RECALL, SKIP/REQUEUE, START/COMPLETE, rollback audit, autentikasi, snapshot, Socket.IO dan Public Display. Suite integrasi baru mencakup alur appointment/walk-in lengkap, HIBRIDA bersama, ruang/tanggal/relasi invalid, akhir slot, akhir sesi, status/audit tetap MENUNGGU, dan kelanjutan DIPANGGIL/DILAYANI.

Uji konkurensi terarah: 20 booking paralel dari tiga pasien pada kapasitas satu menghasilkan satu 201, 19 respons 409, satu tiket/appointment/audit; CALL paralel menghasilkan satu 200, satu 409 dan hanya satu tiket aktif. Ini bukti skenario teruji, bukan sertifikasi load/performance produksi.

Semua E2E hanya menggunakan `127.0.0.1:5433/capstone_antrean_test`. Runner lokal ignored `tmp/run-hospital-e2e.cjs` memvalidasi target URL, current_database dan enum HIBRIDA sebelum Jest. Runner membandingkan fingerprint row existing pada 16 tabel sebelum/sesudah dalam transaksi baca; hanya jumlah agregat dicatat. Cleanup terbatas fixture unik yang dibuat tes sesuai persetujuan; tidak ada reset atau migration. Suite rollback existing memakai constraint sementara untuk menyuntikkan kegagalan audit pada fixture lalu melepaskannya, bukan migration schema aplikasi.

Hasil pembandingan run akhir: 13 record existing sebelum tes; 0 hilang, 0 berubah, dan 0 record baru tersisa setelah cleanup. Log ERROR constraint audit pada skenario rollback merupakan fault injection yang disengaja; seluruh assertion rollback lulus. Tidak ada koneksi atau perubahan pada database development utama.

## Risiko dan keputusan yang masih terbuka

1. **Resolusi manual HOSP-OPS-01 tetap gap atas keputusan Project Lead.** Perlu persetujuan terpisah untuk perluasan pembatalan PETUGAS atau perpanjangan sesi resmi, termasuk otorisasi, alasan, lock dan audit. Jangan menyatakan fitur ini selesai atau membuat CALL bypass.
2. Daftar Hospital mengambil kandidat layanan/tanggal untuk diurutkan sebelum membatasi respons 100. Filter membantu melihat ketidaklayakan tetapi belum menyediakan pagination/backlog historis; ukuran antrean besar belum diuji beban.
3. Perubahan master dokter/poli/ruang/jadwal dapat membuat tiket existing tidak layak. Penolakan kini lebih lengkap; pemulihan operasional untuk data yang tidak konsisten memerlukan SOP dan jalur mutasi sah. Tidak ada perbaikan data otomatis.
4. Risiko race administrasi penugasan yang tercatat di baseline belum ditutup. Uji booking/CALL relevan telah lulus; seluruh interleaving administrasi, deployment multiproses dan failure jaringan belum dibuktikan.
5. Temuan dependency historis di panduan belum diaudit ulang atau dimitigasi pada milestone ini. Tidak ada upgrade package/lockfile. E2E masih mengeluarkan warning Node VM Modules dan deprecation query paralel pg; jangan menganggap warning ini sebagai hasil audit vulnerability terbaru.
6. Test ThrottlerStorage disederhanakan pada suite konkurensi baru agar menguji integritas booking/CALL. Regresi rate limit existing tetap dijalankan, tetapi 20 request paralel ini bukan bukti kapasitas limit produksi.
7. Otorisasi room realtime sudah memakai timezone layanan; reverse proxy/origin, provisioning akun/perangkat, broadcast multi-instance, konfigurasi rahasia dan monitoring tetap gate deployment. Hasil CI dilaporkan dari check PR aktual setelah finalisasi Git.

## Git dan langkah review

Branch dibuat dari main yang telah memuat merge PR #37. Schema Prisma, migration existing, generated client, dependency dan frontend tidak diubah. Artefak existing `apps/api/prisma/schema.hospital.H1.REVIEW.prisma`, `backups/`, `cls`, `sql/`, `.env` dan seluruh `tmp/` berada di luar manifest; jangan stage.

Pesan commit finalisasi yang diotorisasi Project Lead:

```text
feat(hospital): menyelaraskan integrasi reservasi dan antrean poliklinik
```

Instruksi final Project Lead mengotorisasi staging, commit, push dan PR; auto-merge tetap dilarang. Perubahan MVP wajib setelah checkpoint ini dicatat terpisah agar hasil pengujian dan manifest Milestone 2 tidak disalahartikan sebagai seluruh perubahan final.
