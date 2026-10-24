# P1 — Profil profesional dokter

P1 memperluas modul Dokter existing dengan foto dan biografi. Tidak ada modul
dokter baru, avatar akun Pengguna, perubahan autentikasi, Queue Engine, slot atau
booking. Frontend memakai token/komponen ADMIN compact dan Patient UI V3 existing.

## Kontrak dan implementasi

- `Dokter.fotoProfil`: nullable, referensi media API, VARCHAR(200).
- `Dokter.tentangDokter`: nullable, teks biasa maksimum 1.500 karakter.
- ADMIN mengelola biografi melalui POST/PATCH Dokter existing; foto melalui
  POST/DELETE `/dokter/:id/foto`, dengan JWT dan RBAC existing.
- Pasien membaca foto/biografi pada katalog dan detail. DOKTER membaca profil
  sendiri dari endpoint existing dan dialog Profil akun → Profil profesional.
- Media publik hanya berupa raster profesional yang masih direferensikan DB.
  Tidak ada static directory mount, token dalam URL, atau kebocoran path internal.
- Upload JPEG/PNG/WebP maksimal 2 MiB, diperiksa signature serta decoding Sharp,
  dibatasi 16 juta piksel, orientasi diterapkan, metadata dibuang, output WebP
  maksimal 640×640. Nama UUID v4 dibuat server; file asli tidak dipublikasikan.
- Referensi dikunci per dokter dalam transaksi; pembersihan file lama sesudah
  commit. Dua upload paralel tidak menimpa file satu sama lain. File tidak lagi
  direferensikan tidak dapat dibaca melalui API. File yatim akibat hard delete
  profil/kegagalan disk perlu pembersihan operasional terpisah.
- Storage default `apps/api/.queueb-media/dokter` jika API dijalankan dari
  `apps/api`, diabaikan Git. `DOCTOR_MEDIA_DIR` dapat menunjuk volume persisten.
  Backup DB perlu disertai backup media; deployment ephemeral/multi-instance belum
  dicakup filesystem lokal P1.
- UI ADMIN menyimpan metadata sebelum foto. Bila upload gagal setelah create,
  retry PATCH/upload menggunakan ID yang telah tersimpan; tidak membuat profil
  atau akun duplikat. Poliklinik dan akun login tetap dikelola melalui alur existing.
- Pasien memakai URL media dari konfigurasi API, avatar fallback, biografi ringkas
  dengan Baca Selengkapnya, serta jadwal/ruang/booking existing. Tidak ada rating,
  ulasan atau pengalaman buatan.

Kontrak lengkap tersedia pada bagian 23
[API_INTEGRATION_GUIDE.md](API_INTEGRATION_GUIDE.md).

## Checkpoint migration development

Migration `20261024_doctor_professional_profile` hanya berisi:

```sql
ALTER TABLE "dokter"
  ADD COLUMN "foto_profil" VARCHAR(200),
  ADD COLUMN "tentang_dokter" VARCHAR(1500);
```

Tidak ada reset, restore, DROP, penghapusan data, perubahan relasi, FK, enum atau
migration historis. Kolom nullable tanpa default tidak mengubah nilai record lama.

Migration sudah diuji hanya pada `127.0.0.1:5433/capstone_antrean_test`: kedua kolom
nullable tersedia dan 13 record existing identik setelah perbandingan yang
mengabaikan dua kolom baru. Tidak ada data development dimutasi untuk pengujian.

Checkpoint development dilakukan **READ ONLY** pada 24 Oktober 2026, pukul
20:51:44 WIT: target `127.0.0.1:5433/capstone_antrean`, 354 record existing pada 16
tabel, kedua kolom P1 belum tersedia dan hanya migration P1 ini yang pending.
Baseline hash tersimpan lokal di `tmp/doctor-profile-dev-baseline.json`, tidak
masuk Git dan tidak berisi nilai token/kredensial. Sesi autentikasi yang berjalan
dapat berubah secara sah; data pelayanan harus diperiksa kembali sebelum aktivasi.

**Development belum dimigrasi. Menunggu persetujuan Project Lead.** API development
yang sudah berjalan tetap melayani build existing dengan schema existing. Jangan
restart build P1 ke database itu sebelum migration disetujui dan diterapkan.
Setelah persetujuan: validasi ulang target/baseline, buat backup PostgreSQL custom
dan verifikasi checksum/arsip, gunakan `prisma migrate deploy`, verifikasi data dan
Prisma Client, lalu restart API dan cek health. Jangan reset atau rollback destruktif.

