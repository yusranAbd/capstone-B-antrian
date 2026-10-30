# QueueB Motion System V1

## 1. Executive summary

Penerapan selektif berdasarkan panduan UI QueueB dan baseline Git `84dc84dca10a81dd7945639cce16dfd855378d26` yang sinkron dengan origin/main saat preflight. PASIEN mempertahankan pilot; PETUGAS dan ADMIN menerima animasi pada feedback existing. DOKTER dan Public Display sengaja tidak menerima efek baru. Tidak mengubah layout, palet, typography, BLoC/Cubit, repository, go_router, API, RBAC, Queue Engine, schema, transaksi atau timeout backend.

Empat perubahan historis (README, doctor_dashboard.dart, doctor_visual.dart, doctor_visual_refresh_test.dart), dokumen setup/R0, backup dan untracked lama dipertahankan. SHA-256 sebelum/sesudah dicatat di evidence lokal. Dependency dan SDK tetap: Flutter 3.47.5/Dart 3.13.4, flutter_animate 4.5.2, flutter_shaders 0.1.5, go_router 18.1.1. `responsive_framework` tetap ditunda.

## 2. Motion design principles

Motion memperjelas hasil tindakan yang sudah sah, tanpa menjadi sumber state atau perintah. Gunakan satu efek lokal, singkat, tanpa loop. Pesan/status tetap segera terlihat dan tidak bergantung pada selesainya animasi. Tidak menganimasikan seluruh daftar, data klinis, nomor panggilan TV, kamera/scanner, kode aktivasi, QR, atau pergantian halaman global. Pertahankan komponen existing dan skalanya per portal.

## 3. Token, durasi dan kurva

`lib/src/queueb_motion.dart` adalah foundation UI kecil hasil generalisasi helper pilot, bukan provider/state manager atau framework navigasi baru.

| Token QueueBMotion | Durasi | Penggunaan V1 |
| --- | ---: | --- |
| instant | 0ms | Langsung ke state akhir, tanpa Animate/controller |
| fast | 160ms | Tersedia untuk feedback lokal; belum dipakai portal |
| standard | 200ms | PASIEN, PETUGAS dan ADMIN |
| emphasis | 260ms | Tersedia; belum dipakai portal/Display |

Efek yang dipakai: fade 0,88→1 dan translasi vertikal 3→0 logical pixels secara paralel, `Curves.easeOut`, tanpa delay/loop/shader/blur/scale. Opacity awal tidak nol. Token fast/emphasis tidak berarti semua komponen boleh dianimasikan. Tidak mengubah ThemeData global.

## 4. PASIEN existing

`patient_motion.dart` mempertahankan nama/API `PatientMotionOnce`, `PatientMicroEntrance.duration` dan `minimumOpacity` sebagai kompatibilitas foundation bersama. Integrasi pada `patient.dart` tidak diubah: notice sukses Tiket Saya setelah submit sah dan label Tanggal praktik, dengan token per event/flow existing. TickerMode offstage, reduced motion, remount dan disposal tetap mengikuti pilot. Checkpoint M1: analyze bersih dan 25 tes pilot PASS setelah generalisasi.

## 5. PETUGAS

`queue.dart` membungkus hanya slot MobileNotice existing dengan `QueueBConfirmedFeedback`. Widget presentasi tersebut tetap mounted saat pesan kosong. Rising edge `command == confirmed && message != null` membuat token anonim sekali pakai. Initial hydration/remount yang sudah confirmed tampil statis. Enam command CALL, RECALL, SKIP, REQUEUE, START dan COMPLETE tetap memakai jalur BLoC/repository yang sama.

Status confirmed sudah diterbitkan BLoC setelah drain/reconciliation REST existing; motion tidak mengubah arti status. Trigger sengaja tidak memakai loading/synchronized/connection status karena nilainya berubah saat polling. Refresh existing menghapus feedback sementara; widget mempertahankan perilaku itu dan tidak memunculkan ulang pesan. Error dan hasil uncertain yang hanya terverifikasi melalui snapshot tetap memakai presentasi existing tanpa entrance sukses baru. Feedback header dari command scan yang sudah confirmed mengikuti pola umum yang sama; preview/dialog/decoder/processing guard scanner tidak dibungkus animasi dan tidak diubah.

