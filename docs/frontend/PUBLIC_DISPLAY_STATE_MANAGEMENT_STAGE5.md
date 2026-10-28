# Public Display — Tahap 5 dan penutup migrasi lima portal

29 Oktober 2026. Baseline aktual `b416a16`, `main` sinkron dengan `origin/main`.
[CI Tahap 4](https://github.com/yusranAbd/capstone-b-antrian/actions/runs/40783447387)
sukses saat preflight. Acuan: [UI QueueB](QUEUEB_UI_UX_GUIDELINES.md),
[kontrak API](../backend/API_INTEGRATION_GUIDE.md) §7–8, §20, §25, §27–28,
[multi-monitor existing](PUBLIC_DISPLAY_MULTI_MONITOR.md), serta dokumentasi
[ADMIN](ADMIN_STATE_MANAGEMENT_STAGE2E.md), [PASIEN](PATIENT_STATE_MANAGEMENT_STAGE3.md)
dan [PETUGAS](STAFF_STATE_MANAGEMENT_STAGE4.md).

## Ownership 5A–5D

| Komponen | Tanggung jawab |
|---|---|
| `DisplayDeviceCubit` | State metadata perangkat, pairing/restore/reject/disconnect, status operasi dan error aman. Tidak menyimpan kode/token. |
| `DisplayDeviceRepository` | Adapter QueueApi dan DisplaySelection existing. Memiliki capability scope transport (ID perangkat, selector, poli, API base, epoch); token manual hanya memori privat adapter. Tidak memiliki cache metadata perangkat kedua. |
| `DisplayMonitorBloc` | Satu snapshot immutable, refresh/invalidation, connection epoch, keputusan announcement dan cleanup scope. |
| `DisplayMonitorRepository` | Satu owner RealtimeFeed dan delegasi REST melalui capability perangkat yang sama; tidak memiliki cache antrean. |
| `DisplayAudioController` | Satu instance per monitor, adapter FlutterTts existing, aktivasi melalui gesture, mute/error, pembatalan utterance lama dan disposal. Bisa diinjeksi fake engine. |
| Widget | Form/controller sementara, fullscreen, jam ValueNotifier, visual pagination dan navigasi. Tidak memiliki HTTP business flow/socket/snapshot paralel. |

`DisplayPage` membuat owner sekali; MultiBlocProvider memakai `.value`. BLoC
dipasang sebelum restore perangkat. Event bootstrap lama ditolak berdasarkan
generation sehingga begin/activate yang berdekatan tidak membuka dua feed.
Pada disposal, halaman menutup BLoC/Cubit dan resource miliknya; repository/audio
eksternal tetap dibuang pemanggil. QueueApi bersama tidak ditutup oleh feature.
State perangkat dan monitor ditempatkan pada models bersama; event monitor berada
di file BLoC, tanpa file tambahan yang tidak memiliki fungsi.

## Pairing, identitas, dan cookie

- Web tetap POST `/display/pairing` dengan kode transient dan `isolasiSesi:true`.
  Respons metadata divalidasi, selector publik disimpan melalui adapter existing,
  kemudian GET `/display/sesi` harus cocok dengan ID dan poli hasil pairing.
- Tab isolated tanpa selector tidak membaca cookie ambient untuk mengambil sesi
  tab lain. GET sesi/snapshot dan POST `/display/putuskan` memakai selector yang
  sama; Socket.IO mempertahankan `auth.perangkatId`/`auth.layananId` existing.
- Cookie browser HttpOnly tetap dikelola browser/backend; tidak ada pembacaan
  `document.cookie`, secret storage baru, token baru atau JWT akun kiosk. Seluruh
  endpoint device memakai `authenticated:false`. Transport native terenkripsi dan
  header token manual existing tetap kompatibel; token manual tidak masuk state.
- Metadata `Aktif` merupakan izin administratif, bukan bukti online. State ready
  berasal dari respons sesi server; koneksi realtime tetap memiliki status sendiri.
- Scope terikat device identity, poli, API base dan epoch. Mengganti perangkat
  mengosongkan scope lama, menghentikan feed/audio dan menolak hasil request lama.
  Penulisan/penghapusan selector diserialkan; write yang selesai setelah close
  dibersihkan bila masih menunjuk ID operasi lama.
- Pairing tidak diulang otomatis setelah timeout. Pada isolated tab yang kehilangan
  respons sebelum ID diketahui, cookie tidak ditebak/dibaca untuk menemukan ID.
  State uncertain menahan pengiriman ulang dan menyediakan pemeriksaan sesi.
  ACK pairing diikuti GET gagal dapat dipulihkan dari selector tanpa POST kedua.
- Disconnect menunggu pencabutan backend. Setelah ACK, scope langsung dihentikan.
  Jika cleanup selector gagal, state menjelaskan pencabutan sudah dikonfirmasi
  tetapi penyimpanan tab belum bersih; credential tidak dipakai lagi.
- 401/403 REST atau penolakan socket mengosongkan snapshot, mematikan audio dan
  membuang subscription. Ganti perangkat dari kondisi ditolak dapat membersihkan
  selector tanpa mencoba mengaktifkan credential yang sudah ditolak.

Kode di controller dibersihkan setelah percobaan; token input dibersihkan setelah
connect. Tidak ada kode/token/raw QR/password dalam emitted state, log atau cache.
Error API dipetakan ke pesan statis dan status; metadata memakai whitelist.
Menghapus referensi String bukan jaminan wipe byte memori runtime.

## Snapshot, completion dan realtime

REST tetap sumber kebenaran. Snapshot hanya menerima versi skema existing dan
scope poli yang sesuai bila ID poli tersedia. Whitelist mempertahankan proyeksi
publik server: nomor, nama yang telah diproyeksikan, status, ruang, total aktual,
tanggal dan announcement. Field akun/email/NIK/QR/token yang tidak termasuk kontrak
tidak diterbitkan. Map/List immutable; perubahan status/loading menggunakan
referensi snapshot yang sama, tanpa menyalin seluruh daftar saat clock tick.

Satu Future drain berlaku per scope. Refresh selama fetch bergabung, menandai
dirty dan menunggu trailing read. Burst dikoaleskan; invalidasi selama trailing
tetap diproses. Pemeriksaan dirty sebelum completion menutup celah akhir drain.
Scope baru boleh mulai sementara request scope lama berakhir; hasil lama diabaikan.
Kegagalan refresh mempertahankan snapshot valid dengan indikator error, bukan
empty/zero palsu. Penolakan otorisasi membersihkan snapshot.

RealtimeFeed existing mempertahankan namespace `/display`, cookie/header token,
ready, filter layanan/skema, event `display:updated` serta reconnect existing.
Bootstrap live menunggu `display:ready`; fallback REST existing 15 detik tetap
tersedia. Tidak ada socket atau polling Widget kedua. Satu notifikasi onEvent +
onRefresh milik adapter diperlakukan sebagai satu invalidasi BLoC, tanpa dua fetch
yang tidak perlu. Event ID didedup dengan batas 256 per scope. Callback feed lama
ditolak setelah scope diganti/dispose. Setelah reject, timer tidak mengakses data;
close membatalkan timer dan subscription.

## CALL, RECALL, baseline senyap, dan TTS

AnnouncementGate existing dipindahkan ke service dan tetap diekspor dari
`display.dart` untuk kompatibilitas. Deduplikasi suara memakai `peristiwaId` dari
REST, bukan ticket ID atau ID sintetis. RECALL dengan ID audit baru tetap bersuara.
Event socket CALL/RECALL yang sah memberi sinyal untuk memeriksa pengumuman;
payload socket sendiri tidak menjadi teks TTS atau snapshot lokal.

Initial load, reconnect, resume dan refresh manual membentuk baseline senyap.
Connection epoch menolak bacaan yang dimulai sebelum rebase. Event selama fetch
menjadi milik trailing read, sehingga snapshot sebelum invalidasi tidak
mengumumkan teks yang salah. SKIP/REQUEUE/START/COMPLETE/ENQUEUE hanya merekonsiliasi
REST. Pengumuman yang diterima saat mute tetap dikonsumsi; mengaktifkan audio tidak
memutar backlog. Tidak ada TTS pada `build()` atau perubahan pagination.

Audio baru enabled setelah aktivasi pengguna berhasil memeriksa voice `id-ID`,
menetapkan bahasa dan mengirim utterance aktivasi. Tidak ada bypass autoplay atau
provider berbayar. Controller menghentikan utterance sebelumnya dan memeriksa epoch
setelah setiap await. Mute, scope invalid, background, revoke dan close membatalkan
suara lama; resume tetap senyap. Error engine mematikan audio dengan fallback
visual. Callback error dilepas pada disposal.

Nama/teks di layar dan TTS memakai proyeksi server yang sama. Frontend tidak
memilih kebijakan LENGKAP/SAMAR/TANPA_NAMA atau membangun nama lengkap dari API akun.
Konfigurasi dan persetujuan privasi server tidak diubah.

## Multi-monitor dan UI

Setiap instance memiliki selector, scope, repository feed, gate dan audio controller
sendiri. Tes fake mencakup A/poli A, B/poli B, C/poli A, pairing B saat A aktif,
revoke/rotate A, disconnect/reconnect A dan announcement pada dua monitor satu
poli. Operasi satu instance tidak mengubah state/engine fake instance lainnya.

Solusi named cookie/sessionStorage di source baseline sudah tersedia dan
dipertahankan, tanpa mengandalkan status PR historis. Duplicate/opener tab dapat
menyalin sessionStorage dan mula-mula mewakili perangkat yang sama; tab independen
memerlukan selector/pairing sendiri. Origin sama bukan batas terhadap XSS;
kuota cookie/header browser dan proxy tetap berlaku.

Board V3, layout/warna/font/spacing, fullscreen, call hero, status MENUNGGU/DILEWATI,
total server dan auto-pagination existing tidak diubah. Jam menggunakan zona
pelayanan `Asia/Jakarta` melalui AppConfig dan ValueNotifier existing. Tick jam
tidak membangun ulang snapshot; pagination 12 detik tidak melakukan fetch atau TTS.

## Ringkasan lima portal dan technical debt

| Portal | Ownership feature setelah migrasi |
|---|---|
| DOKTER | DoctorPortalCubit / DoctorRepository (ApiDoctorRepository). |
| ADMIN | Cubit per modul, shared AdminCatalogRepository dan adapter command existing. Dashboard tetap proyeksi katalog. |
| PASIEN | Cubit overview/booking/reservations/ticket, PatientRepository dan booking adapter; AccountProfileCubit lintas role. |
| PETUGAS | StaffQueueBloc / StaffQueueRepository, satu guard command dan feed. |
| PUBLIC DISPLAY | DisplayDeviceCubit + DisplayMonitorBloc, repository scope/monitor dan audio controller per instance. |

Feature state kini mengikuti pola immutable, DI, generation guard, cleanup dan
REST reconciliation yang konsisten. Ini tidak menghapus seluruh local State:
form/controller, navigasi, search/filter, scroll, animasi, fullscreen, clock dan
pagination visual tetap lokal secara sengaja. QueueApi/SessionStore masih menjadi
fondasi autentikasi/transport existing. RealtimeFeed, DisplaySelection/client/
fullscreen adapters tetap diperlukan. SnapshotLoader lama masih ada untuk
kompatibilitas/tes, tanpa owner produksi PETUGAS/Public Display setelah migrasi.

Risiko yang tersisa:

- Invalidasi best effort dan `pengumumanTerakhir` bukan log replay. Burst CALL atau
  offline dapat melewati pengumuman antara; tahap ini tidak menambah endpoint/outbox.
- Gate/event dedup dibatasi 256 ID per scope; tidak ada persistensi snapshot pasien.
- Pairing tanpa ID hasil yang terverifikasi dan storage yang tidak tersedia
  memerlukan pemulihan operator; tidak ada idempotency key/backend cancellation.
- FlutterTts existing memakai kanal platform bersama per Flutter engine. Instance
  controller/fake terisolasi, tetapi banyak DisplayPage dalam satu engine bukan
  bukti isolasi speaker. Tab/browser/perangkat nyata tetap harus diverifikasi.
- Tidak ada benchmark baru; tidak ada klaim peningkatan performa. Beban snapshot,
  burst invalidasi dan lifecycle engine perlu diamati saat QA end-to-end.

## File dan pengujian

Baru: tujuh file fitur display (models, dua repository, DeviceCubit, MonitorBloc,
AnnouncementGate, audio controller), fixture dan empat file tes, serta dokumen ini.
Diubah: `display.dart` dan satu ekspektasi pesan aman pada `display_pairing_test.dart`.
Tidak ada dependency/tooling, backend/API/RBAC/Queue Engine/database/migration,
privacy config, pairing backend atau implementasi portal lain yang diubah.
README dan tiga file dokter lokal dilindungi SHA-256; backup/untracked lama tidak
diikutkan commit.

Tes baru **76**: **5A 22, 5B 16, 5C 21, 5D 17**. Validasi terarah akhir **123 lulus**,
mencakup Completer untuk race/refresh/selector, fake API/socket/timer/audio,
secret hygiene, pairing, revoke partial, multi-monitor dan UI V3. Viewport integrasi
1280×720, 1366×768 dan 1920×1080 lulus tanpa scrolling/overflow pada kondisi diuji.
Validasi akhir:

- **1.041 tes lulus**, 0 gagal, 0 skip dalam suite yang dijalankan: 67 file,
  **7m10s**. Satu file live integration sengaja dikecualikan, bukan diklaim lulus.
  Hitungan lokal termasuk tes dokter terlindungi yang tidak masuk commit.
- Flutter analyze **No issues found**; pemeriksaan format 14 file Dart **0 perubahan**.
  Diff whitespace bersih.
- Web release berhasil **249.1s**, memakai `--no-pub --release
  --no-web-resources-cdn --no-wasm-dry-run`; output `apps/client/build/web`.
- APK debug berhasil **133.7s**; output
  `apps/client/build/app/outputs/flutter-apk/app-debug.apk`. Warning Java native
  access dan KGP `flutter_tts` existing tetap ada; tooling tidak di-upgrade.

Tidak ada pengujian manual/browser live/perangkat fisik pada tahap ini. Saat
preflight QA, port fixture E2E 3001 tidak aktif dan FLUTTER_REAL_FIXTURE tidak
disediakan. Tes meniadakan fixture/capture live dan tidak menyentuh database
development. Hasil browser historis bukan validasi live migrasi ini. Cookie
HttpOnly/profil/tab, speaker/voice/autoplay, TV fisik, reconnect jaringan nyata,
revoke/rotate perangkat, kamera QR, operasi antrean/booking paralel, session dan
RBAC live tetap **pending verification** pada environment test yang tervalidasi.
Tidak ada deployment atau pekerjaan baru di luar Tahap 5 yang dimulai.
