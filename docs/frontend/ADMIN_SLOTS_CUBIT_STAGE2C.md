# Tahap 2C — Slot Konsultasi ADMIN

## A. Implementation Summary

Slot Konsultasi memakai `SlotSessionCubit` untuk snapshot, lazy load, refresh, invalidasi, error, mutasi, dan rekonsiliasi. `AdminSlotSession` dipertahankan sebagai adapter presentasi; widget tersebut hanya menyimpan ekspansi panel, bukan data/fetch/error kanonis.

Audit baseline `9c073c4` mengonfirmasi bahwa `load()` pada widget lama memakai `if (loading) return`; invalidasi di tengah request dapat hilang. Selain itu form/aksi slot mengirim HTTP dari presentation layer. Seluruh jalur portal tersebut kini masuk ke Cubit/repository.

Perilaku existing dipertahankan: sembilan menu, grup poli/dokter/sesi, tabel, pagination, filter status/search, Aksi, form tambah/edit, date/time picker, konfirmasi Nonaktifkan/Hapus Permanen, serta label loading/error. Filter Dari/Sampai tanggal tidak ditambahkan. Tidak ada generate/bulk/booking baru.

## B. Architecture

- `AdminSlotRepository` menerima `AdminCatalogRepository` existing; transport memakai `catalog.api`/`QueueApi` existing. Tidak ada HTTP client, autentikasi, socket, atau katalog baru.
- GET tetap `/slot-praktik?jadwalPraktikId=...`. Mutasi tetap POST `/slot-praktik`, PATCH/DELETE `/slot-praktik/:id`, dan DELETE `/slot-praktik/:id/permanen`. Payload form, termasuk waktu UTC hasil konversi `Asia/Jakarta`, dipertahankan. Backend tetap memutuskan validitas kapasitas/appointment/relasi.
- Repository hanya menyimpan lock command per sesi dan penanda hasil belum terverifikasi; tidak menyimpan daftar slot. Respons array dan identitas sesi divalidasi agar respons cacat tidak dianggap sebagai daftar kosong yang sah.
- `SlotSessionState` membedakan initial, loading, loaded, empty, refreshing, failure, sesi berakhir/dihapus, serta mutation idle/submitting/success/failure/unknown. `hasLoaded` membedakan belum pernah berhasil membaca dari hasil kosong yang sah. `needsReconciliation` memblokir mutasi berisiko. Map/List dibekukan rekursif melalui utility snapshot immutable 2A, tanpa membentuk owner katalog baru.
- `AdminPage` memiliki registry Cubit keyed ID sesi selama portal aktif. Satu sesi memakai satu owner slot, termasuk saat form dan tabel mengakses data yang sama. Beberapa sesi terbuka memiliki state/read terpisah. Snapshot slot tidak diterbitkan ke katalog atau disalin menjadi cache widget/parent.
- Pembuatan Cubit dan rebuild/dashboard tidak mengambil slot. Ekspansi pertama, refresh manual, command reconciliation, dan invalidasi dependensi pada sesi terbuka yang memicu GET. Sesi tersembunyi ditandai dirty dan diverifikasi saat dibuka kembali; kartu yang dihancurkan oleh navigasi/pagination juga ditandai dirty.
- Satu fetch aktif per sesi dengan satu dirty flag untuk trailing refresh. Invalidasi berulang digabung; invalidasi saat trailing read tetap memerlukan read berikutnya. Semua pemanggil `refresh()` menunggu drain selesai. `settled` memungkinkan observer menunggu invalidasi tanpa mengirim GET tambahan.
- Backpressure dibatasi satu request aktif dan satu kebutuhan refresh tertunda, bukan antrean setiap event. Invalidasi terus-menerus dapat memperpanjang drain sampai tenang, tanpa paralelisme, busy loop, timer, atau retry kegagalan otomatis. Kegagalan tanpa invalidasi baru selesai sebagai state failure dan menunggu tindakan berikutnya.
- Cubit mengamati proyeksi immutable dari sesi yang sama serta dokter/poli/ruang/jam-kapasitas terkait pada katalog 2A. Perubahan tidak terkait atau snapshot identik tidak mengambil slot lagi. Perubahan scope dokter/poli/ruang membersihkan slot lama sebelum hasil konteks baru diterapkan. Epoch menolak read lama. Hilangnya sesi atau pergantian akun/role mengosongkan state dan menutup listener Cubit.
- PracticeScheduleCubit, ServiceScheduleCubit, dan AdminScheduleRepository 2B tetap digunakan seperti existing. Rekonsiliasi katalog setelah mutasi 2B memicu invalidasi slot relevan; tidak ada refresh balik dari slot ke katalog sehingga tidak membentuk loop. Reload halaman secara eksplisit juga memuat ulang sesi terbuka ketika proyeksi referensinya identik.
- CRUD slot menolak double-submit. Hasil timeout/5xx/respons cacat direkonsiliasi lewat GET, tidak diulang otomatis. Jika GET gagal, hasil command tetap diketahui sebagai success/unknown sesuai respons sebenarnya dan mutasi berikutnya diblokir sampai refresh berhasil. Tidak ada rollback UI semu atau pengubahan status booking.
- Portal menutup seluruh Cubit yang dimilikinya; widget standalone menutup Cubit/katalog fallback miliknya saja. Cubit tidak mematikan shared repository. Transport existing tidak mendukung cancellation: respons terlambat kehilangan hak apply, sedangkan write yang mungkin sudah diproses server tidak dianggap dibatalkan.

