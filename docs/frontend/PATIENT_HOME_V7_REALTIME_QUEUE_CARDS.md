# Patient Home V7 / V7.1 — kontrak, integrasi realtime dan quality assurance

## V7.1 — integrasi yang diotorisasi 30 Oktober 2026

**Status implementasi: V7.1 REALTIME VERIFIED — seluruh gate lokal PASS.** Commit/push dan CI diperiksa pada SHA commit ini setelah publikasi Git dan dicatat dalam laporan eksekusi akhir. Bagian bernomor V7 di bawah tetap menjadi catatan historis audit/fallback sebelum otorisasi backend; blocker kontrak tersebut telah ditangani oleh implementasi V7.1 ini.

### Sumber data dan kontrak final

| Data | Sumber existing | Definisi dan penyelesaian gap |
|---|---|---|
| Total check-in | tiket_antrean.checkInPada | Count row tiket pada layananId/tanggalAntrean, timestamp tidak null. PK unik, tanpa join. Selesai tetap dihitung; reservasi DIPESAN tidak. GET agregat baru mengatasi gap akses USER. |
| Menunggu | status MENUNGGU + checkInPada + urutanMasukAntrean | Mengikuti selector antrean persisted, bukan pengurangan total dengan nomor pelayanan. CHECK_IN belum enqueue dan DIPANGGIL tidak ikut. |
| Pelayanan aktif | DILAYANI + loket aktif | START telah berhasil. CALL/RECALL/last-called bukan currently-serving. Banyak loket menjadi collection; relasi loket-layanan tidak cocok diabaikan. |
| Scope | ID layanan dari katalog | Pendaftaran/Apotek mempunyai layananId sendiri; nama tampil bukan primary key. Ruang terikat layanan. Hari menggunakan tanggalAntrean, tidak bergantung timezone browser. |
| Hari | waktuPelayanan / konfigurasi Asia/Jakarta | Tanggal kalender strict, default server, GET/join/event/UI memakai scope yang sama. |
| Realtime | interceptor pascakomit + gateway /patient existing | Subscription layanan/tanggal tervalidasi dan invalidation ANTREAN baru. Hasil transaksi dan payload privat tidak disiarkan. |

Endpoint final **GET /api/v1/layanan/antrean?layananId=<csv>&tanggal=YYYY-MM-DD**, JWT/session **USER** existing, no-store. DTO versiSkema:1, tanggalPelayanan, diperolehPada dan layanan[] dengan layananId, totalCheckIn, jumlahMenunggu, sedangDilayani[]. Item pelayanan berisi loketId/kodeLoket/nomorAntrean. Lihat [kontrak lengkap](../backend/API_INTEGRATION_GUIDE.md). Query SELECT-only RepeatableRead memakai sumber persisted; tidak ada schema/migration atau perubahan Queue Engine.

### Pascakomit, scope dan privacy

Interceptor hanya menerbitkan notifikasi setelah handler mutasi berhasil selesai. Queue Engine/check-in tetap menjalankan transaksi, lock, idempotency dan aturan existing. Scope notifikasi dibaca dari tiket hasil command yang telah tersimpan. CALL/RECALL/SKIP/REQUEUE/START/COMPLETE memicu GET ulang tanpa menambah count. Rollback tidak melalui success handler. Kegagalan emit tidak mengubah hasil command, dan tidak diikuti retry POST.

Socket `/patient` existing menerima **patient:antrean:ikuti** `{layananIds, tanggalPelayanan}`. Server memvalidasi USER/session aktif, UUID unik (maksimum 100), hari kalender dan layanan aktif sebelum mengganti room. ACK canonical menjadi bukti subscription, scope lama dilepas, request join beruntun diserialisasi. Disconnect membersihkan room. Setiap emit memvalidasi ulang sesi aktif.

Event **patient:updated** membawa `{versiSkema:1,eventId,jenis:'ANTREAN',terjadiPada,layananId,tanggalPelayanan}`. Tidak ada nama/ID pasien, ID tiket, NIK, raw QR, JWT atau token Display. Event bukan sumber angka. Delivery best effort tanpa outbox; GET awal/reconnect dan reconcile berkala memulihkan event yang hilang. Kind privat TIKET tetap hanya pemilik; namespace staff tidak dibuka.

### Owner frontend dan binding V7

PatientRepository existing memiliki satu immutable queueState untuk semua card. PatientOverviewCubit mengekspos listenable tersebut; tidak dibuat repository/Cubit/socket per card. PatientUpdates tetap satu koneksi dan debounce bersama. KATALOG/scope mengonfigurasi identitas layanan di luar build; ANTREAN-only memperbarui listenable card tanpa notify seluruh PatientPage atau invalidasi booking.

