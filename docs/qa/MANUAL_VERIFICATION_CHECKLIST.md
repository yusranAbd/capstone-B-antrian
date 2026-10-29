# QueueB — verifikasi manual akhir

Status awal seluruh item: **NOT RUN — PENDING MANUAL VERIFICATION**. Bukti otomatis dan batasnya ada di [FINAL_E2E_QA.md](FINAL_E2E_QA.md). Checklist ini tidak mengubah hasil otomatis menjadi hasil perangkat fisik.

## Gate sebelum pengujian

1. QA engineer memverifikasi koneksi aktual backend: hanya `127.0.0.1:5433/capstone_antrean_test`, `current_database() = capstone_antrean_test`. Port server Docker internal boleh 5432. Hentikan jika target ambigu. Database development `capstone_antrean` dilarang untuk mutasi QA.
2. Gunakan akun/pasien/poli/ruang/perangkat sintetis dengan penanda unik per run. Simpan registry ID fixture dan fingerprint awal secara privat. Jangan menggunakan akun atau data pasien existing.
3. Pastikan API mengikuti `docs/backend/API_INTEGRATION_GUIDE.md`, timezone `Asia/Jakarta`, tidak ada migration tertunda. Jangan seed/reset/deploy untuk memulai checklist.
4. Siapkan akun ADMIN, dua PASIEN, dua PETUGAS dengan penugasan yang tepat, DOKTER terkait, dua poli, tiga perangkat display. Credential disampaikan melalui kanal privat yang disetujui; jangan masukkan ke dokumen/bukti Git.
5. Backend dan build Web harus mengarah ke API test yang sama. Periksa URL aktual sebelum login. Untuk Android lokal, gunakan pemetaan ADB yang dibuat khusus run ini; jangan menimpa mapping existing.
6. Catat versi build/commit, OS, Chrome, Android, ukuran layar, zoom/text scaling, nama perangkat tanpa serial pribadi, serta waktu pengujian. Hasil harus PASS/FAIL/BLOCKED/NOT RUN/NOT APPLICABLE, dengan alasan dan bukti.

Pemulihan umum **R1**: logout/tutup sesi uji, tutup scanner agar kamera berhenti, nonaktifkan hanya display fixture, hapus hanya fixture yang tercatat dalam registry dalam urutan relasi yang benar, cabut hanya mapping ADB milik run, bandingkan fingerprint awal/akhir. Jangan reset/clean database, menghapus backup, mengubah existing data, atau memakai filter nama/email umum untuk cleanup. Jika fingerprint berbeda, hentikan dan investigasi sebelum run berikutnya.

Bukti umum **B1**: rekam hasil/status/count/HTTP code dan waktu; screenshot hanya setelah password, QR, activation code, token dan cookie disembunyikan. Jangan ekspor HAR mentah, request body login, QR, cookie value atau JWT. Gunakan pasien sintetis; jika perlu bukti scan, foto hasil check-in setelah panel QR ditutup.

## Prosedur dan hasil

### M01 — Android: instalasi, navigasi, lifecycle dan sesi

- **Prasyarat/perangkat/role:** APK QA dengan API test, emulator Android dan satu Android fisik; PASIEN dan PETUGAS fixture. Kamera fisik diperlukan untuk M02.
- **Langkah:** instal build QA; login PASIEN; buka kelima navigasi; ubah orientasi dan ukuran teks sistem; background/resume; tutup/buka ulang aplikasi; logout; login akun PASIEN kedua lalu PETUGAS.
- **Expected:** tidak overflow, crash, loading abadi atau data akun lama; state sesuai sesi; request lama tidak mengisi akun baru. Restore mengikuti kebijakan session store platform existing.
- **Hasil:** ______ **Level:** Android Device (tandai emulator/fisik) **Build/waktu:** ______
- **Bukti:** B1 + versi Android, hasil setiap transisi. Screenshot statis tidak membuktikan lifecycle.
- **Pemulihan:** R1; jangan clear data aplikasi pengguna existing. Gunakan instalasi/perangkat khusus QA.

### M02 — QR Android fisik: izin, atomisitas, duplikasi

- **Prasyarat/perangkat/role:** Android fisik berkamera, PETUGAS ditugaskan; tiket DIPESAN milik PASIEN fixture pada tanggal yang sah; QR sintetis hanya ditampilkan sementara pada perangkat kedua.
- **Langkah:** tolak izin kamera pertama kali; tutup scanner; izinkan melalui pengaturan; buka lagi; scan QR valid; scan QR sama dua kali cepat dan saat request pending; scan QR invalid/expired/sudah dipakai; background/resume saat scanner aktif; tutup scanner.
- **Expected:** pesan izin jelas, kamera dapat pulih; One-Scan mengirim operasi atomik existing dan menghasilkan satu tiket MENUNGGU; tidak ada duplikasi atau POST otomatis saat hasil tidak pasti; kamera berhenti saat ditutup.
- **Hasil:** ______ **Level:** Android Device fisik **Build/waktu:** ______
- **Bukti:** B1 + jumlah POST/hasil snapshot/record sebelum-sesudah, tanpa payload QR atau frame kamera.
- **Pemulihan:** R1; hentikan stream kamera dan cabut izin khusus aplikasi QA bila dibutuhkan.

