# QueueB Motion System V2 — Perceptible & Purposeful

Tanggal: 31 Oktober 2026 (WIT). Timezone layanan tetap Asia/Jakarta.
Baseline source: `013a8ff065d5375d7478bf557b29043e86124d78`.

Status: **MOTION V2 PARTIALLY IMPLEMENTED**. Gate teknis implementasi aman lulus: analyze, regresi penuh, browser, Web dan APK. Monitoring DOKTER serta custom month/slot motion tetap deferred. Pengguna menyetujui pengecualian terbatas atas delta sesi baru untuk satu commit/push Motion pada 31 Oktober 2026 WIT; SHA dan hasil CI exact dilaporkan pada handoff setelah diverifikasi.

## Tujuan dan batas

V2 memperjelas respons tekan, hubungan halaman, nilai antrean yang berubah, serta hasil perintah yang sudah dikonfirmasi. V1 memakai entrance/feedback ringan; V2 memperluas token dan menambahkan transform lokal, switch nilai, highlight terbatas, dan entrance awal yang dibatasi viewport. Branding, tipografi, layout konten, callback bisnis, serta tema portal tetap.

Acuan desain adalah `QUEUEB_UI_UX_GUIDELINES.md` dan permintaan pengguna. Flutter 3.47.5/Dart 3.13.4, flutter_animate 4.5.2, go_router 18.1.1, flutter_bloc 9.1.1 tetap; tidak ada dependency baru. Bukan pekerjaan deployment atau penyelesaian backlog keamanan.

## Fondasi dan dua belas pola

`lib/src/queueb_motion.dart` tetap menjadi sumber token bersama. Curves: entering easeOutCubic, exiting easeInCubic, posisi easeInOutCubic. Tidak ada bounce/elastic global. Token instant 0, press 120, release 160, micro 180, component 260, navigation 320, realtime 280, highlight 600, display 400, stagger 40 ms. Press .985, modal .97→1, entrance Y 10 px, route X 12 px. Alias V1 tetap menunjuk token V2, tidak ada konfigurasi kedua.

| Motion | Portal | Status implementasi | Durasi normal | Test |
|---|---|---|---|---|
| Card Press | PASIEN | Kartu layanan dengan InkWell existing | 120/160 ms | Widget/browser PASS |
| Route Transition | PASIEN | Child booking, dokter, detail tiket; push/pop | 320 ms | Widget/browser PASS |
| Staggered Entrance | PASIEN | Maksimum lima layanan awal yang terlihat | 260 ms + indeks × 40 | Widget/browser PASS |
| Smart Scroll | PASIEN | Owner existing, threshold 20 px | 260 ms | Widget/browser PASS |
| Tab Transition | PASIEN | Controller native yang sama; preference terbaru | 260 ms | Widget/browser PASS |
| Queue Number | PASIEN/PETUGAS/DISPLAY | Nilai authoritative berbeda; DOKTER deferred | 280/400 ms | Widget/browser PASS untuk scope diterapkan |
| Counter Highlight | PASIEN | Total check-in aktual, termasuk koreksi turun | 280 + 600 ms | Widget/browser realtime PASS |
| Action Confirmation | PETUGAS/PASIEN/ADMIN | Feedback V1 dipertajam setelah hasil sah | 260 ms | Widget/browser PASS |
| Calendar | PASIEN | Seleksi tanggal; bulan/slot custom deferred | 180 ms | Selection widget/booking browser PASS; month/slot DEFERRED |
| Modal/Sheet | PASIEN/ADMIN | Review appointment, editor CRUD, menu sheet existing | 260 ms | Widget/browser PASS |
| List Update | PETUGAS/ADMIN | Badge status dan highlight row/cell ber-key stabil | 180 + 600 ms | Widget/browser PASS |
| Display Announcement | DISPLAY | Switch nomor + border hero pada event baru | 400 + 600 ms | Widget/browser PASS |

Durasi reduced adalah 0; state/informasi tetap ditampilkan. Baris dengan cakupan deferred bukan klaim implementasi penuh seluruh portal.

