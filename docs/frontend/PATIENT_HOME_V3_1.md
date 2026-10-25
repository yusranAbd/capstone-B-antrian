# Beranda Pasien V3.1

Perubahan terbatas pada beranda pasien Flutter. Backend, schema, kontrak API,
halaman detail, booking, QR, autentikasi, dan role lain tidak diubah.

## Perilaku

- Avatar akun menggunakan komponen P2; nama dari akun login. Notifikasi membuka aktivitas tiket existing.
- Pencarian memakai katalog dokter/poliklinik. Kategori horizontal berasal dari poliklinik aktif API dan hanya memfilter pratinjau beranda.
- Kunjungan terdekat langsung setelah pencarian. Tanpa kunjungan, judul, kartu, dan jarak section tidak dibuat.
- Tiket dipilih dari tiket sendiri dan appointment sendiri; snapshot tiket mengungguli status pada appointment. Tanggal pelayanan diurutkan dahulu, kemudian status aktif (dilayani/dipanggil/menunggu/check-in/dilewati/dipesan), slot, dan ID untuk hasil deterministik. Ini hanya prioritas kartu beranda, bukan urutan Queue Engine.
- Appointment menampilkan dokter/spesialisasi booking, foto katalog dengan ID yang sama, ruang, tanggal DATE, waktu slot dalam zona pelayanan, nomor aktual, dan status. Walk-in tidak diberi dokter/slot rekaan; ruang hanya jika tersedia.
- Kedua aksi Lihat Detail dan QR Code membuka dialog tiket existing dengan tiket.id. QR tidak disimpan oleh beranda; penerbitan/expiry tetap milik dialog dan API existing.
- Foto P1 dan jadwal bertanggal aktual digunakan pada Dokter Pilihan. Tidak ada rating, ulasan, durasi perkiraan, atau jadwal mingguan rekaan.
- Banner promosi tidak ditampilkan. Pendaftaran, janji temu, tiket, riwayat, profil, walk-in, dan informasi display tetap dapat diakses.
- PatientUpdates/RefreshGate tetap menjadi pemilik refresh REST setelah event, reconnect, dan polling fallback. Bottom navigation beranda dipadatkan menjadi 68 px dengan SafeArea existing.

## Validasi aktual

- dart format: PASS pada empat file Dart berubah.
- flutter analyze: PASS, tanpa issue.
- flutter test --concurrency=1: 309 PASS, 1 live opt-in SKIP (termasuk satu tes lokal pengguna yang tidak dimasukkan commit).
- Tes beranda: 22 PASS, termasuk tanpa kunjungan, appointment aktual, walk-in, hilangnya kunjungan terminal, QR dengan tiket.id berbeda dari appointment.id, QR kedaluwarsa, kategori, error/loading, serta navigasi detail.
- Lebar widget diuji: 320, 360, 375, 390, 412, 414, dan 768 px; nama panjang dan tidak ada overflow.
- flutter build web --release --no-wasm-dry-run: PASS.
- flutter build apk --debug: PASS. Perangkat Android fisik tidak digunakan.
- Browser pada Web release/API nyata: nama/foto/spesialisasi/ruang/slot/nomor sesuai booking QA; QR untuk tanggal mendatang tidak diterbitkan; Doctor Card membuka detail existing; tidak ada error JavaScript.
- Cancellation appointment QA melalui API existing menghilangkan kartu otomatis pada tab beranda tanpa reload, melalui mekanisme realtime existing.
- Screenshot 390 x 1000: [dengan kunjungan](images/patient-home-v3-1/01-dengan-kunjungan.jpg), [tanpa kunjungan](images/patient-home-v3-1/02-tanpa-kunjungan.jpg).

Screenshot memakai akun/dokter ilustrasi berlabel Demo/QA dan booking sementara
pada 127.0.0.1:5433/capstone_antrean_test, bukan data pasien development.
Seluruh fixture milik QA dibersihkan dengan pembandingan ID/hash baseline.
Build Web QA berada di direktori tmp terpisah; server development existing tidak ditimpa.

## File implementasi

- apps/client/lib/src/patient.dart
- apps/client/lib/src/patient_home.dart
- apps/client/test/patient_home_v3_test.dart
- apps/client/test/patient_v2_test.dart (ekspektasi grid lama diselaraskan dengan kategori horizontal)

Tidak ada migration atau aktivasi database development pada pekerjaan ini.
