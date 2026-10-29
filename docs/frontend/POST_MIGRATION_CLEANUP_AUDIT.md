# QueueB Hospital — Post-Migration Cleanup & Optimization Audit

> Update stabilisasi: lihat bagian K. Patch dua policy read snapshot yang disetujui sudah diterapkan. Run akhir **13 kelompok E2E PASS, nol HTTP 5xx/P2028**; Flutter/backend/build PASS. **Cleanup terverifikasi dan finalisasi Git diotorisasi**: pengguna menyetujui pengecualian historis Gate E beserta satu commit dan push fast-forward. Delta sesi development awal tetap belum teratribusi; seluruh window validasi patch tidak mengubah kedua database.

Tanggal pengukuran: 29 Oktober 2026. Baseline release **READY FOR FINAL MANUAL VERIFICATION**. **Seluruh regresi lokal PASS; pengecualian Gate E historis dan finalisasi Git disetujui pengguna.**

## A. Executive Summary

Cleanup menghapus **14 deklarasi class dan satu fungsi top-level** yang tidak mempunyai konsumen produksi. Delapan file produksi berubah; tidak ada file produksi, dependency, aset, endpoint, atau adapter aktif yang dihapus. Dua tes implementasi `SnapshotLoader` dipensiunkan dengan pemetaan eksplisit ke tes perilaku BLoC yang tetap berjalan. Source produksi berkurang **660 baris / 20.600 byte**.

Validasi stabilisasi terbaru: analyze bersih, **1.040 tes Flutter**, build Web/APK, **679 unit + 7 tooling backend**, dan **387 integrasi backend dalam 31 proses terpisah** lulus. Pengguna menyetujui tepat dua policy read snapshot pada bagian K5; patch sudah diterapkan. Run akhir **13 kelompok E2E strict PASS, nol HTTP 5xx/P2028**, pending request nol. Run pascapatch yang gagal tetap disimpan; satu run sukses tidak membuktikan seluruh variasi latency host telah diatasi. Delta sesi development 124→125 pada awal investigasi tetap belum teratribusi. Pengguna kemudian menyetujui pengecualian historis Gate E dan satu commit/push; [rekaman persetujuan](cleanup-evidence/recovery/historical-gate-e-approval.json). Perubahan lokal lama tetap dikecualikan.

Seluruh 106 file produksi masih terjangkau dari entry point. Tidak ditemukan alasan terverifikasi untuk mengganti ownership BLoC/Cubit, mengurangi refresh transaksi, mengubah UI, atau melakukan optimasi rebuild. Tidak ada klaim perbaikan memory leak maupun peningkatan FPS. Hasil build dan runtime terukur dibahas terpisah dari pengurangan source.

## B. Baseline