## Komponen dan lifecycle

- `queueb_interaction_motion.dart`: PressMotion hanya mengisi onHighlightChanged milik InkWell; tidak memasang onTap kedua. RouteMotion memakai animation route existing; ModalMotion berbagi clock DialogRoute native. Tidak ada controller route baru.
- `queueb_value_motion.dart`: switch scalar/record immutable, scope dan available eksplisit. AnimatedSwitcher memegang maksimum satu outgoing visual dalam layout; outgoing dikeluarkan dari semantics dan hit testing. Child terkini menentukan ukuran. Highlight controller dibuat hanya ketika nilai benar-benar berubah, berhenti saat selesai/offstage/reduced/unavailable, dan di-dispose.
- `queueb_content_motion.dart`: token once dimiliki PatientPage, key layanan stabil, maksimum lima kandidat awal. Satu pemeriksaan viewport setelah layout; card cache/offscreen langsung statis. Tidak ada listener scroll/timer sequence baru. SelectionMotion memakai child tanggal terkini, bukan snapshot slot lama.
- `queueb_motion.dart`: token, preference, once/event feedback V1 diperluas; tidak ada global animation service, provider, repository, BLoC atau Cubit baru.

AnimatedBuilder menerima child ter-cache untuk bagian yang tidak berubah per frame. Tidak ada permanent loop, API call pada lifecycle animation, local total++, extra subscription, atau RepaintBoundary baru tanpa bukti pengukuran.

## Mapping portal dan navigasi

PASIEN mendapat press layanan, bounded entrance, child route, smart scroll, tab native, switch currentlyServing/total check-in, seleksi tanggal, serta modal review. PETUGAS memakai switch nomor aktif, feedback perintah existing, badge dan highlight status row paginated. ADMIN mendapat highlight cell status dalam tabel paginated dan modal/sheet existing. DISPLAY mendapat switch nomor dan border hero. Monitoring DOKTER tetap existing karena file dilindungi; tidak ada wrapper seluruh dashboard.

go_router hanya mengganti page presentation pada tiga child route PASIEN. Route path, state.pageKey/URI key, redirect, root navigator, session owner, lima StatefulShellRoute branch dan indexedStack tetap. Root portal/Display tidak diberi transisi pasien. Back/Forward, deep link, auth eviction, same-role account switch, busy booking, serta owner identity tercakup regresi routing.

Smart scroll memakai owner/controller existing, akumulasi arah 20 px, easeInOutCubic 260 ms. Hanya input vertikal pengguna yang relevan; programmatic/horizontal/nested tak relevan diabaikan. Hidden control tidak menerima pointer/focus; perubahan tab memulihkan chrome. Tidak ada setState seluruh shell per pixel.

## State authoritative, realtime dan TTS

BLoC/Cubit/repository/socket/auth/Queue Engine/backend tidak diubah. ValueMotion membandingkan nilai presentation, bukan jumlah event yang diterima. Initial hydration, unavailable, scope baru, duplicate nilai, reconnect identik dan rebuild biasa tidak memainkan highlight baru. Koreksi turun tetap memakai angka server. Available/scope/reduced/offstage membuang outgoing stale tanpa replay saat kembali.

Serving pasien tetap hasil read model V7.1 tanpa nama pasien lain. Tidak ada +1 spekulatif. Success feedback memakai confirmation owner V1 setelah backend sukses, bukan saat POST dikirim; kegagalan mempertahankan error existing. Tidak ada retry/perintah dari animation callback.

Display hero membandingkan room, nomor, dan ID peristiwa announcement. RECALL dengan ID peristiwa baru dapat menandai hero tanpa memalsukan pergantian nomor. Nomor terbaru menjadi current segera, incoming/outgoing dibatasi; tidak ada antrean animasi panjang. Nama terbaru ditampilkan langsung. Fungsi TTS, event/command CALL/RECALL, device auth, fullscreen, monitor isolation dan socket owner tidak disentuh. Tidak ada audio callback dalam helper motion.

