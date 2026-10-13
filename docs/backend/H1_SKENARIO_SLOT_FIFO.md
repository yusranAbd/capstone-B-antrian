# H1/H3 — Kebijakan Antrean Prioritas Slot lalu FIFO (Disetujui Tim)

**Kebijakan:** Untuk tiap poli/dokter/ruang, calon tiket yang layak dipanggil adalah tiket `MENUNGGU` milik janji temu pada slot **yang sudah dimulai**. Urutkan menurut:

```sql
ORDER BY slot_praktik.mulai_pada ASC,
         tiket_antrean.urutan_masuk_antrean ASC,
         tiket_antrean.id ASC
```

Tanggal pelayanan mengikuti `SERVICE_TIME_ZONE`, bukan tanggal UTC mentah. Jika slot belum dimulai, tiket tidak layak CALL meskipun sudah CHECK_IN. Dalam slot yang sama, pasien yang lebih dulu dimasukkan ke FIFO lebih dulu dipanggil; ini terkait waktu `masukAntreanPada` (hasil ENQUEUE setelah Check-In), bukan saat reservasi dibuat.

| Waktu sekarang | Pasien | Slot | Waktu ENQUEUE | Layak dipanggil? | Prioritas |
|---|---|---|---|---|---|
| 08:20 | A | 08:00–08:30 | 08:15 | Ya | Pertama, slot 08:00 telah dimulai |
| 08:20 | B | 09:00–09:30 | 08:05 | Tidak | Slot 09:00 belum dimulai |
| 09:05 | B | 09:00–09:30 | 08:05 | Ya | Pertama di antara tiket slot 09:00 |
| 09:05 | C | 09:00–09:30 | 08:50 | Ya | Setelah B, karena FIFO lebih akhir |

Contoh pukul 09:05 mengasumsikan pasien dari slot 08:00 sudah tidak lagi `MENUNGGU`. Jika tiket slot 08:00 masih memenuhi syarat dalam **sesi dan loket dokter yang sama**, tiket itu lebih dahulu dipanggil daripada B/C. Pasien tidak hadir ditangani manual dengan SKIP dan REQUEUE, bukan oleh auto-skip berdasar jam.

**Kondisi batas yang wajib diuji saat H3:** slot di masa depan, dua pasien satu slot, dua dokter pada poli sama, pasien salah loket, interval sesi tidak aktif, sesi berlainan pada ruang yang sama, race dua CALL, SKIP lalu REQUEUE, snapshot multi-ruang, serta pengguna lama mode ANTREAN_HARIAN.

**Batas kebijakan:** Satu slot dokter bukan jaminan jam konsultasi tepat, dan perubahan ini belum mengimplementasikan SLA pasien terlambat ataupun kuota antrean darurat.