## Dependency dan batas deployment

Sharp 0.35.5 dan file_selector 1.1.0 ditambahkan untuk decoding/reencoding dan file
picker Web/Android. Multer dipin ke 2.5.0 untuk patch
[advisory resmi](https://github.com/expressjs/multer/security/advisories/GHSA-q7qp-rjg7-q26m);
P1 tidak menggunakan fileFilter asinkron. Tidak ada upgrade mayor Nest/Prisma.

`npm audit` sesudah patch: 12 temuan transitive existing (2 low, 2 moderate, 7 high,
1 critical), tanpa temuan Sharp/Multer. Temuan lain, termasuk Handlebars dan rantai
tooling Prisma/CLI, dicatat untuk pemeliharaan dependency terpisah; tidak dijalankan
`audit fix --force`. Ini bukan pernyataan bahwa seluruh dependency siap produksi.

## QA

- Backend: **660/660 unit**, 42 suite; lint, type check dan build NestJS PASS.
- E2E final: **339/339**, 29/29 suite PASS, memakai database test tervalidasi;
  13 record existing identik, nol hilang/berubah dan nol fixture tersisa pada
  pemeriksaan setelah setiap suite. Mencakup 12 tes baru profil/foto, harian,
  HIBRIDA, REQUEUE, Doctor Portal, QR, booking, RBAC, pairing dan realtime existing.
- Percobaan awal E2E yang berbarengan dengan build Web berat mengalami timeout
  transaksi/socket pada dua suite dokter. Seluruh suite kemudian diulang dengan
  proses terpisah secara berurutan tanpa build paralel dan semuanya lulus.
  Tidak ada perubahan timeout produksi, Queue Engine atau aturan bisnis.
- Flutter: **287 PASS**, satu tes live opt-in dilewati; analyzer bersih.
  Sesudah label aksesibilitas menu Aksi dirapikan, 23 tes profil/ADMIN relevan
  diulang dan PASS. CI juga memvalidasi checkout PR tanpa perubahan lokal pengguna.
- Web release JavaScript PASS. APK debug PASS (API emulator
  `http://10.0.2.2:3000/api/v1`); instalasi/smoke pada HP fisik belum dilakukan.
- Responsif diuji pada 320, 375, 414 dan 768 piksel, termasuk nama panjang,
  avatar fallback, biografi panjang, error upload dan retry tanpa profil duplikat.
- Smoke browser dengan Flutter hasil build dan API nyata PASS: upload, ganti,
  hapus, biografi, render media, daftar/detail pasien, serta navigasi booking.
  Nol page/runtime error; media dan seluruh fixture unik dibersihkan; baseline
  13 record database test tetap identik. Tidak ada pengujian mutasi development.
- `git diff --check` PASS. Seluruh **51 file lokal pengguna** tetap identik dan
  dikecualikan dari commit P1; termasuk pekerjaan dashboard dan React existing.

Screenshot berasal dari **fixture database test**. Gambar contoh QA diunggah ke
backend dan dinormalisasi, bukan fallback asset pada aplikasi pasien. Data/foto
dokter development tidak ditambah atau diganti. Tidak ada file hasil upload mentah
yang masuk Git; screenshot adalah bukti pengujian dengan data contoh.

- [Form ADMIN](../frontend/images/doctor-profile-p1/01-admin-profil-dokter.png)
- [Daftar dokter pasien](../frontend/images/doctor-profile-p1/02-pasien-daftar-dokter.png)
- [Detail dokter pasien](../frontend/images/doctor-profile-p1/03-pasien-detail-dokter.png)

Reproduksi QA: `node apps/client/tool/run-live.cjs --doctor-profile` setelah build
API dan build Web dengan API_BASE_URL test port 3001. Runner menolak database lain
dan build Web yang mengarah ke development. Menu Aksi tetap compact; fallback
koordinat pada tooling QA menangani keterbatasan semantic tree sel tabel Web.

Batas dependency frontend existing: `flutter_tts` memberi peringatan migrasi KGP
untuk Flutter mendatang; APK saat ini tetap berhasil dibangun. Build Wasm tidak
menjadi target P1. Penyempurnaan dependency di luar parser upload tidak dilakukan.