GET memakai batch ID, serialized single-flight dan trailing refresh. Scope epoch, account identity dan request revision mencegah late response menimpa hasil baru. Jika event tiba selama GET, hasil lama dibuang dan union ID dibaca ulang. Event duplicate/foreign scope ditolak. Tidak ada `total++` atau mutasi saat render/tap card.

Initial load membaca GET tanpa menunggu event. ACK subscription/reconnect memicu reconciliation; offline/background menghapus status Live. Loading/error awal tidak menjadi nol. Data lama dipertahankan dengan **Data terakhir** setelah gangguan; Live hanya untuk subscription terkonfirmasi, hari cocok, data berumur maksimal 3 menit, tanpa request/error tertunda. Rekonsiliasi existing 2 menit; pemeriksaan pergantian hari memakai timer feed existing. Logout/account switch membuang snapshot dan listener serta menolak late response.

Desain V7 lokal dipertahankan: personal AppBar, smart scroll, search, nearest visit, booking/QR/profile, lima branch pasien dan portal lain. Urutan V7.1 memprioritaskan **Pendaftaran lalu Apotek**, sisanya stable mengikuti katalog; alias hanya bila kode utama tidak ada. Nomor Antreanmu tetap tiket milik akun dari endpoint privat. Highlight memakai nomor pelayanan aktif (collection per loket jika perlu), tanpa nama pasien. Collection kosong ditulis **Belum ada pelayanan aktif** agar tidak menyatakan CALL sudah dilayani. Total hari ini dan X menunggu memakai agregat sah, placeholder jujur bila tidak tersedia. Tidak ada animasi angka baru, dependency/aset generatif, tombol internal atau navigasi baru.

### Hasil QA V7.1 lokal

- Analyze Flutter bersih; 74 tes terarah PASS (DTO, burst/single-flight, late response, account/date/service switch, reconnect, zero/null/error, 24 kombinasi viewport/text scale, identitas widget Home tetap, ordering dan regresi V7/feed).
- Backend typecheck/build PASS; targeted unit 23 PASS. SQL integration awal 21 PASS diperluas menjadi 22 kasus dan disertakan dalam regresi penuh 409 PASS dengan cleanup/baseline utuh.
- Web release main.dart PASS dengan API test port 3001/Asia/Jakarta. Peringatan Wasm dry-run dependency existing dicatat; bukan bukti dukungan Wasm.
- Backend unit penuh: **689 PASS / 47 suite**, tooling data **7 PASS**, tooling QA client **8 PASS**. Lint backend bersih setelah menghapus spread array yang tidak diperlukan pada iterasi room; typecheck/build PASS.
- Integrasi backend penuh: **409 PASS / 32 suite**, termasuk 22 kasus read-model/realtime baru. Target tervalidasi 127.0.0.1:5433/capstone_antrean_test, 13 record baseline utuh dan cleanup nol residual. Suite existing mencakup fault injection rollback dengan HTTP 500 yang memang diharapkan; diagnostic P2039 pada log integrasi tidak disamakan dengan gate browser operasional tanpa 5xx. Tidak ada P2028 pada ringkasan integrasi.
- Browser realtime A–G **PASS** pada compiled Web + Nest/PostgreSQL/Socket.IO asli: tiga konteks USER independen, satu sesi PETUGAS. GET awal dan tiket personal berbeda; scan QR kamera terkontrol membuat total 0→1 pada A/B melalui event + GET tanpa reload; repeated scan tetap 1; CALL bukan pelayanan aktif, START menampilkan nomor A tanpa menimpa nomor pribadi B; Apotek tetap 0. A offline saat satu check-in kedua melalui REST One-Scan asli memakai sesi petugas yang sama; B menjadi 2, A tetap data terakhir 1, lalu reconnect/ACK/GET memulihkan 2. Logout menutup socket akun A; login akun lain tidak membawa tiket A.
- Run browser akhir: HTTP 5xx **0**, P2028 **0**, pending **0**, automatic booking/QR/check-in POST dari masing-masing pasien **0**, maksimum socket aktif setiap konteks **1**. A membuka 3 transport sepanjang reconnect/logout/login (bukan tiga socket bersamaan). Cleanup mempertahankan 13 record existing dan menyisakan **0** record fixture. UI C mengikuti layanan Home yang sama melalui feed bersama; card Apotek tetap terisolasi. Isolasi room subscription layanan/tanggal yang berbeda diuji terpisah dalam SQL/Socket.IO integration.
- Visual browser V7 **normal/reduced-motion PASS**: initial GET 0 yang sah, serving kosong, smart scroll turun/naik, programmatic/small scroll diabaikan, card Apotek menuju flow existing tanpa POST, avatar/profile, tab, logout. Setiap mode: 1 socket dibuat/ditutup, error console/runtime/5xx dan booking/QR POST **0**. Ledger browser visual bersih (P2028/5xx/pending 0), baseline 13 record utuh dan residual 0.
- Web release, APK debug, fingerprint akhir dan enam hash file terlindungi PASS. Bukti lokal apps/client/build/v7-1 (ignored) memuat log sukses/gagal, screenshot, ledger, manifest build dan audit integritas. Git/CI diverifikasi terpisah pada SHA commit akhir; evidence runtime dan rahasia tidak di-stage.