## C. File Changes

Baru:

- `apps/client/lib/src/features/admin/application/slot_session_cubit.dart`
- `apps/client/lib/src/features/admin/application/slot_session_state.dart`
- `apps/client/lib/src/features/admin/data/admin_slot_repository.dart`
- `apps/client/lib/src/features/admin/models/admin_slot_models.dart`
- `apps/client/test/admin_slot_cubit_test.dart`
- `apps/client/test/admin_slot_widget_test.dart`
- Laporan ini.

Dimodifikasi:

- `apps/client/lib/src/admin.dart`: registry/injeksi scope serta routing command form/Aksi existing ke Cubit.
- `apps/client/lib/src/admin_data.dart`: adapter BlocProvider/BlocBuilder per kartu; ownership slot lokal dihapus.
- `apps/client/test/admin_schedule_widget_test.dart`: observer integrasi menunggu completion invalidasi Cubit di dalam `runAsync`, mempertahankan assertion lazy loading, query, dan jumlah GET existing.

Tidak ada dependency baru. README, `doctor_dashboard.dart`, `doctor_visual.dart`, dan `doctor_visual_refresh_test.dart` tetap dilindungi dengan pemeriksaan SHA-256. File/direktori untracked existing tidak dimodifikasi atau di-stage.

## D. Test Results

49 tes baru: 40 tes Cubit/repository dan 9 widget. Concurrency memakai Completer/handshake request yang deterministik, tanpa delay acak. Cakupan mencakup lazy/empty/error/recovery, immutability rekursif, single flight, burst/trailing invalidation dan completion, read lama setelah scope baru, dua sesi, close, logout/akun/role, konteks dokter/poli, sesi dihapus, CRUD/conflict/appointment, known/unknown write, rekonsiliasi gagal dan pemulihan, payload Jakarta di batas hari, form create melalui date/time picker, konfirmasi hapus, invalidasi kapasitas dan jadwal 2B, navigasi kembali, serta pembatasan rebuild ke kartu sesi.

56 tes terarah (49 baru + 7 integrasi scheduling existing) lulus. Seluruh 677 tes Flutter aman lulus (628 baseline lokal + 49 baru), termasuk portal dokter, katalog 2A, scheduling 2B, slot 2C, login/logout, pasien, petugas, dan Public Display. Setelah tinjauan akhir memperketat completion reload halaman, analyze dan sembilan tes widget slot dijalankan ulang dan lulus; tes menahan GET slot dengan Completer dan memastikan reload belum dinyatakan selesai sebelum GET tersebut selesai.

Format dibatasi sembilan file Dart dalam scope (pemeriksaan format terakhir tanpa perubahan). Build ulang dari source final: Web release sukses, 54,9 detik (`--no-web-resources-cdn --no-wasm-dry-run`); APK debug sukses, 45,0 detik. Gradle memberi peringatan native access Java dan kompatibilitas KGP plugin `flutter_tts` untuk Flutter mendatang; tidak ada upgrade tooling/dependency. `git diff --check` bersih. Jumlah tes lokal mencakup satu tes visual dokter yang sudah berubah sebelum tugas dan tidak ikut commit tahap ini.

Verifikasi manual browser, perangkat Android, live API/CRUD, appointment nyata dan realtime lintas klien masih pending. `live_integration_test.dart` tidak dijalankan. Seluruh mutasi pengujian menggunakan fake HTTP, tidak menulis database development atau test database.

## E. Regression & Security

Tidak ada perubahan backend, schema/migration, Queue Engine, mode poliklinik, auth, RBAC, API, atau database. Timezone tetap `Asia/Jakarta`. Tidak ada token/password/QR atau data pasien ditambahkan pada state/commit. Kapasitas terisi/sisa/tersedia dan konflik memakai nilai server. Katalog 2A dan scheduling 2B tidak digandakan; state akun lama dibuang pada event sesi existing. Tidak ada redesign atau perubahan portal pasien/petugas/dokter/display.

## F. Git Status

Baseline `9c073c4562e3b6f868c14eb85c861498c579788a`, branch `main`. Fetch preflight menunjukkan ahead/behind `0/0`, tanpa commit baru setelah Tahap 2B. [CI baseline 2B](https://github.com/yusranAbd/capstone-b-antrian/actions/runs/40698236235) telah diperiksa melalui GitHub CLI dan sukses. Commit/push tahap ini memakai direct-to-main, staging eksplisit file tugas, pemeriksaan staged diff/hash/remote, serta fast-forward tanpa force. SHA dan status CI terbaru dilaporkan pada hasil akhir setelah push.

## G. Next Step

Fondasi slot siap untuk pekerjaan berikutnya; Tahap 2D tidak dikerjakan tanpa persetujuan pengguna. Pengujian browser/device dan live API yang disebutkan di atas tetap perlu dilakukan sebelum menganggap perilaku deployment nyata terverifikasi. Registry mempertahankan snapshot sesi yang pernah dikunjungi sampai portal berakhir, dengan invalidasi lazy pada sesi tersembunyi; tidak ada cache slot global lintas akun. Keterbatasan cancellation dan idempotensi transport existing tetap berlaku; frontend mengandalkan guard, REST, serta validasi/unique key backend.
