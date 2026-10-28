# Portal PASIEN — state management Tahap 3 terpadu

29 Oktober 2026. Baseline `e0d53af` (2E), `main` sinkron saat preflight;
[CI baseline](https://github.com/yusranAbd/capstone-b-antrian/actions/runs/40726542826)
sukses. Acuan: [UI QueueB](QUEUEB_UI_UX_GUIDELINES.md),
[API Integration Guide](../backend/API_INTEGRATION_GUIDE.md) §6.4, §11–12, §17, §24.
Home V6, lima navigasi, desain, mode layanan, serta timezone `Asia/Jakarta` dipertahankan.

## Ownership setelah 3A–3D

| Area | Owner dan tanggung jawab |
|---|---|
| Overview/katalog | `PatientRepository` memiliki satu snapshot immutable layanan, dokter, jadwal, tiket dan appointment. `PatientOverviewCubit` memproyeksikan snapshot/status read untuk Home V6. |
| Booking | `PatientBookingCubit` memiliki pilihan layanan/dokter/tanggal/sesi/slot, kalender kontekstual, availability/nearest preview dan status command. `PatientBookingRepository` adalah adapter QueueApi tanpa cache daftar kunjungan kedua. |
| Reservasi/riwayat/agenda | `PatientReservationsCubit` memakai snapshot repository yang sama dan memiliki status pembatalan. Semua kartu/proyeksi existing tetap digunakan. |
| Detail tiket | `PatientTicketCubit` per dialog membaca ID tiket sebenarnya, menerbitkan status operasi dan mereferensikan snapshot repository. Detail GET memperbarui tiket kanonis, bukan membuat tiket baru. |
| QR | `PatientQr` hanya hasil sementara ke dialog; payload tidak masuk emitted state/repository fields/persistence. Dialog memiliki countdown dan timeout cleanup sekali jalan berdasarkan expiry server. |
| Profil | `AccountProfileCubit` / `AccountProfileRepository` dipakai `UserProfilePage` lintas role. QueueApi tetap pemilik identitas, cache avatar, autentikasi dan SessionStore. Cubit hanya memproyeksikan metadata aman/status operasi dan informasi role read-only. |
| Realtime | Satu `PatientUpdates` per scope repository, dibagikan kepada seluruh konsumen termasuk detail tiket. Tidak ada socket baru per tab/dialog. |

Portal membuat repository/Cubit sekali dan mempertahankannya selama navigasi.
Cubit ditutup sebelum repository milik portal dibuang. Injection repository
eksternal di `PatientPage` mengikuti ownership pemanggil; halaman hanya menutup
Cubit/listener miliknya. Profil dibuat saat pertama dikunjungi dan dipertahankan
oleh IndexedStack existing. Cubit tiket ditutup ketika dialog selesai.

Search/controller, tab, filter tampilan, preview foto, visibility dialog, dan
posisi scroll tetap lokal. Initial/manual loading serta status command berasal
dari Cubit. Side effect konfirmasi, snackbar, dan navigasi tetap di presentation.

## Invalidasi, snapshot dan sesi

Feed membagikan himpunan jenis event yang sudah didedup/debounce. `TIKET` hanya
memuat ulang `/tiket/saya`, `/janji-temu`, dan detail yang sedang terbuka. `KATALOG`
memperbarui katalog serta referensi/slot pilihan atau nearest preview yang aktif.
Ready/reconnect/resume/fallback tetap melakukan rekonsiliasi penuh. Interval
existing 250 ms debounce, fallback foreground 30 detik, rekonsiliasi dua menit
dipertahankan; tidak ada polling kedua.

Repository menggabungkan invalidasi dalam dirty paths dan menserialkan drain.
Future refresh menunggu trailing read yang diperlukan. Detail dibaca setelah list
dalam drain yang sama agar respons list lebih lama tidak menimpa detail baru.
Metadata tiket pada appointment dinormalisasi dengan tiket kanonis sehingga agenda,
reservasi dan detail memakai status yang sama. Bila list gagal tetapi appointment
berhasil, metadata tiket yang terverifikasi dapat memperbarui proyeksi parsial;
error endpoint tetap tersedia. Kegagalan tidak diubah menjadi empty terverifikasi.

Snapshot Map/List dibekukan rekursif. Epoch dan identitas akun/peran mengabaikan
respons lama. Logout/pergantian identitas mengosongkan snapshot, menghentikan feed,
membersihkan input pribadi dan menutup QR. Provider baru mengikuti scope akun baru;
scope lama tidak diaktifkan ulang. Auth restore/refresh/storage tetap ditangani
QueueApi dan SessionStore existing, tanpa mekanisme login baru.

## Mutasi dan rekonsiliasi

- Booking mempertahankan payload POST `/reservasi` `{layananId,tanggalAntrean}`
  atau `/janji-temu` `{slotPraktikId}`. Konfirmasi memakai pilihan immutable;
  perubahan pilihan/referensi selama review membatalkan draft sebelum POST.
  Request dokter/tanggal/slot lama tidak menimpa pilihan baru. Preview bukan jaminan
  kapasitas; backend tetap memutuskan konflik, mode dan kuota.
- Hanya kanal ANTREAN_HARIAN/HIBRIDA yang menerima walk-in dan
  JANJI_TEMU_DOKTER/HIBRIDA yang menerima appointment. Poli harian, termasuk
  Bedah Umum, tetap tidak mendapat POST appointment ilegal.
- Guard mencakup POST dan rekonsiliasinya. Timeout tidak memicu POST ulang.
  Baseline daftar kunjungan harus terverifikasi sebelum POST. Booking tak pasti
  dicocokkan terhadap ID server baru untuk layanan/tanggal atau
  slot yang tepat. Bila belum terverifikasi, command berikutnya diblokir dalam
  scope tersebut; GET kosong bukan bukti POST gagal. Metadata tidak diberi ID sintetis.
- Pembatalan hanya memakai ID appointment milik sendiri dengan tiket DIPESAN,
  melalui POST `/:id/batalkan` existing setelah konfirmasi. Tidak ada penghapusan
  optimistis. Timeout mempertahankan penanda ID sampai server membuktikan status;
  penolakan/check-in tidak diklaim sebagai sukses pembatalan.
- QR memakai `/tiket/<tiket.id>/qr`, bukan appointment.id. Identitas respons dan
  expiry diperiksa. Tidak ada penerbitan otomatis pada polling, reconnect atau
  expiry. Penerbitan baru hanya dari aksi QR explicit existing. Payload dibuang
  saat tutup, expiry, perubahan status/sesi atau disposal; menghapus referensi String
  bukan jaminan penghapusan byte oleh runtime. One-Scan tetap wewenang PETUGAS.
- Profil mempertahankan endpoint/nama field existing. Avatar yang POST/DELETE-nya
  sukses tetapi reload metadata gagal ditandai partial, bukan upload gagal yang
  diputar ulang. Muat ulang profil diperlukan sebelum command berikutnya. Password
  hanya argumen sementara ke QueueApi; input dibersihkan setelah percobaan/dispose.
  Hasil password tak pasti tetap diblokir meskipun GET profil berhasil. Keberhasilan
  password memakai pencabutan sesi dan login ulang existing.

Error credential/QR dipetakan ke pesan statis yang aman, tanpa arbitrary server
text/cause. Metadata menyaring token/password/QR/hash secara rekursif. Tidak ada
HTTP client tambahan, log secret, backend/API/RBAC/Queue Engine/database/migration
yang diubah. Public Display tidak dimodifikasi.

## File dalam scope

- Integrasi: `apps/client/lib/src/patient.dart`, `patient_sync.dart`, `user_profile.dart`.
- Baru: `features/patient/data/{patient_repository,patient_booking_repository}.dart`,
  `features/patient/models/patient_models.dart`, dan empat `patient_*_cubit.dart`
  pada `features/patient/application/` (overview, booking, reservations, ticket).
- Profil bersama: `features/account/data/account_profile_repository.dart`,
  `features/account/application/account_profile_cubit.dart`.
- Helper metadata: `features/shared/safe_snapshot.dart`.
- Tes: `patient_cubit_fixture.dart`, `patient_overview_cubit_test.dart`,
  `patient_booking_cubit_test.dart`, `patient_visits_cubit_test.dart`,
  `patient_session_cubit_test.dart`, `account_profile_cubit_test.dart`.

Tidak ada dependency baru. README dan tiga file dokter existing dilindungi dengan
SHA-256; backup/untracked lama tetap dipertahankan dan tidak ikut commit.

## Pengujian dan batas

Tes baru: **3A 11**, **3B 27**, **3C 31**, **3D 25** (94 total).
Tes per fase lulus: 33 overview/Home/swipe/realtime, 62 booking/reservasi,
89 kunjungan/QR/mobile, dan 45 profil/session/lintas role. Cakupan menggunakan fake
HTTP/socket dan Completer deterministik: burst/trailing completion, stale reads,
double submit, timeout sebelum/sesudah commit, canonical ticket ID, immutability,
secret filtering, partial avatar, expiry/cleanup, pergantian akun dan navigasi.
Seluruh **886 tes Flutter aman lulus** (792 baseline lokal + 94 baru), tanpa gagal
atau skip dalam suite yang dijalankan, dalam 6 menit 2 detik. Rerun seluruh 93 tes
baru sebelum tambahan guard baseline juga lulus; BookingCubit final lulus 27 tes.
`live_integration_test.dart` dikecualikan dan env live fixture/capture dinonaktifkan.
Jumlah lokal mencakup satu tes dokter existing yang sengaja tidak ikut commit.
Pemeriksaan format 19 file Dart tugas menghasilkan nol perubahan. Analyzer final
bersih. Web release berhasil dalam **69,7 detik** (`--no-web-resources-cdn
--no-wasm-dry-run`); APK debug berhasil dalam **83,1 detik**. Warning Java native
access dan KGP `flutter_tts` existing dipertahankan tanpa upgrade tooling.
Artefak lokal berada di `apps/client/build/web` dan
`apps/client/build/app/outputs/flutter-apk/app-debug.apk`. `git diff --check` bersih.

Verifikasi manual browser/Android, QR ke pemindai PETUGAS, booking paralel lintas
klien, realtime server/reconnect, RBAC dan pencabutan sesi live masih pending.
Mock tidak membuktikan izin/transaksi backend atau kondisi jaringan nyata. Tidak
ada mutasi database maupun live integration dalam validasi lokal ini.

Debt: backend belum menyediakan idempotency key/cancellation transport; snapshot
multi-endpoint bukan transaksi database tunggal; invalidasi server best effort.
Outcome booking/cancel yang tak terverifikasi sengaja dibatasi secara konservatif,
dan penandanya mengikuti scope sesi, bukan persistence. Periksa hasil server sebelum
mengulangi tindakan melalui sesi baru. Fondasi siap untuk evaluasi Tahap 4 PETUGAS;
implementasi Tahap 4 belum dimulai.