#### Failure history harness (tidak dihapus)

Empat run awal browser tidak dinyatakan PASS: (1) setelah account switch harness mencari Home sementara shell mempertahankan branch Profil; diperbaiki dengan menekan tab Beranda; (2) mengganti file kamera simulasi menghasilkan timeout sebelum POST kedua; (3) upaya mengganti browser kamera tidak bisa memindahkan session Web yang memang hanya disimpan di memori; pendekatan tersebut dibuang; (4) assertion membaca atribut DOM aria-label yang null pada semantics Flutter, diperbaiki dengan matcher accessible-name. Run akhir tetap menguji scan dan scan ulang melalui kamera UI; perubahan pada skenario offline memakai satu request One-Scan REST sah dari sesi petugas existing. Tidak ada stub respons API/socket, retry mutasi otomatis, perubahan auth atau timeout produksi untuk melewati kegagalan ini. Summary/log/ledger keempat kegagalan disimpan terpisah; masing-masing cleanup nol fixture residual dan tidak ada 5xx/P2028. Seluruh skenario A–G diulang pada run akhir yang lulus.

Regresi Flutter penuh pertama menghasilkan 1.230 PASS, 1 SKIP dan 1 FAIL: FakePatientSocket pada tes existing belum menyediakan emitWithAck ketika reconnect mencoba join scope baru. Fake dilengkapi ACK penolakan eksplisit; tidak mengubah assertion existing atau perilaku produksi. Tes ACK/session/feed/queue terarah sesudah perbaikan: **49 PASS**. Regresi penuh ulang dengan concurrency 2 untuk membatasi RAM: **1.231 PASS, 1 SKIP**, analyze bersih. Skip existing tidak dihapus atau dijadikan PASS; log run gagal tetap disimpan.

Run pertama regresi browser 13 kelompok berhenti setelah 8 PASS pada appointment-through-complete dan gagal strict gate karena **2 P2028** bacaan Display, meskipun HTTP 5xx 0/pending 0. Event Windows System membuktikan host masuk sleep (Kernel-Power 42, **Button or Lid**) 18.39 WIT dan wake 18.50 WIT (**Power Button**); clock meloncat 633.178 ms, sesuai event-loop stall maksimum 633.507,676 ms pada ledger. Sleep UTC 09:39:49.788 → wake 09:50:27.142 melewati watchdog browser. Cleanup tetap mempertahankan 13 record baseline dan nol fixture residual. Log/ledger/report gagal serta diagnosis daya disimpan terpisah. Suite diulang pada host aktif tanpa perubahan kode produksi, timeout, query atau pelemahan strict gate: **13/13 PASS**, 14 layout tanpa overflow, routing **PASS**, HTTP 5xx **0**, P2028 **0**, pending **0**, 13 record baseline utuh dan fixture residual **0** (270,8 detik). PASS ulang tidak menghapus kegagalan sleep sebelumnya.

### Integritas database dan aktivitas development eksternal

Baseline 17 tabel pada masing-masing database dicatat sebelum implementasi. Setelah regresi backend, database test identik. Pada development, sesi_pengguna bertambah **142→144** dan satu sesi USER lama dicabut. Pengguna mengonfirmasi **“Ada aktivitas login development”** selama task: metadata menunjukkan logout USER 17.36.44 WIT, login ADMIN 17.37.07, logout ADMIN 17.38.03, lalu login USER 17.38.19 pada akun USER yang sama. Tidak ada nama/token/QR yang dipublikasikan.

Perbandingan read-only merekonstruksi hanya field dicabut_pada pada tepat satu sesi lama di memori dan memisahkan tepat dua ID sesi baru yang fingerprint-nya telah dicatat. Hash 142 row sesi baseline kemudian cocok **persis**, termasuk seluruh kolom lain. Seluruh 16 tabel development lain dan seluruh 17 tabel test cocok baseline tanpa pengecualian. Ini membuktikan delta teratribusi pada aktivitas pengguna, bukan alasan menghapus sesi atau mengabaikan hash tabel. Sesi aktual tetap utuh; tidak ada UPDATE/DELETE development. Fingerprint awal yang mendeteksi delta, metadata teredaksi, hasil perbandingan dan konfirmasi pengguna dipertahankan dalam evidence lokal. Verifikasi akhir setelah ketiga rangkaian browser menghasilkan kecocokan yang sama; seluruh fixture test dibersihkan.

### Batas teknis yang tetap berlaku

