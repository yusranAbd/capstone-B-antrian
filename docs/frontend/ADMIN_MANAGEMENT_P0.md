# ADMIN Management P0 — QueueB Hospital

Implementasi 24 Oktober 2026 pada branch `feature/admin-management-p0`.

## Perubahan operasional

- Halaman Penugasan petugas mempunyai tab **Akun Petugas** dan **Penugasan Loket**.
- ADMIN dapat melihat/mencari akun PETUGAS berdasarkan nama/email, membuat akun baru, serta mengaktifkan atau menonaktifkan akun.
- Role PETUGAS ditentukan backend. Registrasi publik tetap USER. Penonaktifan mencabut sesi; reaktivasi memerlukan login ulang dan tidak menghidupkan sesi lama.
- Akun baru langsung menjadi pilihan penugasan. Form tidak menyediakan input atau clipboard UUID. Pilihan ruang baru dibatasi ke ruang dan poliklinik aktif.
- Tanggal penugasan tetap inklusif, tanpa shift atau pembatasan satu petugas per loket. Pemeriksaan benturan dan penyimpanan menggunakan transaksi dengan row lock akun. Penonaktifan penugasan tetap bisa dilakukan ketika akun sudah nonaktif.
- Status penugasan membedakan akan berlaku, berlaku, berakhir, nonaktif, dan akun nonaktif.
- Tabel dokter mengutamakan nama/spesialisasi, memisahkan status profil dari akun login, serta menyediakan tindakan berlabel untuk hubungan poliklinik dan akun.
- Alur dokter tetap tiga penyimpanan terpisah: profil → hubungan poliklinik → provisioning akun. Kegagalan langkah berikutnya tidak membuat ulang data sebelumnya. Dialog provisioning mempertahankan input saat gagal dan daftar direkonsiliasi setelah dialog ditutup.
- Penautan akun DOKTER existing memakai pilihan nama/email akun aktif yang belum tertaut. Endpoint mutasi provisioning existing dipertahankan.

Tidak ada perubahan Prisma schema/migration, Queue Engine, registrasi publik, atau desain dashboard role lain. Seluruh 51 file pekerjaan lokal pengguna yang tercatat pada fingerprint awal tetap identik dan dikecualikan dari commit P0.

## Kontrak API

Lihat [API Integration Guide bagian 22](../backend/API_INTEGRATION_GUIDE.md#22-admin-management-p0--akun-dan-penugasan-24-oktober-2026).

Tambahan khusus JWT ADMIN:

| Endpoint | Kegunaan |
|---|---|
| GET `/api/v1/akun-petugas` | Direktori metadata akun PETUGAS aktif/nonaktif |
| POST `/api/v1/akun-petugas` | Membuat akun PETUGAS, body nama/email/kataSandi |
| PATCH `/api/v1/akun-petugas/:id` | Mengubah status akun, body aktif boolean |
| GET `/api/v1/dokter/akun-tersedia` | Akun DOKTER aktif yang belum tertaut |

Respons dokter menambahkan metadata `pengguna:{nama,email,aktif}|null` hanya untuk ADMIN. Non-ADMIN tidak menerima metadata akun atau penggunaId. Respons penugasan menambahkan `petugas.aktif`. Tidak ada hash/password/token pada metadata atau log audit akun.

## Validasi

| Pemeriksaan | Hasil |
|---|---|
| Backend unit | 648 PASS, 41 suite |
| Backend E2E | 332 PASS, 27 suite |
| Type check, lint, build NestJS | PASS |
| Flutter analyze | PASS |
| Flutter test | 268 PASS, 1 tes live dilewati karena fixture opt-in |
| Build Flutter Web release | PASS |
| Browser Flutter + API nyata | PASS: akun, status, penugasan dan provisioning dokter |
| Integritas database test | 13 record awal identik; 0 hilang/berubah; 0 fixture tersisa |

Seluruh E2E dijalankan melalui guard `test/run-admin-delete.cjs` pada `127.0.0.1:5433/capstone_antrean_test`. Regresi penuh diulang satu suite per proses untuk menghindari kontaminasi teardown Jest setelah timeout runner lokal. Tidak ada penghapusan atau reset data development.

Regresi khusus: `apps/api/test/admin-management-p0.e2e-spec.ts` dan `apps/client/test/admin_management_p0_test.dart`. Cakupan termasuk RBAC semua role, role tetap dari server, pencabutan sesi/refresh, reaktivasi, penolakan akun nonaktif, benturan batas tanggal, create/update paralel, privasi metadata dokter, konfirmasi UI, serta akun baru langsung tersedia di penugasan.

## Screenshot dari aplikasi terkompilasi

Data pada screenshot adalah fixture test unik, bukan akun atau data development. Tampilan diverifikasi pada 1366×768, 1440×900, dan tablet 768×1024. Tabel mempertahankan scroll horizontal existing pada ruang sempit.

- [Akun Petugas](images/admin-p0/01-akun-petugas.png)
- [Penugasan Loket](images/admin-p0/02-penugasan-loket.png)
- [Manajemen Dokter](images/admin-p0/03-manajemen-dokter.png)
- [Dokter pada tablet](images/admin-p0/04-dokter-tablet.png)

## Panduan demo

1. Jalankan backend dan Flutter dari branch P0 atau main setelah PR disetujui/di-merge. Server/build lama perlu dimuat ulang agar route dan UI baru tersedia.
2. Login ADMIN → Penugasan petugas → Akun Petugas → Tambah akun PETUGAS.
3. Masukkan nama, email dan kata sandi awal. Sampaikan kata sandi melalui saluran aman.
4. Buka Penugasan Loket → Tambah → cari petugas dengan nama/email → pilih ruang aktif → pilih periode → Simpan.
5. Verifikasi status dan periode. Nonaktifkan akun untuk mencabut login; nonaktifkan penugasan untuk mengakhiri penempatan saja.
6. Buka Dokter → Tambah profil → Hubungkan poliklinik → Buat akun login. Untuk akun DOKTER existing, aktifkan opsi penautan lalu pilih berdasarkan nama/email.
7. Verifikasi email/status akun dan status profil pada tabel. Profil dokter nonaktif memblokir akses portal.

Untuk mengulang QA browser secara terisolasi: build API, build Web dengan `--dart-define=API_BASE_URL=http://127.0.0.1:3001/api/v1`, lalu jalankan `node apps/client/tool/run-live.cjs --admin-p0` dari root. Runner memvalidasi target test, membuat fixture sendiri, mengambil screenshot dan membersihkan hanya fixture tersebut.

## Di luar P0

Pelepasan/penggantian akun DOKTER, mutasi status akun DOKTER secara terpisah, reset password administratif, shift jam, pagination server dan redesign tabel umum tidak ditambahkan. Reaktivasi akun PETUGAS memungkinkan penugasan yang masih aktif/berlaku digunakan kembali setelah login baru; penugasan tidak dihapus otomatis.
