# P2 — Profil Saya dan keamanan akun

ADMIN, PETUGAS, DOKTER, dan USER/PASIEN memakai komponen profil bersama. Dashboard, Queue Engine, Public Display, dan kewenangan role mempertahankan alur existing.

## API

URL relatif terhadap `/api/v1`. Semua endpoint memakai JWT; identitas selalu berasal dari `CurrentUser`, tanpa parameter userId bebas.

| Metode | URL | Kontrak |
| --- | --- | --- |
| GET | `/auth/me` | Metadata existing ditambah `aktif`, `avatarProfil: string|null`, `dibuatPada`; tanpa hash/token |
| PATCH | `/auth/me` | `{nama}`; dipangkas, 3–150 karakter; respons metadata profil |
| POST | `/auth/me/avatar` | Multipart satu file `foto`; JPEG/PNG/WebP statis, maksimal 2 MiB dan 16 juta piksel; 201 `{id,avatarProfil}` |
| GET | `/auth/me/avatar` | Byte WebP akun sendiri; 404 jika belum ada; `private, no-store`, `nosniff` |
| DELETE | `/auth/me/avatar` | Idempoten; 200 `{id,avatarProfil:null}` |
| POST | `/auth/me/password` | `{kataSandiLama,kataSandiBaru}`; 200 `{message,loginUlang:true}` |

Email, peran, status, ID, dan referensi media tidak dapat diubah melalui body profil. Field tambahan ditolak 400. Referensi `avatarProfil` merupakan identitas media internal, **bukan URL publik**. Flutter membaca byte melalui GET `/auth/me/avatar` dengan JWT dan pemulihan access token existing.

Nama/avatar langsung memperbarui state akun dan header tanpa logout. Cache avatar dipisahkan menurut identitas dan referensi; respons terlambat setelah pergantian sesi ditolak. Halaman menyembunyikan data ketika identitas sesi berubah, dan snapshot role diberi scope agar transisi logout tidak menafsirkan penugasan PETUGAS sebagai data DOKTER. Avatar DOKTER tidak mengubah `dokter.foto_profil` atau `dokter.tentang_dokter`.

## Password dan sesi

Password baru minimal 8 karakter, maksimal 72 karakter dan **72 byte UTF-8**, sesuai batas bcrypt. Password lama diverifikasi oleh PasswordService existing; password baru yang identik ditolak. Flutter memvalidasi konfirmasi.

Password lama salah menghasilkan **400**, bukan 401, agar kesalahan formulir tidak dianggap sebagai kedaluwarsa JWT. Perubahan password dibatasi 5 request/menit **per akun terautentikasi**; upload avatar 10/menit per akun. Rate limit autentikasi existing tetap berlaku.

Pembaruan hash dan pencabutan seluruh sesi menggunakan satu transaksi, row lock, serta compare-and-swap. Login juga mengunci baris pengguna dan memeriksa kembali hash yang sebelumnya diverifikasi: login password lama yang sedang berlangsung tidak dapat membuat sesi setelah perubahan password selesai. Refresh existing tetap memakai CAS dan menolak sesi dicabut.

Setelah sukses Flutter menghapus pasangan token melalui SessionStore existing dan meminta login ulang pada semua perangkat. Audit hanya berisi aksi, aktor, dan waktu; tidak ada password/token. Timeout jaringan tidak membuktikan mutasi gagal; periksa keadaan akun sebelum mengulang.

## Informasi role

- ADMIN: identitas dan keamanan akun sendiri.
- PETUGAS: GET `/penugasan-petugas` existing membatasi hasil pada pemilik sesi; poliklinik/loket, periode inklusif, dan status ditampilkan read-only.
- DOKTER: GET `/portal-dokter/profil` serta `/portal-dokter/jadwal` existing; foto profesional, biografi, spesialisasi, poliklinik, dan jadwal tanggal pelayanan read-only.
- USER/PASIEN: informasi pribadi dan kembali ke navigasi Tiket Saya/Riwayat existing. Tidak ada informasi klinis baru.

## Migration dan storage