Tidak ada durable event delivery/monotonic snapshot version baru. Single-flight/generation dan reconciliation membatasi stale application di klien; event yang benar-benar hilang dipulihkan lewat GET. Fixture sintetis dan kamera video terkontrol tidak membuktikan kamera Android fisik, performa perangkat rendah, atau FPS produksi. Tidak ada deploy publik.

### Build dan metrik V7.1

Web release dan APK debug dibangun dari **lib/main.dart**, Flutter **3.47.5**, Dart **3.13.4**, API_BASE_URL=http://127.0.0.1:3001/api/v1 dan SERVICE_TIME_ZONE=Asia/Jakarta. Dependency tetap. Verifikasi kernel APK menemukan main.dart, patient_home_v7.dart, patient_scroll_shell.dart, patient_queue_models.dart dan patient:antrean:ikuti; integration_test/live_backend_test.dart tidak menjadi entrypoint. APK SHA-256: `f1120879138836cc170c40c148718a32ad06f2d014b36b03904b48b54fab1aac`.

| Metrik | V7 lokal tervalidasi | V7.1 | Delta |
|---|---:|---:|---:|
| Source Dart lib | 116 file / 27.687 baris | 117 file / 28.164 baris | +1 file / +477 baris |
| Web seluruh artifact | 51.241.934 byte | 51.251.211 byte | +9.277 byte |
| main.dart.js | 5.522.835 byte | 5.532.112 byte | +9.277 byte |
| APK debug | 259.612.388 byte | 259.631.477 byte | +19.089 byte |

Baseline memakai manifest after.json V7 fallback yang flag/entrypoint-nya telah diverifikasi. Artifact cache awal 185.567.966 byte tidak dipakai sebagai pembanding karena flag build-nya belum terbukti. Metrik ini merupakan ukuran artifact/source, tanpa klaim peningkatan FPS. Build Web mengeluarkan warning Wasm dry-run dari dependency existing; APK mengeluarkan warning toolchain native-access/KGP flutter_tts existing, dan keduanya selesai sukses tanpa mengubah dependency. ADB tersedia tetapi tidak ada perangkat/emulator terhubung saat pemeriksaan; uji kamera Android fisik/kemampuan perangkat tetap manual.

### Audit Git dan cakupan akhir

Preflight dan pemeriksaan ulang remote: main/HEAD/origin/main pada 15ec32f, divergensi 0/0. Cakupan akhir **25 file**: perubahan V7 lokal yang memang diminta, read-model/controller/module, gateway/interceptor, integrasi repository/feed/Cubit/card, tes relevan, harness browser dan dua dokumen kontrak/laporan. Stage dilakukan berdasarkan daftar path eksplisit. Tidak ada branch/worktree/PR baru, stage global, reset/clean atau force push.

Enam fingerprint file/dokumen terlindungi cocok sebelum Git; empat perubahan historis tracked serta backup, apps/web, dokumen setup/audit dan untracked lama dipertahankan di luar commit. pubspec.yaml/lock dan package backend tidak berubah. Tidak ada perubahan implementasi Queue Engine/check-in/auth/JWT/QR, RBAC existing, Prisma schema/migration, timezone, atau UI portal lain. Direct-to-main commit berbahasa Indonesia dan push fast-forward hanya diizinkan setelah gate lokal di atas; status CI akhir harus mengacu ke exact SHA yang dilaporkan pada hasil eksekusi, bukan CI baseline V7.

---

## Arsip V7 — audit sebelum otorisasi backend

Tanggal: 30 Oktober 2026 (Asia/Jayapura). Baseline aktual `15ec32f37964967ef81bbdf89096caa236e5d9d0`, `main` sama dengan origin/main saat preflight. Acuan: permintaan V7 Live Queue Cards, gambar **Pastel Healthcare Queue Dashboard**, [panduan UI QueueB](QUEUEB_UI_UX_GUIDELINES.md) dan [kontrak API](../backend/API_INTEGRATION_GUIDE.md).

## 1. Executive summary

**Status fitur utama: V7 BLOCKED BY BACKEND CONTRACT.** Visual dan fallback diimplementasikan, tetapi total check-in realtime, nomor pelayanan global, serta jumlah menunggu belum dapat dihubungkan secara sah untuk role USER. Keterbatasan ini bukan alasan menampilkan angka reservasi sebagai total check-in atau menghitung event di klien.

AppBar personal, urutan Pendaftaran, satu aksi per kartu dan smart scroll dari V7 sebelumnya dipertahankan. Perubahan baru hanya pada kartu, tes, pemeriksaan fallback browser dan dokumen ini. Tidak ada perubahan backend, API, RBAC, Queue Engine, Prisma, auth atau subscription. Sesuai kebijakan data gap dalam permintaan, perubahan tidak di-stage/commit/push sebagai implementasi final.

## 2. Desain final yang dapat diterapkan

