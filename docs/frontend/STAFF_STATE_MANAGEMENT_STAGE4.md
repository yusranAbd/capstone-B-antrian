# Portal PETUGAS — state management Tahap 4 terpadu

29 Oktober 2026. Baseline aktual `c04fa07` di `main`, sinkron dengan `origin/main`.
[CI Tahap 3](https://github.com/yusranAbd/capstone-b-antrian/actions/runs/40750740524)
sukses saat preflight. Acuan: [UI QueueB](QUEUEB_UI_UX_GUIDELINES.md),
[kontrak API](../backend/API_INTEGRATION_GUIDE.md) §4, §6, §8, §17, §26 dan
proyeksi Portal PETUGAS V4; [Tahap 2E](ADMIN_STATE_MANAGEMENT_STAGE2E.md) dan
[Tahap 3](PATIENT_STATE_MANAGEMENT_STAGE3.md).

## Ownership dan integrasi 4A–4D

| Area | Pemilik |
|---|---|
| Snapshot/penugasan/jadwal | Satu `StaffQueueBloc` per `QueuePage`; satu state immutable, tanpa cache snapshot paralel di Widget/repository. |
| Transport | `StaffQueueRepository` mengadaptasi `QueueApi` existing dengan DI; autentikasi, token dan SessionStore tetap milik QueueApi. |
| Realtime | Repository memiliki satu `RealtimeFeed` untuk layanan ruang terpilih; feed lama dibuang sebelum penggantinya dibuat. Widget tidak memiliki socket/listener snapshot. |
| Command | Semua CALL, RECALL, SKIP, REQUEUE, START, COMPLETE, pemulihan CHECK_IN (`masuk`) dan One-Scan memakai satu jalur BLoC/repository. |
| Poll/resume | Timer fallback existing 15 detik dimiliki BLoC; Widget meneruskan resume sebagai event refresh. Factory timer bisa diinjeksikan untuk tes deterministik. |
| Presentation | Search/controller, pagination visual `StaffPatientList`, dialog, navigasi dan kamera tetap milik Widget. Batch tindak lanjut server dimiliki BLoC. |

`QueuePage` membuat BLoC/repository sekali. Provider `.value` tidak membuat owner
baru saat rebuild. Halaman menutup BLoC, dialog privat, controller dan repository
miliknya pada disposal. Repository eksternal yang diinjeksi tetap dibuang oleh
pemanggil; BLoC tetap menghentikan feed scope miliknya. QueueApi bersama tidak
ditutup. Profil lintas role hasil Tahap 3 tetap digunakan tanpa modifikasi.

UI V4, header compact/avatar/profil, pemilih ruang, dokter terjadwal, panel
pelayanan, daftar CHECK_IN/MENUNGGU/DILEWATI, search/pagination, FAB QR, spacing,
tipografi dan layout existing dipertahankan. `BlocConsumer` menghubungkan state dan
cleanup dialog; perubahan koneksi saja memakai `BlocSelector` status realtime.
Tidak ada fetch dari `build()`. Tidak ditemukan jalur input QR manual aktif;
tidak ada fitur manual baru. Dokter terjadwal tidak diberi status kehadiran baru.

## Event, state, scope

- Event: `StaffRefresh` (initial/manual/realtime/resume/fallback, opsional reload
  penugasan), `StaffRoomSelected`, `StaffPageSelected`, `StaffCommand`, status
  realtime dan invalidasi sesi. Seluruh command memakai enum route existing.
- State: assignment sah, room/date, snapshot, jadwal, batch, load/error kategori,
  status command, `mutationConfirmed`, `synchronized`, status koneksi. Map/List
  dibekukan rekursif dengan helper metadata aman existing. Proyeksi pasien
  dideduplikasi menurut ID tiket tanpa mengubah urutan server.
- Tanggal memakai `QueueApi.config.today` pada zona pelayanan `Asia/Jakarta` dan
  `tanggalPelayanan` snapshot, bukan kalender perangkat. Tidak ada pemilih tanggal
  historis baru karena UI/API operasional existing tidak menyediakannya.
- Generation berubah saat ruang/batch/tanggal/identitas berubah. Respons ruang
  atau jadwal lama diabaikan. Pemilihan ruang/batch ditahan selama command aktif;
  invalidasi sesi/tanggal tetap mengalahkan hasil HTTP lama.
- Identitas akun/peran dan session phase diperiksa di repository. Logout atau
  pergantian akun/peran mengakhiri scope secara permanen, menghentikan feed/timer,
  mengosongkan state dan menutup BLoC. Scanner/detail privat ditutup. Hasil HTTP
  terlambat tidak diterapkan; request yang sudah terkirim bukan dianggap batal.

## S02/S03 dan completion refresh

Audit source baseline membuktikan S02 masih ada pada `SnapshotLoader.refresh()`:
pemanggil kedua langsung kembali ketika fetch aktif. S03 masih berupa
`unawaited(loadSchedules(...))`. Portal PETUGAS kini tidak memakai SnapshotLoader;
implementasi bersama/Public Display tidak diubah dalam tahap ini.

BLoC memiliki satu Future drain untuk scope yang sama. Refresh menandai dirty;
caller selama fetch bergabung ke Future tersebut. Snapshot dibaca, batch yang
menyusut diklem lalu dibaca ulang, kemudian jadwal untuk ruang/tanggal snapshot
ditunggu dalam siklus yang sama. Invalidasi saat request aktif menghasilkan
trailing read; invalidasi saat trailing juga diproses. Pemeriksaan dirty terakhir
sebelum completion mencegah invalidasi hilang pada batas penyelesaian drain.
Tidak ada fetch snapshot/jadwal paralel pada scope yang sama. Scope baru dapat
berjalan sementara request scope lama berakhir, dengan generation guard.

Queue snapshot valid ditampilkan saat tersedia. Jadwal memakai status load/error
sendiri; kegagalan jadwal nonotorisasi menampilkan kegagalan jadwal existing tanpa
mengarang kehadiran atau memblokir snapshot antrean valid. 401/403 mengosongkan
pasien/jadwal privat. Refresh snapshot gagal mempertahankan bacaan valid terakhir
untuk konteks yang sama, tetapi menandainya tidak sinkron dan menahan mutasi.

## Global guard dan rekonsiliasi mutasi

Satu `_running` di jalur `StaffCommand` dipasang secara sinkron sebelum `await`
pertama. Semua jenis command, termasuk QR, berbagi pengunci ini. Handler event
berbeda tidak diberi asumsi bahwa `sequential()` menjamin mutual exclusion.
Repository juga mencegah POST paralel. Tidak ada dependency concurrency baru.

Alurnya: admission → sending → respons backend → reconciling → REST drain selesai
→ confirmed/failed/unsynced/uncertain. `mutationConfirmed` membedakan ACK backend
dari snapshot yang sudah sinkron. Busy mencakup POST **dan seluruh drain/trailing**.
Hasil POST tidak menulis transisi optimistis, nomor antrean, atau prioritas lokal.
Endpoint/payload tetap `/queue/panggil`, `/queue/:tiketId/<aksi>` dengan `loketId`.
Eligibility tombol mengikuti proyeksi existing; backend tetap memutuskan RBAC,
penugasan, konflik dan state machine.

- POST ditolak (400/401/403/404/409/410/429): baca ulang, pertahankan kategori error
  aman, jangan menampilkan sukses atau mengulang POST otomatis.
- POST dikonfirmasi, refresh gagal: status `unsynced`, ACK tetap diketahui tetapi
  tidak ada klaim snapshot terbaru. Command berikutnya ditahan sampai REST scope
  yang benar berhasil. Reload GET tidak mengirim POST yang sama.
- Timeout/5xx/hasil respons tidak valid: status `uncertain`, simpan metadata aman
  operation/room/date/ticket/version, tanpa QR. GET direkonsiliasi. Perubahan
  status tiket nyata dapat memverifikasi keadaan aman; RECALL memerlukan versi
  backend meningkat. Verifikasi keadaan tidak mengklaim atribusi transaksi milik
  klien ini. Tidak ada retry POST.
- CALL kehilangan ID hasil, QR opaque kehilangan hasil, atau COMPLETE tidak
  terlihat lagi pada snapshot terbatas: ketiadaan bukan bukti gagal/berhasil.
  Marker konservatif tetap menahan mutasi dalam scope sesi, termasuk setelah
  pergantian ruang. Diperlukan pemeriksaan operator/backend yang sah; tahap ini
  tidak menambah endpoint untuk menghapus ketidakpastian tersebut.

Marker bukan persistence lintas login dan bukan idempotency key. Transport tidak
memiliki cancellation transaksi backend. Beberapa endpoint GET bukan satu snapshot
database atomik lintas jadwal/assignment/antrean.

## QR dan realtime

Kamera, permission, preview, pause/resume dan disposal tetap pada `StaffQrScanner`.
Frame QR identik ditekan selama dialog; callback mengirim event transient yang
mengonsumsi payload sekali dan memiliki diagnostik redacted. BLoC meneruskan
`{qrPayload,loketId}` ke **POST `/check-in/auto-antrean`** existing. Validasi,
expiry, otorisasi, deduplikasi serta check-in/auto-enqueue atomik tetap di backend.
ID tetap ID tiket, bukan appointment. Scanner hanya menerima hasil sukses setelah
respons MENUNGGU dan rekonsiliasi berhasil. Tidak ada status sukses palsu ketika
refresh gagal. Menutup dialog tidak membatalkan mutasi server atau membuka guard.

Payload/password/token/cookie tidak masuk emitted state/persistence/log. QR
hanya argumen sementara dan nilai lokal scanner; referensinya dibersihkan pada
disposal/sesi berubah. Menghapus referensi String bukan jaminan wipe byte memori.
Error dipetakan ke pesan statis dan kategori status; exception non-API scanner
tidak dirender mentah. Feedback audio tetap opsional/nonblocking.

`RealtimeFeed` mempertahankan namespace `/queue`, `queue:join`/ACK, schema dan
filter layanan, `queue:updated`, refresh setelah reconnect serta penanganan token
existing. Socket payload hanya invalidasi, bukan data antrean final. Tidak ada
listener Widget lama atau polling kedua. Callback feed yang telah dibuang ditolak
oleh epoch adapter. Strategi existing maksimal delapan reconnect tidak diubah:
setelah habis, REST fallback 15 detik dan reload tetap tersedia; pembukaan scope
baru membuat satu feed baru. Pemulihan koneksi setelah offline lama, autentikasi
socket dan retry nyata tetap memerlukan pengujian live.

## File dan validasi

Baru: lima file di `features/staff/` (repository, models, BLoC, event, state),
`test/staff_bloc_fixture.dart` dan empat `staff_*_bloc_test.dart`. Modifikasi:
`queue.dart`, `staff_qr_scanner.dart`. Satu dokumen ini. Tidak ada dependency baru.
README dan tiga file dokter lokal dilindungi SHA-256; backup/untracked lama tidak
ikut commit. Backend/API/RBAC/Queue Engine/database/migration, booking pasien,
SessionStore dan Public Display tidak dimodifikasi.

Tes baru **79**: 4A **18**, 4B **31**, 4C **14**, 4D **16**. Seluruhnya lulus
bersama. Tes fase bersama regresi existing: 4A 32, 4B 39, 4C 18, 4D 47 lulus.
Mencakup Completer untuk S02/S03, penguncian lintas aksi, hasil tidak pasti,
reconciliation gagal, scope/session, burst/trailing, fake realtime/timer, cleanup
scanner serta widget V4. Regresi compact existing menguji 320–1920 logical px,
tanpa overflow pada viewport yang diuji. Tidak ada klaim percepatan tanpa ukur.

Validasi akhir:

- **965 tes lulus**, 0 gagal, 0 skip dalam suite yang dijalankan (63 file, 8m36s).
  Termasuk tes dokter lokal yang dilindungi dan tidak ikut commit. Satu file
  `live_integration_test.dart` sengaja dikecualikan; `FLUTTER_REAL_FIXTURE` serta
  variabel capture dinonaktifkan. Tidak ada mutasi backend live/database.
- Flutter analyze: **No issues found**. Format terbatas pada 12 file Dart:
  pemeriksaan akhir **0 perubahan**. Diff whitespace bersih.
- Web release berhasil, **231.8s**, dengan `--no-pub --release
  --no-web-resources-cdn --no-wasm-dry-run`; output `apps/client/build/web`.
- APK debug berhasil, **279.1s**; output
  `apps/client/build/app/outputs/flutter-apk/app-debug.apk`. Warning Java native
  access dan KGP `flutter_tts` existing tetap dicatat; tidak ada upgrade tooling.

Manual/perangkat/live belum dilakukan: kamera Web/Android dan izin, background/
resume kamera fisik, scan QR pasien nyata, RBAC backend live, dua klien petugas
berlomba, response loss pada transaksi nyata, reconnect setelah delapan percobaan,
midnight pelayanan dan pencabutan sesi end-to-end. Fake API/build tidak membuktikan
hasil tersebut. Database development tidak disentuh. Tahap 5 Public Display belum
dimulai dan memerlukan arahan pengguna berikutnya.