## Reduced Motion dan aksesibilitas

Semua helper membaca MediaQuery.disableAnimationsOf. Route/content/value motion settle ketika offstage/reduced, tidak replay hanya karena setting dikembalikan. TabController tetap satu instance; duration dibaca ulang untuk aksi berikutnya ketika preference berubah. Native TabBar/TabBarView, dialog focus trap/barrier/theme capture/Back, dan InkWell keyboard activation dipertahankan.

Native dialog fade tetap dimiliki DialogRoute; style awal reduced memakai duration 0, scale lokal memakai policy yang sama. Pergantian preference di tengah native fade tidak diklaim teruji. Content opacity 0 memakai alwaysIncludeSemantics; outgoing angka ExcludeSemantics, incoming tetap dapat diakses sejak frame pertama. Feedback konfirmasi mempertahankan opacity minimum .88 agar kontras teks existing tidak bergantung pada animasi. Tidak ada live-region announcement per frame.

Tes mencakup semantics tunggal nilai terbaru, keyboard/focus/callback tunggal, mode normal/reduced, disposal saat delay/transisi, tanggal akhir bulan, disabled date dan skala teks 2 pada 320/360/390/430/768/1366. Pembaca layar fisik, keyboard Android fisik dan speaker TV belum diuji manual.

## Gate pengujian dan koreksi yang ditemukan

Evidence lokal terisolasi: `apps/client/build/motion-v2/` (ignored, tidak masuk commit). Failed attempts dipertahankan.

| Gate | Hasil aktual sebelum QA akhir |
|---|---|
| V2.1 | analyze PASS; 149 targeted tests PASS |
| V2.2 | analyze PASS; 143 targeted tests PASS |
| V2.3 | 96 targeted tests PASS; analyze bersih |
| Regresi penuh pertama | 1.284 PASS + 1 SKIP existing |
| Live tab preference | Diagnostic FAIL direproduksi, diperbaiki; 38 targeted PASS, analyze PASS |
| Regresi penuh final | **1.285 PASS + 1 SKIP existing**, 7m50s |
| Tooling | **11 node tests PASS**, termasuk 3 profile tests; syntax enam CJS PASS |
| Build API existing | PASS; source backend tidak berubah |
| Build Web release | PASS, 177,7 detik compile; warning Wasm dependency existing, bukan build Wasm |
| Home browser | Normal/reduced PASS, enam layanan, viewport 320/360/390/430/768/1366; 0 error/console error/5xx, 0 booking/QR POST, 1 socket ditutup saat logout |
| Cross-portal browser | PASS: PASIEN ×2, PETUGAS ×2 (6 commands/mode), ADMIN ×2 (9 modules/4 CRUD writes), DOKTER read-only ×1; 0 error/5xx, existing 13 records utuh, 0 fixture residual |
| Final scope Display | Analyze PASS; 85 targeted tests PASS (normal/reduced, snapshot, announcement, isolation, multi-monitor) |
| Full regression final source | **1.285 PASS + 1 SKIP existing**, 6m22s, setelah scope fix |
| Web final source | Release PASS, 116,6 detik compile |
| Final E2E rerun | **13/13 PASS**, 14 layouts, routing 16 checks PASS, **0 5xx / 0 P2028 / 0 pending**, runtime errors 0; 255,4 detik, baseline 13 record utuh/0 residual |
| APK debug final | PASS, Gradle 182,8 detik; heap 2 GiB/workers 2; warning KGP flutter_tts/native access existing. Tidak diuji pada emulator/perangkat fisik |
| Format dan scope | 21 Dart format PASS/0 changed; 6 CJS Prettier/syntax PASS; 28 Motion paths, 30 status entries historis tetap, protected/dependency 8/8 cocok, known .env private-value scan 0 match |

Temuan yang diperbaiki: durasi switch awal nol menghilangkan outgoing pertama; gunakan initial mount statis native dengan durasi normal untuk update berikutnya. Semantics fade awal ditahan eksplisit. Tab duration yang semula menangkap preference awal sekarang membaca preference terbaru tanpa membuat controller pengganti. Fixture tes memakai MediaQuery ukuran nyata/tema portal yang benar. Completion wait V1 yang hardcoded 210 ms disesuaikan token V2; assertion single POST/success/error/ownership tetap.

