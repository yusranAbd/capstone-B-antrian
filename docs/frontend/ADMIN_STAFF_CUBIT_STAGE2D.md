# Tahap 2D — Akun dan Penugasan PETUGAS

## A. Implementation Summary

Manajemen akun PETUGAS dan Penugasan Loket memakai `StaffAccountCubit`, `AssignmentCubit`, dan `AdminStaffRepository`. Form/tabel, tab, sidebar sembilan menu, search/filter/pagination, dropdown Aksi, konfirmasi, dan konversi tanggal `Asia/Jakarta` dipertahankan. Tidak ada redesign atau dependency baru.

Audit baseline `f41fd97` menemukan daftar akun/penugasan sudah diterbitkan melalui katalog bersama, sedangkan create/status akun dan form/Aksi penugasan masih mengirim HTTP dari presentation layer. Akun dan assignment memakai operasi/form terpisah; migrasi mempertahankan pemisahan tersebut. Tidak ada transaksi atomik frontend, rollback semu, atau assignment otomatis setelah create akun.

Kemampuan akun tetap terbatas pada GET daftar, POST `{nama,email,kataSandi}`, dan PATCH `{aktif}`. Tidak ada edit profil akun, perubahan role, reset password, undangan, atau DELETE akun. Penugasan tetap memakai GET/POST/PATCH, DELETE untuk nonaktif, dan DELETE `/:id/permanen` dengan konfirmasi existing.

## B. Architecture

- Kedua Cubit dikelompokkan di `staff_management_cubit.dart`, dengan instance/state operasi yang terpisah. Keduanya memakai `AdminCatalogState` immutable existing; tambahan `unknown` dan `recoveredMutation` membedakan hasil tidak pasti dari akun yang ditemukan oleh rekonsiliasi. Loaded dengan rows kosong dibedakan dari initial/failure melalui load status dan keberadaan collection pada snapshot.
- `AdminStaffRepository` menerima katalog 2A melalui constructor; request memakai `catalog.api`/`QueueApi` existing. Tidak ada HTTP client, JWT manager, polling, socket, persistence, atau service locator baru.
- `AdminCatalogRepository` tetap satu pemilik snapshot kanonis selama portal aktif, termasuk projection akun/penugasan yang sebelumnya dipakai adapter legacy. Repository staff hanya menyimpan guard write dan path yang perlu diverifikasi, bukan cache daftar/kredensial. Widget tidak menjadi owner kedua; callback refresh parent setelah mutasi staff dihilangkan karena rekonsiliasi sudah dilakukan Cubit.
- Hook kecil `refreshRecords`, recovery, dan failure status pada fondasi 2A memungkinkan adapter staff mengelola transport serta hasil unknown. Default feature 2A/2B tetap sama. Collection yang sudah dimuat oleh batch katalog bersama dapat menandai feature lain sebagai loaded tanpa fetch kedua; kedua tab staff tidak menggandakan initial GET.
- Refresh memakai single-flight/dirty union/trailing refresh katalog existing. Invalidasi saat loading tetap diproses dan pemanggil menunggu drain. Rekonsiliasi setelah write membaca akun, assignment, master terkait, dan koleksi yang sudah dimuat; slot tetap lazy dan tidak diambil massal.
- Write akun dan penugasan memakai guard bersama untuk mencegah operasi yang saling bertabrakan. Double-submit per Cubit juga diblokir. Respons baru diterbitkan melalui REST setelah backend mengonfirmasi; tidak ada optimistic insertion/removal.
- Timeout/5xx/respons mutasi cacat tidak diulang otomatis. Setelah REST sukses, create akun yang tidak pasti dapat menemukan metadata PETUGAS berdasarkan email ternormalisasi. Identitas memakai ID aktual dari server. UI menyebut akun **terverifikasi**, tanpa mengklaim request tadi pasti yang membuatnya. Bila akun belum ditemukan, outcome tetap unknown. Bila rekonsiliasi gagal, mutasi berisiko di kedua scope staff diblokir sampai pembacaan yang relevan berhasil.
- Keberhasilan akun tetap tersimpan ketika assignment ditolak; perbaikan/retry memakai form assignment yang sama dan tidak membuat akun kedua. Jika create sudah dikonfirmasi tetapi reload gagal, feedback menyebut akun tersimpan dan meminta reload sebelum penugasan.
- Form assignment membaca snapshot katalog secara live, termasuk perubahan nama ruang dan akun yang baru tersedia. ID akun/assignment/ruang tidak ditukar. Pilihan akun baru hanya PETUGAS aktif, dengan akun current saat edit tetap ditampilkan jika nonaktif. Konflik periode, role, status ruang, izin pencabutan, dan hubungan operasional tetap keputusan backend; tidak ada aturan satu assignment per petugas yang ditambahkan.
- Scope identitas/role dan generation guard katalog existing mengabaikan respons akun lama. Logout mengosongkan snapshot terkait. Portal menutup Cubit dan shared repository yang dimilikinya; Cubit tidak menutup katalog milik portal. Auth/session store, Portal PETUGAS, DOKTER, PASIEN, dan Public Display tidak dimigrasikan.

## C. File Changes

Baru:

- `apps/client/lib/src/features/admin/application/staff_management_cubit.dart`
- `apps/client/lib/src/features/admin/data/admin_staff_repository.dart`
- `apps/client/lib/src/features/admin/models/admin_staff_models.dart`
- `apps/client/test/admin_staff_cubit_test.dart`
- `apps/client/test/admin_staff_widget_test.dart`
- Laporan ini.

