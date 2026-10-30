# Development Dataset V2 — 30 Oktober 2026

**Status: V2 FUNCTIONALLY VERIFIED — HISTORICAL SESSION AUDIT UNRESOLVED.** Pada 30 Oktober 2026 pengguna menyetujui pengecualian historis terbatas untuk penutupan development dan selective commit/push. Ketiga sesi lama tetap UNATTRIBUTED; `historicalStrict=FAIL`, `historicalSessionAttribution=FAIL`, dan `stageAGate=FAIL` dipertahankan. Lima kandidat cleanup tetap utuh. Lihat [keputusan penutupan](#final-closure--accepted-historical-audit-exception) dan [backlog keamanan](AUTH_SESSION_AUDIT_FOLLOWUP.md). Bagian refresh/smoke awal di bawah adalah catatan historis, bukan klaim bahwa audit keamanan telah lulus.

Target tunggal maintenance: **127.0.0.1:5433/capstone_antrean**, PostgreSQL 18, schema public. Semua automated mutation tests memakai **127.0.0.1:5433/capstone_antrean_test**, bukan development. Timezone pelayanan tetap **Asia/Jakarta**. Tidak ada perubahan Prisma schema/migration, Queue Engine atau auth/RBAC. Perluasan katalog frontend dijelaskan pada hasil verifikasi akhir. Tidak ada deployment publik.

## Backup dan safety

Batch privat di luar seluruh worktree Git: `D:/QueueB-Backups/development-dataset-v2/20261030-v2`.

Backup terakhir sebelum apply:

- File: `capstone_antrean_2026-10-30T11-02-13-284Z_29c5c88c.dump`.
- SHA-256: `f294101a02cc4eb39fdf2cbedfceb8176396be0ee37198bc5901be6b69c29138`.
- Ukuran: **146.179 byte**, custom archive PostgreSQL.
- Inventaris 17 tabel, `pg_restore --list` dan decoding penuh offline berhasil. Tidak melakukan restore ke database mana pun.
- Backup awal sebelum perencanaan juga disimpan; backup segar dibuat ulang tepat sebelum apply.
- ACL batch: inheritance dimatikan; hanya pemilik Windows saat ini dan SYSTEM memperoleh akses. CLI V2 memeriksa ACL sebelum membuka batch privat. Pada Unix, mode direktori harus 0700.
- Snapshot hash per-ID, admin utama, 22 foreign key dan 8 migration diverifikasi. Query DATE memakai teks YYYY-MM-DD; instan praktik dibuat dengan offset +07:00, terpisah dari timezone host WIT.

## Provenance dan cleanup

Provenance bukan nama generik: manifest `queueb-synthetic-20261027-v1` yang complete, ID layanan/jadwal pada seed-state, identitas akun/role dari credential manifest seed, rentang pembuatan seed, serta fingerprint checkpoint backup 28 Oktober. Daftar ID dan dependensi tersimpan privat pada `plan-final.json`; tidak dimasukkan ke Git.

Tiket harus cocok dengan akun seed, layanan seed dan waktu pembuatan seed. Aktivitas/update/event di luar window, aktor tidak terverifikasi, atau dependensi bukan-demo memblokir penghapusan. Jadwal lama hanya dihapus bila ID-nya tercatat pada manifest, tanggal sebelum 31 Oktober, hash jadwal/slot cocok checkpoint, dan tidak mempunyai appointment yang dipertahankan. Counter hanya dihapus pada scope seed yang tidak menyisakan tiket lain.

| Model | Dihapus |
|---|---:|
| notifikasi | 0 |
| peristiwa_antrean | 70 |
| janji_temu | 29 |
| tiket_antrean | 42 |
| urutan_antrean_harian | 31 |
| slot_praktik | 213 |
| jadwal_praktik | 21 |
| pengguna / sesi_pengguna / perangkat_tampilan | 0 / 0 / 0 |

Total **406 record** terverifikasi dibersihkan dalam satu transaksi. DELETE selalu memfilter array ID allowlist; tidak memakai cascade, TRUNCATE, DROP, migration reset, atau menonaktifkan constraint. Baseline diperiksa ulang sesudah lock singkat; perubahan tak terencana membatalkan transaksi. Hash seluruh record yang tidak dihapus cocok segera sesudah apply.

**Dipertahankan:** satu tiket seed dengan aktivitas lanjutan dan empat jadwal seed lama beserta dependensi/slot yang tidak aman dibersihkan; 12 tiket di luar provenance seed; seluruh akun lama termasuk akun nonaktif; seluruh session lama, enam perangkat/pairing Display; dokter dan konfigurasi existing yang valid. Dua jadwal FARM01 tanggal 29–30 Oktober juga tetap. Tidak ada klaim bahwa semua data tersisa adalah dummy atau semua dummy telah dihapus.

## Layanan harian dan petugas

| Kode | Layanan | Petugas simulasi V2 | Role |
|---|---|---|---|
| PENDAFTARAN | Pendaftaran | Nadia Putri | PETUGAS |
| APOTEK | Apotek | Arif Hidayat | PETUGAS |
| LABORATORIUM | Laboratorium | Rina Maharani | PETUGAS |
| RADIOLOGI | Radiologi | Dimas Pratama | PETUGAS |
| KASIR | Kasir/Pembayaran | Fajar Maulana | PETUGAS |
| REKAM_MEDIS | Rekam Medis | Salsa Nabila | PETUGAS |

Pendaftaran/Apotek dipakai kembali dengan ID, prefix, mode, loket dan jam existing: Senin–Sabtu **07.00–17.00 WIB**, kapasitas 80/hari; tidak ada Minggu. Empat layanan baru memakai model resmi **ANTREAN_HARIAN**, satu loket per layanan, kapasitas demo 80/hari, Senin–Jumat **08.00–16.00 WIB**, Sabtu **08.00–12.00 WIB**, tanpa Minggu. Keterangan layanan baru menyatakan simulasi development, bukan konfigurasi operasional rumah sakit yang telah diverifikasi.

Enam akun V2 mempunyai email unik stabil `<kode>.petugas.dataset-v2@example.test`, satu assignment ke loket layanannya dari **30 Oktober–30 November 2026**. Mulai 30 Oktober memungkinkan dashboard PETUGAS diperiksa pada hari refresh. Akun/assignment Apotek lama tetap utuh; petugas V2 adalah identitas simulasi terpisah dengan credential yang diketahui untuk pengujian, bukan rename/reset akun existing. Penugasan poli lain yang sudah sah tetap dipertahankan.

Provisioning memakai AkunPetugasService dan PenugasanPetugasService existing, tidak memperoleh ADMIN. Password acak independen 24 byte, di-hash PasswordService. Plaintext hanya dalam `dataset-v2-credentials.json` pada batch privat di atas. Developer dapat membuka file tersebut secara lokal dengan editor tepercaya; jangan menyalin isinya ke chat, terminal log atau Git. Tidak ada password pada dokumen/source repository ini. Credential ADMIN, seluruh akun lama, dan FARM01 tidak diubah.

## Dokter, praktik dan slot

- Sepuluh dokter sintetis seed existing dipertahankan: masing-masing dua dokter pada Anak, Penyakit Dalam, Mata, Bedah Umum dan Saraf. **130 sesi target existing** dipakai kembali dengan pola pagi/siang aslinya dan slot yang sah.
- Dokter existing **FARM01** pada Apotek mempunyai akun DOKTER aktif dan relasi/loket sah. Identitas dan credential-nya dipertahankan. Ditambahkan **26 sesi 08.00–12.00 WIB**, Senin–Sabtu, pada periode target; tidak ada Minggu. Semua memakai JadwalPraktikService dengan pemeriksaan kalender, dokter/ruang dan conflict lock existing.
- Total target **156 sesi untuk seluruh 11 dokter aktif**, tanggal **31 Oktober–30 November 2026 inklusif**. Tidak membuat sesi baru di luar rentang tersebut. Enam sesi lama di luar rentang tetap dipertahankan karena provenance/dependensi.
- Ditambahkan **312 slot** FARM01, interval 20 menit dan kapasitas 2, melalui SlotPraktikService. Slot adalah entitas terpisah; service create jadwal tidak otomatis membuat slot. Tidak ada generator ganda.
- Model Apotek/Bedah yang ANTREAN_HARIAN tetap tidak membuka booking appointment dokter; API slot menandai ketersediaan sesuai mode existing. Tidak mengubah mode layanan atau mengarang workflow farmasi/klinis agar slot tampak bookable.
- Slot konsultasi pada HIBRIDA/JANJI_TEMU_DOKTER yang valid terbaca dan tersedia bagi USER. Tidak membuat reservasi, QR, check-in, atau status antrean palsu.

## Counts sebelum/sesudah apply

| Model | Sebelum | Sesudah apply |
|---|---:|---:|
| pengguna | 64 | 70 |
| layanan | 7 | 11 |
| loket | 9 | 13 |
| jadwal_layanan | 42 | 66 |
| penugasan_petugas | 8 | 14 |
| dokter / dokter_layanan | 11 / 11 | 11 / 11 |
| jadwal_praktik | 157 | 162 |
| slot_praktik | 1.425 | 1.524 |
| tiket_antrean | 55 | 13 |
| janji_temu | 35 | 6 |
| peristiwa_antrean | 138 | 68 |
| urutan_antrean_harian | 41 | 10 |
| notifikasi | 0 | 0 |
| sesi_pengguna | 147 | 147 |
| perangkat_tampilan | 6 | 6 |
| _prisma_migrations | 8 | 8 |

Verifikasi segera setelah apply: seluruh baseline yang dipertahankan cocok hash, admin/akun lama dan perangkat utuh, 22 FK valid tanpa orphan, 0 overlap dokter/ruang, 0 overlap slot, semua slot berada dalam sesi dan kapasitas positif. Unique constraint existing menjaga kode/email/pasangan jadwal/slot; enam assignment V2 masing-masing tunggal. Pemeriksaan read-only berikutnya membuktikan total kapasitas slot per layanan/hari target tidak melampaui kapasitas operasional.

## Repeatability dan menjalankan tooling

Tooling V2 terpisah dari reset/seed lama dan tidak dipanggil saat startup. Build NestJS terbaru wajib tersedia. Semua file batch harus di luar worktree dengan ACL privat. Periksa target dan preview terlebih dahulu; contoh berikut memakai placeholder path yang harus diisi dari inventaris lokal:

```powershell
node apps/api/tool/development-dataset-v2.cjs plan --output=<BATCH_PRIVAT> --report=plan-final.json --source-batch=<BATCH_SEED_27_OKTOBER> --provenance-checkpoint=<CHECKPOINT_28_OKTOBER>
node apps/api/tool/development-data.cjs backup --admin-id=<UUID_ADMIN_DARI_INVENTARIS> --output=<BATCH_PRIVAT>
node apps/api/tool/development-dataset-v2.cjs apply --output=<BATCH_PRIVAT> --plan=plan-final.json --backup-checkpoint=<CHECKPOINT_BACKUP_SEGAR> --confirm=APPLY-DATASET-V2
node apps/api/tool/development-dataset-v2.cjs verify --output=<BATCH_PRIVAT> --plan=plan-final.json
node apps/api/tool/development-dataset-v2.cjs plan --output=<BATCH_PRIVAT> --report=plan-after.json --source-batch=<BATCH_SEED_27_OKTOBER> --provenance-checkpoint=<CHECKPOINT_28_OKTOBER>
```

Apply menolak backup lebih dari satu jam, checksum berubah, target/environment lain, migration berbeda, baseline non-sesi berubah, stable-key collision atau state/journal tak cocok. Journal dan credential ditulis privat sebelum provisioning; akun/service/domain memakai stable key dan ID tercatat. Tidak melakukan reset/restore otomatis ketika parsial.

Dry-run kedua aktual: **0 cleanup, 0 layanan baru, 0 akun baru, 0 jadwal baru**; 156 sesi target dipakai kembali, lima blocker tetap. Verify read-only sebelum smoke juga lulus no-op. Jangan mengulang cleanup destruktif untuk membuktikan idempotency. Untuk batch aktual, apply sudah complete: **jangan menghapus journal, mengubah plan/hash, mengulang reset, atau merestore backup untuk menghilangkan delta sesi**.

## Smoke lintas portal dan batas pengujian

Perintah smoke memakai instance Nest HTTP lokal khusus, Prisma dipaksa ke target development tervalidasi, dengan guard JWT/session/RBAC dan throttle asli. Middleware hanya menerima GET serta login/logout; POST bisnis dan endpoint refresh ditolak. Tidak menulis booking, QR, check-in, device atau profile.

```powershell
node apps/api/tool/development-dataset-v2.cjs smoke --output=<BATCH_PRIVAT> --plan=plan-final.json --source-batch=<BATCH_SEED_27_OKTOBER>
```

- **PETUGAS:** keenam akun baru berhasil login; masing-masing hanya satu assignment, snapshot loket sendiri 200, loket lain 403, pengelolaan akun ADMIN 403. Limit lima login per menit dipatuhi dengan jeda antar batch.
- **DOKTER:** sepuluh akun seed berhasil login dan membaca profil/jadwal miliknya. FARM01 diverifikasi melalui PortalDokterService read-only; HTTP login tidak dicoba karena credential existing tidak tersedia dan tidak direset.
- **PASIEN:** satu akun seed berhasil login, katalog memuat keenam layanan harian; sesi tanggal 31 Oktober = 6, 1 November (Minggu) = 0, 30 November = 6. Slot HIBRIDA yang sah tersedia melalui GET.
- **ADMIN:** katalog layanan, akun, assignment dan jadwal dibaca melalui service resmi dengan scope administratif. Login ADMIN utama tidak dibuat/dipalsukan atau direset; credential-nya tidak tersedia untuk smoke HTTP.
- **PUBLIC DISPLAY:** seluruh enam record pairing/token/config existing cocok hash setelah apply; tidak membuat device atau pairing baru.
- **Batas UI:** source Flutter tidak berubah. Empat layanan baru terbaca katalog USER dan alur Reservasi existing, tetapi whitelist Home “Ambil Antrean” hanya Pendaftaran/Apotek. Tidak memperluas whitelist atau mengklaim seluruh empat card baru muncul di Home. Tidak ada klaim smoke Flutter UI development lengkap.

Semua request yang diuji sukses sesuai status yang diharapkan, **HTTP 5xx 0**. Smoke membuat **17 sesi baru miliknya**, lalu logout resmi masing-masing; sesi tersebut tetap tercatat sebagai history, bukan dihapus. Count sesi akhir **164**; seluruh **147 ID sesi lama tetap ada**, tanpa sesi baru tak teratribusi.

## Gate sesi yang belum selesai

Smoke keseluruhan **FAIL pada assertion fingerprint sesi terakhir**, bukan pada login/katalog/assignment/slot. Dibandingkan backup, dua sesi lama (PETUGAS dan ADMIN) hanya berubah pada `token_refresh_hash` dan `kedaluwarsa_pada`, sekitar **20.07 WIT**. Audit berikutnya menemukan satu sesi USER lama juga mengalami perubahan dua kolom yang sama sekitar **20.17 WIT**, sehingga total akhir **3 sesi lama berubah**. Tidak ada sesi lama hilang/dicabut dan tidak ada kolom bisnis lain berubah. Semua 17 sesi baru cocok tepat dengan ID hasil login smoke; tidak ada sesi baru tak teratribusi.

User menyatakan **“Tidak ada aplikasi/tab aktif”**. Server smoke tidak menggunakan akun ADMIN, dan hanya AuthService.refresh existing yang memperbarui dua jenis kolom tersebut; endpoint refresh ditolak middleware smoke. Ini membatasi jalur penyebab, tetapi **caller aktual belum terbukti**. Sesi aktual tidak disentuh untuk mengembalikan hash baseline. Diagnosis privat menyimpan nama kolom, timestamp dan identitas hash; tidak menampilkan token atau hash refresh.

Computer-use read-only mencoba inventaris browser, lalu dihentikan tool karena URL Chrome tidak dapat diverifikasi cukup yakin untuk pemeriksaan keamanan. Tidak melanjutkan atau mengakali pembatasan UI. Tidak ada tab/proses pengguna ditutup. Investigasi caller dan smoke/gate akhir tetap tertunda; strict verification tidak dilemahkan untuk menghasilkan PASS.

## QA source dan Git

- Typecheck, lint dan build backend aktual lulus.
- 10 tes tooling V2 lulus, termasuk PostgreSQL test nyata: guard target, provenance/aktor/dependensi tak dikenal, counter yang masih dipakai, checkpoint jadwal, batas WIB, stable-key/idempotency, allowlist, rollback kegagalan yang disuntikkan dan preservasi seluruh baseline test.
- Lifecycle tooling existing: 16 PASS, 1 SKIP (SQL opt-in terpisah); 689 unit backend / 47 suite PASS. SQL opt-in sudah dijalankan terpisah dan lulus; tidak mengklaim skip sebagai PASS.
- Regresi integrasi terkait **51 PASS / 5 suite**: jadwal-layanan 10, jadwal-praktik 11, slot-praktik 10, penugasan-petugas 12, admin-management-p0 8. Setiap runner memverifikasi target test, 13 record baseline tetap utuh dan nol fixture residual. Pengujian SQL tooling terakhir juga mengembalikan seluruh fingerprint test ke baseline.
- Source terbatas pada tooling development, tes terkait dan dokumen ini. Empat file historis, dokumen setup/audit, backup dan untracked lama dilindungi. Dump, credential, plan per-ID, session diagnostics dan evidence lokal tidak di-stage.
- **Commit/push ditahan:** cleanup tidak full, fingerprint sesi akhir belum dapat dinyatakan lulus dan pemeriksaan UI terhenti. Data lokal tidak otomatis ikut ketika repo di-clone; tool memerlukan provenance/backup/credential privat yang sah pada mesin tujuan. Tidak ada deployment publik.

Tindak lanjut: atribusikan ketiga refresh melalui telemetry proses/API yang relevan sebelum menerima perubahan sesi sebagai aktivitas eksternal; gunakan checkpoint baru yang terverifikasi untuk verifikasi lanjutan, tanpa menghapus atau memulihkan sesi lama secara spekulatif. Cleanup lima blocker memerlukan bukti ownership/dependensi tambahan, bukan penghapusan berdasarkan nama.

## Final Verification & Session Audit

Status tindak lanjut: **DEVELOPMENT DATASET V2 BLOCKED BY SESSION AUDIT**. Bagian sebelumnya adalah catatan pelaksanaan refresh/smoke awal, bukan hasil pengujian ulang. Refresh, cleanup, provisioning dan login development tidak diulang pada tahap ini. Seluruh perubahan source tetap lokal karena Stage A belum lulus.

### A. Investigasi dan batas atribusi

Audit baru `apps/api/tool/development-dataset-v2-audit.cjs` membandingkan sesi dari dump backup secara offline dengan sesi aktual. Koneksi audit SQL dan pool Prisma untuk pembacaan service resmi memakai `default_transaction_read_only=on`; identitas database dan pengaturan read-only diperiksa sebelum pembacaan. Tidak menjalankan HTTP server, AuthService, login, refresh atau logout. Report baru ditulis hanya di direktori batch privat dengan nama baru; dump, plan dan journal lama tidak ditimpa.

| Session aman / role | Perubahan dibanding backup | Waktu estimasi rotasi, 30 Oktober 2026 WIT | Pemicu / bukti | Status |
|---|---|---|---|---|
| `791635faaeabe97b` / PETUGAS | `token_refresh_hash`, `kedaluwarsa_pada` | 20:07:33.504 | Cocok bentuk refresh existing; pemilik akun tidak dipakai smoke V2; tidak ada trace request yang membuktikan caller | UNATTRIBUTED |
| `85569e754e0d58b1` / ADMIN | Dua kolom yang sama | 20:07:33.539 | Smoke tidak memakai ADMIN; tidak ada trace request yang membuktikan caller | UNATTRIBUTED |
| `39fb20a8559053da` / USER | Dua kolom yang sama | Temuan awal 20:17:29.255; expiry saat audit awal tahap ini mengindikasikan rotasi terbaru 20:32:12.710 | Pemilik akun tidak dipakai smoke V2; tidak ada trace request yang membuktikan caller | UNATTRIBUTED |

Identifier di atas adalah SHA-256 ID sesi yang dipotong 16 karakter, bukan refresh token atau hash refresh. Waktu rotasi adalah **estimasi dari expiry dikurangi TTL konfigurasi**, bukan timestamp access log. Presisi milidetik dipertahankan untuk hasil PostgreSQL bertipe Date; tes audit mencakup kasus tersebut. Waktu layanan/jadwal tetap Asia/Jakarta; tabel forensik memakai WIT agar sesuai korelasi investigasi sebelumnya.

Source auth menunjukkan login membuat sesi baru, refresh memutar hash dan expiry melalui conditional update, serta logout mencabut sesi. Flutter `api.dart` menjadwalkan refresh JWT menjelang expiry; jalur 401, restore dan resume juga dapat memicu refresh. Timer ini tidak membuktikan adanya tab/proses tertentu. Label sesi awal `QueueB Flutter` adalah metadata klien, bukan bukti identitas proses. Pengguna menyatakan tidak ada aplikasi/tab aktif; pernyataan itu tidak diganti dengan dugaan aktivitas pengguna.

Ketiga owner akun berbeda dari owner 17 sesi smoke V2. Middleware smoke hanya menerima GET serta login/logout miliknya dan memblokir refresh. Ini membatasi hipotesis efek samping smoke, tetapi tidak mengidentifikasi caller lain. Tidak ada bukti cukup untuk menyatakan penggunaan tidak sah, maupun untuk menyatakan rotasi tersebut sudah sah dan teratribusi.

PostgreSQL yang diperiksa memakai `logging_collector=off`, `log_destination=stderr`, `log_statement=none`, `log_min_duration_statement=-1`, tanpa current logfile. Schema sesi tidak menyimpan histori IP/UA/request correlation untuk rotasi; konfigurasi HTTP existing tidak menyediakan access trace historis yang menghubungkan ketiga update ini dengan request tertentu. **Penyebab caller tetap tidak terbukti.** Tidak ada perubahan auth production, penambahan logging production, reset credential atau normalisasi sesi.

### B. Strict verification

Baseline historis tetap backup/plan V2 asli. Hasil `historicalStrict=FAIL`, `historicalSessionAttribution=FAIL`, **`stageAGate=FAIL`**. Perbedaan tiga sesi tidak di-allowlist. Seluruh 147 ID sesi historis tetap ada, tidak ada revocation/deletion historis; 17 sesi smoke awal tetap tercatat, total aktual 164.

Snapshot awal dan snapshot baru setelah transaksi read-only terpisah cocok selama setiap audit yang selesai. Hasil `readOnlyAuditWindow=PASS` hanya membuktikan interval audit saat ini; hasil itu **tidak menggantikan FAIL historis**. CLI audit final mengembalikan exit code 2 bila ada gate FAIL; exit 1 dipakai untuk kegagalan pelaksanaan. Laporan audit awal yang dibuat sebelum penambahan exit code gate tetap menyimpan FAIL eksplisit dan tidak ditulis ulang.

Audit penutupan `final-verification-end.json` selesai dengan **exit 2**: ketiga sesi tetap UNATTRIBUTED dan latest expiry sama dengan awal tahap ini. Perbandingan fingerprint seluruh tabel antara awal **30 Oktober 2026 21:02:11.951 WIT** dan akhir **21:47:20.163 WIT** menunjukkan **0 tabel berubah**, termasuk sesi: tidak ada rotasi tambahan sepanjang seluruh QA. Ringkasan aman tersimpan di `final-safety-summary.json` pada direktori evidence build. Hasil ini membuktikan keamanan interval QA baru, bukan atribusi terhadap rotasi sebelum interval tersebut.

Tidak ditemukan bukti yang membenarkan perubahan prosedur auth smoke sebagai penyebab ketiga rotasi. Perbaikan tooling terbatas pada audit non-mutasi, pemisahan gate historis/interval, presisi waktu dan tes yang memastikan pola refresh tidak berubah menjadi VERIFIED tanpa bukti caller.

### C. Sebelas akun dokter dan jadwal

Semua akun di tabel berikut aktif, role DOKTER, nama account cocok profil, relasi poli/ruang aktif, dan penugasan PETUGAS mencakup jadwal. Account ID penuh tidak dipublikasikan; identifier korelasi aman tersedia dalam report privat.

| Dokter | Poli | Sesi target | Verifikasi tahap ini |
|---|---|---:|---|
| DOKAN01 | ANAK | 13 | Account/relasi/profil/jadwal/slot read-only PASS |
| DOKAN02 | ANAK | 13 | PASS |
| DOKPD01 | PDALAM | 13 | PASS |
| DOKPD02 | PDALAM | 13 | PASS |
| DOKMT01 | MATA | 13 | PASS |
| DOKMT02 | MATA | 13 | PASS |
| DOKBU01 | BEDAH | 13 | PASS |
| DOKBU02 | BEDAH | 13 | PASS |
| DOKSR01 | SARAF | 13 | PASS |
| DOKSR02 | SARAF | 13 | PASS |
| FARM01 | APOTEK | 26 | PASS; HTTP login tetap NOT VERIFIED, credential existing tidak direset |

Jadwal target aktual **156 = 130 reused + 26 baru** pada **31 Oktober–30 November 2026 inklusif**, dengan **312 slot baru**. Enam sesi praktik historis di luar periode tetap utuh. **147 adalah sesi autentikasi historis, bukan sesi praktik historis**; total praktik aktual 162 dan total slot 1.524. Tidak memaksa jumlah praktik historis menjadi 147.

Hasil audit: 0 konflik dokter/ruang, 0 duplicate practice, 0 duplicate slot, 0 overlap slot, 0 slot invalid, 0 kapasitas harian terlampaui dan 0 praktik baru di luar rentang. Batas tanggal Asia/Jakarta: 31 Oktober 6 sesi, 1 November 0 (Minggu), 30 November 6; transisi bulan tidak bergeser karena UTC.

Pembacaan **service resmi** yang digunakan endpoint existing berhasil: katalog ADMIN/USER memuat enam layanan; JadwalPraktikService mengembalikan 156 target untuk kedua role dan batas tanggal 6/0/6. PortalDokterService profil/jadwal milik sendiri serta pembacaan jadwal USER dan SlotPraktikService berhasil untuk semua 11 dokter. Ini adalah verifikasi service/read model, **bukan HTTP login ADMIN/FARM01 atau browser development**. Slot Apotek/Bedah yang mode ANTREAN_HARIAN tetap mengikuti aturan existing dan tidak dipaksakan bookable sebagai appointment dokter.

### D. Katalog Home PASIEN

Whitelist berada pada `isAuxiliaryHomeService` di `patient_home_v6.dart`; sebelumnya hanya menerima kode Pendaftaran/Apotek beserta alias. Katalog tetap berasal dari API `/layanan`. Filter aktif dan mode ANTREAN_HARIAN/HIBRIDA, bukan nama layanan, menentukan dukungan Ambil Antrean. Mode appointment tetap terpisah. Setiap enam layanan aktual memiliki satu loket aktif, enam hari kalender operasional valid dan cakupan petugas sah; Queue Engine dan kontrak reservasi generik existing mendukungnya.

Perluasan source minimal mengaktifkan **PENDAFTARAN → APOTEK → LABORATORIUM → RADIOLOGI → KASIR → REKAM_MEDIS**, mempertahankan urutan relatif sisa katalog. Tidak membuat objek layanan produksi atau ID palsu. Kategori baru memakai warna/ink V7 existing dan ikon/subtitle yang sesuai. Kartu tetap putih, seluruh area clickable, tanpa tombol internal; realtime summary tetap memakai ID backend serta feed/batch existing, termasuk fallback jujur saat data belum tersedia. Tidak menambah feed atau mengubah V7.1 realtime.

Keempat kartu tambahan menggunakan route reservasi existing, membawa ID layanan asli, dan tidak membuat POST reservasi sebelum konfirmasi. AppBar, banner, search, kunjungan terdekat, tab Janji Temu, bottom navigation, smart scroll dan portal lain tidak diubah. Layanan tidak aktif, mode unsupported dan kode unknown tetap dibatasi; layanan klinis harian existing seperti BEDAH mempertahankan jalur eksplorasinya. Tidak ada workflow backend baru atau perubahan booking rule.

### E. Lintas portal dan perlindungan database

- ADMIN: katalog, akun dokter, enam petugas/assignment, ruang, kapasitas serta jadwal diperiksa read-only; HTTP auth ADMIN tidak dicoba ulang.
- PETUGAS: assignment cocok layanan dan role tetap PETUGAS. Bukti HTTP 200 sendiri/403 silang berasal dari smoke awal; regresi RBAC ulang menggunakan fixture database test, bukan login enam akun development.
- DOKTER/PASIEN: service read model di atas PASS; regresi katalog/navigasi dilakukan dengan mock widget dan harness database test yang terpisah dari development. Tidak mengklaim browser pada dataset development telah dijalankan.
- PUBLIC DISPLAY: enam record perangkat/pairing/config tetap cocok fingerprint; tidak ada device, token, cookie atau konfigurasi baru.

Backup privat tetap pada batch semula; SHA-256 diverifikasi ulang **f294101a02cc4eb39fdf2cbedfceb8176396be0ee37198bc5901be6b69c29138**. Tidak dibuat dump pengganti. Seluruh data bisnis baseline yang dipertahankan cocok hash, 22 FK valid, 8 migration tetap, tidak ada schema/migration/reset/reseed/cleanup tambahan. Lima blocker cleanup lama tetap utuh. Semua pengujian yang menulis dibatasi runner ke `127.0.0.1:5433/capstone_antrean_test` dengan fixture unik dan cleanup; tidak memakai development untuk mutasi pengujian.

### F. Regresi aktual tahap ini

| Pemeriksaan | Hasil |
|---|---|
| Backend typecheck / lint / build | PASS / PASS / PASS |
| Backend unit | 689 PASS / 47 suite |
| Tooling lifecycle + V2 + audit | 21 PASS, 1 SQL opt-in SKIP; SQL V2 dijalankan terpisah |
| Tooling V2 dengan PostgreSQL nyata | 10 PASS, tanpa skip |
| Tes audit baru | 5 PASS, termasuk perlindungan atribusi/secret dan presisi waktu |
| Integrasi jadwal-layanan / jadwal-praktik / slot / assignment / admin | 10 + 11 + 10 + 12 + 8 = 51 PASS; 13 record baseline test dan cleanup cocok setiap suite |
| Flutter format / analyze | PASS; no issues |
| Flutter targeted katalog/V7/V6/summary | 95 PASS |
| Flutter full regression | 1.253 PASS, 1 SKIP existing |
| Web release | PASS; build QA memakai API localhost 3001 dan timezone Asia/Jakarta |
| APK debug | PASS; `assembleDebug` 173,1 detik, artefak baru 259.632.143 byte; build QA API localhost 3001/timezone Asia/Jakarta, tidak diinstal/deploy |
| Browser Home compiled Web | PASS normal/reduced motion; keenam kartu, scroll, profile/tabs/logout; 0 POST reservasi/QR, 0 runtime/console error, 0 HTTP 5xx, satu socket ditutup; 13 baseline test utuh, 0 fixture tersisa |
| Browser lintas portal | 13 kelompok E2E PASS: login role, booking, audio native, tiga display, kamera One-Scan, session policy, enam command, appointment complete, fullscreen, reconnect, rotate/revoke, runtime |
| Browser realtime V7.1 | 7 skenario PASS: initial, dua check-in, repeated scan, serving, isolasi layanan, reconnect, logout/account switch |

Analyze percobaan awal menemukan import nama QueueBApp salah dan satu brace pada tes baru; diperbaiki sebelum analyze bersih dan regresi di atas. Tidak ada error produksi yang disembunyikan. Log percobaan disimpan terpisah dari log rerun di `apps/client/build/dataset-v2-final/` (ignored).

Browser Home percobaan pertama gagal pada pembuatan fixture HTTP 400 karena CreateLayananDto hanya menerima kode alfanumerik, sedangkan kode existing V2 `REKAM_MEDIS` mengandung underscore. Harness sekarang membuat **hanya fixture test yang terdaftar tersebut** melalui LayananService existing, mengikuti jalur provisioning V2. Tidak melonggarkan DTO atau menambah API; pembacaan katalog dan reservasi existing memakai UUID sehingga kode persisted tersebut dapat digunakan. Pembuatan ulang kode ber-underscore melalui HTTP ADMIN tetap dibatasi kontrak existing, di luar scope tahap ini. Percobaan kedua menemukan locator hint pencarian hilang ketika input terisi; harness memakai tombol `Bersihkan pencarian` existing. Percobaan akhir lulus kedua mode; setiap percobaan membersihkan fixture dan membuktikan 13 baseline test utuh/0 residual. Seluruh bukti gagal dipertahankan pada direktori build terpisah.

Build Web mengeluarkan warning wasm dry-run dari dependensi `flutter_tts`/`socket_io_common`; build JavaScript release berhasil. Tidak mengklaim build Wasm PASS dan tidak mengubah dependensi untuk menyembunyikan warning.

Build APK berhasil dengan batas Gradle heap 2 GiB/dua worker. Log mencatat warning native-access Java dan penggunaan KGP oleh `flutter_tts`; dependensi tidak diubah dalam scope katalog/audit ini. Permintaan eksekusi build pertama belum dimulai karena pemeriksaan persetujuan otomatis timeout; satu retry yang diizinkan tool berhasil menjalankan build. Tidak mengklaim build sebelum artefak baru dan exit 0 terkonfirmasi; tidak ada klaim uji perangkat Android fisik.

Browser dijalankan sebagai pengujian software proyek melalui Chrome headless **baru**, Web compiled `127.0.0.1:8080` dan API `127.0.0.1:3001`, dengan target PostgreSQL test tervalidasi. Tidak memakai CUA, tidak mengendalikan Chrome/tab pengguna yang sebelumnya diblokir karena URL tidak terverifikasi, dan tidak mengklaim hasilnya sebagai pemeriksaan browser development. Kedua regresi browser lintas portal/realtime mencatat **HTTP 5xx 0, serverFailure false, pendingAtFinish 0**, tidak ada P2028; runtime/response observer bersih dan 13 baseline test tetap utuh/0 residual. Hasilnya terpisah dari unit/widget tests.

Evidence baru disimpan di `apps/client/build/dataset-v2-final/`: log QA, `backend/`, `home-final/browser-after/summary.json`, `browser-cross/`, `browser-realtime/transactions.json`, `realtime-browser/summary.json`, `browser-safety-summary.json`, `final-safety-summary.json`, protected hashes dan hasil scan credential. Report forensik lengkap tetap privat: `final-verification-start.json`, `final-verification-readmodels.json`, serta `final-verification-end.json` dalam batch backup semula. File ini tidak di-stage. Satu tes Flutter yang dilewati adalah `live_integration_test.dart` tanpa fixture; regresi browser integration nyata dijalankan terpisah sebagaimana hasil di atas.

### G. Protected files, Git/CI dan risiko tersisa

Keenam file terlindungi cocok SHA-256 sebelum/sesudah pekerjaan: `README.md`, `apps/client/lib/src/doctor_dashboard.dart`, `apps/client/lib/src/doctor_visual.dart`, `apps/client/test/doctor_visual_refresh_test.dart`, `docs/setup/LOCAL_INSTALLATION_GUIDE.md`, `docs/frontend/GO_ROUTER_MIGRATION_AUDIT_R0.md`. Dua dokumen terakhir diidentifikasi dari artefak fingerprint aktual. Backup dan untracked lama dipertahankan.

Source lokal mencakup tooling V2 sebelumnya, tooling audit beserta tes, perluasan katalog/mapping Flutter, targeted tests, tambahan pemeriksaan empat kartu pada harness browser Home existing dan dokumen ini. Tidak ada perubahan source API production/auth/Queue Engine/schema. Evidence lokal berada di build ignored; dump, credential, hash per-ID dan diagnostik sesi lengkap tetap di direktori privat di luar Git.

Tidak melakukan stage, commit atau push. Fetch terakhir membuktikan HEAD `251236fd734691a992d55ff4e151bfe4925099f2` pada main sama dengan origin/main (0 ahead/0 behind); index kosong. Pemeriksaan 13 file source/dokumen terkait tidak menemukan nilai credential privat V2 atau secret environment yang diketahui. Pemeriksaan ini bukan klaim audit secret menyeluruh seluruh repository. Tidak ada CI baru yang dipicu atau deployment. **Stage A gagal karena caller tiga rotasi belum teratribusi; commit/push dilarang oleh gate tugas aktif.** Bukti request/proses historis yang dapat dikorelasikan masih dibutuhkan. Kecocokan pola refresh atau PASS regresi tidak cukup untuk mengubah status menjadi VERIFIED.

## Final Closure — Accepted Historical Audit Exception

Tanggal keputusan: **30 Oktober 2026, Asia/Jayapura (WIT)**. Status fungsional: **V2 FUNCTIONALLY VERIFIED — HISTORICAL SESSION AUDIT UNRESOLVED**. Keputusan ini menggantikan larangan Git pada tahap verifikasi sebelumnya hanya untuk selective release source V2 development. Hasil audit historis di bagian sebelumnya tetap berlaku dan evidence gagal tidak dihapus.

### Penerimaan risiko dan batas persetujuan

> Pengguna menyetujui penyelesaian Development Dataset V2 meskipun tiga rotasi sesi historis belum dapat diatribusikan. Persetujuan berlaku terbatas untuk pekerjaan development dan selective commit/push source yang telah diverifikasi. Hasil strict audit tetap FAIL dan wajib ditindaklanjuti secara terpisah. Persetujuan ini tidak membuktikan keamanan sesi historis dan tidak mengizinkan deployment publik.

| Sesi aman | Role | Perubahan | Atribusi |
|---|---|---|---|
| `791635faaeabe97b` | PETUGAS | `token_refresh_hash`, `kedaluwarsa_pada` | UNATTRIBUTED |
| `85569e754e0d58b1` | ADMIN | Kolom yang sama | UNATTRIBUTED |
| `39fb20a8559053da` | USER | Kolom yang sama | UNATTRIBUTED |

Caller tidak dapat dibuktikan karena histori request/proses dan correlation ID yang diperlukan tidak tersedia. Pola kolom, expiry dan timer Flutter hanya menjelaskan mekanisme yang mungkin; tidak membuktikan sumber request. Tidak tersedia bukti cukup untuk membenarkan maupun menolak kemungkinan penggunaan tidak sah. Status keamanan historis: **UNRESOLVED**.

| Gate audit asli | Hasil tetap |
|---|---|
| historicalStrict | FAIL |
| historicalSessionAttribution | FAIL |
| stageAGate | FAIL |
| readOnlyAuditWindow | PASS |

Tidak ada penghapusan/normalisasi sesi, reset password, perubahan expiry/hash manual, allowlist historis baru, pelonggaran assertion atau perubahan auth production. Pengecualian tidak berlaku untuk perubahan RBAC/credential, hardening production, audit production, deployment aplikasi/database atau sinkronisasi data ke production.

### Integritas penutupan dan aktivitas development terpisah

Bukti QA final sebelumnya tetap sah untuk interval **21:02:11.951–21:47:20.163 WIT**: seluruh fingerprint development sama, tidak ada rotasi tambahan, 22 FK valid, 8 migration tetap dan checksum dump asli cocok. Audit read-only baru `closure-start-20261030.json` kembali menghasilkan gate historis FAIL dan interval baca PASS, seluruh data bisnis tetap cocok baseline, 11 dokter/156 sesi/312 slot baru valid, serta enam layanan kompatibel.

Antara akhir QA lama dan awal closure, ditemukan **satu sesi USER baru**, identifier aman `d8e12aa8fc6212b8`, dibuat **21:57:42.130 WIT** dengan label `QueueB Flutter`; total sesi 164→165. Pengguna secara eksplisit mengonfirmasi **“Ya, saya login portal PASIEN saat itu”**. Perubahan ini dicatat sebagai login development pengguna yang terkonfirmasi berdasarkan role/waktu/metadata dan pernyataan pengguna, bukan hasil trace request server. Tidak ada perubahan tabel bisnis atau perubahan tambahan pada sesi lama dalam perbandingan tersebut. Runner closure tidak login dan tidak membuat sesi itu. Konfirmasi ini tidak mengatribusikan tiga sesi historis dan tidak mengubah strict FAIL. Tidak mengklaim fingerprint seluruh periode closure sama dengan QA lama.

Audit penutupan berikutnya, **22:10:03.787 WIT**, menunjukkan total sesi **167**: tambahan ADMIN `cc7740cfefe1a731` dibuat **22:02:27.674** dan logout **22:04:11.160 WIT**; USER `d7be28033e6c2c3c` dibuat **22:04:26.571** dan logout **22:05:15.228 WIT**. Pengguna mengonfirmasi **“Ya, keduanya aktivitas saya”**. Dibandingkan awal closure, tidak ada sesi sebelumnya berubah/hilang dan hanya dua sesi baru tersebut yang berbeda; seluruh tabel bisnis tetap sama. Dengan demikian ada tiga login pengguna terkonfirmasi sejak QA lama (164→167), bukan tiga sesi baru dari runner. Perbandingan fingerprint keseluruhan yang mendeteksi perubahan sesi tetap disimpan; tidak dihapus atau diganti menjadi klaim unchanged. Integritas bisnis serta audit read-only baru lulus, sedangkan historicalStrict/historicalSessionAttribution/stageAGate tetap FAIL.

Backup, plan, journal dan credential privat tidak ditimpa. Tidak mengulang refresh/cleanup/reseed/provisioning/smoke development. Lima kandidat cleanup berisiko dan enam sesi praktik historis tetap dipertahankan. FARM01 lolos account/profile/relasi/jadwal/service read-only; **HTTP login FARM01 tetap NOT VERIFIED**. Browser sebelumnya memakai fixture database test, bukan browser dataset development.

### Review source dan pembagian selective release

Kelompok A — tooling/dokumentasi V2:

- `apps/api/tool/development-data.test.cjs`: mendaftarkan tes V2/audit dalam lifecycle CI existing.
- `apps/api/tool/development-dataset-v2.cjs`: CLI maintenance eksplisit, guard target/backup/provenance, journal, allowlist cleanup dan strict verify; tidak dipanggil startup/CI untuk apply.
- `apps/api/tool/development-dataset-v2-smoke.cjs`: HTTP GET serta login/logout milik smoke awal; **tidak dijalankan ulang saat closure**.
- `apps/api/tool/development-dataset-v2.test.cjs`: safety/provenance/calendar/idempotency dan SQL opt-in hanya pada test DB dengan fixture unik/cleanup.
- `apps/api/tool/development-dataset-v2-audit.cjs` dan `apps/api/tool/development-dataset-v2-audit.test.cjs`: audit read-only, gate FAIL terpisah dan pengujian anti-atribusi spekulatif.
- `docs/backend/DEVELOPMENT_DATASET_V2.md` dan `docs/backend/AUTH_SESSION_AUDIT_FOLLOWUP.md`: hasil, penerimaan risiko dan backlog terbuka.

Kelompok B — Patient Catalog V2:

- `apps/client/lib/src/patient_home_v6.dart` dan `apps/client/lib/src/patient_home_v7.dart`: filter/mapping enam kode, urutan stabil, ID API dan route reservasi existing; tidak mengubah auth, realtime owner, layout global atau booking rule.
- `apps/client/test/patient_daily_catalog_v2_test.dart` dan `apps/client/test/patient_home_v7_test.dart`: kategori, ordering, batas mode/aktif, navigasi tanpa POST dan responsive/text scaling.
- `apps/client/tool/browser-patient-home-v7.cjs` dan `apps/client/tool/run-live.cjs`: pemeriksaan empat kartu tambahan dan provisioning fixture REKAM_MEDIS melalui service existing, hanya pada test DB tervalidasi.

Kelompok C dikeluarkan dari release: enam file terlindungi, perubahan dokter/README, `apps/web/`, backup, `sql/`, dokumen setup/R0 dan untracked historis lain. Tidak ada file API production/auth/Queue Engine/schema/migration, dependency/lockfile, private diagnostics, dump, credential JSON atau evidence build dalam daftar release. Staging harus tepat **14 file** pada kelompok A/B, menggunakan path eksplisit.

Satu perubahan source saat closure hanya memperbaiki teks metadata `homeAuxiliaryCodes` pada laporan smoke: visibilitas Home dibuktikan oleh tes katalog, bukan GET katalog saja. Field sebelumnya masih menyebut whitelist dua layanan. Ini tidak mengubah request, auth, assertion, mutasi atau hasil report historis. Seluruh kode fungsional Flutter/backend dan harness yang diuji pada QA final tetap sama; bukti full regression/build/browser sebelumnya digunakan ulang secara eksplisit, bukan dilaporkan sebagai run baru.

### QA closure dan keputusan Git

Pemeriksaan baru: review setiap file kelompok A/B, fingerprint **6/6** protected file cocok baseline, audit development read-only/checksum, format **8 CJS PASS**, lifecycle tooling **21 PASS/1 SQL opt-in SKIP** termasuk 5 tes audit. Format empat file Dart tidak mengubah file; Flutter analyze **no issues** dan **95 targeted tests PASS** dijalankan ulang. Tidak mengulang SQL mutasi development. Evidence full backend 689, integrasi 51, SQL tooling V2 10, Flutter full 1.253/1 skip, Web/APK, browser 13 kelompok dan realtime 7 pada bagian F adalah hasil run sebelumnya yang diperiksa, bukan hasil baru closure. Source fungsional yang terkait tidak berubah; hanya metadata teks smoke/dokumentasi bertambah.

Evidence closure terpisah di `apps/client/build/dataset-v2-closure/`: manifest hash source, status Git awal, format/tooling/analyze/targeted logs, hasil fingerprint, serta metadata sesi aman. Report read-only lengkap `closure-start-20261030.json` dan `closure-final-20261030.json` berada pada batch privat semula. Masing-masing CLI tetap **exit 2** untuk historical gate FAIL, dengan readOnlyAuditWindow PASS. Staged secret scan, daftar file serta sinkronisasi remote harus PASS sebelum commit; hasil aktual Git/CI dicatat setelah release.

Keputusan: selective commit berbahasa Indonesia dan push **fast-forward** ke `origin/main` diizinkan bila seluruh gate lain lulus. Pengecualian ini hanya menerima risiko historis di atas; `stageAGate` tidak diubah menjadi PASS. Hasil SHA/push/CI harus dicatat berdasarkan eksekusi aktual. Tidak ada deployment publik atau produksi.

### Backlog kontrak katalog — CATALOG-01 (OPEN)

Kode persisted `REKAM_MEDIS` dapat dibaca dan dipilih dengan UUID layanan pada alur reservasi existing. `CreateLayananDto` HTTP ADMIN menerima kode alfanumerik sehingga menolak underscore. Closure tidak mengubah DTO, kode persisted, data layanan atau migration dan tidak membuat workaround rename. Fixture QA mengikuti LayananService yang juga dipakai provisioning V2; ini bukan bukti bahwa HTTP create menerima kode tersebut.

Tindak lanjut terpisah: sepakati kontrak kode katalog yang konsisten antara DTO/domain/persisted data; inventarisasi konsumen dan backward compatibility; baru implementasikan setelah desain disetujui. Acceptance criteria: create/update/read mengikuti kontrak yang disetujui, UUID/relasi/reservasi existing tetap valid, tidak ada rename otomatis/migration spekulatif, dan regresi terisolasi lulus. Status tetap OPEN pada closure.

### Risiko dan mitigasi lanjutan

Tiga sesi historis tetap UNATTRIBUTED; login HTTP FARM01 belum diuji; CATALOG-01 belum diselesaikan. Jangan menafsirkan PASS fungsional sebagai bukti keamanan tiga sesi. Mitigasi pada scope closure adalah preservasi evidence/backup/sesi, akses privat pada diagnostik, pengujian terisolasi dan penerimaan risiko yang tercatat. Desain telemetry, monitoring dan kriteria penyelesaian ada pada [AUTH_SESSION_AUDIT_FOLLOWUP.md](AUTH_SESSION_AUDIT_FOLLOWUP.md); backlog tersebut **OPEN** dan tidak mengimplementasikan logging production dalam tugas ini.