### M03 — QR kamera Chrome nyata

- **Prasyarat/perangkat/role:** Chrome dengan kamera fisik, secure context/localhost, PETUGAS dan tiket fixture.
- **Langkah:** ulangi izin tolak/izinkan; scan QR dari layar kedua; pindah tab/background; ulangi scan ketika request pertama pending; putus jaringan sesudah server menerima scan, lalu pulihkan dan rekonsiliasi.
- **Expected:** satu check-in/enqueue, tanpa retry POST otomatis; hasil tidak pasti tidak dianggap sukses; kamera berhenti saat modal ditutup.
- **Hasil:** ______ **Level:** Browser E2E + kamera fisik **Versi/waktu:** ______
- **Bukti:** B1 + hasil decode dan snapshot aktual. Fake Y4M browser otomatis tidak menutup item ini.
- **Pemulihan:** R1; hentikan kamera dan pulihkan permission khusus origin QA.

### M04 — Booking dan final state lima portal

- **Prasyarat/perangkat/role:** kelima portal terbuka, poli ANTREAN_HARIAN/JANJI_TEMU_DOKTER/HIBRIDA, jadwal dan kapasitas sah; semua akun fixture.
- **Langkah:** ADMIN mengubah konfigurasi fixture dan refresh modul terkait; PASIEN mencoba kedua jalur HIBRIDA dan jalur mode tunggal; coba slot penuh/tanggal invalid; booking valid; PETUGAS scan; jalankan CALL → RECALL → SKIP → REQUEUE → CALL → START → COMPLETE; amati PASIEN/DOKTER/display setelah tiap aksi.
- **Expected:** mode harian tidak menawarkan appointment; kapasitas dan backend otoritatif; final SELESAI konsisten; dokter read-only; tidak ada tiket/command duplikat atau state palsu.
- **Hasil:** ______ **Level:** Browser E2E/Android Device (cantumkan) **Waktu:** ______
- **Bukti:** B1 + matriks status per portal, ID fixture disimpan privat, request count dan respons backend.
- **Pemulihan:** R1; jangan mengubah status langsung lewat SQL untuk mempercepat alur.

### M05 — Dua lalu tiga monitor fisik, cookie dan selector

- **Prasyarat/perangkat/role:** ADMIN; perangkat A/C poli pertama, B poli kedua; minimal dua lalu tiga layar, satu Chrome profile bersama dan profile terpisah.
- **Langkah:** pair A/B, lalu C; panggil antrean poli pertama; refresh/tab switch masing-masing; reload browser; periksa atribut cookie di DevTools tanpa menyalin value; periksa selector REST dan handshake perangkat; coba akses poli lain melalui sesi B.
- **Expected:** A/C menampilkan poli sama dengan identitas berbeda; B tidak menerima data/pengumuman A; cookie HttpOnly dan SameSite sesuai kontrak, `document.cookie` tidak membaca credential; scope lintas poli ditolak backend.
- **Hasil dua monitor:** ______ **Hasil tiga monitor:** ______ **Level:** Physical Multi-Monitor
- **Bukti:** B1 + atribut cookie saja, selector disamarkan, matrix monitor/poli dan respons negatif; foto semua layar tanpa activation code.
- **Pemulihan:** R1; putuskan hanya sesi display fixture, jangan hapus seluruh cookie profile pengguna.

### M06 — TTS, autoplay dan speaker fisik

- **Prasyarat/perangkat/role:** M05, voice Indonesia terpasang, output speaker untuk tiap layar yang benar, volume terukur; PETUGAS untuk CALL/RECALL.
- **Langkah:** buka initial snapshot tanpa gesture (harus senyap); aktifkan suara dengan klik; CALL; kirim event identik; RECALL sah setelah jeda; mute/unmute/ubah volume; manual refresh; pagination; widget resize; panggil dua nomor berurutan; reconnect ketika TTS berjalan; ganti perangkat.
- **Expected:** CALL sekali, RECALL baru tetap berbunyi; event duplikat/initial/reload/pagination tidak memutar sejarah; pengumuman tidak overlap; mute/volume bekerja; voice/autoplay gagal memiliki pesan yang sesuai dan snapshot tetap berfungsi. Dengarkan speaker nyata untuk menilai isolasi kanal FlutterTts bersama.
- **Hasil:** ______ **Level:** Physical Multi-Monitor/audio fisik **Voice/browser/OS:** ______
- **Bukti:** B1 + observer mencatat nomor/urutan/jumlah suara dan output speaker. Catatan automated controlled Web Speech bukan bukti suara terdengar.
- **Pemulihan:** R1; stop TTS, pulihkan volume dan perangkat output awal.

### M07 — Reconnect panjang dan revoke koneksi aktif

