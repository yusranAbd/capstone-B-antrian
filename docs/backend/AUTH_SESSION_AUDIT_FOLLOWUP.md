# AUTH-SESSION-01 — Tindak lanjut audit refresh sesi

Tanggal: 30 Oktober 2026 (WIT). Status: **OPEN — desain belum disetujui, implementasi belum dilakukan**.

Asal: [Development Dataset V2 — accepted historical audit exception](DEVELOPMENT_DATASET_V2.md#final-closure--accepted-historical-audit-exception). Ini backlog keamanan terpisah dari penutupan dataset. Tidak ada backlog auth existing yang lebih tepat; dokumen gap operasional existing membahas antrean klinis, bukan lifecycle sesi.

## Temuan historis yang tetap terbuka

Sesi pseudonim `791635faaeabe97b` (PETUGAS), `85569e754e0d58b1` (ADMIN), dan `39fb20a8559053da` (USER) mengalami perubahan `token_refresh_hash` dan `kedaluwarsa_pada`. Caller tidak dapat dibuktikan dari evidence historis yang tersedia. Ketiganya tetap **UNATTRIBUTED**; `historicalStrict=FAIL`, `historicalSessionAttribution=FAIL`, dan `stageAGate=FAIL` tidak berubah. `readOnlyAuditWindow=PASS` hanya berlaku untuk interval audit yang stabil, bukan atribusi historis.

Tidak cukup bukti untuk membenarkan maupun menolak kemungkinan penggunaan tidak sah. Timer Flutter, label client atau pola expiry tidak membuktikan proses pemicu. Telemetry baru tidak dapat memulihkan histori request yang tidak pernah tersimpan dan tidak otomatis menutup temuan lama.

Persetujuan pengguna terbatas pada selective commit/push source V2 development dengan risiko ini tetap terbuka. Persetujuan itu tidak memberi izin logging production, penghapusan/normalisasi sesi, reset credential, perubahan RBAC/auth atau deployment publik.

## B1. Usulan session refresh telemetry

Rancang event lifecycle yang terstruktur, dengan minimal field berikut. Nama field adalah usulan desain, bukan kontrak API yang sudah tersedia.

| Field | Tujuan dan batas |
|---|---|
| Timestamp UTC | Waktu event dari server; tampilan dapat dikonversi ke timezone investigator |
| Safe session correlation ID | Korelasi sesi tanpa token; usulkan HMAC dengan key terpisah dari JWT dan prosedur rotasi/versioning |
| Pseudonymous account ID | Hanya bila diperlukan untuk korelasi; jangan log email/nama/password |
| Endpoint/action | Login, refresh, logout, revocation; route template, bukan query/body mentah |
| Request correlation ID | Dibuat/divalidasi server, format/panjang dibatasi dan disanitasi; jangan percaya nilai klien tanpa validasi |
| Client type | Nilai terkontrol; label yang dikirim klien diberi atribut unverified |
| Result | Success/denied/error tanpa payload autentikasi |
| Reason/error code | Kode allowlist; jangan serialize exception/Prisma args/request mentah |
| Process source and confidence | Identitas proses hanya bila dapat dibuktikan, misalnya identitas service terautentikasi; jika tidak, UNKNOWN/UNVERIFIED |

**Dilarang menyimpan** access token, refresh token, password, raw Authorization header atau raw authentication cookie. Jangan menyimpan token/hash refresh sebagai pengganti correlation ID. Jangan merekam body login/refresh, isi credential file, nama/data pasien, maupun URL dengan secret. Korelasi metadata IP/UA, bila kelak dibutuhkan, harus melalui keputusan privasi/minimisasi/retensi tersendiri; bukan default proposal ini.

Mekanisme CAS/rotation, expiry, JWT/session validation dan kontrak response existing harus tetap benar. Tentukan semantik pencatatan event sukses setelah commit dan pencatatan kegagalan yang aman. Putuskan perilaku ketika log sink gagal, batas latensi, idempotency/deduplikasi event dan dampak terhadap ketersediaan melalui review desain; jangan mengubah auth secara diam-diam.

## B2. Usulan monitoring dan tata kelola log

- Korelasikan login–refresh–logout/revocation dengan request ID serta safe session ID. Bedakan event auth berhasil/gagal dan level bukti asal proses.
- Usulkan deteksi refresh berulang terlalu cepat, refresh sesudah revocation, kegagalan/replay dan pergantian client yang tidak dapat dijelaskan. Threshold harus disetujui berdasarkan perilaku timer/resume/reconnect dan observasi test; jangan menganggap sinyal otomatis sebagai serangan.
- Pisahkan aktivitas fixture terisolasi dari penggunaan development biasa dengan application/process identity yang dapat diverifikasi. Jangan menandai client sah hanya karena label `QueueB Flutter`.
- Tetapkan retensi minimum yang terbatas dengan TTL/penghapusan terkontrol, enkripsi, akses berbasis peran, audit akses, key custody/rotation dan prosedur insiden. Durasi/owner operasional harus disepakati sebelum implementasi, bukan dianggap sudah ditetapkan dokumen ini.
- Uji serialisasi/redaksi menggunakan marker secret sintetis dan fault injection pada log sink. Pantau volume, sampling yang tidak menghilangkan event penting, dan beban refresh tanpa merekam secret.

## B3. Penanganan audit historis

Pertahankan dump, plan, journal, diagnostik gagal dan sesi asli pada lokasi privat. Jangan menghapus sesi, memutar token, mereset password atau menulis expiry untuk menyamakan baseline. Batasi akses dan catat penggunaan evidence tanpa menyalin isinya ke Git/chat.

Bila muncul evidence historis baru, evaluasi keaslian, clock skew, relasi request–sesi–aktor dan confidence-nya. Hanya evidence yang cukup boleh mengubah keputusan atribusi; dokumentasikan keputusan tambahan dan pertahankan jejak hasil lama. Jika evidence tidak tersedia, laporkan keterbatasan permanen dan pertahankan UNATTRIBUTED/FAIL. Penerimaan risiko fungsional bukan bukti atribusi.

## B4. Acceptance criteria (belum terpenuhi)

- [ ] Desain telemetry, data minimization, trust model, schema event, retensi dan akses log disetujui secara eksplisit.
- [ ] Tidak ada secret atau data pasien pada log normal, kegagalan, stack trace, response error maupun monitoring/export; marker sintetis membuktikan redaksi.
- [ ] Request refresh dapat dikaitkan secara sah ke safe session dan identitas proses yang memang terverifikasi; sumber yang tidak dapat dibuktikan tetap UNKNOWN/UNVERIFIED.
- [ ] Skenario login, auto-refresh, restore/resume, 401, concurrent refresh/CAS, replay, logout/revocation dan log-sink failure diuji menggunakan fixtures unik pada PostgreSQL lokal `127.0.0.1:5433/capstone_antrean_test`, dengan validasi target dan cleanup.
- [ ] Auth, expiry, session rotation, RBAC dan response contract existing tidak rusak; tidak ada reset/mutasi data development untuk tes.
- [ ] Retensi, key/access protection, biaya/latensi dan alert triage memiliki prosedur operasional yang disepakati.
- [ ] Hasil historis tidak diubah menjadi PASS tanpa evidence historis yang meyakinkan; keberhasilan telemetry prospektif dilaporkan terpisah.

Implementasi dan review keamanan memerlukan tugas/persetujuan tersendiri. Closure V2 tidak menutup backlog ini. Ketidaksesuaian `REKAM_MEDIS`/CreateLayananDto dicatat terpisah sebagai **CATALOG-01 OPEN** di dokumen V2; tidak diperbaiki dengan perubahan auth atau rename data.
