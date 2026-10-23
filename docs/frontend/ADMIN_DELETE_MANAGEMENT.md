# Penghapusan data ADMIN

## Implementasi

Branch `feature/admin-delete-management` dibuat dari main setelah PR #57 (`17b7a4b`). Desain ADMIN Compact dipertahankan. Delapan modul pengelolaan memiliki aksi Hapus merah; Dashboard tidak memiliki aksi hapus.

- Dialog konfirmasi dengan nama data, peringatan permanen, dan konfirmasi kode/nama untuk Poliklinik/Dokter.
- Tombol terkunci selama request; tidak ada retry hapus otomatis.
- Pesan penolakan backend ditampilkan pada dialog. Data aktif dapat diarahkan ke alur Nonaktifkan existing, tetap dengan konfirmasi.
- Berhasil hapus memuat ulang katalog dan menampilkan notifikasi; state pencarian/filter tetap dipertahankan.
- Slot mempertahankan pemuatan bertahap; jam/kapasitas mempertahankan bulk input.
- Perangkat mendapat aksi ubah nama yang terbatas pada metadata nama, agar kontrol Ubah/Nonaktifkan/Hapus konsisten. Scope poliklinik dan kredensial tidak berubah saat rename.

Kontrak, aturan relasi konservatif dan batas transaksi: [API_INTEGRATION_GUIDE.md](../backend/API_INTEGRATION_GUIDE.md#penghapusan-permanen-data-admin).

## QA aktual

- Backend unit: **641/641 PASS** (40 suite).
- Backend E2E: **314/314 PASS** (26 suite), seluruhnya pada target test terisolasi.
- Integritas test: **13 record awal**, `missing=0`, `changed=0`, `remaining=0` setelah cleanup fixture.
- Backend lint, TypeScript `tsc --noEmit`, NestJS build: **PASS**.
- Flutter analyze: **PASS**, tidak ada issue.
- Flutter test: **251 PASS, 1 SKIP existing** (tes live membutuhkan runner khusus).
- Dart format: **58 berkas, 0 perubahan**.
- Flutter build Web: **PASS**. Wasm dry-run dependency TTS/Socket.IO existing masih memberi temuan; build JavaScript selesai.
- `git diff --check`: **PASS**.
- Peringatan deprecation `pg` ketika query paralel merupakan batas dependency existing; pengujian konflik/konkurensi tetap lulus.

E2E dijalankan melalui `node test/run-admin-delete.cjs` dengan kredensial lokal yang tidak dicetak/disimpan ke Git. Runner memaksa target `127.0.0.1:5433/capstone_antrean_test`, memverifikasi `current_database()` dan port server, membuat fingerprint semua record existing sebelum tes, serta membandingkan sesudah cleanup fixture unik. Tidak ada reset, restore, migrasi atau penghapusan data development.

Tes baru meliputi: delapan resource tanpa relasi; JWT/RBAC USER/PETUGAS/DOKTER; data terpakai dan akun dokter; tidak berubahnya appointment/tiket/audit; dua hapus bersamaan; hapus bersamaan booking appointment; Nonaktifkan existing; rename display tanpa perubahan kredensial; pairing, pencabutan socket, sesi lama/kode lama dan reconnect setelah perangkat dihapus. Tes widget memverifikasi konfirmasi nama/kode, batal tanpa request, pesan 409, refresh daftar dengan pencarian aktif, serta penghapusan perangkat dari tabel terfilter.

Satu regresi penuh menemukan SQLSTATE `40001` pada `meta.driverAdapterError.cause.originalCode`; pemetaan konflik kini mencakup bentuk tersebut, dengan tes unit khusus.

## Berkas utama

Backend: modul baru `src/admin-delete`, registrasi modul pada `app.module.ts`, metadata rename terbatas pada `display-device.*`, E2E/runner aman. Frontend: `admin_delete.dart`, wiring pada `admin.dart`, `admin_data.dart`, `admin_schedules.dart`, `admin_display.dart`, serta tes baru `admin_delete_test.dart`.

Tidak ada perubahan Prisma schema/migration, Queue Engine, autentikasi, RBAC existing atau UI role lain. Log audit master data menggunakan logger server; belum ada tabel audit master-data generik dan tidak ditambahkan pada scope ini.

## Penggunaan setelah merge

Fitur ini baru tersedia saat frontend dan backend sama-sama diperbarui ke commit PR ini. Setelah PR di-merge: sinkronkan main, build/restart NestJS dan Flutter, lalu refresh browser. Menjalankan frontend baru dengan backend lama akan menghasilkan 404 pada endpoint `/permanen`; jangan mengubah arti endpoint Nonaktifkan untuk mengatasinya.

Pekerjaan dilakukan pada worktree terpisah; 51 berkas lokal pengguna termasuk revisi DOKTER tetap dipertahankan. Tidak ada file rahasia, backup atau artefak build yang masuk commit. PR tanpa auto-merge.