- **Prasyarat/perangkat/role:** M05, tiga koneksi Socket.IO aktif; ADMIN/PETUGAS fixture.
- **Langkah:** putus koneksi jaringan hanya A dalam durasi singkat lalu panjang (>interval heartbeat/refresh); ubah antrean ketika offline; pulihkan; rotate A saat aktif; pair ulang A; revoke A tanpa menekan refresh; amati B/C selama seluruh proses.
- **Expected:** hanya satu koneksi per context, tidak refresh storm/stale/history speech; A ditolak setelah pencabutan server, B/C tetap beroperasi; POST rotate tidak diulang otomatis jika respons hilang.
- **Hasil:** ______ **Level:** Physical Multi-Monitor/network fisik **Durasi:** ______
- **Bukti:** B1 + timeline disconnect/reconnect/ready/snapshot dan pengamatan A/B/C. Bedakan refresh REST dari pencabutan socket aktif.
- **Pemulihan:** R1; pulihkan koneksi dan pasangan fixture saja.

### M08 — Dua pasien paralel dan dua petugas paralel

- **Prasyarat/perangkat/role:** dua PASIEN, dua PETUGAS dengan ruang/penugasan fixture, slot terakhir kapasitas 1, dua browser/perangkat.
- **Langkah:** booking slot terakhir serentak; satu pasien klik dua kali; dua petugas scan QR sama serentak; lalu jalankan CALL/START/COMPLETE dari dua UI pada tiket terkait; ulangi saat satu respons sengaja hilang setelah server commit.
- **Expected:** satu pemenang kapasitas; backend menolak konflik sesuai kontrak; satu tiket/check-in; guard UI berlaku per instance; semua UI merekonsiliasi dan tidak retry mutasi tak pasti secara otomatis.
- **Hasil:** ______ **Level:** Browser E2E/Android Device dua perangkat **Waktu:** ______
- **Bukti:** B1 + status/count database/snapshot dan HTTP tiap request; jangan menyimpulkan race hanya dari urutan klik.
- **Pemulihan:** R1; selesaikan atau batalkan fixture mengikuti API, tanpa force-update SQL.

### M09 — RBAC live, logout pending dan pergantian scope

- **Prasyarat/perangkat/role:** seluruh role fixture; daftar endpoint aktual dari laporan QA; request barrier/proxy lokal yang disetujui, tidak merekam secret.
- **Langkah:** PASIEN mencoba modul ADMIN; DOKTER mencoba command; PETUGAS mencoba ruang lain; non-ADMIN mencoba rotate; display mencoba poli lain; token invalid/expired/revoked; tahan GET lalu logout/login akun berbeda; ganti ruang/dokter/perangkat dan API base hanya jika selector existing tersedia.
- **Expected:** backend menolak tanpa mutasi/data leakage; response/event context lama tidak mengisi scope baru; auth tidak dipulihkan oleh request lama; tidak ada token di URL/state/log publik.
- **Hasil:** ______ **Level:** Backend Integration + Browser E2E **Waktu:** ______
- **Bukti:** B1 + HTTP code, nama endpoint dan state akhir; jangan simpan JWT/refresh token. API-base switching UI yang tidak tersedia: NOT APPLICABLE, repository isolation diuji terpisah.
- **Pemulihan:** R1; lepaskan barrier, logout seluruh akun fixture, verifikasi tidak ada request tertahan.

### M10 — Layout, keyboard, fullscreen dan aksesibilitas

- **Prasyarat/perangkat/role:** Chrome nyata, semua portal fixture; pasien 360×800/390×844/412×915; operasional desktop/tablet; display 1280×720/1366×768/1920×1080.
- **Langkah:** navigasi seluruh modul ADMIN; lima navigasi pasien; tabel/aksi PETUGAS; monitoring dokter; display pagination/fullscreen enter-exit; keyboard Tab/Enter/Escape; zoom browser dan text scaling; rotasi Android.
- **Expected:** kontrol penting dapat dicapai, teks tidak terpotong secara menghambat, tidak ada overflow/scroll trap, fokus masuk/keluar dialog benar, fullscreen pulih, QR tidak tampil pada screenshot bukti.
- **Hasil:** ______ **Level:** Browser E2E/Android Device **Ukuran/scale:** ______
- **Bukti:** B1 + langkah interaktif dan screenshot tiap masalah. Tidak ada document overflow saja belum membuktikan seluruh layout Flutter bebas clipping.
- **Pemulihan:** R1; keluar fullscreen, pulihkan zoom/orientasi/scale awal.

## Penutupan

QA lead: ______ Engineer frontend/backend: ______ Tanggal: ______

Jumlah PASS: ____ FAIL: ____ BLOCKED: ____ NOT RUN: ____ NOT APPLICABLE: ____

Semua P0/P1 tertutup dengan regression evidence: ______

Fingerprint awal/akhir identik dan fixture tersisa 0: ______

Keputusan readiness setelah review bukti: ______. Checklist yang belum diisi tidak memberi otorisasi deployment.
