# State management ADMIN setelah Tahap 2E

Tanggal: 29 Oktober 2026. Baseline implementasi: `18e67c4` (2D).
Referensi desain: [panduan QueueB](QUEUEB_UI_UX_GUIDELINES.md).
Kontrak transport: [API Integration Guide](../backend/API_INTEGRATION_GUIDE.md).

## Ownership dan integrasi sembilan modul

Backend tetap sumber kebenaran persisten. `AdminCatalogRepository`, satu instance
per `AdminPage`, memiliki snapshot immutable katalog. Cubit menyimpan referensi
snapshot tersebut beserta status operasi; tidak memiliki cache daftar kanonis lain.
`QueueApi` existing tetap memiliki transport dan autentikasi.

| Modul | Pemilik state / transport | Hubungan dengan katalog |
|---|---|---|
| Dashboard | Proyeksi `AdminDashboard`, refresh oleh owner portal | Membaca snapshot yang sama; koleksi belum dimuat ditampilkan sebagai belum tersedia |
| Poliklinik | `PolyclinicCubit` / `AdminCatalogRepository` | Master bersama |
| Dokter | `DoctorCatalogCubit` / `AdminCatalogRepository` | Master bersama dan referensi jadwal |
| Ruang & Loket | `RoomCubit` / `AdminCatalogRepository` | Master bersama dan referensi assignment |
| Jam & Kapasitas | `ServiceScheduleCubit`, `ScheduleBatchCubit` / `AdminScheduleRepository` | Jadwal tetap berada dalam katalog bersama; batch milik dialog |
| Jadwal Praktik | `PracticeScheduleCubit` / `AdminScheduleRepository` | Snapshot jadwal yang sama untuk form dan invalidasi slot |
| Slot Konsultasi | `SlotSessionCubit` per ID praktik / `AdminSlotRepository` | Slot dimiliki Cubit sesi, referensi praktik berasal dari katalog |
| Penugasan Petugas | `StaffAccountCubit`, `AssignmentCubit` / `AdminStaffRepository` | Metadata akun dan assignment dalam katalog; password tidak disimpan |
| Manajemen Display | `DisplayManagementCubit` / `AdminDisplayRepository` | Metadata perangkat dan pilihan poliklinik memakai katalog bersama |

Dashboard tidak membutuhkan Cubit baru. Dashboard tidak mengambil seluruh slot
atau perangkat Display untuk menghitung metrik. Perangkat dimuat saat menu Display
pertama dibuka. Perpindahan kembali ke Display memakai snapshot yang telah tersedia;
tombol refresh melakukan pembacaan eksplisit. Rebuild/search/sidebar tidak mengambil
data. Refresh Dashboard tetap memakai daftar endpoint katalog existing.

Provider `.value` memakai instance milik portal. Perpindahan menu tidak menutup
Cubit bersama. Portal menutup Cubit dan melepas listener sebelum membuang katalog.
Mode standalone `AdminDisplayPage` membuat dan membersihkan owner lokal hanya bila
tidak menerima Cubit portal. Slot baru dibaca saat sesi dibuka; sesi tersembunyi
tetap mengikuti kebijakan dormant/invalidation 2C. Tidak ada socket atau polling
baru pada manajemen ADMIN.

## Refresh, lifecycle, dan mutasi

- Katalog menggabungkan path invalidasi dan menserialkan fetch. Invalidasi selama
  fetch menghasilkan trailing read; invalidasi saat trailing tetap diproses.
  Future refresh menunggu drain yang relevan, bukan hanya request pertama.
- Adapter dapat menghasilkan beberapa Future untuk drain yang sama. Semua wrapper
  error kini diamati; waiter pertama tetap menerbitkan hasil. Perbaikan fondasi ini
  diregresikan pada Display, akun, dan assignment saat burst refresh gagal.
- Identitas akun/peran dan epoch katalog mencegah respons sesi lama diterapkan.
  Logout/pergantian identitas mengosongkan snapshot; disposal mencegah emit terlambat.
  Penutupan transport tidak dipaksakan sebagai cancellation request.
- Mutasi perangkat dijaga pada Cubit dan repository. Tidak ada optimistic delete,
  retry POST otomatis, ID sintetis, atau UI side effect di repository. Setelah
  sukses/hasil tak pasti, metadata direkonsiliasi melalui REST. Kegagalan rekonsiliasi
  memblokir mutasi lanjutan hingga refresh berhasil.
- Hasil rotasi tak pasti menyimpan penanda ID perangkat, tanpa kode. GET metadata
  dan pengubahan nama tidak menghapus penanda tersebut. Rotasi pengganti memerlukan
  konfirmasi eksplisit baru; revoke/delete berhasil menyelesaikan penanda perangkat.
  Penanda mengikuti scope sesi ADMIN, bukan persistence lintas login.

## Kontrak dan informasi pairing

Repository memakai `QueueApi` yang sama: GET/POST `/perangkat-display`, PATCH `/:id`
untuk nama, DELETE `/:id/permanen`, POST `/:id/nonaktifkan`, dan POST `/:id/aktivasi`.
Create mengirim `{nama, layananId}`. Scope poliklinik perangkat tidak diubah melalui
edit nama. Pilihan poliklinik mengikuti katalog aktif, termasuk ketika referensi
berubah sewaktu form terbuka.