Kartu existing tetap putih, radius 20, border/shadow lembut, ikon/kategori, chevron, geometri transparan dan dua kolom. Highlight kecil **Sedang dilayani / Belum tersedia** sekarang berada langsung di bawah nomor pribadi, dengan tint kategori, padding 8×5 dan ikon Material. Tidak ada nama orang lain, indikator +1, tombol internal, Live palsu, animasi berulang, dependency, gambar atau timer tambahan.

Label kiri konsisten **Nomor Antreanmu**, dengan nomor sah atau `— / Belum ada tiket`. Tooltip tanpa tiket menjelaskan ketiadaan tiket milik pengguna, bukan nomor panggilan global. Semantics satu aksi menjelaskan ketidaktersediaan serving, total check-in dan menunggu. Seluruh highlight tetap bagian dari InkWell kartu, tanpa nested handler.

## 3. Service ordering

Stable move PENDAFTARAN pada hasil filter Ambil Antrean tetap menggunakan kode katalog, dengan alias REGISTRASI/ADMINISTRASI bila kode utama tidak ada. Urutan relatif item lain dan input katalog tidak berubah. Tidak membuat layanan atau memindahkan poliklinik ke Ambil Antrean. Eligibility V6 dan mode Janji Temu tetap.

## 4. Nomor Antreanmu

Sumber: `GET /tiket/saya`, melalui PatientRepository → PatientSnapshot → PatientOverviewCubit → callback Home existing. `homeServiceTicket` memeriksa identitas login, ID/nomor tiket tidak kosong, layanan, tanggal pelayanan (`Asia/Jakarta`) dan status aktif. penggunaId harus cocok bila disediakan; bila tidak, ownership berasal dari endpoint terautentikasi yang memang hanya mengembalikan tiket akun tersebut. Status terminal/tanggal/layanan/owner lain tidak dipakai.

Repository memegang identitas saat dibuat, mengosongkan snapshot dan menutup feed ketika sesi berubah. Tidak ada cache tiket baru dalam kartu. Nomor global dari field bebas katalog tidak akan menjadi nomor pribadi.

## 5. Currently serving

Kontrak USER saat ini tidak memasok antrean layanan yang sedang dilayani. `GET /queue/snapshot` adalah dashboard PETUGAS berdasarkan loket/penugasan; tiket aktif dapat berstatus DIPANGGIL **atau** DILAYANI. Itu bukan endpoint pasien, dan status DIPANGGIL tidak otomatis berarti pelayanan telah dimulai. `GET /display/:layananId/snapshot` memakai capability token perangkat Display, bukan JWT pasien. Token tersebut tidak diambil atau dipasang di Portal PASIEN.

Highlight memakai **Belum tersedia** karena ketiadaan sumber tidak membuktikan bahwa tidak ada panggilan. Tidak mengambil lastCalled, tiket terbesar, tiket pribadi lain, nama pasien, atau respons One-Scan petugas. Bila kelak tersedia kontrak sah, definisi DILAYANI/START dan beberapa loket perlu ditangani eksplisit, bukan memilih nomor tertinggi.

## 6. Definisi Total Hari Ini

Definisi yang diminta: jumlah tiket unik yang sudah berhasil check-in pada layanan dan tanggal pelayanan tersebut. Reservasi DIPESAN saja tidak cukup. CALL/RECALL/SKIP/REQUEUE/START/COMPLETE bukan check-in baru. Repeated scan/retry harus tetap satu tiket yang sama.

Data dasar backend memang ada: CheckInService mengubah DIPESAN → CHECK_IN dengan update bersyarat `checkInPada: null`, menetapkan timestamp dan audit CHECK_IN dalam transaksi yang sama. AutoCheckInService menyatukan check-in dan ENQUEUE dalam transaksi, serta mengenali sudahTerdaftar. Namun, belum ada read-model agregat check-in yang diizinkan untuk USER. Kartu tetap menampilkan **Total hari ini — / Belum tersedia**, bukan nol atau total reservasi.

## 7. Source event check-in existing

Sumber aktual yang diperiksa:

| Komponen                           | Kontrak/perilaku aktual                                                                                | Implikasi                                                                   |
| ---------------------------------- | ------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------- |
| CheckInController / CheckInService | POST `/check-in`, role PETUGAS, hasil tiket/checkInPada setelah commit                                 | Command petugas, bukan read-model total pasien                              |
| AutoCheckInService                 | POST `/check-in/auto-antrean`, role PETUGAS; setelah commit mengirim ENQUEUE jika belum terdaftar      | Event ENQUEUE bukan penambahan angka lokal                                  |
| PatientInvalidationInterceptor     | Sukses queue/check-in mencari penggunaId pemilik tiket lalu invalidate TIKET hanya ke pemilik tersebut | Pasien lain tidak menerima invalidasi check-in layanan itu                  |
| PatientRealtimeGateway             | `/patient`, JWT USER + sesi aktif; `patient:ready`, `patient:updated`                                  | Payload updated hanya versiSkema, eventId, jenis TIKET/KATALOG, terjadiPada |
| RealtimeEvents                     | queue:updated beraksi ENQUEUE/CALL/RECALL/SKIP/REQUEUE/START/COMPLETE                                  | Kanal queue terotorisasi operasional, bukan feed agregat USER               |