Tidak menambah listener/BlocConsumer, socket, controller kamera, command callback, retry, busy guard atau provider. Command handler `action`, `submitQr`, room/date scope dan cleanup dialog tetap. Event baru yang datang saat branch offstage dikonsumsi secara statis agar kembali dari profil tidak memutar ulang feedback.

## 6. ADMIN

`admin.dart` memberi identitas presentasi baru pada assignment pesan sukses existing. Assignment tersebut berasal dari completion CRUD/dialog existing, termasuk create/update/delete/deactivate/save configuration yang memakai notice header bersama. Dua operasi sukses dengan teks sama tetap dibedakan; rebuild katalog tidak membuat identitas baru. Token tidak menyimpan nama/ID akun atau pasien.

Hanya AdminNotice pada header konten utama yang dibungkus QueueBMicroEntrance. Live region, SelectableText, isi pesan, validasi, konfirmasi, refresh, uncertain write/reconciliation dan owner existing tetap. Tidak memodifikasi AdminNotice secara global atau menganimasikan pesan error, form, bulk editor, slot editor, kode aktivasi/perangkat. Submodul yang memiliki feedback privat tidak dipaksa mengikuti helper. Navigasi sembilan URL dan profil tetap dari go_router. Token baru tidak dibuat bila katalog tidak aktif atau host sedang menampilkan routeChild profil.

## 7. DOKTER

Tidak menambah animasi. Host `doctor.dart` menyerahkan dashboard secara utuh; filter/status non-kritis yang relevan berada pada `doctor_dashboard.dart`/`doctor_visual.dart` yang dilindungi. Membungkus seluruh dashboard akan memengaruhi tabel klinis, sedangkan menambah banner/status baru akan mengubah struktur UI. Keduanya dihindari. Monitoring, filter tanggal, DoctorPortalCubit, profil, sesi dan logout dipertahankan; file terlindungi diverifikasi identik.

## 8. Public Display

Tidak menambah animasi. DisplayBoard menerima snapshot; keputusan event CALL/RECALL yang valid serta deduplikasi berada dalam DisplayMonitorBloc/AnnouncementGate dan jalur audio existing. Snapshot terakhir bukan identitas trigger visual yang aman: initial load, polling/reconnect/refresh/resize dapat membawa pengumuman yang sama. V1 tidak membuat gate kedua, menambah subscription, atau menghubungkan motion ke TTS hanya untuk memperoleh efek opsional.

Nomor antrean langsung dirender dengan indikator/status existing. Tidak mengubah satu DisplayPage/device scope/DisplayMonitorBloc, HttpOnly cookie/selector, multi-monitor, fullscreen, pagination, voice selection, speech queue, deduplikasi peristiwaId atau audio stop. Regresi Display existing tetap wajib lulus. Tidak mengklaim efek CALL/RECALL baru pada Display.

## 9. Reduced motion dan accessibility

`MediaQuery.disableAnimationsOf(context)` atau durasi instant menampilkan child akhir langsung tanpa Animate/controller. Preference berubah saat playback menghentikan motion; mengaktifkannya kembali tidak replay token lama. Helper tidak menghapus semantics, mengubah theme/warna/typography, atau membungkus input dengan transisi layout. AdminNotice live region existing dan MobileNotice/SelectableText tetap.

Tes mencakup fokus/input dan kedua notice pada 320×568, 360×800, 390×844, 412×915, 1280×720, 1366×768, 1440×900 dan 1920×1080, text scale 1,0 dan 1,5. Pilot mempertahankan tes kontras komposit minimal 4,5:1. Viewport ini menguji komponen terdampak, bukan klaim seluruh halaman diaudit ulang pada semua ukuran. Screen reader/perangkat fisik tetap NOT RUN/manual pending.

## 10. Event-driven lifecycle

QueueBMotionOnce hanya menyimpan consumed bool. ObjectKey memakai identitas objek presentasi, tanpa backend ID/payload QR atau data pasien. Helper mengamati TickerMode/MediaQuery, memakai controller internal flutter_animate dan disposal native library. Tidak ada timer aplikasi baru, onPlay/onComplete callback bisnis, autoplay navigation, POST, speech atau fetch dari effect/build.