Run realtime pertama FAIL pada check-in: menunggu POST One-Scan dari kamera sintetis melewati 30 detik; satu skenario awal PASS, 0 5xx/error runtime, 13 existing records utuh dan 0 fixture residual. Bukti disimpan di `realtime/summary.json` dan `realtime-browser.log`. Belum ada bukti penyebab; tidak dinyatakan regresi motion maupun berhasil. Rerun terpisah menambahkan metadata video/label boolean/host media gagal tanpa token, QR, perubahan timeout, fallback mutasi, atau pelemahan assertion. Source scanner tidak diubah.

Rerun realtime **7/7 PASS**, 0 error/5xx, maksimum 1 socket aktif per pasien, 0 automatic mutation, 0 reload, seluruh baseline test utuh/0 residual. Bukti `realtime-rerun/summary.json`; sebab timeout pertama tetap belum terbukti.

Final E2E run pertama FAIL setelah 8 kelompok PASS, pada appointment-through-complete. Strict ledger mencatat **4 P2028 dan 4 HTTP 5xx**, pending 0: tiga read snapshot berlangsung sekitar 35–42 detik (Queue timeout 10 detik, Display 15 detik) dan satu gagal memperoleh transaksi setelah sekitar 3 detik. Event-loop maksimum 2.600,5 ms; RAM minimum 435 MiB. Tidak ada bukti sleep atau sebab tunggal dari angka ini. Tidak mengubah backend, query, timeout maupun assertion. Baseline 13 record utuh, 0 residual. Evidence `final-e2e/browser-execution.json`, `browser-final.json`, `transactions.json` dan log disimpan; pengguna bersedia menutup aplikasi berat sebelum rerun terpisah.

Review scope Display kemudian menambah assertion pergantian layanan/tanggal pada widget nyata: normal FAIL sebelum fix (nomor scope sebelumnya tertahan sebagai outgoing), reduced PASS. Switch nomor sekarang menerima scope layanan/tanggal dan available yang sama dengan hero. Tidak mengubah snapshot/TTS/monitor owner. Bukti diagnostic `display-scope-before.log`; analyze dan 85 tes Display/realtime PASS sesudah fix (`display-scope-after-final.log`). Attempt sebelumnya `display-scope-after.log` memuat 30 PASS dan dua load FAIL karena dua nama file suite salah pada perintah runner; diperbaiki ke nama file existing tanpa mengubah assertion. Source terakhir kemudian lulus full regression, Web release dan final E2E rerun. Hasil sebelum fix tidak menjadi satu-satunya verifikasi source final.

Rerun final strict PASS tidak membuktikan sebab empat P2028 run awal sudah diselesaikan permanen. Policy/backend tidak berubah. Ledger akhir: RAM minimum 531 MiB, event-loop maksimum 238,9 ms, dibanding run awal 435 MiB/2.600,5 ms. Ini observasi dua run, bukan bukti kausalitas RAM. Seluruh failed attempts tetap disimpan.

## Browser, build dan profiling

Fresh compiled release app diuji dengan fresh headless Playwright di `http://127.0.0.1:8080`, guarded API `127.0.0.1:3001/api/v1`, PostgreSQL test `127.0.0.1:5433/capstone_antrean_test`; tidak mengendalikan existing Chrome. Tidak ada seed/reset/migration. Fixture unik didaftarkan sebelum dibuat dan dibersihkan oleh harness existing. Home, lintas portal, realtime rerun dan final-E2E rerun PASS: masing-masing 13 existing domain records utuh dan 0 fixture tersisa. Web release dan APK debug final PASS; APK memakai konfigurasi localhost QA, bukan artefak deployment.

