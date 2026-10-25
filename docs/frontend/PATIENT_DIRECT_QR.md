# Perbaikan tombol QR beranda pasien

Tombol **QR Code** pada Kunjungan Terdekat sebelumnya membuka detail tiket yang sama dengan **Lihat Detail**, sehingga pasien masih harus menekan **Terbitkan QR**.

Sekarang tombol QR mengambil status tiket terbaru, lalu otomatis menerbitkan dan menampilkan QR satu kali jika tiket memenuhi kontrak existing: status DIPESAN dan tanggal pelayanan sama dengan tanggal hari ini di SERVICE_TIME_ZONE. Loading ditampilkan selama pemeriksaan/penerbitan; pembukaan dialog dan permintaan ganda dicegah.

Lihat Detail tetap membuka detail tanpa menerbitkan QR. Polling, reconnect, dan berakhirnya masa QR tidak menerbitkan ulang secara otomatis. QR kedaluwarsa atau tiket yang berubah status disembunyikan. Kegagalan API ditampilkan dengan retry manual. Tiket untuk tanggal mendatang menampilkan penjelasan tanggal pelayanan; tidak dibuat QR palsu dan tidak ada perubahan backend atau aturan check-in.

## Validasi

- 140 tes regresi terkait pasien, QR, booking, jadwal, sinkronisasi, login, dan sesi: PASS.
- Flutter analyze: tanpa issue. Build Web release: PASS.
- Smoke test Flutter Web 390 px melalui API nyata: satu klik QR Code langsung menampilkan QR dan countdown; Lihat Detail tetap tanpa penerbitan otomatis; tidak ada error console browser.
- Fixture pengujian hanya pada 127.0.0.1:5433/capstone_antrean_test dan dibersihkan berdasarkan ID milik tes. Seluruh 13 record baseline identik setelah pengujian.
- Seluruh 51 file lokal pengguna yang dilindungi tetap identik dan dipisahkan dari finalisasi Git perubahan ini.

Screenshot menggunakan fixture sementara yang telah dibersihkan: [QR langsung tampil](images/patient-direct-qr/01-qr-langsung.jpg).

Untuk runtime Flutter yang masih berjalan pada localhost:5173, lakukan hot restart **R** agar source baru termuat.