Rising edge feedback PETUGAS merespons perubahan state terkonfirmasi, bukan teks/snapshot baru. Assignment sukses ADMIN adalah event UI existing; polling/repository notification biasa tidak memanggil setter sukses. Rebuild dengan token sama mempertahankan efek yang selesai; token consumed yang di-remount tampil statis. Efek dapat muncul lagi hanya untuk tindakan sah berikutnya. Route cover/unmount tidak meninggalkan controller.

## 11. State dan routing safety

Tidak mengubah file di features/*/application atau features/*/data, QueueApi, SessionStore, route policy, provider keys atau router. Foundation tidak memiliki Bloc/listener/socket/API reference. Owner create/close dan repository identity diperiksa pada tes portal; count request/POST dan feed tetap diperiksa. Session eviction/account switch/late results menggunakan mekanisme existing dan tidak boleh menjadi sukses visual baru. URL/Back/Forward tetap diregresikan.

## 12. Test coverage dan hasil

| Scope | Bukti |
| --- | --- |
| M1/pilot | 25 tes existing PASS; API kompatibilitas dan perilaku pasien tetap |
| Foundation baru | motion_system_test.dart: 23 tes token, hydration/remount, edge/rebuild, reduced motion/semantics, offstage, instant dan 16 kombinasi viewport/text-scale/fokus |
| PETUGAS baru | staff_motion_test.dart: 16 tes; enam command normal/reduced, pending POST dan REST reconciliation, satu POST, refresh tertahan antar-frame, feed/owner, conflict/uncertain, pergantian akun dan late result |
| ADMIN baru | admin_motion_test.dart: 7 tes; pending/repeated identical save, create/deactivate/delete, failure/uncertain, repository/owner/rebuild, logout pada modal pending |
| Targeted gabungan | 71 PASS (25 existing + 46 baru) |
| Regresi existing | Enam command, scanner/QR, room isolation; sembilan modul/form/bulk/slot/session/modal; DOKTER read-only/filter/profil/eviction; Display dedup/TTS/isolation/fullscreen/pagination; PASIEN dan routing |

| Gate final lokal | Hasil |
| --- | --- |
| Format tujuh file Dart terkait | PASS, tidak ada perubahan tersisa |
| Syntax/Prettier empat file JS terkait | PASS |
| Flutter analyze | PASS, tanpa issue (13,3 detik) |
| Flutter test lengkap | 1.162 PASS, 1 live-fixture SKIP pada command standar (5 menit 17 detik) |
| Web release | PASS (165,6 detik) |
| APK debug main.dart | PASS (111,6 detik); kernel memuat pilot dan foundation V1 |
| QA tooling existing | 8 PASS; mock-only observer, strict failure detection, drain, redaction dan worker ownership |

Build mengeluarkan peringatan existing Wasm/plugin dan migrasi Kotlin/native access. SDK/dependency/toolchain tidak di-upgrade untuk menyembunyikan peringatan tersebut. Backend unit/integration/destructive E2E lengkap tidak diulang lokal untuk perubahan presentasi ini.

Browser memakai runner existing `--motion-v1 --browser`: fixture unik, target test diverifikasi, context serial agar sesuai host 8 GiB. Pilot browser existing dipanggil dengan output directory khusus V1 sehingga evidence pilot lama tidak ditimpa. Scope baru mencakup enam command PETUGAS, CRUD ADMIN/sembilan URL/Back/Forward dan DOKTER read-only/profil; normal/reduced pada portal yang berubah. Display browser tidak diperluas karena tidak berubah.

Reproduksi dari `apps/client` setelah build dengan defines di §13:

```powershell
$env:QUEUEB_RECOVERY_DIAGNOSTICS = '1'
$env:QUEUEB_QA_EVIDENCE_DIR = Join-Path (Get-Location) 'build/motion-v1/browser-ledger'
node tool/run-live.cjs --motion-v1 --browser
```

Runner memvalidasi target test sebelum mutasi. Fingerprint read-only kedua database diambil terpisah sebelum/sesudah run. Harness memakai CanvasKit identik dari output build lokal untuk pemuatan engine, dengan pemeriksaan revisi sesuai flutter_bootstrap.js dan hash file yang dicocokkan ke SDK. Tidak mengganti font atau meng-intercept REST/Socket.IO/app script. Ini menghindari ketergantungan unduh engine pada smoke; tidak menyimpulkan penyebab jaringan dari timeout saja.