Profiling opt-in `QUEUEB_MOTION_PROFILE=1` memakai 1.200 ms requestAnimationFrame dengan fallback terbatas 2.200 ms dan LongTask observer. Action existing dijalankan tepat sekali. Sample hanya menyimpan interval/durasi/visibility; tanpa DOM, token atau nama pasien. Origin divalidasi sebelum aksi. Ini metrik scheduling browser pada host pengujian, termasuk host/API wait; bukan Flutter UI/raster timing, bukan bukti 60 FPS perangkat. Sample kosong menghasilkan null, bukan angka FPS buatan. Sample setelah commit/konfirmasi dapat melewatkan onset animasi; tidak diklaim seluruh frame setiap transisi ditangkap. Tidak ada baseline V1 terkontrol dengan metode sama untuk klaim peningkatan.

Home: idle normal p95 17 ms, scroll normal p95 17 ms (0 interval >25 ms); card+route normal p95 16,9 ms, maksimum 133,2 ms (2 interval >25 ms; long tasks 136/94 ms). Reduced card+route juga memiliki spike: maksimum 166,6 ms, long tasks 171/123 ms. Karena spike muncul saat motion dimatikan juga dan sampling meliputi navigasi/data/host scheduling, penyebab belum dapat diatribusikan ke animasi. Ini belum memenuhi klaim setiap frame ≤16,7 ms. Tidak ada penambahan RepaintBoundary atau perubahan state owner berdasarkan dugaan.

PETUGAS: sampling awal setelah login (bukan idle yang sudah disettle terpisah) p95 normal 83,3 ms dan reduced 83,1 ms. Dua CALL normal p95 33,4/50 ms, reduced 49,8/33,3 ms. Ada jank aktual dalam run normal dan reduced; tidak diklaim target 60 Hz terpenuhi atau V2 memperbaiki seluruh beban Web. Perlu Flutter UI/raster timeline dan baseline V1 terkontrol untuk atribusi; tidak ada bukti yang cukup untuk menyalahkan state management atau satu efek motion dari angka rAF ini. DISPLAY pada run awal: idle p95 16,8 ms dan CALL setelah commit 16,9 ms, maksimum 19,1 ms, tanpa interval >25 ms; run tersebut tetap FAIL di strict backend gate kemudian, sehingga angka ini hanya measurement fase yang sempat berjalan.

Sample final source: realtime check-in pasien p95 16,8 ms, maksimum 16,9 ms; Display idle p95 17,1 ms dan CALL setelah commit 17 ms, maksimum 17,1 ms; masing-masing 0 interval >25 ms/0 long task. Seluruh 15 sample tersimpan di `profile-summary.json`, semua foreground/visible dengan action PASS. Ringkasan menyimpan p95 per sample, bukan rata-rata p95 atau pooled percentile. Render/rebuild counter dan Flutter raster timeline belum diukur; cached child/lifecycle dinilai melalui source dan widget tests, bukan dianggap bukti FPS.

Screenshot lokal (fixture test): `apps/client/build/motion-v2/home/browser-after/home-{normal,reduced}-{320,360,390,430,768,1366}.png`, serta `hidden-normal.png`/`hidden-reduced.png`. Tampilan 320 dan 1366 telah diperiksa visual: konten/kartu/navigation tetap terbaca dan di dalam viewport. Raw screenshot dan profiling JSON tetap ignored, bukan credential/data development.

Evidence portal di `portals/`: staff normal/reduced, admin normal/reduced, doctor unchanged, dan patient pilot. Pemeriksaan visual staff/admin/doctor mempertahankan geometri serta typography existing. `realtime-rerun/two-check-ins.png` memperlihatkan nilai authoritative dari dua check-in. Screenshot layout final E2E tersedia untuk pasien 360/390/412/1280, staff 390/768/1366, doctor 390/1366, admin 768/1366, Display 1280/1366/1920. Screenshot layout bukan bukti semua frame motion atau physical screen-reader/audio berhasil.