Tidak ada field total check-in, nomor serving, layananId atau tanggal pelayanan dalam PatientInvalidation yang dapat diperlakukan sebagai snapshot agregat. Tidak membuat event baru atau menafsirkan jumlah event sebagai jumlah pasien.

## 8. Realtime architecture dan matriks ketersediaan

Arsitektur pasien tetap menggunakan invalidation → GET authoritative, bukan event payload sebagai UI state. PatientRepository hanya memuat `/layanan`, `/dokter`, `/jadwal-praktik`, `/tiket/saya`, `/janji-temu` dan detail tiket yang sedang dibuka. LayananService.findAll mengembalikan katalog aktif berurutan kode, tanpa query agregat antrean.

| Field           | Source existing                                                  | Available untuk USER                     | Real-time                                                 | Fallback                           |
| --------------- | ---------------------------------------------------------------- | ---------------------------------------- | --------------------------------------------------------- | ---------------------------------- |
| Nomor Antreanmu | `/tiket/saya` dan detail tiket milik akun; repository existing   | Ya, bila tiket cocok                     | Invalidation TIKET pemilik + reconciliation REST existing | `— / Belum ada tiket`              |
| Sedang dilayani | Tiket aktif snapshot PETUGAS; snapshot token perangkat Display   | Tidak, tidak ada kontrak pasien yang sah | Belum dapat diverifikasi pada card USER                   | `Sedang dilayani / Belum tersedia` |
| Total check-in  | Timestamp checkInPada/audit CHECK_IN persisten, internal backend | Tidak ada read-model agregat USER        | BLOCKED                                                   | `— / Belum tersedia`               |
| Jumlah menunggu | menunggu.total pada snapshot operasional/Display                 | Tidak melalui API USER                   | BLOCKED                                                   | `Belum tersedia`                   |

Ketersediaan di tabel adalah akses untuk **Portal PASIEN**, bukan klaim bahwa data dasar tidak ada di database atau portal petugas.

## 9. Socket ownership

Tetap satu PatientUpdates per PatientRepository portal, dipakai overview dan detail. Tidak ada socket/repository/subscription per kartu/layanan, global BLoC tambahan, polling kartu, atau request baru dari build/scroll/animasi. Card tidak mempunyai sumber state realtime kedua.

## 10. Refresh, reconnect dan deduplikasi

Mekanisme existing: PatientUpdates memvalidasi versiSkema/jenis/eventId, menduplikasi eventId, debounce invalidasi, reconnect dan invalidasi setelah ready/resume. Fallback berkala 30 detik dan reconciliation 2 menit tetap milik satu feed. PatientRepository memakai drain single-flight/trailing dirty paths dan epoch/session guard sehingga hasil sesi lama tidak masuk snapshot akun baru.

Hal itu memverifikasi lifecycle **tiket pribadi**, bukan counter global. Tanpa endpoint dan invalidasi global yang sah, reconnect hanya membaca ulang koleksi yang sudah ada, tidak memulihkan angka 42/43/44 yang tidak disediakan server. Tidak mengubah mekanisme tersebut untuk menutupi data gap.

## 11. Fallback, loading, error dan offline

Serving, total, dan menunggu tetap tidak tersedia ketika data tidak dipasok, baik socket terhubung, offline, loading, maupun error. Tidak mempertahankan angka agregat palsu atau memberi Live hanya karena socket pribadi terhubung. Loading/error overview existing tetap; profil dan tiket pribadi tetap mengikuti state sebelumnya. Tidak menambah status Buka/Tutup atau memperkirakan antrean dari selisih nomor.

## 12. Privacy dan security

Referensi visual memuat nama pasien lain, tetapi instruksi privacy teks secara eksplisit melarangnya. Implementasi mengikuti batas tersebut: hanya nomor tiket pribadi yang sah, tanpa nama/identitas pasien lain pada highlight. Field bebas currentlyServing/lastCalled/namaPasien/NIK/telepon pada katalog tidak dipetakan. Tidak mengakses API petugas dengan JWT pasien, menyalin token Display, mengubah permissions atau membuka room queue.

## 13. Personalized AppBar

Komponen PatientHomeAppBarV7 dari baseline dipertahankan: nama QueueApi.user aktif dengan fallback, bell/dialog keterbatasan notifikasi tanpa badge palsu, AccountAvatar existing dan `/patient/profile`. Tidak mengimplementasikan ulang, menambah request profil, atau mengubah halaman Profil. Logout/account switch tetap menghapus identitas lama melalui ownership sesi existing.