Browser final PASS pada tujuh context serial: PASIEN normal/reduced, PETUGAS normal/reduced, ADMIN normal/reduced dan DOKTER normal. PASIEN masing-masing satu POST booking, nol POST QR, lima tab, satu socket yang ditutup saat logout. PETUGAS masing-masing enam jenis command melalui tujuh POST (CALL kedua setelah REQUEUE), satu socket yang ditutup saat logout, profil dan Back. ADMIN masing-masing sembilan URL, Back/Forward, create/update/deactivate/delete melalui tepat empat write, profil/logout, tanpa socket. DOKTER monitoring hanya GET, kontrol tanggal tersedia, profil/Back/logout, satu socket. Filter tanggal DOKTER diregresikan pada widget suite existing; smoke tidak mengklaim perubahan tanggal melalui picker.

Semua context final memiliki nol pageerror/HTTP5xx. Screenshot PASIEN, PETUGAS dan ADMIN pada kedua mode serta DOKTER diperiksa: pesan sukses terbaca, kontrol/layout existing tetap dan teks tidak terpotong. DOKTER tertangkap saat refresh snapshot existing; tidak diberi animasi baru. Screenshot adalah pemeriksaan visual, bukan automated OCR atau screen-reader test. Lima percobaan harness awal belum lulus dan diarsipkan; hanya run final dihitung sebagai acceptance PASS.

## 13. Performance/build comparison

Preflight APK yang ada berukuran 185.567.966 byte dan tidak dipakai sebagai baseline main.dart yang terverifikasi. Baseline Web release/APK debug main.dart dibangun ulang dari implementasi pilot committed sebelum integrasi portal; draft wrapper pasien milik tugas ini disimpan/dipulihkan otomatis, tanpa menyentuh file historis. Draft foundation yang belum di-import tidak masuk dependency tree aplikasi baseline. Inventori source baseline berasal dari preflight Git sebelum penambahan helper.

Kedua sisi memakai Flutter 3.47.5/Dart 3.13.4, `API_BASE_URL=http://127.0.0.1:3001/api/v1`, `SERVICE_TIME_ZONE=Asia/Jakarta`, `--no-pub`, Web release dan APK debug entrypoint `lib/main.dart`. Empat perubahan lokal historis tetap ada pada kedua build dan tidak ikut commit. Baseline aktual dapat sedikit berbeda dari angka historis brief; tidak menganggap artefak lama otomatis sebanding.

| Artifact (byte) | Baseline aktual | V1 | Selisih |
| --- | ---: | ---: | ---: |
| Output Web release | 51.230.273 | 51.231.403 | +1.130 |
| main.dart.js | 5.511.454 | 5.512.584 | +1.130 |
| APK debug main.dart | 259.596.498 | 259.594.252 | −2.246 |

Source produksi `lib/`: 111→112 file, 26.959→27.059 baris setelah normalisasi LF; empat file produksi terdampak, +100 LOC bersih. Tes, browser harness dan dokumentasi dihitung terpisah. pubspec.yaml/lockfile byte-identik dengan preflight. APK baseline diperiksa memiliki main.dart dan pilot, tanpa import foundation V1; APK sesudah memiliki foundation tersebut. Selisih APK debug bukan bukti penghematan runtime atau ukuran library secara terpisah; ukuran terkompresi/metadata build dapat bervariasi. Ukuran Web menghitung seluruh direktori dengan metode identik pada kedua sisi.

Tidak mengklaim peningkatan FPS/RAM, zero overhead, atau hasil profiling yang tidak dijalankan. Motion tidak menambah shader/effect berat atau loop. Screenshot/evidence disimpan di luar build/web supaya tidak mencemari pengukuran output Web.

## 14. Masalah yang ditemukan, risiko dan manual verification