[Screenshot Display setelah CALL, fixture test lokal](../../apps/client/build/motion-v2/final-e2e-rerun/display-called-motion.png) telah diperiksa: nomor terbaru dan tujuan terbaca, nama tetap mengikuti mode SAMAR server. Evidence final/routing/ledger berada di `final-e2e-rerun/`; ini artefak lokal ignored, bukan file yang dipublikasikan melalui Git.

### Reproduksi QA

Dari `apps/client`, dependency/engine bundled existing dan API dist dibangun terlebih dahulu. Gunakan environment evidence di bawah `build/motion-v2/<run-unik>` untuk mempertahankan failed attempts. `QUEUEB_RECOVERY_DIAGNOSTICS=1` mengaktifkan strict ledger existing, dan `QUEUEB_MOTION_PROFILE=1` mengaktifkan sampling di harness frontend; keduanya bukan pengaturan aplikasi produksi.

```powershell
flutter analyze --no-pub
flutter test --no-pub --concurrency=2 --reporter expanded
flutter build web --release --target lib/main.dart --no-pub --dart-define=API_BASE_URL=http://127.0.0.1:3001/api/v1 --dart-define=SERVICE_TIME_ZONE=Asia/Jakarta
node --test tool/motion-profile.test.cjs tool/qa-event-observers.test.cjs tool/browser-qa-worker.test.cjs tool/recovery-observer.test.cjs
# Set QUEUEB_QA_EVIDENCE_DIR, QUEUEB_HOME_V7_EVIDENCE_DIR,
# QUEUEB_MOTION_EVIDENCE_DIR, QUEUEB_REALTIME_EVIDENCE_DIR per run.
node tool/run-live.cjs --patient-home-v7 --browser-only
node tool/run-live.cjs --motion-v1 --browser
node tool/run-live.cjs --patient-queue-v7-1 --browser-only
node tool/final-qa.cjs browser
# Jalankan APK terpisah dari Chrome/full regression pada host RAM 8 GiB.
flutter build apk --debug --target lib/main.dart --no-pub --dart-define=API_BASE_URL=http://127.0.0.1:3001/api/v1 --dart-define=SERVICE_TIME_ZONE=Asia/Jakarta
```

Flag/nama `motion-v1` adalah harness regresi existing yang dipakai ulang terhadap Web **V2** freshly compiled, bukan klaim aplikasi masih V1. Tidak ada stub REST/socket; kamera Y4M dan Web Speech merupakan input terkontrol. Profiling tidak mengubah jumlah mutasi existing. Listener/request observer dibersihkan pada akhir run. Windows host warning pg concurrent-query deprecation tercatat dari tooling existing; dependency/backend tidak diubah untuk warning tersebut.

## Integritas workspace, database dan Git

Enam protected file dan dua pubspec di-hash sebelum implementasi dan dibandingkan kembali: **8/8 cocok**. Tiga puluh status entries historis di luar 28 path Motion tidak berubah. Perubahan lama, backup, untracked historis dan secret tidak dimasukkan. Tidak ada perubahan backend/schema/dependency/auth/TTS source.

Baseline read-only 17 tabel × dua database dicatat sebelum edit. Pemeriksaan sementara: seluruh tabel bisnis development dan semua tabel test identik; fingerprint sesi development berbeda dengan jumlah tetap 176. Metadata menunjukkan refresh sesi PASIEN sekitar 31 Oktober 02:06:31 WIT. Pengguna menjawab **tidak ada aktivitas yang diketahui**; delta baru tetap **UNATTRIBUTED**, bukan tercakup pengecualian tiga sesi historis. Runner browser Motion belum dijalankan pada pemeriksaan ini. Sesi tidak diubah/dihapus oleh pekerjaan ini. Tiga sesi audit historis tetap UNATTRIBUTED, historicalStrict=FAIL; CI bukan penyelesaian audit tersebut.

Audit penutup membandingkan **34 fingerprint** sejak sebelum browser hingga sesudah seluruh browser: **semuanya identik**, termasuk sesi development. Dibanding baseline awal tugas, hanya fingerprint tabel sesi development berbeda, count tetap 176; **33/34 fingerprint awal lainnya cocok**. Dengan agregat ini tidak dapat disimpulkan hanya satu kolom/row yang berubah. Metadata expiry menjadi indikasi refresh, bukan atribusi pelaku. Runner browser telah dikunci ke test, dan selisih awal sudah ditemukan sebelum browser Motion dijalankan. Tidak ada reset/pencabutan sesi atau perubahan histori audit.

