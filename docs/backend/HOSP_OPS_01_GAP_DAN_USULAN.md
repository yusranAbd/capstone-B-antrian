# HOSP-OPS-01 — Gap penanganan manual dan usulan kontrak

Tanggal: 14 Oktober 2026. Branch: feature/hospital-integrasi-h3.
Status: metadata/filter baca disetujui Project Lead. Resolusi manual tetap gap; mutasi, perpanjangan sesi dan transisi tambahan belum disetujui.

## Hasil audit operasi existing

- POST /janji-temu/:id/batalkan hanya untuk USER pemilik dan tiket DIPESAN. Tiket CHECK_IN/MENUNGGU tidak dapat dibatalkan melalui jalur ini.
- CALL menolak appointment di luar interval sesi; tidak mengubah status MENUNGGU.
- SKIP memerlukan DIPANGGIL, REQUEUE memerlukan DILEWATI, START memerlukan DIPANGGIL, COMPLETE memerlukan DILAYANI. Tidak ada transisi sah untuk menutup MENUNGGU yang tidak dapat dilayani.
- PATCH /jadwal-praktik/:id saat ini menolak pengubahan waktu jika sesi sudah mempunyai slot. Karena itu belum ada mekanisme API untuk memperpanjang sesi berisi appointment.
- Data tetap dicatat; tidak ada auto-cancel/reschedule/requeue atau perpindahan tanggal. Alur manual BELUM dapat dinyatakan selesai hanya dengan menampilkan layakDipanggil false.

## Usulan aditif untuk visibilitas petugas

Usulan ini telah disetujui dan diimplementasikan: alasanTidakLayak opsional pada tiket Hospital di GET /queue/menunggu dan GET /queue/snapshot. Tiket layak membawa null; tiket tidak layak membawa kode seperti SESI_BERAKHIR, SESI_BELUM_DIMULAI, SLOT_BELUM_DIMULAI, RUANG_BERBEDA, TANGGAL_TIDAK_SESUAI, RELASI_TIDAK_AKTIF, atau BELUM_CHECK_IN. Kode merupakan metadata API, bukan status atau enum database.

Tambah filter opsional hanyaTidakLayak pada GET /queue/menunggu untuk mengakses tiket yang memerlukan pemeriksaan tanpa tersisih oleh batas 100 kandidat layak. Scope layanan/penugasan, urutan selector, batas respons, dan endpoint existing dipertahankan. Filter tidak mengubah tiket. Nilai benar berarti tiket yang belum/tidak layak, bukan jaminan semua tiket tersebut harus dibatalkan; SLOT_BELUM_DIMULAI dapat cukup ditunggu.

Semua metadata tetap tanpa nama pasien, data medis, QR, atau rahasia. Data sumber dan keputusan operasional tetap berada pada backend.

## Usulan minimal resolusi yang memerlukan persetujuan terpisah

Pilihan A: perluas POST /janji-temu/:id/batalkan existing untuk PETUGAS, khusus appointment MENUNGGU dengan sesi yang telah berakhir. USER tetap hanya dapat membatalkan DIPESAN miliknya sendiri. PETUGAS wajib memiliki penugasan aktif pada ruang sesi dan tanggal pelayanan, mengirim loketId serta kode alasan yang disetujui, dan telah mengoordinasikan keputusan dengan pihak berwenang/pasien. Gunakan DIBATALKAN existing, transaksi Serializable, status/versi kondisional, lock sesi/slot yang sama, audit aktor/status/alasan dan sinyal refresh realtime yang kompatibel. Jangan membuat endpoint duplikat, status atau migration baru. Bukan auto-cancel dan tidak berlaku untuk DIPANGGIL/DILAYANI.

Pilihan B: perluas PATCH /jadwal-praktik/:id existing agar ADMIN dapat menaikkan selesaiPada saja pada sesi berisi slot. Dokter, tanggal, ruang, mulaiPada dan slot tetap; validasi jam poli, overlap dokter/ruang, lock sumber daya dan audit tiket terdampak wajib. Perpanjangan bukan reschedule atau pembuatan appointment baru. Audit master sesi tanpa tiket perlu disepakati karena PeristiwaAntrean existing terkait tiket.

Pilihan A menyediakan resolusi ketika pelayanan tidak dapat dilanjutkan; pilihan B menyediakan kelanjutan pelayanan hanya ketika perpanjangan resmi disetujui. Keduanya belum diimplementasikan dan tidak boleh dianggap sudah tersedia. Project Lead perlu menetapkan izin dan mekanisme audit sebelum salah satu perilaku ini diaktifkan.

## Pekerjaan independen yang telah disetujui

Lanjutkan kuota harian semua mode Hospital, validasi relasi/tanggal/ruang pada booking/CHECK_IN/ENQUEUE/CALL, ketersediaan slot, konsistensi SERVICE_TIME_ZONE, pengujian alur valid/tidak valid dan konkurensi. Pertahankan tiket MENUNGGU setelah sesi berakhir serta kelanjutan DIPANGGIL/DILAYANI. Jangan mengimplementasikan resolusi otomatis atau baru selama persetujuan tambahan belum ada.