`20261024_user_profile_p2` hanya menambahkan `pengguna.avatar_profil VARCHAR(200) NULL`. Tidak ada perubahan relasi, migration historis, cascade, atau reset.

`USER_AVATAR_DIR` menunjuk direktori persisten terpisah dari `DOCTOR_MEDIA_DIR`; default `.queueb-media/avatar` relatif terhadap working directory API. Gunakan path absolut/volume persisten dan backup database bersama kedua direktori media. Tidak ada static mount avatar. UUID filename dan normalisasi WebP maksimal 640×640 membuang metadata/payload asli. Pembaruan referensi memakai transaksi; pembersihan file lama hanya setelah commit dan jika tidak lagi direferensikan. Kegagalan cleanup dapat menyisakan orphan privat untuk pemeliharaan terpisah.

**Migration development belum dijalankan.** Aktivasi `127.0.0.1:5433/capstone_antrean` memerlukan persetujuan Project Lead, validasi target, backup lengkap terverifikasi, dan pemeriksaan integritas sebelum `prisma migrate deploy`. Jangan menjalankan runtime P2 pada database tanpa kolom avatar. Runtime development P1 tidak perlu direstart selama checkpoint ini.

Pengujian hanya memakai `127.0.0.1:5433/capstone_antrean_test`. Cleanup dibatasi fixture unik milik tes dengan pemeriksaan hash record existing. Akun/password development tidak diubah oleh pengujian P2.

## Validasi dan batas

Backend mencakup keempat role, mass assignment, avatar privat, isolasi foto P1, upload/ganti/hapus, password salah, pencabutan semua sesi, password paralel, login in-flight, serta rate limit per akun. Flutter mencakup role, desktop/mobile, avatar/nama, konfirmasi password, dan respons setelah logout. Hasil aktual dicatat pada PR.

Tidak ada perubahan email, reset password, MFA, profil kesehatan, atau pengelolaan akun orang lain. Multi-instance kelak memerlukan volume media bersama. Build APK tidak membuktikan pengujian fisik Android bila perangkat tidak tersedia.

## Hasil QA lokal — 25 Oktober 2026 WIT

- Backend: 664 unit test (43 suite), 360 E2E (30 suite) lulus; lint, type check, format, NestJS build lulus.
- Flutter: 299 tes lulus, satu tes integrasi live opt-in dilewati; analyze dan format bersih. Tambahan verifikasi source final: 67 tes navigasi/profil/sesi lulus.
- Build Web JavaScript release dan APK debug lulus. APK memakai URL emulator `http://10.0.2.2:3000/api/v1` dan memerlukan aktivasi migration P2 sebelum penggunaan pada development. Perangkat fisik tidak diuji.
- Browser dengan API nyata pada database test: profil keempat role, perubahan nama/header, avatar privat, informasi role read-only, navigasi kembali, logout/pergantian role lulus. Build final tidak mencatat error browser.
- Foto profesional P1 non-null tetap identik setelah upload/ganti/hapus avatar akun pada seluruh role. Password paralel dan login lama in-flight juga tercakup E2E.
- Setiap suite E2E mempertahankan 13 record baseline. Fixture UI terisolasi dibersihkan dan baseline kembali identik. Cleanup suite Hospital diperkuat agar setup parsial tidak memakai UUID kosong atau menyisakan fixture.
- Seluruh 51 file lokal pengguna tetap identik dan tidak dimasukkan dalam commit P2. Migration hanya dipasang pada database test; development tetap pada P1.

Screenshot memakai akun/ilustrasi demo, bukan data pasien: [ADMIN](../frontend/images/user-profile-p2/01-admin.jpg), [PETUGAS](../frontend/images/user-profile-p2/02-petugas.jpg), [DOKTER](../frontend/images/user-profile-p2/03-dokter.jpg), [PASIEN](../frontend/images/user-profile-p2/04-pasien.jpg).

Build Web QA disimpan terpisah di `tmp/p2-web` agar tidak mengganti Web development P1 yang sedang disajikan. Pada Windows gunakan path output absolut untuk kompilasi shader. Peringatan migrasi Built-in Kotlin dari flutter_tts tetap berasal dari dependency existing; build debug tetap berhasil.