Syarat acceptance pengguna adalah database development tidak berubah; syarat Git adalah semua gate wajib lulus sebelum commit/push. Delta baru semula menahan Git walaupun gate teknis Motion PASS. Pada 31 Oktober 2026 WIT, setelah laporan dan 28 file siap direview, pengguna menjawab: **"Setujui pengecualian delta sesi baru dan lanjutkan commit/push"**. Persetujuan ini terbatas untuk satu commit 28 path Motion dan push fast-forward ke main; delta tetap UNATTRIBUTED, bukan dianggap terselesaikan atau tercakup pengecualian tiga sesi historis. Risiko sesi, kegagalan run awal dan jank tetap dicatat. Tidak ada reset/pencabutan sesi, perubahan historicalStrict=FAIL, force push, branch/worktree/PR atau deployment. Hasil SHA/CI exact disampaikan dalam handoff setelah operasi Git benar-benar dilakukan.

## File berubah

Production: `queueb_motion.dart`, tiga helper `queueb_{interaction,value,content}_motion.dart`; `patient.dart`, `patient_home_v6.dart`, `patient_home_v7.dart`, `patient_scroll_shell.dart`, `routing/app_router.dart`, `doctor_schedule_ui.dart`, `queue.dart`, `staff_v4.dart`, `admin.dart`, `admin_ui.dart`, `display_board.dart` (semua di `apps/client/lib/src`).

Tests: tiga `motion_v2_*_test.dart`; penyesuaian token/wait `motion_system_test.dart`, `patient_motion_test.dart`, `staff_motion_test.dart`. Tooling frontend: `motion-profile.cjs` dan test; integrasi opt-in pada `browser-patient-home-v7.cjs`, `browser-motion-v1.cjs`, `browser-patient-queue-v7-1.cjs`, `browser-final-e2e.cjs`. Dokumentasi: file ini. Raw evidence, fingerprint DB dan credential tidak di-stage.

## Deferred dan batas verifikasi

1. Motion monitoring DOKTER: memerlukan file doctor_dashboard/doctor_visual yang dilindungi. Existing monitoring hanya diregresi, bukan dinyatakan V2.
2. Custom month-slide/slot-crossfade: native month UI dipertahankan; tidak menahan outgoing slot yang dapat dibaca/diaktifkan sebagai tanggal baru. V2 kalender hanya selection pulse/warna tanggal di komponen pasien yang aman.
3. Stagger ADMIN dan press row PETUGAS tidak dipaksakan: tabel bukan kartu navigasi dan row dengan menu aksi tidak diubah menjadi satu target klik baru.
4. Tidak ada pengukuran profile Android fisik/TV, Flutter raster timeline atau pembaca layar fisik. APK compile tidak berarti device E2E. Batas host RAM 8 GiB mengharuskan QA berat serial.
5. Native transisi kalender/dialog yang tidak diganti tetap mengikuti perilaku Flutter existing; tidak diklaim seluruh animasi legacy sudah dimigrasikan.
6. Jank PETUGAS dan spike navigasi Web masih terukur, termasuk dalam reduced mode. Belum ada baseline V1 terkontrol/raster timeline untuk menentukan sebab atau menjamin 60 FPS. Kegagalan kamera pertama dan empat P2028 pertama tetap bagian dari laporan, walaupun rerun lulus.
7. Delta sesi development baru tetap UNATTRIBUTED dan diterima sebagai pengecualian eksplisit untuk satu commit/push Motion; audit historis tiga sesi/historicalStrict=FAIL tetap utuh. Persetujuan Git bukan atribusi pelaku atau penyelesaian risiko sesi.

Pola yang ditunda tetap ditandai deferred meskipun gate implementasi aman lulus.