Baseline aktual: `main`, HEAD lokal dan `origin/main` pada awal audit **`c6e64417801567188fb1495b75ec9dc9ca4dfc37`**. Fetch origin sudah dilakukan. CI baseline [sukses](https://github.com/yusranAbd/capstone-b-antrian/actions/runs/40806608797). Tidak membuat branch, worktree, atau PR.

Working tree awal mempunyai perubahan pengguna pada `README.md`, `doctor_dashboard.dart`, `doctor_visual.dart`, dan `doctor_visual_refresh_test.dart`; keempatnya dikecualikan dari staging dan cleanup. Untracked awal `apps/web/`, `backups/`, `sql/`, `DOCTOR_DASHBOARD_COMPACT_REVIEW.md`, serta `images/doctor-compact/` dipertahankan. Baseline pengukuran memakai isi working tree aktual tersebut, bukan rekonstruksi HEAD yang menghilangkan perubahan pengguna.

SHA-256 file dilindungi tersedia dalam [before-source.json](cleanup-evidence/before-source.json) dan [after-source.json](cleanup-evidence/after-source.json), identik untuk keempat file. Tidak ada backup atau file lokal pengguna yang dihapus.

| Metrik source tracked | Before | After | Metode |
|---|---:|---:|---|
| Dart lib + test + integration_test | 181 file | 181 file | `git ls-files`, working-tree bytes |
| Produksi lib | 106 file | 106 file | Semua terhubung ke main, termasuk conditional imports |
| Test/support Dart dalam test | 73 file | 73 file | 68 `*_test.dart` + 5 helper |
| integration_test | 2 file | 2 file | Terpisah dari suite host Flutter |
| LOC produksi | 26.514 | 25.854 | Baris fisik, CRLF dinormalisasi, baris terminal kosong dikecualikan |
| LOC seluruh Dart | 50.155 | 49.481 | Scope identik; termasuk 20 baris tes recovery baru |
| Byte produksi | 891.870 | 871.270 | Byte aktual, termasuk line endings |
| Byte seluruh Dart | 1.703.319 | 1.682.486 | Scope identik; termasuk 873 byte tes recovery baru |
| Class produksi | 280 | 266 | AST, termasuk abstract/private |
| Dependency langsung | 17 | 17 | 13 runtime + 4 dev; SDK entries termasuk |
| Repository | 13 | 13 | Deklarasi berakhiran Repository; 12 konkret + 1 abstract |
| Cubit / BLoC | 20 / 2 | 20 / 2 | Termasuk subclass Cubit lokal |
| ChangeNotifier | 11 | 11 | Hierarki lokal eksplisit, termasuk implementasi platform alternatif |
| setState | 184 call site | 184 call site | Bukan jumlah rebuild atau defect |
| Resource terdeteksi AST | 59 site | 59 site | Alokasi/listen; bukan jumlah instance aktif |
| addListener / removeListener | 30 / 30 site | 30 / 30 site | Jumlah seimbang saja tidak membuktikan disposal |

Baseline tes Flutter **1.041 PASS** berasal dari [eksekusi Final QA pada hari yang sama](../qa/evidence/flutter-execution.json), dengan source lokal dilindungi yang sama. Audit ini menjalankan ulang suite lengkap sesudah cleanup; baseline tes tidak diklaim sebagai pengukuran ulang sebelum penghapusan. Analyze, build Web/APK, dan benchmark browser before diambil ulang sebelum cleanup.

## C. Dependency & Architecture Inventory

Peta panggilan yang diperiksa: `main.dart → QueueBApp/role router → Widget/presentation → Cubit/BLoC → feature repository → QueueApi → platform HTTP/Socket.IO → Nest`. `web/index.html → flutter_bootstrap.js → lib/main.dart`; Android `MainActivity : FlutterActivity` memakai target Dart yang sama. Tidak ada consumer alternatif yang teridentifikasi melalui provider, router, generator, service locator, refleksi, konfigurasi, atau registrasi plugin untuk deklarasi REMOVE.

Inventaris AST memeriksa import/export/part dan **semua cabang conditional imports**, bukan hanya platform host. Semua 106 file produksi reachable. Scope tidak mencakup penghapusan file di `apps/web/` yang untracked. Graph lengkap, referensi identifier, daftar class, resource dan importer dependency: [before](cleanup-evidence/before-architecture.json), [after](cleanup-evidence/after-architecture.json). Kandidat lexical bukan hasil resolver semantik; keputusan REMOVE juga memakai pencarian exact-token seluruh repo di luar build/dependency/backup/dokumen historis, pemeriksaan source konsumen, dan validasi compiler/tes. Versi HEAD dari tiga file Dart dilindungi yang tidak ikut commit juga diperiksa read-only terhadap semua nama yang dihapus: [nol referensi](cleanup-evidence/committed-consumer-check.json).

| Portal | Owner state kanonis | Repository dan batas ownership |
|---|---|---|
| DOKTER | DoctorPortalCubit; AccountProfileCubit untuk profil akun | ApiDoctorRepository/DoctorRepository, AccountProfileRepository; PatientUpdates role DOKTER namespace doctor, bukan feed pasien kedua |
| ADMIN | PolyclinicCubit, DoctorCatalogCubit, RoomCubit, ServiceScheduleCubit, PracticeScheduleCubit, ScheduleBatchCubit, SlotSessionCubit, StaffAccountCubit, AssignmentCubit, DisplayManagementCubit | AdminCatalogRepository bersama; AdminSchedule/Slot/Staff/DisplayRepository menjadi bridge command dan membaca katalog bersama; slot/display lazy sesuai kebutuhan |
| PASIEN | PatientOverview/Booking/Reservations/TicketCubit; AccountProfileCubit | Satu PatientRepository + PatientUpdates per scope; PatientBookingRepository/AccountProfileRepository untuk command; refresh trailing dan generation guard dipertahankan |
| PETUGAS | StaffQueueBloc | StaffQueueRepository, satu feed scope ruang aktif; command lock global dan reconciliation dipertahankan |
| PUBLIC DISPLAY | DisplayDeviceCubit dan DisplayMonitorBloc | DisplayDeviceRepository + DisplayMonitorRepository; satu feed per device aktif; audio, fullscreen, clock, pagination mempunyai owner tersendiri |

Jumlah 20 Cubit mencakup base `AdminCatalogCubit`, `AdminScheduleCubit`, `AdminStaffCubit` dan subclassnya. Dua BLoC adalah `StaffQueueBloc` dan `DisplayMonitorBloc`. Tidak ada store kanonis baru atau perpindahan state presentasional ke BLoC.

Constructor injection dan batas externally-owned repository tetap dipertahankan. Snapshot admin/dokter di-freeze rekursif; pasien/staff/display memakai safeSnapshot/unmodifiable pada jalur data yang ditinjau. Credential dan QR sekali pakai tidak dimasukkan ke snapshot feature. Draft form/controller tetap milik Widget. Guard sesi/generation, trailing read dan status mutation/unknown/reconciliation diperiksa pada owner aktif, bukan disalin ke state manager baru.

### Dependency langsung

| Package | Keputusan | Bukti |
|---|---|---|
| flutter | KEEP | UI/framework dan registrasi platform |
| cupertino_icons | KEEP | Font package terdaftar dalam FontManifest build; compiler benar-benar memproses/tree-shake menjadi 1.472 byte. Tidak menyimpulkan unused dari nol import aplikasi; penghapusan perlu audit glyph/platform terpisah |
| http | KEEP | QueueApi dan native/web display client; juga mock HTTP di tes |
| socket_io_client | KEEP | RealtimeFeed dan PatientUpdates |
| timezone | KEEP | main/config, timezone pelayanan Asia/Jakarta |
| qr_flutter | KEEP | Tiket/QR serta tes |
| mobile_scanner | KEEP | StaffQrScanner dan integrasi kamera |
| flutter_tts | KEEP | FlutterDisplaySpeech; plugin dan Web Speech aktif |
| flutter_localizations | KEEP | MaterialApp/delegates locale id dan tes |
| intl | REVIEW direct constraint; retained | Tidak ada import langsung; dipakai transitif flutter_localizations (SDK lokal mendeklarasikan ^0.20.3). Potensi redundansi deklarasi langsung, bukan package runtime yang terbukti bisa dibuang. Tidak mengubah kontrak resolusi dependency untuk pengurangan semu |
| flutter_secure_storage | KEEP | SessionStore Android serta secure selector/header display native |
| file_selector | KEEP | Upload media dokter/admin dan tes |
| flutter_bloc | KEEP | State management produksi dan provider |
| bloc_test | KEEP | Tes katalog admin dan portal dokter |
| integration_test | KEEP | Dua entry point integration_test |
| flutter_test | KEEP | Tes Flutter dan fixtures |
| flutter_lints | KEEP | `analysis_options.yaml` include, meski tanpa import Dart |

`pubspec.yaml` dan `pubspec.lock` tidak berubah. Aset `doctor_avatar.png` dan `patient_ticket.webp` mempunyai consumer aktif. `login_hospital.webp` masih terdaftar sebagai branding dalam pubspec tetapi tanpa consumer Dart langsung yang ditemukan: **REVIEW**, dipertahankan sampai keputusan pemakaian branding/platform, tanpa menghapus aset berdasarkan nama. Native/Web display client, fullscreen, selector, dan socket header conditional adapters **KEEP**; Flutter compiler memilih cabang sesuai platform.

## D. Dead Code Findings

Untuk seluruh REMOVE: identifier AST dan import graph ditelusuri, pencarian exact-token di lib/test/integration_test/web/android/tool serta source/config repo tidak menemukan konsumen aktif, deklarasi diperiksa manual, kemudian analyze dan tes dijalankan bertahap. Bukti offsets, referensi sebelum penghapusan, hash potongan source dan pemetaan tes: [removals.json](cleanup-evidence/removals.json). Tidak menggunakan satu hasil rg sebagai dasar penghapusan.

| File/Komponen (di apps/client kecuali disebut) | Keputusan | Bukti | Perubahan | Risiko | Hasil Tes |
|---|---|---|---|---|---|
| lib/src/mobile_ui.dart: DoctorCard | REMOVE | Nol consumer; PatientDoctorCard adalah class aktif berbeda | Hapus class | Rendah, constructor tidak pernah dipanggil | Tahap mobile: analyze 0; 79 PASS |
| lib/src/mobile_ui.dart: HospitalVisual, _HospitalPainter | REMOVE | Nol consumer HospitalVisual; private painter hanya dipakai subtree tersebut | Hapus dua class | Rendah, tidak menyentuh aset branding | 79 PASS; full regression |
| lib/src/admin_delete.dart: AdminDeleteButton | REMOVE | Nol consumer; UI aktif memakai AdminRowActions; showAdminDelete tetap aktif | Hapus wrapper icon | Rendah | Tahap wrappers: analyze 0; 50 PASS |
| lib/src/patient_design.dart: PatientWordmark | REMOVE | Nol consumer; QueueBBrand/Home V6 tetap digunakan | Hapus class | Rendah | 50 PASS; full regression |
| lib/src/patient_home.dart: PatientHomeBrand, PatientHomeShortcuts, PatientHomeTip | REMOVE | Nol consumer; Home V6 dan komponen current tetap aktif | Hapus tiga class | Rendah | 50 PASS; full regression |
| lib/src/patient_ui.dart: PatientWelcome, PatientClinicGrid | REMOVE | Nol consumer; active home/catalog memakai komponen lain | Hapus dua class | Rendah | 50 PASS; full regression |
| lib/src/staff_ui.dart: StaffHeaderContext, StaffMetric | REMOVE | Nol consumer; toolbar/panel petugas aktif terpisah | Hapus dua class; import config.dart menjadi unused lalu dihapus | Rendah | 50 PASS; full regression |
| lib/src/staff_ui.dart: StaffLiveStatus | REMOVE | Satu-satunya consumer sebelumnya StaffHeaderContext; AST dan pencarian diulang sesudah penghapusan parent | Hapus child dead subtree | Rendah | Analyze 0; 12 tes compact PASS |
| lib/src/patient.dart: appointmentDetails | REMOVE | Nol caller; fungsi string murni, bukan API/booking flow | Hapus satu fungsi | Rendah | 50 PASS; full regression |
| lib/src/realtime.dart: SnapshotLoader | REMOVE | Nol consumer produksi, hanya dua tes implementasi lama; state aktif dimiliki BLoC | Hapus class dan komentar terkait; RealtimeFeed dipertahankan | Rendah dengan coverage mapping | Tahap loader: analyze 0; 51 PASS |
| test/core_test.dart: dua tes SnapshotLoader + import realtime.dart | REMOVE | Implementasi tidak digunakan produksi; perilaku dijamin tes BLoC aktif di bawah | Pensiunkan tepat dua tes, bukan suite perilaku | Rendah; penurunan hitungan dijelaskan | 51 PASS; full regression |
| lib/src/doctor_visual.dart: DoctorHeaderIdentity | DEFER | Kandidat AST nol consumer, tetapi file berisi perubahan lokal pengguna yang dilindungi | Tidak disentuh | Konflik dengan pekerjaan lokal | Hash identik; tes dokter dalam full suite |
| Seluruh 106 file produksi | KEEP | Semua reachable dari main termasuk cabang platform | Tidak ada file dihapus | Menjaga entry/config/platform | Compiler Web dan Android |
| intl constraint langsung, login_hospital.webp | REVIEW | Bukti redundansi potensial, penggunaan tidak langsung/intensi branding belum diselesaikan | Dipertahankan | Hindari pengurangan yang tidak bermanfaat/berisiko | Lock dan aset tidak berubah |

### Cakupan dua tes yang dipensiunkan

`Snapshot loader fetches again for mid-request events, no parallel requests` digantikan cakupan owner nyata `display_snapshot_bloc_test.dart`: `all callers await active and trailing refresh (S02)`, `burst invalidations coalesce without parallel fetches`, dan `invalidation during trailing read is retained`.

`Disposed loader cannot update another room` tetap dijamin oleh tes display `stale old-device response never overwrites new device`, `close while fetching clears snapshot and ignores late response`, serta tes staff `old room schedule cannot overwrite new room (S03)` dan `logout during fetch clears private data and ignores late response`. Tes memblokir response, mengganti scope/close, melepas response, memeriksa snapshot bersih dan feed tertutup. Tidak menghapus tes QR, transaksi, sesi, realtime, privasi, atau TTS.

## E. Cleanup Performed

Delapan file produksi dan satu file tes dibersihkan sesuai tabel D. **Tidak ada file source dihapus.** Total 14 class, satu fungsi top-level, dua tes usang, dua import yang menjadi unused. Tidak ada dependency/export/asset yang dihapus dan tidak ada perubahan fitur/backend.

Tahap terarah dijalankan berurutan: mobile 79 PASS; wrappers 50 PASS; loader/core/staff/display 51 PASS; closure staff 12 PASS. Satu warning unused import config.dart muncul sesudah penghapusan StaffHeaderContext, diperbaiki lalu analyzer diulang bersih. Review AST ulang menemukan StaffLiveStatus sebagai child dead subtree; suite penuh pendahuluan dihentikan secara sengaja, tidak dijadikan hasil gate. Suite final dijalankan setelah source terakhir stabil.

Tooling audit ditambahkan di `scripts/post_migration_audit.dart`, `cleanup_source_metrics.cjs`, `cleanup_artifact_metrics.cjs` dan `apps/client/tool/browser-cleanup-benchmark.cjs`. Runner existing memperoleh mode benchmark dan override folder evidence agar hasil Final QA historis tidak ditimpa. `QUEUEB_QA_SCREENSHOTS=0` mencegah penyimpanan screenshot fixture pada audit ini. E2E runner menambahkan diagnostik status GET tanpa payload, scheduling tab headless tanpa background throttling, dan menunggu admission gate UI petugas sebelum/sesudah command; assertion transaksi/QR/TTS tetap dipertahankan. Tidak ada instrumentasi benchmark yang masuk binary aplikasi.

## F. Runtime Audit

### Legacy compatibility dan state

Inventaris legacy didefinisikan sebagai **10 unit compatibility yang diaudit**, bukan semua class bernama lama: QueueApi; keluarga SessionStore; RefreshGate; PatientUpdates; RealtimeFeed; _AdminEditor; showAdminDelete; DoctorAccountDialog; PracticeScheduleEditor; SnapshotLoader. **9 KEEP, 1 REMOVE**. Platform adapters modern dihitung terpisah di graph dan tidak dicap dead legacy.

| Unit | Consumer / state kanonis | Keputusan dan risiko |
|---|---|---|
| QueueApi | Auth/session, token refresh, transport semua role | KEEP. Kanonis untuk sesi, feature Cubit tidak menggantikan transport/auth; penghapusan berdampak seluruh modul |
| SessionStore family | platformSessionStore dari main, Android secure/Web memory; tes | KEEP. Penyimpanan credential, bukan cache feature duplikat; secure_storage masih aktif |
| RefreshGate | PatientBookingCubit dan AccountProfileCubit | KEEP. Coalescing/trailing untuk request aktif; bukan state daftar kedua |
| PatientUpdates | PatientRepository serta ApiDoctorRepository dengan role/namespace terpisah | KEEP. Invalidasi/status/polling, bukan snapshot kedua; menghapusnya merusak realtime dua role |
| RealtimeFeed | StaffQueueRepository dan DisplayDeviceRepository | KEEP. Bridge transport scope, tidak menyimpan snapshot kanonis; socket_io_client tetap dibutuhkan |
| _AdminEditor | Form standalone dan fallback command saat callback tidak diinjeksi | KEEP. Form draft/command, katalog utama di repository/Cubit; migrasi penuh lintas form di luar cleanup |
| showAdminDelete | Dialog dipanggil aksi admin; callback command/fallback | KEEP. Konfirmasi/command, bukan owner koleksi kedua; penghapusan merusak CRUD |
| DoctorAccountDialog | Provision/link akun dokter oleh ADMIN | KEEP. Daftar pilihan lokal untuk dialog/command pendukung; bukan state portal DOKTER |
| PracticeScheduleEditor | Form jadwal; callback onSave atau standalone QueueApi fallback | KEEP. Draft form, bukan snapshot katalog kedua; mengubah kontrak fallback berisiko |
| SnapshotLoader | Hanya dua tes lama, nol produksi | REMOVE. Tidak ada dependency yang hanya diperlukan class ini |

Adapter aktif tidak ditemukan menyebabkan cache kanonis ganda atau masalah terukur pada skenario audit. Pekerjaan penggabungan form/callback membutuhkan refactor lebih luas dan **DEFER**. `ChangeNotifier` tersisa untuk invalidasi/repository/status/platform/auth; 184 setState site adalah state presentasional seperti form, tab, filter, pagination, fullscreen. Jumlah tersebut tidak dijadikan daftar bug.

### Resource, request, dan TTS

59 site AST pada 32 kelompok owner mencakup TextEditingController, Scroll/Tab/AnimationController, timer, notifier, audio/scanner dan feed; juga DefaultTabController yang didispose framework. Ini bukan 59 objek hidup atau hitungan leak. Dua timer polling BLoC dibuat lewat injectable `(periodicTimer ?? Timer.periodic)`, dan factory socket juga diperiksa manual di luar hitungan constructor AST. Anchor source pemeriksaan tersedia dalam [lifecycle-review.json](cleanup-evidence/lifecycle-review.json); kemunculan kata dispose pada file bukan bukti ownership otomatis.

Form admin/pasien/login/akun mendispose controller; repository melepas listener sesi; Cubit close melepas listener tanpa menutup repository bersama dari anak; page owner menutup scope miliknya. Staff/Display close membatalkan polling, melepas feed/listener dan menolak response lama menggunakan generation/scope checks. PatientUpdates membatalkan polling/debounce/socket dan status notifier. QueueApi membatalkan renewal timer dan menutup HTTP clients. Display clock/pagination timers, fullscreen subscriptions, scanner/controller, tab/scroll/animation controller mempunyai cleanup masing-masing. Bukti statik dilengkapi `performance_resources_test.dart`, tes session/isolation/snapshot/realtime dan browser connection counts; tidak mengklaim semua kemungkinan lifecycle perangkat fisik terbukti bebas leak.

Snapshot tetap dimiliki feature owner. Katalog ADMIN dimuat bersama dan slot/display dibuka lazy. Request pasien/dokter/staff dapat tercatat dua kali saat login awal karena load awal dan invalidasi/join/reconnect; tidak dianggap redundant hanya karena path sama. Tes trailing refresh, command serialization, double-submit dan reconciliation dipertahankan. Dua resize tetap tidak memicu request tambahan pada benchmark; tidak ditemukan request storm yang direproduksi sehingga tidak mengurangi refresh yang menjaga konsistensi.

DisplayMonitorBloc memakai event dedup bounded serta AnnouncementGate berdasarkan `peristiwaId`: initial/reconnect rebased senyap, CALL sekali, RECALL dengan event baru sah. Audio tidak dipanggil dari Widget build; audio context/epoch menolak operasi lama, stop dan error handler dilepas pada disposal. Provider FlutterTts tidak berubah. Pengujian suara engine/browser tidak membuktikan speaker fisik atau TV terpasang.

## G. Optimization Measurements

Environment sama: Windows, Flutter 3.47.5 / Dart 3.13.4; `API_BASE_URL=http://127.0.0.1:3001/api/v1`, `SERVICE_TIME_ZONE=Asia/Jakarta`; target `lib/main.dart`. Host RAM 8 GB, pengujian/build/browser berat dijalankan serial. Durasi single-run dipengaruhi cache dan beban host; bukan benchmark startup murni.

Build before dilakukan sebelum penghapusan: Web release dengan `--no-pub --release --no-web-resources-cdn --no-wasm-dry-run`, APK debug dengan `--debug --no-pub --target=lib/main.dart`. After menggunakan flag identik. Web bytes hanya file compiler root terpilih + assets/canvaskit/icons, **bukan seluruh build/web** yang juga berisi 53 output QA historis. File historis tidak dihapus. gzip9 dihitung lokal untuk main.dart.js, bukan ukuran transfer HTTP yang diukur. APK dibandingkan debug dengan debug, tidak mencampur artifact integration-test target lama.

| Artifact | Before (byte) | After (byte) | Selisih |
|---|---:|---:|---:|
| Web compiler output, 42 file | 48.151.299 | 48.150.962 | −337 |
| main.dart.js | 5.444.135 | 5.444.135 | 0; SHA-256 identik |
| main.dart.js gzip9 lokal | 1.384.718 | 1.384.718 | 0 |
| APK debug lib/main.dart | 258.817.135 | 258.817.135 | 0; hash archive berubah |

Font Material Icons hasil tree shaking berkurang 22.288→21.952 byte. Pengukuran ulang build stabilisasi menghasilkan total Web satu byte lebih kecil dari after cleanup awal 48.150.963; sumber perbedaan satu byte itu tidak diatribusikan. Tidak ada pengurangan JS atau ukuran APK yang terukur. Hasil ini mendukung manfaat maintainability, bukan klaim aplikasi menjadi lebih cepat. Bukti ukuran/hash: [before-artifacts](cleanup-evidence/before-artifacts.json), [after-artifacts](cleanup-evidence/after-artifacts.json); metrik after awal dipertahankan di recovery/cleanup-baseline-after-artifacts.json.

Build before Web/APK berhasil dalam 16,5/75,2 detik; after 193,1/86,7 detik (wrapper wall time). Source berubah memicu kompilasi ulang Web; cache dan beban host tidak dinormalisasi. Durasi tersebut bukan benchmark performa aplikasi atau bukti regresi startup. Log after memuat warning Java/Kotlin/plugin yang sudah ada; tidak melakukan upgrade toolchain untuk menghilangkannya. Bukti command/exit: [before-build](cleanup-evidence/before-build.json), [after-build](cleanup-evidence/after-build.json).

Benchmark runtime real Chrome headless + Nest + test PostgreSQL berjalan satu context per portal, dua viewport changes 1366→1280→1366, settling tetap, lalu CDP heap setelah collectGarbage. Bukti [before](cleanup-evidence/runtime-before/runtime-metrics.json), [after](cleanup-evidence/runtime-after/runtime-metrics.json), dan [comparison](cleanup-evidence/runtime-comparison.json). Counter HTTP browser hanya method+path yang UUID-nya dinormalisasi; tanpa body/query/header/token, provisioning fixture di luar halaman tidak dihitung. readyMs mencakup navigasi/login/typing/settling (display juga provisioning), **bukan startup aplikasi murni**. JS heap bukan heap penuh Dart/wasm/GPU/Android. LayoutCount adalah layout browser, bukan jumlah Flutter rebuild. Tidak mengukur FPS/frame timing karena profiler frame yang setara tidak dijalankan.

| Portal | Request before→after | Socket aktif before→after | Request tambahan dua resize | JS heap post-GC sebelum resize, byte before→after | readyMs before→after |
|---|---:|---|---:|---:|---:|
| ADMIN | 8→8 | 0→0 | 0→0 | 29.156.332→29.260.788 | 10.262→21.324 |
| PASIEN | 12→12 | patient 1→1 | 0→0 | 27.734.924→27.725.880 | 6.033→10.707 |
| PETUGAS | 7→7 | queue 1→1 | 0→0 | 27.869.360→27.924.712 | 5.984→9.185 |
| DOKTER | 10→10 | doctor 1→1 | 0→0 | 28.143.556→28.479.372 | 6.238→19.662 |
| DISPLAY | 3→3 | display 1→1 | 0→0 | 25.834.756→25.606.920 | 3.831→5.539 |

Counter per endpoint identik pada kedua sampel, bukan hanya totalnya. Socket tetap satu dalam scope terkait selama resize dan seluruh namespace menjadi nol setelah context ditutup; runtime errors nol. Heap setelah resize, DOM/layout counters dan request paths lengkap tersedia pada JSON. Nilai readyMs after lebih lama pada seluruh portal dan dilaporkan apa adanya. Pengukuran hanya satu sampel, beban/cold cache host tidak terkontrol, sedangkan hash JS identik: penyebab perbedaan durasi belum dapat diatribusikan kepada cleanup. Jangan menyebutnya percepatan atau menyimpulkan regresi startup kausal; lakukan pengukuran berulang di host stabil bila waktu masuk menjadi masalah operasional.

Perubahan dead code dapat sudah dihilangkan tree shaking pada release sebelum cleanup. Pengurangan LOC menunjukkan maintainability; perubahan satu sampel heap/durasi tidak membuktikan optimasi performa kausal atau leak teratasi. Tidak ada target persentase yang dipaksakan.

## H. Regression Results

| Gate lokal | Hasil aktual |
|---|---|
| dart format pada seluruh file Dart berubah | PASS |
| Analyze before / after final | 0 / 0 issues |
| Tes terarah | 79 + 50 + 51 + 12 PASS; bukan tambahan ke total suite penuh |
| Flutter safe host suite | **1.040 PASS**, 67 file, 549,4 detik; dua tes implementasi usang dipensiunkan dari baseline 1.041, satu tes perilaku recovery ditambahkan |
| Flutter Web release | PASS, konfigurasi identik baseline |
| Android APK debug lib/main.dart | PASS, konfigurasi identik baseline |
| Runtime benchmark lima portal | PASS before dan after; 0 runtime errors |
| Backend build, unit/tooling | Build PASS; **679 unit + 7 tooling PASS**, 46 unit suites |
| Backend integration | **387 PASS / 31 suite**, serial proses baru per file pada patch yang disetujui; seluruh fingerprint existing/cleanup PASS |
| Browser E2E strict akhir | **13 kelompok PASS**, nol HTTP 5xx/P2028, nol observer error/pending request; kegagalan historis tetap disimpan pada K6 |
| Safety | Kedua DB tidak berubah sepanjang validasi patch, fixture sisa nol, empat hash identik; **pengecualian Gate E historis disetujui pengguna**, sesi development tetap utuh dan belum teratribusi |

Bukti: [Flutter suite](cleanup-evidence/flutter-execution.json), [analyze before](cleanup-evidence/before-analyze.json), [analyze after](cleanup-evidence/after-analyze.json), dan validasi bertahap di folder evidence. `test/live_integration_test.dart` tidak dijalankan sebagai host unit test tanpa fixture; integrasi nyata dijalankan melalui runner guarded. Dua entry point integration_test tidak dijalankan ulang pada emulator/perangkat dalam audit ini. Hasil Android 1 tes/4 kelompok dari Final QA adalah **historis**, bukan hasil baru; build APK current sudah dijalankan. Tidak ada klaim kamera/speaker/TV/perangkat fisik terverifikasi pada audit ini.

Percobaan E2E pertama [e2e-after](cleanup-evidence/e2e-after/browser-final.json) lulus login/booking/TTS native/pairing, QR benar-benar didekode dan POST mengembalikan MENUNGGU, tetapi UI rekonsiliasi menunjukkan belum tersinkron. Percobaan kedua [e2e-after-retry](cleanup-evidence/e2e-after-retry/browser-final.json) lulus One-Scan lalu timeout menunggu POST antre-ulang; diagnostik mencatat GET snapshot/jadwal 200 dan satu GET snapshot gagal. Percobaan ketiga [e2e-final](cleanup-evidence/e2e-final/browser-final.json) menemukan kesalahan readiness check baru pada runner: kontrol halaman belakang dicari saat popup sudah terbuka; GET tercatat 200 tanpa kegagalan GET. Diperbaiki dengan membuka popup di dalam action sesudah readiness check. Semua kegagalan dipertahankan dalam evidence, bukan ditimpa atau dianggap PASS. Runner sebelumnya hanya menunggu POST; runner final juga menunggu admission gate UI sesudah rekonsiliasi dan menjaga tab headless lintas role tetap dijadwalkan. Tidak mengganti timeout/request/Queue Engine aplikasi atau melemahkan assertion. Penjadwalan browser dan race kesiapan runner adalah faktor yang ditangani; penyebab setiap GET gagal pada percobaan awal tidak dinyatakan sudah terbukti.

Tes mutasi memakai runner existing yang membentuk ulang URL lokal `127.0.0.1:5433/capstone_antrean_test`, memverifikasi current_database, port server, migration state dan target sebelum fixture dibuat. Tidak menjalankan migration/seed/reset. Fixture unik, cleanup scoped, fingerprint semua 16 tabel domain sebelum/sesudah. Database development `capstone_antrean` tidak menjadi target. Unit backend memakai URL dummy port 1.

Percobaan browser keempat [e2e-verified](cleanup-evidence/e2e-verified/browser-final.json) sudah lulus One-Scan dan keenam command, lalu berhenti pada rekonsiliasi check-in appointment; diagnostik mencatat satu snapshot HTTP 500 dan satu GET gagal. Backend dibangun ulang tanpa mengubah source. Batch integrasi satu proses kemudian menghasilkan 382/386 PASS, empat kegagalan pada `hospital-hibrida.e2e-spec.ts`, dengan kode Prisma P2028/P2039. Suite yang sama langsung dijalankan dalam proses baru dan **4/4 PASS**, tanpa mengubah timeout/transaksi. Untuk memverifikasi cakupan penuh dan membatasi akumulasi heap, seluruh 31 suite dijalankan berurutan melalui runner guarded dengan proses baru per file. Percobaan batch awal tetap disimpan di [backend-after](cleanup-evidence/backend-after/backend-execution.json), targeted di [backend-targeted](cleanup-evidence/backend-targeted/backend-hospital-hibrida-execution.json).

Regresi seluruh suite dengan proses terpisah selesai **386 PASS, 31/31 exit 0**, tanpa suite gagal. Setiap file memakai assertion, timeout Jest, transaction config dan guard DB existing. Seluruh fingerprint memuat 13 record existing dan cocok persis setelah cleanup. Bukti dan daftar 31 file hasil: [backend-isolated-summary.json](cleanup-evidence/backend-isolated-summary.json). Ini bukan klaim bahwa batch awal satu proses lulus. Penyebab lengkap error batch perlu profiling host/backend terpisah; pemisahan proses tidak mengubah behavior backend yang diuji.

Percobaan kelima setelah rebuild backend [e2e-backend-rebuilt](cleanup-evidence/e2e-backend-rebuilt/browser-execution.json) masih **FAIL**, dengan PrismaClientKnownRequestError/P2028 pada log server yang disanitasi, satu GET snapshot petugas HTTP 500, dan assertion jumlah pengumuman CALL pada display tidak meningkat sesuai harapan. Ini korelasi pada satu eksekusi, bukan pembuktian akar penyebab TTS. Enam kelompok sebelumnya lulus; tidak mengklaim semua 13 kelompok lulus dengan menggabungkan percobaan gagal. Hasil Final QA 13 kelompok PASS adalah baseline historis. Tidak mengubah backend, Queue Engine, transaction budget, timeout aplikasi, provider TTS, atau assertion untuk memaksakan PASS.

Ringkasan fingerprint seluruh eksekusi mutasi yang evidence-nya disimpan: [database-integrity-summary.json](cleanup-evidence/database-integrity-summary.json). Seluruhnya menargetkan test DB, 13 record existing tetap sama, tanpa record fixture tersisa. Tidak memeriksa/menulis data development untuk mencoba memperbaiki kegagalan.

Cakupan UI selain browser E2E: suite admin katalog/jam/kapasitas/jadwal/slot/penugasan/display; pasien Home V6/lima navigasi/booking/appointment/reservasi/tiket/QR/profil/realtime; staff keenam command/QR/global lock/session; dokter read-only/refresh/profil/session; display pairing/device/isolation/pagination/fullscreen/reconnect/privacy/TTS. Browser tidak menggantikan seluruh coverage widget/BLoC, dan tidak diklaim sebagai pengujian manual fisik.

Perubahan backend production terbatas pada dua policy read snapshot yang disetujui pada K5, dengan expected options dan regression test terkait. Tidak mengubah schema/migration, query production, kontrak API, RBAC, mutasi Queue Engine, mode poliklinik, status antrean atau auth. Dokumen acuan diperiksa: AGENTS.md, QueueB UI/UX Guidelines, API Integration Guide, Admin Stage2E, Patient Stage3, Staff Stage4, Public Display Stage5, Final E2E QA. Perubahan lokal dilindungi tidak akan ikut commit; pengukuran lokal mencakupnya dan CI belum dijalankan untuk source yang belum dikomit.

## I. Residual Technical Debt

1. Form standalone/callback fallback ADMIN tetap compatibility aktif; migrasi hanya layak bila ada manfaat terukur dan tes kontrak tambahan. Jangan menghapus QueueApi/SessionStore/PatientUpdates/RefreshGate karena namanya lama.
2. `DoctorHeaderIdentity` perlu ditinjau bersama pekerjaan visual dokter lokal; DEFER pada audit ini, hash file tetap.
3. `intl` direct constraint dan branding login terdaftar perlu keputusan terarah, bukan upgrade/hapus package massal. Font cupertino/platform adapters dipertahankan.
4. Long-session heap retention, perangkat Android fisik, kamera nyata dan suara TV/speaker masih perlu verifikasi manual. Heap CDP single-run tidak menutup risiko tersebut.
5. Artifact debug besar mencakup runtime/plugins/debug infrastructure; jangan menjanjikan pengurangan release hanya dari cleanup source. Ukuran release Android belum diukur.
6. Deadline acquisition/expiry P2028 snapshot telah direproduksi. Dua policy read disetujui dan diterapkan, tetapi run pascapatch masih dapat gagal. Profiling client/host dan korelasi socket masih diperlukan; perubahan query, pool atau budget lain belum disetujui. Kode P2039 pada suite integrasi rollback tetap disimpan dalam evidence; suite tersebut memang memuat fault injection dengan expected HTTP 500, sehingga hasilnya tidak disamakan dengan gate browser nol 5xx.

## J. Next Recommendations

Cleanup source sudah diterapkan, dengan adapter aktif dipertahankan. **Run akhir E2E penuh lulus dan pengguna telah menyetujui pengecualian historis Gate E untuk finalisasi Git.** Jangan menyimpulkan perubahan read policy menjamin semua latency host pulih. Profiling/optimasi query atau pool production lebih lanjut memerlukan scope backend tersendiri. Lanjutkan acceptance kamera/speaker/TV aktual serta sesi lama pergantian akun/perangkat setelah finalisasi. Ambil profil frame dan heap berulang di perangkat target bila ada keluhan operasional nyata. Audit go_router dapat menjadi pekerjaan terpisah setelah finalisasi; implementasinya tidak termasuk tugas ini. Tidak perlu refactor BLoC/Cubit, memindahkan setState lokal, mengganti TTS, mengecilkan tema, atau meng-upgrade toolchain/dependency untuk scope ini.

### Git dan reproduksi

Branch tetap `main`, base sebelum finalisasi **c6e64417801567188fb1495b75ec9dc9ca4dfc37**, sinkron dengan origin pada fetch terakhir (0 ahead/0 behind). Remote terverifikasi `github.com/yusranAbd/capstone-b-antrian`. Pengguna secara eksplisit menyetujui satu commit `refactor(flutter): finalisasi pembersihan kode pascamigrasi` dan push fast-forward ke `origin/main`, dengan pengecualian historis Gate E tetap dicatat. Tidak membuat branch/worktree/PR atau deployment. Stage memakai manifest file tugas eksplisit; empat perubahan lokal dan untracked lama dikecualikan. [final-review.json](cleanup-evidence/recovery/final-review.json) adalah snapshot **sebelum** pengecualian disetujui; [approval](cleanup-evidence/recovery/historical-gate-e-approval.json) dan [review finalisasi](cleanup-evidence/recovery/git-finalization/review.json) melengkapinya. Hash commit, hasil push dan CI dilaporkan setelah operasi Git aktual, tanpa menyatakan hasil yang belum terjadi dalam dokumen commit ini.

CI baseline c6e6441 tetap [run sukses historis](https://github.com/yusranAbd/capstone-b-antrian/actions/runs/40806608797). CI commit cleanup harus diperiksa setelah push; CI baseline tidak dianggap sebagai verifikasi source cleanup. Suite lokal mencakup empat perubahan pengguna yang dilindungi dan tidak dikomit; CI menguji hanya source dalam commit. Tidak mengubah readiness menjadi READY FOR DEPLOYMENT.

Perintah inventaris dari root: `node scripts/cleanup_source_metrics.cjs after`; `dart --packages=apps/client/.dart_tool/package_config.json scripts/post_migration_audit.dart after`; `node scripts/cleanup_artifact_metrics.cjs after`. Script source menolak menimpa before baseline yang sudah ada. AST tooling memakai analyzer/path/yaml yang sudah tersedia di package config dev; tidak menambah dependency runtime.

Dari `apps/client`: jalankan `node tool/final-qa.cjs benchmark|browser|unit|backend` dengan `QUEUEB_QA_EVIDENCE_DIR` menunjuk folder audit di dalam repo; browser audit memakai `QUEUEB_QA_SCREENSHOTS=0`. Semua operasi database tetap melalui guard runner; jangan menjalankan mode live dengan URL development. Perintah build dan tes penuh tercatat dalam evidence eksekusi. Tidak ada deployment.

## K. Cleanup Stabilization & E2E Recovery

### K1. Bukti P2028 dan HTTP 500

Observer **test-only**, diaktifkan melalui `QUEUEB_RECOVERY_DIAGNOSTICS=1`, mencatat request→transaction→ORM operation tanpa argumen/binding/row. Isolation, maxWait, timeout, outcome dan identitas error tidak diubah. Stack dipertahankan untuk source backend/dist; konteks invocation yang mungkin memuat nilai privat dihilangkan. Tes observer memeriksa binding, options, outcome/error identity dan sanitasi.

Pada [diagnosis-2/transactions.json](cleanup-evidence/recovery/diagnosis-2/transactions.json):

- `GET /api/v1/display/<id>/snapshot`, `DisplayService.snapshot` (`dist/display/display.service.js:36`): P2028 **“Transaction API error: Unable to start a transaction in the given time.”** Dua percobaan tercatat 2.304/2.043 ms; query callback belum dijalankan. HTTP 503. Options `RepeatableRead`, timeout 15.000 ms.
- `GET /api/v1/queue/snapshot`, `QueueService.snapshotAntrean` (`dist/queue/queue.service.js:447`): HTTP 500. P2028 **“A batch query cannot be executed on an expired transaction. The timeout for this transaction was 5000 ms, however 5235 ms passed since the start of the transaction.”** Meta `modelName=TiketAntrean`, `timeout=5000`. Wall time wrapper 5.714 ms, request 6.261 ms.
- Query yang gagal berada dalam `bacaPasienOperasional` (`dist/queue/queue-operational-snapshot.js:33`) melalui callback snapshot (`queue.service.js:607`). Urutan: pengguna.findUnique → penugasanPetugas.findFirst → batch loket/tiket/count → jadwalPraktik.findFirst → batch tiket/count operasional. Batas default 5 detik masih berlaku karena snapshot Queue hanya menentukan isolation.
- Semua error berada pada fase **browser**, bukan teardown. Callback transaksi belum selesai ketika query gagal. Tidak ditemukan bukti query fire-and-forget atau penggunaan transaction client setelah callback selesai pada jalur ini.

Pada [isolated-experiment/transactions.json](cleanup-evidence/recovery/isolated-experiment/transactions.json), error yang sama terjadi lagi pada 5.246 ms sejak transaksi dimulai; wall time termasuk akuisisi 7.027 ms. **Pemisahan proses driver tidak menghilangkan error**. Worker kemudian dipakai kembali untuk mengisolasi Playwright/video dari event loop Nest/Prisma saat evaluasi policy yang disetujui; ini bukan klaim fix mandiri. Credential hanya melalui IPC, ownership layanan tambahan di-ACK parent, dan teardown menunggu worker close. Tes IPC kini membedakan exit 1 yang diharapkan dari exit 9 akibat ACK salah.

Sampling read-only [postgres-samples.json](cleanup-evidence/recovery/isolated-experiment/postgres-samples.json): 203 sampel, maksimum 10 koneksi, maksimum dua transaksi idle bersamaan; 790 observasi idle, 35 idle-in-transaction, 9 active. Wait teramati `ClientRead`; tidak ada Lock/IO wait pada sampel tersebut. Ini membatasi hipotesis contention database, bukan membuktikan tidak pernah ada wait lain. Event-loop delay maksimum sekitar 1.050 ms pada diagnosis-2 dan 823 ms pada eksperimen terpisah. Hasil tersebut tidak cukup untuk menyatakan driver CPU atau RAM sebagai satu-satunya akar penyebab.

**Root mechanism terbukti:** acquisition deadline dan interactive transaction expiry pada read snapshot. **Penyebab latency client/host yang mendasarinya belum sepenuhnya diisolasi.** Perubahan production hanya dua policy read yang disetujui; tidak mengubah query, pool, schema, migration, RBAC atau mutasi Queue Engine untuk memaksakan PASS.

### K2. CALL/TTS dan hubungannya dengan snapshot

[isolated-experiment/browser-final.json](cleanup-evidence/recovery/isolated-experiment/browser-final.json) memuat satu eksekusi **13 kelompok UI PASS**, tetapi transaksi HTTP 500/P2028 di run yang sama membuatnya **tidak memenuhi gate strict**. Bukti CALL: REST mengembalikan DIPANGGIL versi 5; source broadcast melakukan publish sesudah commit; kedua monitor layanan terkait menerima CALL/RECALL dengan scope cocok, flag pemeriksaan pengumuman true dan event hash konsisten. Snapshot announcement menyertakan hash peristiwa. Monitor layanan lain tidak menerima event tersebut. Observer Web Speech mencatat dispatch/start/end; native activation terpisah mencatat dua start/end, tanpa error.

Dengan demikian, engine/provider TTS tidak terbukti rusak. Pengujian belum membuktikan bahwa setiap kegagalan TTS historis disebabkan HTTP 500: pada run ini error snapshot petugas terjadi sebelum CALL dan CALL/RECALL berikutnya tetap lulus. Jalur kode display memang melakukan rebase ketika snapshot gagal. Tes perilaku baru `snapshot 500 does not synthesize unverified CALL; new RECALL works after recovery` membuktikan pembacaan gagal tidak menghasilkan suara dari data belum terverifikasi, recovery senyap, dan RECALL baru tetap sekali. Tidak mengubah AnnouncementGate atau audio controller.

Focused Flutter display suite terbaru: **55 PASS**, termasuk tes baru. Full suite terbaru terukur **1.040 PASS**, menambah satu tes perilaku terhadap cleanup baseline 1.039; [flutter-gates.json](cleanup-evidence/recovery/flutter-gates.json).

### K3. Fixture, observer dan pemulihan resource

Daemon Gradle PID 20444 terverifikasi IDLE, terakhir membangun folder Android project ini. Sebelum dihentikan, private memory teramati 1.258.860.544 byte. Setelah `gradlew --stop`, satu daemon berhenti dan free physical memory teramati 932.400 KiB. **Ini kondisi host, bukan penurunan RAM aplikasi.** Run [resource-recovered](cleanup-evidence/recovery/resource-recovered/browser-execution.json) tetap gagal; menghentikan daemon belum terbukti menyelesaikan deadline snapshot.

Run tersebut berakhir tanpa fingerprint akhir dan meninggalkan fixture. Kepemilikan dipastikan read-only melalui timestamp run, pasangan kode W/QB dan dokter D dengan tag unik yang sama, serta lima akun sintetis tepat dari runner. Cleanup SQL transaksional scoped dilakukan hanya pada dua layanan, lima pengguna, satu dokter dan relasinya; tidak ada reset/seed/migration. [Bukti inspect](cleanup-evidence/recovery/fixture-recovery-inspect.json), [bukti apply](cleanup-evidence/recovery/fixture-recovery-apply.json). Sesudahnya fingerprint **seluruh test DB kembali persis ke baseline**, termasuk record existing. Development tidak menjadi target cleanup.

Callback async EventEmitter tidak otomatis ditunggu Node. Observer response sebelumnya berpotensi reject ketika context ditutup. Utility `qa-event-observers.cjs` kini menampung dan men-drain callback, mencatat error nonprivat, serta membedakan error penutupan. Regression test memastikan rejected callback tidak mematikan alur cleanup. Ini memperbaiki defect observer yang terverifikasi secara source/tes; **tidak diklaim sebagai sebab fatal run terakhir**, karena stderr lengkap run lama tidak tersedia. Runner juga menunggu handler/transaksi yang sedang berjalan sebelum teardown dan menyimpan journal ownership ID fixture di build/ tanpa credential agar pemulihan setelah process failure dapat dibuktikan.

Strict gate baru menolak semua HTTP 5xx dan P2028 yang terekam, walau assertion UI lulus. Tes memastikan 13 PASS tidak dapat menutupi HTTP 500/503 atau P2028. Tidak menambah retry POST, skip, delay agar lulus, atau mengubah expected result.

### K4. Baseline dan keamanan development

[baseline-equivalence.json](cleanup-evidence/recovery/baseline-equivalence.json) membandingkan source jalur kritis secara read-only dengan c6e6441: Queue/Display/Prisma service, broadcast, DisplayMonitorBloc, AnnouncementGate, dan audio controller identik. JS release before/after cleanup juga identik. Ini bukan klaim pristine c6 binary diuji ulang; binary baseline pengukuran memuat empat perubahan lokal dilindungi yang sama. Tidak ada bukti cleanup dead declaration memperkenalkan error transaksi atau mengubah logic TTS.

Fingerprint development berubah **hanya sesi_pengguna 124→125** selama jendela investigasi; semua tabel bisnis tetap sama. Pengguna mengonfirmasi tidak ada aktivitas login lain. [Pemeriksaan metadata read-only](cleanup-evidence/recovery/development-session-check.json) menemukan sesi USER non-fixture pada 06:34:05 UTC, sebelum E2E mutasi pertama mulai 06:40:25 UTC. Binary Web mengandung origin test 3001 dan tidak mengandung default development 3000; runner membentuk URL test eksplisit dan meng-override Prisma provider. **Sumber penulis sesi itu belum teridentifikasi.** Tidak menghapus atau mengembalikan sesi development untuk membuat fingerprint tampak sama. Observasi awal Gate Safety development tetap tidak memenuhi syarat unchanged; pengguna kemudian menyetujui pengecualian historis yang didokumentasikan, bukan menyatakan anomali telah terjelaskan.

### K5. Policy backend yang disetujui dan diterapkan

[proposed-backend-policy.patch](cleanup-evidence/recovery/proposed-backend-policy.patch) merekam usulan yang **kemudian disetujui secara eksplisit** melalui jawaban pengguna “Setujui patch read snapshot tersebut”. Tepat dua policy ini sudah diterapkan, bersama update expected options pada dua unit test dan satu regression integration test enam snapshot paralel:

| Read operation | Sebelum patch | Diterapkan setelah approval |
|---|---|---|
| Queue snapshot | RepeatableRead; default timeout 5.000 ms | Isolation sama; maxWait 3.000 ms, timeout 10.000 ms |
| Display snapshot | RepeatableRead; timeout 15.000 ms | Isolation/timeout sama; maxWait 3.000 ms |

Usulan didasarkan pada bukti transaksi 5.235/5.246 ms dan akuisisi sekitar 2,3 detik; **bukan janji mengatasi semua latency host**. Nominal maxWait+timeout 13/18 detik sebelum routing/network overhead, dibanding client 20 detik. Dampak: koneksi/transaction snapshot dapat ditahan lebih lama dan timeout/error dapat bergeser; perlu regression snapshot, load bounded, serta E2E strict tanpa 5xx/P2028. Alternatif yang lebih mendasar adalah profiling/optimasi batch query sambil mempertahankan deadline existing; itu juga memerlukan scope backend terpisah. Tidak menyetujui/menerapkan kenaikan budget secara otomatis.

Bagian 4 dan 7 instruksi stabilisasi mensyaratkan persetujuan untuk backend production/config transaksi; persetujuan tersebut telah diterima dan direkam di [backend-policy-approval.json](cleanup-evidence/recovery/backend-policy-approval.json). Tidak meminta persetujuan lagi untuk scope yang sama. Sumber sesi development yang berubah tetap ditandai belum teratribusi; record tersebut dibiarkan utuh. Fingerprint baru diambil tepat sebelum rangkaian validasi patch yang disetujui agar perubahan pada window eksekusi dapat dibandingkan tanpa menutupi histori window sebelumnya.

### K6. Gate final dan keputusan

Gate C: **1.040 Flutter PASS / 67 file**, analyze nol issue, Web release dan APK debug PASS; [flutter-gates.json](cleanup-evidence/recovery/flutter-gates.json). Android instrumentation/perangkat fisik tidak dijalankan ulang. Gate D: **679 unit + 7 tooling backend PASS**, build/typecheck/lint exit 0; [backend-static.json](cleanup-evidence/recovery/backend-static.json), [unit-execution.json](cleanup-evidence/recovery/backend-approved/unit-execution.json). **387 integration PASS / 31 proses serial**, fingerprint seluruh suite sesuai; [summary.json](cleanup-evidence/recovery/backend-approved/full/summary.json). Observer/async cleanup/IPC **8 PASS**, tanpa skip; [tooling-gates.json](cleanup-evidence/recovery/tooling-gates.json).

Evaluasi pascapatch disimpan tanpa menimpa kegagalan:

| Run | Hasil UI | Gate strict dan diagnosis |
|---|---|---|
| e2e-approved-1 | 13 kelompok PASS | FAIL: Queue timeout 10.000 ms, elapsed 10.857 ms; Display acquisition 3.987 ms; lag maksimum 3.726 ms |
| e2e-approved-isolated | 8 kelompok PASS | FAIL: Queue elapsed 13.713 ms, Display elapsed 22.839 ms, acquisition 3.017/3.007 ms; lag maksimum 3.212 ms |
| driver-diagnosis | 10 kelompok PASS | Nol HTTP 5xx/P2028; FAIL pada jumlah koneksi helper disconnect, bukan assertion refresh senyap. Snapshot maksimum 8.258 ms; pool acquisition maksimum 198 ms, waiting teramati nol; driver query maksimum 3.091 ms. Probe numerik ditambahkan untuk run berikutnya |
| socket-diagnosis (akhir) | **13 kelompok PASS** | **Nol HTTP 5xx/P2028**, nol pending/observer error. Probe: namespace 3, layanan fixture 2, perangkat target 1 koneksi aktif, tepat 1 diputus. Reconnect baru, refresh senyap, rotasi/revoke dan isolasi layanan lulus |

Driver observer memakai promise yang sama dan mengembalikan error yang sama; overload callback/stream dibiarkan utuh. SQL, parameter dan row tidak disimpan, hanya operasi/hash/query duration, backend PID dan request ID diagnostik. Sampling host terukur minimum free memory 421 MiB, interval timer maksimum 1.771 ms dan event-loop delay maksimum 1.135 ms pada driver-diagnosis. Kompresi memori Windows sekitar 1,4 GiB teramati secara read-only. Ini bukti kondisi host dan variasi latency, **bukan pembuktian tunggal penyebab CPU/RAM atau klaim optimasi RAM aplikasi**.

Run akhir: [browser-execution.json](cleanup-evidence/recovery/socket-diagnosis/browser-execution.json), [browser-final.json](cleanup-evidence/recovery/socket-diagnosis/browser-final.json), [transactions.json](cleanup-evidence/recovery/socket-diagnosis/transactions.json). Snapshot maksimum 11.545 ms berada pada jalur Display berbudget 15 detik; tidak ada transaction error. Pool acquisition maksimum 104 ms, driver query maksimum 3.038 ms, event-loop delay maksimum 932 ms, minimum free host memory 388 MiB. Variasi host tetap risiko, bukan perbaikan RAM yang diklaim. CALL/RECALL awal ter-assert, native activation dua start/end; total requested/start/end akhir monitor A=3/3/3, C=5/5/5, layanan lain=1/1/1. Tidak mengklaim seluruh CALL fase lanjut diassert pada setiap monitor; audio/perangkat fisik tetap belum diverifikasi. Helper disconnect yang gagal pada run sebelumnya belum memiliki nilai aktual tersimpan dan tidak direproduksi pada run probe; tidak mengklaim akar kegagalan helper itu telah dibuktikan atau diperbaiki.

Fingerprint kedua database dan empat hash terlindungi tidak berubah sepanjang **seluruh window validasi patch**; [final-window/safety-after.json](cleanup-evidence/recovery/final-window/safety-after.json). Test DB persis baseline awal, fixture sisa nol, semua backup/untracked lama tetap ada. Delta historis development 124→125 pada K4 tetap dicatat dan belum teratribusi. Tidak menutup masalah tersebut dengan baseline baru. Pattern scan artifact JSON/patch tidak menemukan JWT, payload QR, URL berkredensial atau email; ini bukan jaminan deteksi semua jenis secret. [Review pra-persetujuan](cleanup-evidence/recovery/final-review.json) merekam scope, hash, remote dan index kosong; review finalisasi terpisah mencatat persetujuan berikutnya. Metrik production Flutter tetap 25.854 LOC / 871.270 byte; source/AST/artifact diukur ulang setelah build terakhir. Tidak ada migrasi go_router, fitur baru atau deployment.

**Keputusan: CLEANUP VERIFIED; FINALISASI GIT DIOTORISASI.** Gate B/C/D akhir dan focused snapshot/display lulus. Pengguna menjawab **“Setujui pengecualian historis Gate E dan lanjutkan commit/push”**, setelah menerima hasil pengujian dan penjelasan anomali. Persetujuan ini membolehkan satu commit/push cleanup dengan exception tersebut tetap dicatat; bukan izin menghapus sesi atau bukti sumber sesi telah ditemukan. Risiko latency host dan transient helper tetap dicatat. Hasil commit/push/CI disampaikan setelah operasi aktual. Audit go_router dapat dilanjutkan sebagai pekerjaan terpisah; belum dimulai di sini.