Dimodifikasi:

- `apps/client/lib/src/admin.dart`
- `apps/client/lib/src/admin_staff.dart`
- `apps/client/lib/src/features/admin/application/admin_catalog_cubit.dart`
- `apps/client/lib/src/features/admin/application/admin_catalog_state.dart`
- `apps/client/lib/src/features/admin/data/admin_catalog_repository.dart`

Tidak ada perubahan dependency atau platform configuration. README, `doctor_dashboard.dart`, `doctor_visual.dart`, dan `doctor_visual_refresh_test.dart` dipertahankan dengan pemeriksaan SHA-256 dan tidak di-stage. File/direktori untracked existing, termasuk backup/SQL dan catatan visual, juga dipertahankan.

## D. Test Results

61 tes baru: 48 tes Cubit/repository dan 13 widget. Cakupan mencakup initial/refresh/error/empty, immutability rekursif, burst/trailing refresh dan completion dengan Completer deterministik, close/logout/pergantian akun/role, create/status akun, CRUD/revoke/delete assignment, 400/403/404/409, respons hilang setelah commit, rekonsiliasi gagal/pemulihan, lock lintas resource, serta keamanan kredensial.

Provisioning diuji melalui alur existing: akun+assignment berhasil; akun berhasil, assignment ditolak, lalu retry assignment saja; akun ditolak tanpa POST assignment; respons akun hilang tetapi metadata ditemukan; keberhasilan create yang reload-nya gagal. Tes memeriksa ID backend aktual, payload, tidak ada POST akun kedua, tidak ada sukses total palsu, dan password controller bersih setelah error.

Integrasi memeriksa kedua tab tanpa fetch ganda, nama ruang terbaru saat form terbuka, metadata akun pada assignment setelah penonaktifan, konfirmasi status/hapus, search, serta pembuangan state pada logout. Regresi awal 147 tes (termasuk 48 unit baru) lulus. Seluruh **738 tes Flutter aman lulus** (677 baseline lokal + 61 baru), tanpa kegagalan. Analyze bersih. Format dibatasi sepuluh file Dart terkait; pemeriksaan format final tidak mengubah file. Jumlah lokal mencakup tes visual dokter yang sudah berubah sebelum tugas dan sengaja tidak ikut commit.

Web release berhasil, 91,2 detik (`--no-web-resources-cdn --no-wasm-dry-run`). APK debug berhasil, 71,4 detik. Gradle memberi peringatan native access Java dan kompatibilitas KGP plugin `flutter_tts` untuk Flutter mendatang; tidak ada upgrade dependency/tooling. `git diff --check` bersih pada file tugas.

Verifikasi manual browser, perangkat Android, live provisioning/assignment/RBAC, pencabutan JWT petugas yang sedang login, dan operasi paralel lintas klien masih pending. Fake API tidak membuktikan RBAC/transaksi live. `live_integration_test.dart` tidak dijalankan; tidak ada mutasi terhadap database development maupun test database.

## E. Regression & Security

- Password hanya diteruskan sementara sebagai argumen operasi dari controller form ke API. Tidak ada password/token di state, snapshot, cache repository, log, atau persistence tambahan. Controller password dibersihkan setelah percobaan dan sebelum dispose.
- Metadata akun dibatasi field kontrak `{id,nama,email,peran,aktif}` sebelum diterbitkan, termasuk read legacy melalui katalog. Field kredensial pada relasi assignment dibuang rekursif. Array respons staff yang cacat menjadi failure, bukan false empty. Akun role lain tidak diperlakukan sebagai PETUGAS aktif.
- Error request create yang membawa kredensial dipetakan ke pesan aman berdasarkan kategori HTTP sebelum emit/rethrow; arbitrary server text/cause tidak dipertahankan. Status HTTP tetap tersedia untuk recovery. Respons sukses juga disaring sebelum dikembalikan.
- String password/token pada fixture adalah data dummy khusus pengujian, bukan kredensial nyata. Tes secara eksplisit memastikan nilai dummy dan field rahasia tidak muncul dalam emitted state, hasil command, atau pesan error UI.
- Backend/API, RBAC/auth, Queue Engine, mode poli, schema/migration, database, dan timezone tetap. Tidak ada source of truth baru pada portal lain. Build tidak diklaim sebagai bukti izin live sudah teruji.

## F. Git Status

Baseline `f41fd97b8cbc0a098ab5c608ba812d2ae760ae99`, branch `main`, ahead/behind preflight `0/0`, tanpa commit baru setelah 2C. [CI baseline 2C](https://github.com/yusranAbd/capstone-b-antrian/actions/runs/40705514173) diverifikasi lewat GitHub CLI dan sukses. Commit tahap ini memakai staging eksplisit 11 file terkait dan pemeriksaan hash/staged diff/remote; push fast-forward tanpa force. SHA baru dan status CI dilaporkan pada hasil akhir setelah push.

## G. Next Step

Fondasi siap untuk Tahap 2E setelah persetujuan pengguna; Manajemen Display dan tahap berikutnya belum dikerjakan. Verifikasi manual/live yang tercatat di atas tetap diperlukan. Transport existing tidak menyediakan cancellation atau idempotency key; frontend memakai generation guard, REST, guard mutasi, serta validasi backend. Rekonsiliasi masih mengikuti snapshot katalog bersama sehingga ketersediaan endpoint referensi dapat memengaruhi keberhasilan reload; tidak ada refactor global katalog di tahap ini.