## 14. Smart scroll

PatientScrollShell, trusted Web input bridge, hysteresis 12px, animasi 220ms, reduced motion langsung, reset tab/pageKey, pelepasan ruang dan IgnorePointer/ExcludeFocus/ExcludeSemantics tetap dari baseline. Tidak ada perubahan router atau lima branch. Regresi scroll/horizontal/programmatic/reduced dan owner/read akan dijalankan kembali; tidak mengklaim peningkatan FPS tanpa profiling.

## 15. Tests

Evidence baru: `apps/client/build/home-v7-realtime/` (Git-ignored). Hasil di bawah adalah run aktual untuk fallback; counter global tetap terblokir.

| Gate                                                                 | Status                                                                                                                                        |
| -------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| Widget/unit kartu, privacy, matrix responsive, scroll, overview/feed | 64 PASS pada layout final                                                                                                                     |
| Backend check-in/auto-check-in/patient invalidation existing         | 47 PASS, 3 suite; bukan bukti counter USER                                                                                                    |
| Format/analyze                                                       | PASS, no issues                                                                                                                               |
| Full Flutter                                                         | 1.196 PASS, 1 live-fixture SKIP pada suite standar                                                                                            |
| Web release main.dart                                                | PASS, JavaScript release                                                                                                                      |
| APK debug main.dart                                                  | PASS, kernel main.dart/Home V7/scroll shell/fallback baru; bukan integration entrypoint                                                       |
| Tooling observer/worker                                              | 8 PASS, syntax harness PASS                                                                                                                   |
| Browser actual Web normal/reduced                                    | FALLBACK_PASS dua context 390×844, Pendaftaran dan Apotek, Back/avatar/tab/bell/logout, scroll turun/naik, jump DOM programatis dan gerak 2px |
| Browser error dan lifecycle                                          | 0 pageerror/console error/HTTP5xx/POST booking atau QR; tiap context 1 socket dibuat/1 ditutup                                                |
| Backend strict ledger                                                | 0 5xx/P2028/pending saat finish                                                                                                               |
| Database setelah browser                                             | 13 record existing test utuh, 0 fixture tersisa; count/hash 17 tabel × 2 DB identik dengan preflight                                          |
| Protected/dependency                                                 | 6 SHA-256 identik, pubspec.yaml/lock byte-identical; tidak ada stage/commit/push                                                              |

Tes visual menambahkan pemeriksaan highlight tepat di bawah nomor, dua kolom tidak bertabrakan, area highlight satu aksi kartu, serta penolakan nilai/nama/NIK/telepon tidak terkontrak. Matriks lebar 320/360/390/430/768/1366 dan text scaling 1/1.3/1.5/2 tetap. Tidak membuat mock counter lalu menyebutnya bukti integrasi.

Capture actual diperiksa pada [normal](../../apps/client/build/home-v7-realtime/browser-after/home-normal.png), [scroll turun](../../apps/client/build/home-v7-realtime/browser-after/hidden-normal.png), serta mode reduced di direktori evidence yang sama. Semua nama/layanan adalah fixture test. Evidence V7 sebelumnya tidak ditimpa; output baru dibatasi di bawah client/build. Summary browser sengaja berstatus FALLBACK_PASS dengan checkInCounter BLOCKED. Reconnect counter live tidak diklaim lulus dari fake feed.

Seluruh 15 skenario counter (42→43, duplikat, 44, gagal, repeated scan, reconnect/replay, out-of-order, layanan/tanggal lain, concurrent staff, logout, reload, aksi selain check-in, loading/offline/error) berstatus **BLOCKED untuk fitur baru**, karena endpoint/read-model serta invalidasi USER layanan belum ada. Tes lifecycle feed existing tidak menggantikan skenario tersebut. Live check-in E2E tidak dijalankan untuk mengklaim fitur yang belum dapat dibaca pasien; smoke fallback memakai fixture test terisolasi dengan cleanup.

## 16. Build metrics

| Artefak                                       |    Baseline |     Sesudah | Delta bytes |
| --------------------------------------------- | ----------: | ----------: | ----------: |
| Web total                                     |  51.241.106 |  51.241.934 |        +828 |
| main.dart.js                                  |   5.522.203 |   5.522.835 |        +632 |
| APK debug, baseline V7 historis terverifikasi | 259.612.664 | 259.612.388 |        -276 |