- Generalisasi awal memiliki benturan nama static duration API pasien dengan instance duration helper. Properti umum diganti effectDuration; API pasien tetap, M1 analyze/pilot lulus.
- Lint menemukan duplicate import, unused import tes dan kondisi tanpa braces; diperbaiki tanpa menonaktifkan lint.
- Tes awal mengasumsikan feedback PETUGAS tetap mounted setelah refresh. Source existing memang menghapus pesan; assertion disesuaikan untuk membuktikan pesan tetap hilang dan tidak replay, tanpa mengubah behavior aplikasi.
- Fixture modal awal di-unmount ketika mock write masih tertahan. Urutan tes mengikuti pola ADMIN existing: eviction, lepaskan held response, pump reconciliation, lalu disposal. Tes tetap menolak late success dan duplicate write.
- Harness browser awal membedakan API Response secara keliru: Fetch memakai properti status/ok, Playwright memakai method status()/ok(). Diperbaiki pada test helper; pemeriksaan response sukses tetap wajib. Locator profil PETUGAS diselaraskan dengan caption tombol aktual, bukan tooltip.
- Aksi DataTable ADMIN memakai pola cell/text dari runner existing karena exact accessible-name query tidak cocok pada representasi Web. Selector tetap dibatasi nama row fixture unik, hasil create diperiksa, menu dipilih eksplisit dan jumlah write tetap empat. Source tabel/aksi/validasi aplikasi tidak diubah.
- Satu run berhenti pada readiness engine sebelum login PETUGAS. Harness kemudian menyajikan asset engine lokal yang byte-identik dengan SDK/build, sesuai pola tooling existing; batas readiness dan assertion aplikasi tidak dilonggarkan. Setiap failed attempt tetap menjalankan cleanup/fingerprint dan disimpan sebagai evidence, bukan dihitung PASS.
- Engine Web lokal mengekspos SelectableText unfocused sebagai textarea disabled dengan value DOM kosong, seperti pilot. Untuk notice tersebut browser memeriksa permukaan dan screenshot, sedangkan semantics diverifikasi pada widget test. AdminNotice memiliki label/live region existing. Jangan menyamakan bukti ini dengan screen reader fisik/browser PASS.
- Manual pending: screen reader, keyboard/perangkat Android fisik, kamera/TV/speaker fisik. Tidak mengulang emulator dalam V1. Kamera/decoder tidak diberi efek baru.

Semua mutasi browser hanya pada target PostgreSQL lokal `127.0.0.1:5433/capstone_antrean_test` yang divalidasi oleh runner sebelum setup. Fixture unik dibersihkan pada success maupun failure; kode layanan tambahan didaftarkan untuk cleanup sebelum create UI. Seluruh enam run (lima failed attempt dan acceptance final) mempertahankan 13 record domain existing: nol hilang/berubah dan nol fixture tersisa. Fingerprint read-only 17 tabel pada development dan test identik sebelum/sesudah setiap run serta antar-run. Development tidak dipakai untuk mutasi/seed/reset/migration. Ledger acceptance final: HTTP5xx=0, P2028=0, pendingAtFinish=0; mode V1 menjadikan kegagalan strict ledger sebagai exit failure ketika diagnostics diaktifkan.

Bukti lokal tersimpan di `apps/client/build/motion-v1` (Git-ignored): before/after metrics, log analyze/targeted/full/tooling/Web/APK, bukti entrypoint kernel, protected-before/after, fingerprint kedua DB, browser summary/screenshot, ledger dan final-evidence.json. Raw ledger/screenshot/credential/environment/backup tidak di-stage. Tidak ada perubahan produksi backend, Prisma/schema/migration atau Queue Engine.

## 15. Panduan penggunaan berikutnya

Gunakan standard 200ms untuk feedback non-kritis yang sudah dikonfirmasi. Tempatkan token pada owner presentasi existing, bukan Cubit/provider baru. Gunakan QueueBConfirmedFeedback hanya bila confirmed benar-benar mengikuti lifecycle tindakan dan slot dipertahankan saat false; jangan memberikan bool loading/synchronized sebagai trigger. Mount pada state yang sudah confirmed sengaja statis. Untuk completion dialog eksplisit, token baru per hasil sukses sah membedakan teks identik.

Jangan memakai identity raw pasien/peristiwa sebagai key/log. Pertahankan informasi terlihat, reduced motion dan pola ownership. Reuse komponen existing, uji event boundary/pending/error/rebuild/logout/disposal dan hitung POST/listener sebelum memperluas. Fast/emphasis memerlukan alasan operasional dan tes, bukan rollout otomatis. PUBLIC DISPLAY memerlukan identitas event visual yang dapat dibuktikan independen dari TTS; sampai ada kebutuhan teruji, pertahankan baseline. responsive_framework tetap ditunda.

Git direct-to-main hanya setelah seluruh gate otomatis wajib lulus, stage file terkait secara eksplisit. Hasil commit/push dan CI SHA final dicatat pada laporan penyerahan; tidak ada deployment.
