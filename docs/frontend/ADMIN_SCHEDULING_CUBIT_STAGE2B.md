# Tahap 2B — Cubit penjadwalan ADMIN

Baseline: `346b62a` pada `main` (Tahap 2A). CI baseline telah diperiksa melalui GitHub CLI dan sukses: [run 40672411769](https://github.com/yusranAbd/capstone-b-antrian/actions/runs/40672411769).

## Hasil dan batas implementasi

Jam & Kapasitas Poli dan Jadwal Praktik menggunakan Cubit untuk daftar, loading, refresh, error, CRUD, dan rekonsiliasi. Visual, sembilan menu, tabel/Aksi, dialog konfirmasi, kalender/agenda, serta payload existing dipertahankan. Filter Dari/Sampai tanggal tidak ditambahkan. Timezone tetap `Asia/Jakarta` melalui `AppConfig`; tanggal dan jam pada form tetap mengikuti konversi existing.

Tidak ada dependency baru, perubahan API/RBAC/auth, backend, Queue Engine, schema/migration, atau database. Tahap 2C tidak dikerjakan. Semua mutasi pengujian menggunakan fake HTTP.

## Audit dan arsitektur

- Sebelum migrasi, `AdminPage` memuat kedua daftar melalui adapter katalog 2A, form praktik mengirim HTTP sendiri, dan `BulkScheduleEditor` memiliki progress/hasil/error batch lokal. Helper batch existing memakai preflight semua jadwal termasuk nonaktif, POST per hari secara berurutan, lalu GET ulang saat error.
- `AdminCatalogRepository` tetap pemilik tunggal snapshot immutable selama portal terbuka. `AdminScheduleRepository` memakai repository tersebut dan `QueueApi` existing, tanpa cache daftar, HTTP client, token, socket, atau timer tambahan.
- `ServiceScheduleCubit` dan `PracticeScheduleCubit` mewarisi lifecycle `AdminCatalogCubit`/`AdminCatalogState`. Snapshot, initial loading, refreshing, error, mutation status, dan kebutuhan rekonsiliasi memakai fondasi 2A. Dua hook transport/rekonsiliasi pada base memungkinkan resource scheduling memakai adapter sendiri tanpa mengubah perilaku master.
- `ScheduleBatchCubit`/`ScheduleBatchState` memiliki status/progress/hasil per hari untuk satu dialog. Initial loading dan refresh daftar dimiliki `ServiceScheduleCubit`. State batch menyimpan `created`, `existing`, `failed`, dan `uncertain`; progress berasal dari item yang benar-benar selesai.
- Controller, pemilihan hari, date/time picker, validasi visual, dan filter agenda tetap state presentasional. Daftar praktik diambil seluruhnya seperti existing; perpindahan tampilan tanggal pada agenda memfilter snapshot yang sama secara lokal, tanpa request rentang tanggal baru.
- Pilihan pada form bulk, edit jam, dan praktik membaca katalog bersama saat ada pembaruan. Form praktik mengirim command melalui Cubit portal; fallback API hanya dipertahankan untuk pemanggil standalone existing.
- Adapter legacy, dashboard, dan revision counter membaca snapshot bersama. Perubahan snapshot menaikkan revision existing untuk slot yang sedang dibuka. Slot tetap dimuat lazily menggunakan `jadwalPraktikId`; tidak ada SlotSessionCubit atau eager fetch seluruh slot.

## Concurrency dan hasil parsial

- Dirty union/trailing refresh katalog 2A dipertahankan: invalidasi selama fetch tidak hilang dan hasil lama diikuti pembacaan terbaru. Identitas akun/role dan lifecycle guard mencegah respons scope lama diterapkan.
- CRUD menolak double-submit pada Cubit. Adapter menolak operasi berkonflik pada resource yang sedang ditulis/batch. Menutup Cubit tidak membatalkan write yang mungkin sudah diproses server; hasil terlambat tidak melakukan emit pada Cubit tertutup.
- Batch mengikuti urutan hari existing dan mempertahankan endpoint/payload per hari. Tidak ada transaksi atomik atau rollback semu. Kegagalan satu hari tidak menghapus hasil hari lain.
- Tidak ada retry otomatis POST/PATCH/DELETE. Error transport/5xx direkonsiliasi lewat REST. Jika daftar gagal direkonsiliasi, hasil per hari tetap ditampilkan dan mutasi berisiko ditolak sampai pembacaan berhasil. Rekonsiliasi juga membaca resource yang belum pernah dimuat serta resource lain yang masih belum terverifikasi sebelum membuka lock-nya.
- Dialog yang selesai tidak dapat mengirim ulang batch. Percobaan eksplisit lewat dialog baru diawali preflight REST; hari yang sudah ada, termasuk nonaktif, dilewati. Jika preflight gagal, tidak ada POST dikirim.
- Setelah batch ditutup, refresh existing dipertahankan untuk pemulihan jika rekonsiliasi akhir gagal. CRUD biasa tidak memicu GET ganda dari parent setelah rekonsiliasi Cubit.

## File

Baru:

- `apps/client/lib/src/features/admin/application/practice_schedule_cubit.dart`
- `apps/client/lib/src/features/admin/application/schedule_batch_cubit.dart`
- `apps/client/lib/src/features/admin/application/schedule_batch_state.dart`
- `apps/client/lib/src/features/admin/data/admin_schedule_repository.dart`
- `apps/client/lib/src/features/admin/models/admin_schedule_models.dart`
- `apps/client/test/admin_schedule_cubit_test.dart`
- `apps/client/test/admin_schedule_widget_test.dart`
- Laporan ini.

Dimodifikasi:

- `apps/client/lib/src/admin.dart`
- `apps/client/lib/src/admin_schedules.dart`
- `apps/client/lib/src/admin_practice_form.dart`
- `apps/client/lib/src/features/admin/application/admin_catalog_cubit.dart`

Perubahan lokal README, `doctor_dashboard.dart`, `doctor_visual.dart`, dan `doctor_visual_refresh_test.dart` dipertahankan, diverifikasi dengan SHA-256, dan tidak disertakan commit. Direktori/file untracked existing juga tidak diubah atau di-stage.

## Pengujian

49 tes baru: 42 tes Cubit/repository dan 7 widget. Cakupan meliputi initial/refresh sukses dan gagal, CRUD sukses/ditolak, konflik, hasil seluruh/parsial/gagal, respons terputus setelah commit, rekonsiliasi gagal dan pemulihan, retry eksplisit tanpa mengulang hari sukses/nonaktif, double-submit, lock batch/CRUD, trailing refresh, stale read terhadap mutasi, perubahan akun/logout, close saat fetch/write, immutability rekursif, referensi form saat terbuka, agenda/dashboard, dan slot legacy lazily. Tes payload mempertahankan tanggal pelayanan ketika waktu UTC berada pada hari sebelumnya. Regresi form existing tetap menguji date picker dan konversi waktu Jakarta.

Hasil lokal:

- Format hanya 11 file Dart dalam scope.
- Flutter analyze: bersih, termasuk pemeriksaan ulang setelah penguatan guard rekonsiliasi.
- Seluruh 628 tes regresi aman lulus (579 baseline lokal + 49 baru).
- Seluruh 49 tes scheduling dijalankan ulang dan lulus setelah penguatan guard: resource yang belum pernah dimuat juga diverifikasi, dan refresh referensi saja tidak membuka lock jadwal.
- Web release: sukses (`--no-web-resources-cdn --no-wasm-dry-run`), 75,5 detik.
- APK debug: sukses, 167,3 detik. Gradle mengeluarkan peringatan native access Java dan kompatibilitas KGP plugin `flutter_tts` untuk Flutter mendatang; tidak ada konfigurasi platform/dependency yang diubah.
- `git diff --check`: bersih untuk file tugas.

Tes `live_integration_test.dart` tidak dijalankan karena memakai fixture/backend nyata. Verifikasi manual browser, Android device, live CRUD, dan penolakan relasi pada server nyata masih pending; hasil fake API tidak diklaim sebagai verifikasi live. Jumlah lokal mencakup tes visual dokter yang sudah berubah sebelum tugas dan sengaja tidak disertakan commit.

## Tahap berikutnya

Fondasi siap digunakan Tahap 2C setelah persetujuan pengguna. Ownership slot dan presentasi lokal belum dimigrasikan. Transport existing tidak menyediakan cancellation; generation/identity guard melindungi hak apply respons. Backend tetap penentu konflik/relasi/kapasitas, termasuk unique key untuk benturan antar-ADMIN.