Web baseline dicatat saat preflight. APK pembanding berasal dari manifest build V7 sebelumnya pada SHA 15ec32f, dengan entrypoint main.dart yang terverifikasi. File APK cache yang ditemukan saat preflight berukuran 185.567.966 bytes dan SHA-256 berbeda dari manifest tersebut; provenance/build flags cache itu tidak terverifikasi, sehingga tidak dipakai untuk mengatribusikan delta APK ke perubahan UI. Tidak menganggap selisih cache sekitar 74 MB sebagai pertumbuhan akibat highlight. Artefak baru berisi tiga ABI arm64-v8a/armeabi-v7a/x86_64 dan kernel fallback aktual.

Build memakai Flutter 3.47.5/Dart 3.13.4 yang diperiksa dari metadata SDK lokal, lib/main.dart, API_BASE_URL http://127.0.0.1:3001/api/v1 dan SERVICE_TIME_ZONE Asia/Jakarta. Tidak ada dependency baru. Web mengeluarkan warning Wasm dry-run dari plugin TTS/socket existing; target yang dibangun adalah JavaScript release. APK tetap berhasil dengan warning native access Java dan KGP flutter_tts existing. Tidak meng-upgrade plugin pada tugas ini. Ukuran build dan delta historis bukan benchmark FPS, startup atau RAM, dan bukan bukti peningkatan performa.

## 17. Data gap dan kebutuhan backend yang memerlukan persetujuan

Usulan kontrak berikut **belum diimplementasikan dan bukan daftar endpoint/event existing**:

1. Read-model khusus USER untuk layanan aktif dan tanggal pelayanan, berisi agregat total tiket unik check-in, jumlah menunggu menurut definisi Queue Engine, serta daftar nomor berstatus DILAYANI per loket. Tidak ada nama pasien, userId, NIK, rekam medis, telepon, QR/token atau diagnosis. Bila perlu menampilkan panggilan DIPANGGIL, pisahkan label/semantiknya dari DILAYANI.
2. Total dihitung server dari bukti check-in sah, dengan unit tiket unik dan scope layanan/tanggal Asia/Jakarta. Jangan menghitung reservasi, last number, status menunggu saja, atau jumlah event. Unit tiket/pasien dan perilaku pembatalan setelah check-in perlu disepakati eksplisit dalam kontrak.
3. Snapshot konsisten dengan metadata tanggal, waktu perolehan dan revision/watermark yang sesuai untuk menolak snapshot usang. Versi per tiket tidak dapat langsung menjadi versi agregat layanan. Tentukan cara beberapa loket ditampilkan tanpa memilih nomor tertinggi.
4. Invalidasi pascacommit ke konsumen USER yang berhak membaca agregat layanan, memakai namespace pasien existing jika disetujui. Check-in (manual dan auto), perubahan serving/menunggu dan reconnect harus memicu refresh authoritative. Invalidasi hanya ke pemilik tiket saat ini belum cukup untuk pasien lain. Payload tidak perlu membawa identitas atau counter increment.
5. Client kelak memakai satu owner existing: single-flight batched refresh, generation/session guards dan reconciliation; nol local total++, socket per card, atau retry POST check-in. Live hanya setelah snapshot scope/freshness terverifikasi dan dimatikan saat koneksi/status read tidak memenuhi jaminan kontrak.

Data checkInPada sudah persisten; audit ini tidak membuktikan perlunya migration Prisma. Yang belum ada adalah kontrak baca dan notifikasi yang aman bagi pasien. Perubahan backend/API tetap memerlukan persetujuan tersendiri; tidak dilakukan diam-diam dan tidak membuka endpoint PETUGAS/Display untuk USER.

## 18. Final readiness dan Git

Status utama tetap **V7 BLOCKED BY BACKEND CONTRACT**, meskipun fallback visual dapat lulus QA. Jangan menyatakan V7 REALTIME VERIFIED AND PUSHED. Tidak ada stage, commit, push, branch/worktree/PR atau deployment untuk perubahan baru ini selama gate kontrak counter terblokir. HEAD baseline dan CI V7 sebelumnya bukan bukti counter baru sudah lulus.

File scope: `apps/client/lib/src/patient_home_v7.dart`, `apps/client/test/patient_home_v7_test.dart`, `apps/client/tool/browser-patient-home-v7.cjs`, dokumen ini. README, tiga file dokter historis, dokumen setup/R0, backup dan untracked lama dipertahankan; SHA-256 enam file/dokumen dan pubspec/lock sudah dibandingkan dan identik. Database development hanya dibaca untuk aggregate fingerprint; seluruh fixture smoke terbatas pada PostgreSQL lokal `127.0.0.1:5433/capstone_antrean_test` dengan target guard dan cleanup ID run.

Manual QA setelah kontrak dan implementasi lengkap: TalkBack/VoiceOver, Safari/iOS, perangkat Android fisik/Back, jaringan buruk, pergantian hari pelayanan, multi-loket dan dua petugas konkuren. APK build dan fake streams tidak disamakan dengan verifikasi counter realtime atau pengujian perangkat fisik.