`DisplayManagementState` berisi snapshot, status load/mutasi, error aman, kebutuhan
rekonsiliasi, flag disclosure, dan himpunan ID rotasi tak pasti. Metadata perangkat
dibatasi field kontrak dan relasi poliklinik nonrahasia sebelum masuk katalog.
Error endpoint perangkat disanitasi juga ketika dibaca oleh rekonsiliasi modul lain.

Respons kode 12 digit dan expiry hanya menjadi `DisplayActivation` sementara yang
diteruskan ke dialog. Kode tidak masuk emitted state, field repository, log,
analytics, persistence, atau exception. Dialog membersihkan referensi kode saat
ditutup, expiry (maksimal lima menit), logout/perubahan peran, atau disposal.
Timer satu kali hanya untuk cleanup, bukan polling. Menghapus referensi String
bukan jaminan penghapusan byte memori oleh runtime.

`Aktif` tetap status administratif; registrasi bukan bukti pairing/online. Banyak
perangkat dapat memakai poli yang sama dengan ID terpisah. ADMIN tidak membaca
cookie HttpOnly dan tidak memiliki kredensial/socket kiosk. Validasi scope,
pencabutan koneksi, privasi pasien, serta otorisasi tetap wewenang backend.
Public Display, TTS, fullscreen, pagination, dan sesi perangkat tidak dimigrasikan.
Timezone pelayanan tetap `Asia/Jakarta`.

## Temuan audit dan batas arsitektur

Perbaikan terbatas 2E: daftar Display lokal dipindahkan ke shared catalog/Cubit;
cache `_data` parent yang tidak lagi diperlukan dihapus; Dashboard membedakan
koleksi belum dimuat dari nol terverifikasi; loading parent dibersihkan saat sesi
berakhir; error Future burst ditangani; referensi poli pada form Display divalidasi
ulang. Tidak ada redesign, dependency baru, perubahan API/backend/RBAC/database.

Sembilan modul memakai ownership yang sesuai tabel. Form/controller, filter,
dialog, dan status presentasi ringan tetap lokal. Adapter editor/delete standalone
serta dialog pendukung dokter (media, akun, relasi layanan) existing masih memiliki
jalur command legacy yang melakukan rekonsiliasi setelah dialog selesai. Adapter
tersebut tidak memiliki daftar kanonis portal kedua; belum seluruh command tambahan
ADMIN menjadi Cubit tersendiri. Jangan menganggap 2E sebagai penghapusan seluruh
pemanggilan API dari presentation layer.

Debt yang tetap relevan: transport belum menyediakan cancellation/idempotency key;
rekonsiliasi beberapa endpoint dapat gagal sebagai satu drain; hasil create/delete
tak pasti hanya dapat diperiksa dari metadata, bukan diputar ulang otomatis.
Guard frontend tidak menggantikan kontrol backend atau koordinasi lintas klien.

## Validasi

- Tes baru: 33 Cubit/repository Display, 13 widget Display, enam integrasi Dashboard
  dan lintas menu, dua regresi burst akun/assignment (54 total). Fixture pairing
  existing diperbarui menjadi kode dummy 12 digit dan expiry relatif.
- Cakupan: payload/endpoint, immutable/whitelist/error aman, A/B satu poli,
  double-submit, unknown rotation tanpa retry, rekonsiliasi gagal/pemulihan,
  burst/trailing completion, sesi lama/close, cleanup disclosure, CRUD/konfirmasi,
  sinkronisasi referensi, navigasi sembilan menu, dan tidak eager fetch slot.
- Seluruh **792 tes Flutter aman lulus** dalam 6 menit 5 detik (738 baseline lokal
  + 54 baru), tanpa gagal/skip dalam suite yang dijalankan. `live_integration_test.dart`
  dikecualikan; env live fixture/capture dinonaktifkan. Tidak ada mutasi database.
  Jumlah lokal mencakup satu tes dokter existing yang tidak ikut commit 2E.
  102 tes terarah lulus; sanitasi error read lintas modul juga lulus pada rerun
  33 tes Display. `flutter analyze --no-pub` bersih. Pemeriksaan format 14 file
  Dart tugas menghasilkan nol perubahan.
- Web release berhasil dalam 64,2 detik (`--no-web-resources-cdn
  --no-wasm-dry-run`); APK debug berhasil dalam 56,1 detik. Warning Java native
  access dan KGP `flutter_tts` existing tetap dicatat, tanpa upgrade tooling.
  `git diff --check` pada perubahan tugas bersih.
- Manual browser/Android, cookie HttpOnly nyata, live pairing dua monitor,
  rotasi/revoke terhadap koneksi aktif, expiry/relogin, serta RBAC lintas klien
  masih pending. Mock tidak membuktikan kontrak browser/backend live.

README dan tiga file dokter yang sudah berubah sebelum tugas dilindungi dengan
SHA-256; backup/untracked existing dipertahankan. Commit hanya memuat file 2E.
Fondasi ini siap menjadi baseline perencanaan Tahap 3; migrasi PASIEN belum dimulai.
