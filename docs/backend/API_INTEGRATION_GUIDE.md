# QueueB | Panduan Integrasi REST API, Socket.IO, dan Public Display

**Lokasi repository:** `docs/backend/API_INTEGRATION_GUIDE.md`
**Versi dokumen:** 1.6 — Public Display Monitor V3 dan proyeksi nama sesuai kebijakan server
**Tanggal penelaahan:** 19 Oktober 2026
**Status:** Kontrak Authentication, Reservasi, Tiket/QR/Check-In, Queue, Realtime, Display, 20 endpoint Administrasi existing, empat endpoint manajemen display baru dan endpoint Hospital dipetakan terhadap source. Bagian 20 mencatat pairing dan sesi kiosk; Bagian 17 mencatat integrasi Hospital; Bagian 18 menyediakan urutan request untuk dua alur utama. Hasil QA dan batas MVP tersedia pada `MVP_BACKEND_FINAL.md`; checkpoint Milestone 2 tersedia pada `MILESTONE_2_INTEGRASI_HOSPITAL.md`. Resolusi manual HOSP-OPS-01 ditunda sesuai keputusan Project Lead. Deployment produksi tetap memerlukan konfigurasi dan penilaian risiko pada Bagian 14–15.
**Basis:** `QueueController`, `QueueService` terbaru dan dua DTO Queue; source Display/Socket.IO termasuk `PatientRealtimeGateway` dan `PatientInvalidationInterceptor`; Authentication; Reservasi; Tiket/QR/Check-In; empat controller Administrasi; serta controller, DTO dan service Dokter, JadwalPraktik, SlotPraktik dan JanjiTemu. Isi branch/commit terbaru tetap merupakan sumber kebenaran jika ada perbedaan.

## 1. Ruang lingkup dan batas dokumentasi

Dokumen ini menjelaskan endpoint yang benar-benar tampak pada `QueueController`, `DisplayController`, `AuthController`, `ReservasiController`, `TiketController`, `QrController`, `CheckInController`, empat controller Administrasi dan empat controller Hospital; bentuk `SnapshotAntrean`, `DisplaySnapshot`, `QueueUpdatedEvent`, dan `DisplayUpdatedEvent`; serta alur autentikasi dan sinkronisasi frontend.

Berkas `MasukAntreanDto`, `PanggilBerikutnyaDto`, dan `QueueService` versi unggahan 12 Oktober 2026 **sudah ditinjau**; bentuk request dan respons mutasi Queue didokumentasikan berdasarkan implementasi. Dokumentasi Tiket Digital, penerbitan QR, Check-In, Reservasi, dan administrasi dari v0.6 tetap dipertahankan. Tambahan verifikasi `auth.types.ts`, `jwt.strategy.ts`, `current-user.decorator.ts`, dan `users.service.ts` memastikan respons `GET /auth/me`, pemeriksaan sesi, dan peran registrasi. Verifikasi constraint Prisma/infrastruktur tetap pekerjaan terpisah sebelum produksi.

Contoh UUID, nomor tiket, tanggal, dan nama layanan di bawah merupakan **data ilustratif** yang mengikuti struktur tipe, bukan rekaman respons server.

## 2. Konvensi dasar

| Aspek                            | Kontrak yang diketahui                                                        |
| -------------------------------- | ----------------------------------------------------------------------------- |
| Basis REST lokal                 | `http://localhost:3000/api/v1` bila `API_PORT` memakai nilai default          |
| Global prefix                    | `/api/v1`                                                                     |
| Konten request operasi           | JSON dengan `Content-Type: application/json`                                  |
| Endpoint antrean PETUGAS         | Access token JWT pada `Authorization: Bearer <access_token>`                  |
| Endpoint Public Display          | Cookie perangkat HttpOnly (Bagian 20) atau token pada `x-display-token: <token_perangkat>`                     |
| Namespace Socket.IO operasional  | `/queue`                                                                      |
| Namespace Socket.IO monitor      | `/display`                                                                    |
| Namespace Socket.IO pasien       | `/patient` — JWT USER dan sesi aktif, tanpa join dari klien                     |
| Skema snapshot dan event         | `versiSkema: 1`                                                               |
| Format waktu pada contoh payload | ISO 8601; tanggal pelayanan dipisahkan sebagai `YYYY-MM-DD`                   |
| Model update realtime            | Event menandakan perubahan; baca ulang snapshot REST sebagai sumber kebenaran |

**Keamanan:** jangan menulis JWT atau token perangkat ke URL, log aplikasi, sistem analitik, atau berkas repository. Konfigurasi origin yang diizinkan harus disesuaikan untuk Web dan kiosk. CORS bukan autentikasi.

## 3. Matriks akses yang didukung sumber

Matriks berikut mempertahankan tiga role existing; aturan role DOKTER baru, endpoint portal dan pengecualiannya dijelaskan pada Bagian 19.

| Kanal/operasi                                                                         | PETUGAS                                            | ADMIN                   | USER                                | Perangkat Display                    |
| ------------------------------------------------------------------------------------- | -------------------------------------------------- | ----------------------- | ----------------------------------- | ------------------------------------ |
| `GET /queue/snapshot`, `GET /queue/menunggu`, dan seluruh mutasi di `QueueController` | Diizinkan sesuai penugasan dan pemeriksaan service | Ditolak controller      | Ditolak controller                  | Tidak dipakai                        |
| Socket.IO `/queue`                                                                    | JWT valid dan izin room                            | JWT valid dan izin room | Ditolak                             | Tidak dipakai                        |
| Socket.IO `/patient`                                                                  | Ditolak                                            | Ditolak                 | JWT USER + sesi aktif milik sendiri | Ditolak                              |
| `GET /display/:layananId/snapshot`                                                    | Bukan jalur akun                                   | Bukan jalur akun        | Bukan jalur akun                    | Token perangkat + status/layanan sah |
| Socket.IO `/display`                                                                  | Bukan jalur akun                                   | Bukan jalur akun        | Bukan jalur akun                    | Token perangkat + `layananId` sah    |
| Reservasi `POST/GET`                                                                  | Ditolak                                            | Ditolak                 | JWT dan scope milik sendiri         | Tidak dipakai                        |
| Tiket `GET`, penerbitan QR `POST`                                                     | Ditolak                                            | Ditolak                 | JWT dan tiket milik sendiri         | Tidak dipakai                        |
| `POST /check-in`                                                                      | JWT, QR, jadwal, dan penugasan valid               | Ditolak                 | Ditolak                             | Tidak dipakai                        |
| `GET /layanan`, `/loket`, `/jadwal-layanan` (daftar/detail)                           | Aktif saja (termasuk layanan induk)                | Semua termasuk nonaktif | Aktif saja (termasuk layanan induk) | Tidak dipakai                        |
| `POST/PATCH/DELETE /layanan`, `/loket`, `/jadwal-layanan`                             | Ditolak                                            | Diizinkan               | Ditolak                             | Tidak dipakai                        |
| `GET /penugasan-petugas` (daftar/detail)                                              | Hanya milik sendiri (termasuk nonaktif)            | Semua penugasan         | Ditolak                             | Tidak dipakai                        |
| `POST/PATCH/DELETE /penugasan-petugas`                                                | Ditolak                                            | Diizinkan               | Ditolak                             | Tidak dipakai                        |

Pemeriksaan hak akses pada guard tidak menggantikan validasi domain di service. Data penugasan dari GET bisa meliputi periode lampau atau nonaktif, sehingga izin operasional harus divalidasi kembali oleh backend ketika tindakan dilakukan.

## 4. REST: operasi antrean petugas (diverifikasi sampai service dan DTO)

Seluruh route pada tabel memakai prefix `/api/v1`. `QueueController` menggunakan `AuthGuard('jwt')`, memeriksa peran **PETUGAS**, dan menyerahkan pemeriksaan penugasan dan status domain kepada `QueueService`. Semua operasi `POST` menetapkan HTTP **200 OK** pada keberhasilan; `GET` mengembalikan HTTP 200. `tiketId` di path dan `loketId` di query menggunakan `ParseUUIDPipe({ version: '4' })`; dua DTO body di bawah menggunakan `@IsUUID('4')`.

| Method | Path                                   | Aksi                             | Input                                           |
| ------ | -------------------------------------- | -------------------------------- | ----------------------------------------------- |
| `POST` | `/queue/:tiketId/masuk`                | ENQUEUE `CHECK_IN → MENUNGGU`    | Path `tiketId` UUID v4 + body `loketId` UUID v4 |
| `GET`  | `/queue/menunggu?loketId=<uuid-v4>`    | FIFO menunggu pada layanan loket | Query `loketId` UUID v4                         |
| `GET`  | `/queue/snapshot?loketId=<uuid-v4>`    | Snapshot dashboard/reconnect     | Query `loketId` UUID v4                         |
| `POST` | `/queue/panggil`                       | CALL FIFO berikutnya             | Body `loketId` UUID v4                          |
| `POST` | `/queue/:tiketId/panggil-ulang`        | RECALL tiket yang dipanggil      | Path `tiketId` + body `loketId`                 |
| `POST` | `/queue/:tiketId/lewati`               | SKIP tiket yang dipanggil        | Path `tiketId` + body `loketId`                 |
| `POST` | `/queue/:tiketId/antre-ulang`          | REQUEUE ke akhir FIFO            | Path `tiketId` + body `loketId`                 |
| `POST` | `/queue/:tiketId/mulai-pelayanan`      | START pelayanan                  | Path `tiketId` + body `loketId`                 |
| `POST` | `/queue/:tiketId/selesaikan-pelayanan` | COMPLETE pelayanan               | Path `tiketId` + body `loketId`                 |

### 4.1 DTO request Queue

Kedua DTO, `MasukAntreanDto` dan `PanggilBerikutnyaDto`, mempunyai **satu field wajib dengan tipe dan validasi identik**, yaitu `loketId: string` berformat UUID v4. Dengan `ValidationPipe` aplikasi (`whitelist`, `forbidNonWhitelisted`, `transform`), field tak dikenal tidak dapat ditambahkan ke body yang sah.

```http
POST /api/v1/queue/33333333-3333-4333-8333-333333333333/masuk HTTP/1.1
Authorization: Bearer <access_token_petugas>
Content-Type: application/json

{"loketId":"11111111-1111-4111-8111-111111111111"}
```

Contoh yang sama berlaku untuk operasi `panggil`, `panggil-ulang`, `lewati`, `antre-ulang`, `mulai-pelayanan`, dan `selesaikan-pelayanan`; hanya path yang berubah. Tidak ada body `tiketId` untuk operasi yang menggunakannya di URL. Validasi `loketId` milik petugas tetap dilakukan di service—UUID sah belum berarti petugas berhak atas loket.

### 4.2 Contoh permintaan snapshot PETUGAS

```http
GET /api/v1/queue/snapshot?loketId=11111111-1111-4111-8111-111111111111 HTTP/1.1
Authorization: Bearer <access_token>
```

### 4.3 Kontrak JSON `SnapshotAntrean`

```json
{
  "versiSkema": 1,
  "diperolehPada": "2026-10-12T08:10:00.000Z",
  "tanggalPelayanan": "2026-10-12",
  "layanan": {
    "id": "22222222-2222-4222-8222-222222222222",
    "kode": "LAY-A",
    "nama": "Layanan A"
  },
  "loketPeminta": {
    "id": "11111111-1111-4111-8111-111111111111",
    "kode": "01",
    "nama": "Loket 01"
  },
  "menunggu": {
    "total": 1,
    "ditampilkan": 1,
    "tiket": [
      {
        "tiketId": "33333333-3333-4333-8333-333333333333",
        "nomorAntrean": "A-025",
        "status": "MENUNGGU",
        "urutanMasukAntrean": 25,
        "masukAntreanPada": "2026-10-12T08:05:00.000Z",
        "versi": 1
      }
    ]
  },
  "loket": [
    {
      "id": "11111111-1111-4111-8111-111111111111",
      "kode": "01",
      "nama": "Loket 01",
      "tiketAktif": [
        {
          "tiketId": "44444444-4444-4444-8444-444444444444",
          "nomorAntrean": "A-024",
          "status": "DIPANGGIL",
          "urutanMasukAntrean": 24,
          "versi": 2,
          "dipanggilPada": "2026-10-12T08:09:00.000Z",
          "pelayananDimulaiPada": null
        }
      ]
    }
  ]
}
```

**Aturan rendering:**

- `menunggu.total` dapat lebih besar daripada jumlah elemen `menunggu.tiket`, karena daftar ditampilkan dapat dibatasi oleh service. Gunakan `menunggu.ditampilkan` untuk jumlah elemen yang dikirim.
- `loket[].tiketAktif` adalah array, bukan objek tunggal. Frontend harus tetap dapat menampilkan beberapa tiket aktif jika kondisi database memilikinya.
- `versi` pada tiket dapat dipakai untuk mengenali state yang lebih baru pada tiket sama; jangan disamakan dengan `versiSkema`.
- `masukAntreanPada`, `dipanggilPada`, `pelayananDimulaiPada`, dan `urutanMasukAntrean` dapat `null` sebagaimana tipe resminya.
- Snapshot operasional tidak menyertakan data pribadi dalam tipe responsnya.

### 4.4 `GET /queue/menunggu`: daftar FIFO ringkas

Aturan FIFO di bagian ini berlaku untuk `ANTREAN_HARIAN`. Mode Hospital memakai selector slot/sesi serta metadata kelayakan pada Bagian 17; field existing, respons array, dan batas 100 tetap dipertahankan.

Service mengembalikan **array**, bukan objek terbungkus. Semua entri berasal dari tiket `MENUNGGU` untuk **layanan yang terkait dengan loket petugas**, pada tanggal pelayanan saat ini, diurutkan berdasarkan `urutanMasukAntrean ASC` kemudian `id ASC`, dengan batas **100 entri**. Ini bukan pagination dan tidak mencakup `total` keseluruhan; gunakan `/queue/snapshot` jika dashboard membutuhkan `menunggu.total`.

```json
[
  {
    "tiketId": "33333333-3333-4333-8333-333333333333",
    "nomorAntrean": "A-025",
    "status": "MENUNGGU",
    "urutanMasukAntrean": 25,
    "masukAntreanPada": "2026-10-12T08:05:00.000Z"
  }
]
```

`masukAntreanPada` dapat `null` pada tipe data yang dibaca, meski alur ENQUEUE normal mengisinya. Daftar ini **tidak** mengembalikan `versi`, berbeda dengan snapshot.

### 4.5 Matriks transisi dan kontrak respons POST

| Aksi     | Status awal → akhir     | Detail response spesifik; semua juga memuat `tiketId`, `layananId`, `nomorAntrean`, `status`                                                           |
| -------- | ----------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| ENQUEUE  | `CHECK_IN → MENUNGGU`   | `urutanMasukAntrean`, `masukAntreanPada`. **Tidak ada** `versi`/`loketId` pada hasil langsung                                                          |
| CALL     | `MENUNGGU → DIPANGGIL`  | `loketId`, `kodeLoket`, `urutanMasukAntrean`, `dipanggilPada`, `versi`                                                                                 |
| RECALL   | `DIPANGGIL → DIPANGGIL` | `loketId`, `kodeLoket`, `urutanMasukAntrean`, `dipanggilPada` (CALL pertama), `dipanggilUlangPada`, `versi`                                            |
| SKIP     | `DIPANGGIL → DILEWATI`  | `loketId`, `kodeLoket`, `urutanMasukAntrean`, `dipanggilPada` (CALL pertama), `dilewatiPada`, `versi`                                                  |
| REQUEUE  | `DILEWATI → MENUNGGU`   | `loketId: null`, `loketSebelumnya`, `urutanMasukSebelumnya`, `urutanMasukAntrean` (baru), `masukAntreanPada`, `dipanggilPada: null`, `versi`           |
| START    | `DIPANGGIL → DILAYANI`  | `loketId`, `kodeLoket`, `urutanMasukAntrean`, `dipanggilPada`, `pelayananDimulaiPada`, `versi`                                                         |
| COMPLETE | `DILAYANI → SELESAI`    | `loketId`, `kodeLoket`, `urutanMasukAntrean`, `pelayananDimulaiPada`, `pelayananSelesaiPada`, `versi`; `dipanggilPada` **tidak** ada di hasil langsung |

Semua timestamp dihasilkan sebagai string ISO 8601 oleh service. `versi` pada operasi selain ENQUEUE adalah nilai versi tiket **setelah kenaikan 1**. `nomorAntrean` dibentuk dari prefix layanan + nomor reservasi ber-padding minimal tiga angka. `urutanMasukAntrean` adalah urutan FIFO terpisah; jangan mengurutkan berdasarkan `nomorAntrean`.

**Contoh respons ENQUEUE** — `POST /queue/:tiketId/masuk` (200):

```json
{
  "tiketId": "33333333-3333-4333-8333-333333333333",
  "layananId": "22222222-2222-4222-8222-222222222222",
  "nomorAntrean": "A-025",
  "status": "MENUNGGU",
  "urutanMasukAntrean": 25,
  "masukAntreanPada": "2026-10-12T08:05:00.000Z"
}
```

**Contoh respons CALL** — `POST /queue/panggil` (200):

```json
{
  "tiketId": "33333333-3333-4333-8333-333333333333",
  "layananId": "22222222-2222-4222-8222-222222222222",
  "loketId": "11111111-1111-4111-8111-111111111111",
  "kodeLoket": "01",
  "nomorAntrean": "A-025",
  "status": "DIPANGGIL",
  "urutanMasukAntrean": 25,
  "dipanggilPada": "2026-10-12T08:10:00.000Z",
  "versi": 4
}
```

**Contoh respons RECALL** — `POST /queue/:tiketId/panggil-ulang` (200):

```json
{
  "tiketId": "33333333-3333-4333-8333-333333333333",
  "layananId": "22222222-2222-4222-8222-222222222222",
  "loketId": "11111111-1111-4111-8111-111111111111",
  "kodeLoket": "01",
  "nomorAntrean": "A-025",
  "status": "DIPANGGIL",
  "urutanMasukAntrean": 25,
  "dipanggilPada": "2026-10-12T08:10:00.000Z",
  "dipanggilUlangPada": "2026-10-12T08:11:00.000Z",
  "versi": 5
}
```

**Contoh respons SKIP** — `POST /queue/:tiketId/lewati` (200):

```json
{
  "tiketId": "33333333-3333-4333-8333-333333333333",
  "layananId": "22222222-2222-4222-8222-222222222222",
  "loketId": "11111111-1111-4111-8111-111111111111",
  "kodeLoket": "01",
  "nomorAntrean": "A-025",
  "status": "DILEWATI",
  "urutanMasukAntrean": 25,
  "dipanggilPada": "2026-10-12T08:10:00.000Z",
  "dilewatiPada": "2026-10-12T08:12:00.000Z",
  "versi": 6
}
```

**Contoh respons REQUEUE** — `POST /queue/:tiketId/antre-ulang` (200):

```json
{
  "tiketId": "33333333-3333-4333-8333-333333333333",
  "layananId": "22222222-2222-4222-8222-222222222222",
  "nomorAntrean": "A-025",
  "status": "MENUNGGU",
  "loketId": null,
  "loketSebelumnya": "11111111-1111-4111-8111-111111111111",
  "urutanMasukSebelumnya": 25,
  "urutanMasukAntrean": 31,
  "masukAntreanPada": "2026-10-12T08:13:00.000Z",
  "dipanggilPada": null,
  "versi": 7
}
```

**Contoh respons START** — `POST /queue/:tiketId/mulai-pelayanan` (200), ilustrasi alur normal tiket lain:

```json
{
  "tiketId": "44444444-4444-4444-8444-444444444444",
  "layananId": "22222222-2222-4222-8222-222222222222",
  "loketId": "11111111-1111-4111-8111-111111111111",
  "kodeLoket": "01",
  "nomorAntrean": "A-026",
  "status": "DILAYANI",
  "urutanMasukAntrean": 26,
  "dipanggilPada": "2026-10-12T08:14:00.000Z",
  "pelayananDimulaiPada": "2026-10-12T08:15:00.000Z",
  "versi": 5
}
```

**Contoh respons COMPLETE** — `POST /queue/:tiketId/selesaikan-pelayanan` (200):

```json
{
  "tiketId": "44444444-4444-4444-8444-444444444444",
  "layananId": "22222222-2222-4222-8222-222222222222",
  "loketId": "11111111-1111-4111-8111-111111111111",
  "kodeLoket": "01",
  "nomorAntrean": "A-026",
  "status": "SELESAI",
  "urutanMasukAntrean": 26,
  "pelayananDimulaiPada": "2026-10-12T08:15:00.000Z",
  "pelayananSelesaiPada": "2026-10-12T08:20:00.000Z",
  "versi": 6
}
```

**Catatan:** seluruh ID, nomor urut, waktu, dan nilai versi di atas hanya ilustrasi. Field dan status berasal dari objek `return` dalam metode `QueueService`, bukan hasil panggilan HTTP live.

### 4.6 Aturan FIFO, penugasan, dan transaksi

Aturan FIFO berikut merupakan baseline mode `ANTREAN_HARIAN`. Perbedaan Hospital pada CHECK_IN, ENQUEUE, CALL dan HOSP-OPS-01 dijelaskan di Bagian 17. START/COMPLETE tetap memakai State Machine existing agar akhir sesi tidak mengunci pelayanan yang telah dipanggil/dimulai.

1. **ENQUEUE:** tiket harus `CHECK_IN`, memiliki `checkInPada`, belum mempunyai `urutanMasukAntrean`, berasal dari tanggal pelayanan hari ini, dan memiliki layanan serta jadwal aktif. PETUGAS harus aktif dan ditugaskan pada loket yang berada dalam layanan tiket. Service menggunakan counter `urutanMasukTerakhir` untuk mengalokasikan FIFO secara atomik. `CHECK_IN` dan `ENQUEUE` adalah **dua request dan dua transaksi berbeda**.
2. **CALL:** memilih satu tiket `MENUNGGU` dengan urutan paling kecil **untuk layanan**, tidak terbatas pada loket tempat check-in. Loket tidak boleh memiliki tiket `DIPANGGIL` atau `DILAYANI` pada tanggal hari ini. Tidak ada tiket menunggu menghasilkan `404`, bukan respons kosong. Service memeriksa jadwal **aktif pada hari tersebut**, tetapi **tidak membandingkan jam saat ini dengan jamBuka/jamTutup** pada metode Queue; validasi jam ada di QR Check-In.
3. **RECALL:** hanya dari status `DIPANGGIL` dan loket asal yang sama; status tetap, versi naik, waktu CALL pertama tidak diganti. `dipanggilUlangPada` berasal dari waktu request ini dan audit `RECALL`, bukan kolom waktu CALL pertama.
4. **SKIP:** dari `DIPANGGIL` menjadi `DILEWATI` pada loket yang sama. Tiket tidak kembali ke FIFO tanpa REQUEUE. `dipanggilPada` dipertahankan dalam database.
5. **REQUEUE:** hanya tiket `DILEWATI` di loket asal oleh petugas yang berwenang; **nomor antrean tidak berubah**, tetapi mendapat urutan FIFO terbaru; status kembali `MENUNGGU`, `loketId` dan `dipanggilPada` direset menjadi `null`.
6. **START:** dari `DIPANGGIL` menjadi `DILAYANI`, mencatat `pelayananDimulaiPada`. Tidak boleh memiliki waktu pelayanan sebelumnya.
7. **COMPLETE:** dari `DILAYANI` menjadi `SELESAI`, mencatat `pelayananSelesaiPada`, sehingga loket dapat memanggil tiket berikutnya.

Mutasi berlangsung dalam Prisma `$transaction` dengan isolation `Serializable`; perubahan status/versi dan catatan audit dilakukan dalam transaksi yang sama. Permintaan bersamaan dikendalikan melalui update kondisional status dan `versi`. Untuk `P2034`, service melakukan **hingga tiga percobaan**, lalu mengembalikan konflik (`409`) bila tetap gagal. Broadcast Socket.IO dilakukan **setelah commit**, bersifat _best effort_, dan kegagalannya tidak membatalkan perubahan database. Karena itu frontend harus menyinkronkan kembali melalui REST Snapshot.

### 4.7 Error Queue dan penanganan frontend

| Kondisi                                                                                   | HTTP yang berasal dari controller/service | Perilaku UI                                                     |
| ----------------------------------------------------------------------------------------- | ----------------------------------------- | --------------------------------------------------------------- |
| JWT hilang/tidak valid, identitas tak lengkap                                             | `401`                                     | Re-auth / refresh sekali secara aman                            |
| Pengguna bukan PETUGAS, penugasan loket tidak sesuai                                      | `403`                                     | Hentikan operasi; arahkan pemilihan loket sesuai hak akses      |
| `tiketId` / `loketId` bukan UUID v4                                                       | `400`                                     | Validasi input dan jangan retry otomatis                        |
| Tiket tidak ditemukan, CALL tanpa tiket MENUNGGU                                          | `404`                                     | Sinkronkan snapshot dan tampilkan antrean kosong                |
| Status tidak sesuai transisi, jadwal tidak aktif, loket sibuk, konflik update/serialisasi | `409`                                     | Muat snapshot terbaru dan evaluasi ulang tindakan sebelum retry |

**Jangan melakukan blind retry** terhadap mutasi akibat timeout jaringan. Jawaban HTTP mungkin hilang sesudah transaksi berhasil. Ambil snapshot terlebih dahulu dan gunakan `tiketId`, `status`, `versi`, `urutanMasukAntrean`, dan loket terkait untuk menentukan apakah perubahan sudah terjadi. Tidak ada `idempotencyKey` pada kedua DTO Queue yang telah diperiksa. Data yang tidak terlihat di snapshot terbatas 100 entri memerlukan pemeriksaan lain yang sah; jangan menyimpulkan tiket tak ada hanya karena tidak masuk daftar pertama.

### 4.8 Pedoman Dashboard PETUGAS dan realtime

- Setelah koneksi `/queue` diterima dan `queue:join` berhasil, lakukan `GET /queue/snapshot?loketId=...`. Pada setiap `queue:updated` atau reconnect, lakukan refresh snapshot. Event `queue:updated` bukan respons operasi dan tidak menjamin semua field respons REST tersedia.
- Tombol **Panggil** hanya aktif ketika tidak ada tiket `DIPANGGIL`/`DILAYANI` pada loket dan antrean layanan masih menunggu. Jika ada konflik tetap percayai server.
- Tombol **Panggil Ulang / Lewati / Mulai Pelayanan / Selesaikan** mengikuti status tiket aktif loket. Tiket dilewati tidak tersedia dalam `snapshot.loket[].tiketAktif` (snapshot memuat hanya `DIPANGGIL`/`DILAYANI`), sehingga aksi **Antre Ulang** pada tiket `DILEWATI` memerlukan rujukan tiket yang berwenang dari hasil SKIP atau data sumber lain; jangan mengarang endpoint daftar DILEWATI.
- Saat RECALL, TTS perlu memperhatikan event `RECALL` walaupun status tetap `DIPANGGIL`; Public Display memakai sinyal pembaruan dan identitas peristiwa pengumuman untuk menghindari duplikasi.

## 5. REST: Public Display

### 5.1 Endpoint

Alur utama TV kini aktivasi kode sekali pakai dan cookie HttpOnly pada Bagian 20. Header berikut tetap didukung sebagai kompatibilitas token existing; Monitor V3 menambahkan proyeksi nama dan daftar menunggu pada Bagian 25.

```http
GET /api/v1/display/:layananId/snapshot HTTP/1.1
x-display-token: <token_perangkat>
```

- `layananId`: UUID v4.
- Token perangkat harus berbentuk 64 karakter heksadesimal. Service membandingkan hash SHA-256 token terhadap perangkat yang terdaftar, memeriksa bahwa perangkat aktif, layanan aktif, dan keduanya cocok.
- Controller mengatur `Cache-Control: no-store` untuk snapshot.
- Token kosong atau salah menyebabkan penolakan autentikasi; perangkat yang tidak berwenang untuk layanan ditolak.

### 5.2 Kontrak JSON `DisplaySnapshot`

```json
{
  "versiSkema": 1,
  "tanggalPelayanan": "2026-10-12",
  "diperolehPada": "2026-10-12T08:10:10.000Z",
  "layanan": { "kode": "LAY-A", "nama": "Layanan A" },
  "totalMenunggu": 3,
  "modeNama": "SAMAR",
  "menunggu": [
    { "nomorAntrean": "A-026", "namaPasien": "Pasien A." },
    { "nomorAntrean": "A-027", "namaPasien": "Pasien B." },
    { "nomorAntrean": "A-028", "namaPasien": "Pasien C." }
  ],
  "loket": [
    {
      "kode": "01",
      "nama": "Loket 01",
      "tiketAktif": [
        {
          "nomorAntrean": "A-025",
          "namaPasien": "Pasien P.",
          "status": "DIPANGGIL",
          "dipanggilPada": "2026-10-12T08:10:00.000Z"
        }
      ]
    }
  ],
  "pengumumanTerakhir": {
    "peristiwaId": "55555555-5555-4555-8555-555555555555",
    "aksi": "CALL",
    "terjadiPada": "2026-10-12T08:10:00.000Z",
    "nomorAntrean": "A-025",
    "kodeLoket": "01",
    "namaPasien": "Pasien P.",
    "teks": "Panggilan nomor antrean A, nol dua lima atas nama Pasien P., silakan menuju ke Layanan A, terima kasih.",
    "bahasa": "id-ID"
  }
}
```

`pengumumanTerakhir` dapat bernilai `null`. Dalam implementasi service yang ditinjau, pemilihan pengumuman menggunakan peristiwa audit CALL/RECALL terkait tiket yang **masih DIPANGGIL** dan loket aktif pada tanggal pelayanan. Setelah tiket beralih ke DILAYANI, pengumuman lama tidak harus terus tersedia.

**Pembatasan data:** respons monitor tidak mengandung `tiketId`, ID akun, nomor telepon, QR, JWT, atau token perangkat. `namaPasien` merupakan proyeksi sesuai kebijakan server, default disamarkan; mode lengkap memerlukan konfigurasi eksplisit fasilitas (Bagian 25). Contoh nama di atas adalah ilustrasi kontrak.

## 6. Socket.IO: kanal operasional `/queue`

Pada contoh TypeScript, `API_ORIGIN` adalah variabel konfigurasi frontend yang berisi origin backend, misalnya `http://localhost:3000`, **bukan** nama environment backend yang sudah dipastikan tersedia.

### 6.1 Handshake

Klien mengirim JWT akses melalui properti autentikasi Socket.IO:

```ts
const socket = io(`${API_ORIGIN}/queue`, {
  autoConnect: false,
  auth: { token: accessToken },
});
```

Namespace `/queue` mengizinkan JWT role ADMIN/PETUGAS pada handshake. Bergabung ke room tetap memerlukan pemeriksaan kewenangan. Pengguna USER dan DOKTER tidak boleh bergabung. Versi terbaru penerapan keamanan juga membatasi Origin dan percobaan handshake.

### 6.2 Join dan leave

| Arah                  | Event           | Payload / balasan                                                                                                             |
| --------------------- | --------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| Client → server       | `queue:join`    | `{ "layananId": "<uuid-v4>" }`                                                                                                |
| Server → client (ACK) | hasil join      | `{ "ok": true, "layananId": "<uuid-v4>" }` atau `{ "ok": false, "kode": "INVALID_REQUEST" \| "UNAUTHORIZED" \| "FORBIDDEN" }` |
| Client → server       | `queue:leave`   | `{ "layananId": "<uuid-v4>" }`                                                                                                |
| Server → client (ACK) | hasil leave     | Bentuk ACK sama                                                                                                               |
| Server → client       | `queue:updated` | `QueueUpdatedEvent`                                                                                                           |

`queue:join` mensyaratkan objek yang hanya berisi properti `layananId`, bukan properti bebas lain.

### 6.3 Kontrak event `queue:updated`

```json
{
  "versiSkema": 1,
  "eventId": "66666666-6666-4666-8666-666666666666",
  "terjadiPada": "2026-10-12T08:10:00.000Z",
  "aksi": "CALL",
  "layananId": "22222222-2222-4222-8222-222222222222",
  "tiketId": "44444444-4444-4444-8444-444444444444",
  "nomorAntrean": "A-025",
  "status": "DIPANGGIL",
  "loketId": "11111111-1111-4111-8111-111111111111",
  "kodeLoket": "01",
  "urutanMasukAntrean": 25,
  "versi": 2
}
```

`aksi` hanya: `ENQUEUE`, `CALL`, `RECALL`, `SKIP`, `REQUEUE`, `START`, `COMPLETE`. Field `loketId`, `kodeLoket`, `urutanMasukAntrean`, dan `versi` opsional; jangan mewajibkannya pada semua event. `loketId` dan `urutanMasukAntrean` juga dapat bernilai `null`.

**Penting:** event ini merupakan notifikasi _best effort_, bukan catatan perubahan persisten. Frontend melakukan refresh REST Snapshot setelah event, bukan bergantung pada event sebagai database lokal final.

### 6.4 Kanal pasien `/patient`

Kanal ini terpisah dari `/queue` dan `/display`. Hubungkan ke origin backend (tanpa `/api/v1`) dengan `auth: { token: accessToken }`. Hanya JWT akses USER dengan akun aktif dan sesi yang belum dicabut/kedaluwarsa diterima. Token refresh, token display, ADMIN/PETUGAS, JWT kedaluwarsa dan Origin Web asing ditolak. Pembatasan handshake per namespace/IP juga berlaku. Koneksi native tanpa Origin tetap memerlukan JWT sah.

Tidak ada event join/subscribe dari klien: server menentukan pengguna dari JWT dan sesi. Mengirim `penggunaId`, `tiketId`, atau nama room tidak memberikan akses tambahan. Semua perangkat USER yang sama dapat menerima invalidasi tiketnya; USER lain tidak menerima invalidasi tiket tersebut.

| Arah | Event | Payload |
| --- | --- | --- |
| Server → USER terautentikasi | `patient:ready` | `{ "versiSkema": 1 }` |
| Server → USER pemilik | `patient:updated`, jenis `TIKET` | Bentuk minimal di bawah |
| Server → semua USER terautentikasi | `patient:updated`, jenis `KATALOG` | Bentuk minimal di bawah |

```json
{
  "versiSkema": 1,
  "eventId": "66666666-6666-4666-8666-666666666666",
  "jenis": "TIKET",
  "terjadiPada": "2026-10-17T08:10:00.000Z"
}
```

Event **tidak** membawa status, ID/nomor tiket, identitas pasien, QR, atau token. `terjadiPada` adalah timestamp UTC ISO 8601, bukan waktu slot lokal. Dedup berdasarkan `eventId`, lalu baca ulang REST dengan JWT sendiri: `GET /tiket/saya`, `GET /janji-temu`, dan `GET /tiket/:id` bila detail terbuka. Otorisasi kepemilikan REST tetap berlaku. Jenis `KATALOG` memicu pembacaan ulang layanan/dokter serta jadwal/slot yang sedang dipilih; jangan menganggap seluruh katalog ada di event.

Invalidasi diterbitkan setelah operasi HTTP berhasil dan promise transaksi existing selesai commit. Reservasi, booking dan pembatalan appointment mengirim `TIKET` ke pemilik serta `KATALOG` untuk kapasitas/ketersediaan. CHECK_IN dan seluruh mutasi antrean mengirim `TIKET` ke pemilik tiket hasil operasi. Mutasi ADMIN layanan/dokter/relasi dokter, ruang, jam layanan, jadwal praktik dan slot mengirim `KATALOG`. Kegagalan transaksi tidak menghasilkan invalidasi; kegagalan pengiriman tidak membatalkan transaksi yang telah tersimpan. Tidak ada perubahan response REST, state machine, algoritma prioritas, audit atau migration.

Sesi kandidat diperiksa ulang secara batch sebelum pengiriman. Sesi dicabut, akun nonaktif/berubah role atau JWT kedaluwarsa diputus; kegagalan pemeriksaan database menahan event dan memutus koneksi kandidat. Pada kedaluwarsa JWT, refresh lewat REST lalu buat koneksi dengan token akses terbaru. Logout harus menutup socket. Tidak ada data pribadi yang dikirim sambil menunggu pemeriksaan berikutnya karena payload hanya invalidasi.

Flutter memakai satu koneksi per halaman pasien yang dibagi dengan dialog tiket; debounce 250 ms, dedup maksimal 256 event, dan pembacaan REST terserialisasi dengan satu pembacaan susulan bila terjadi invalidasi saat fetch. Saat realtime terputus, fallback foreground berjalan setiap 30 detik; saat terhubung, rekonsiliasi REST setiap dua menit. Saat kembali dari background/reconnect/rotasi token, baca ulang REST. Background tidak menjalankan fallback. Nilai ini adalah interval sinkronisasi teknis, bukan aturan toleransi keterlambatan atau fairness antrean.

**Batas deployment:** sinyal best effort, tanpa replay/outbox, berlaku pada socket lokal proses NestJS. Mutasi internal yang memanggil service langsung di luar HTTP tidak otomatis menerbitkan kanal pasien. Deployment multi-instance memerlukan distribusi invalidasi lintas proses sebelum menjanjikan realtime menyeluruh; fallback REST tetap diperlukan. Kanal PETUGAS dan Public Display mempertahankan kontrak sebelumnya.

## 7. Socket.IO: Public Display `/display`

### 7.1 Handshake dan ready

```ts
const socket = io(`${API_ORIGIN}/display`, {
  autoConnect: false,
  auth: { token: displayToken, layananId },
});
```

Koneksi yang sah bergabung ke room layanan secara otomatis. Tidak ada event `display:join` terpisah. Setelah tergabung, backend mengirim:

```json
{ "versiSkema": 1, "layananId": "22222222-2222-4222-8222-222222222222" }
```

Nama event: **`display:ready`**.

**Alternatif sesi kiosk (Bagian 20):** `io(API_ORIGIN + '/display', {transports:['websocket'], withCredentials:true, auth:{layananId}})`. Browser mengirim cookie host API secara otomatis; jangan membaca cookie atau memasukkan token ke URL/auth JavaScript. Namespace, room, `display:ready` dan `display:updated` sama seperti jalur token existing.

### 7.2 Event `display:updated`

```json
{
  "versiSkema": 1,
  "eventId": "77777777-7777-4777-8777-777777777777",
  "layananId": "22222222-2222-4222-8222-222222222222",
  "terjadiPada": "2026-10-12T08:12:00.000Z",
  "aksi": "RECALL",
  "perluPeriksaPengumuman": true
}
```

`perluPeriksaPengumuman` bernilai `true` untuk CALL dan RECALL; untuk aksi lain `false`. Sinyal tidak membawa identitas pribadi atau nomor antrean. **Setiap `display:updated` tetap boleh memicu snapshot**, bahkan ketika flag pengumuman `false`.

## 8. Pola sinkronisasi awal dan reconnect

### Dashboard PETUGAS

1. Daftarkan listener Socket.IO dan fungsi refresh **sebelum** membuka koneksi.
2. Buka namespace `/queue` dengan access token aktif.
3. Setelah tersambung, kirim `queue:join` untuk `layananId` sesuai penugasan dan pastikan ACK `ok: true`.
4. Setelah ACK diterima, ambil `GET /queue/snapshot?loketId=...`.
5. Pada setiap `queue:updated` dalam layanan tersebut, tandai data kotor (_dirty_) dan ambil snapshot baru.
6. Setelah `disconnect` lalu `connect` lagi, ulangi `queue:join` dan snapshot. Jika JWT/sesi dicabut, hentikan reconnect otomatis dan minta autentikasi ulang.

### Public Display

1. Daftarkan handler `display:ready` dan `display:updated` sebelum `connect()`.
2. Buka namespace `/display` dengan `auth: { token, layananId }`.
3. Setelah menerima `display:ready`, ambil `GET /display/:layananId/snapshot` dengan token perangkat pada header.
4. Pada `display:updated`, refresh snapshot dan periksa apakah `pengumumanTerakhir.peristiwaId` merupakan peristiwa baru.
5. Setelah koneksi putus dan tersambung kembali, tunggu `display:ready` berikutnya lalu ambil snapshot.
6. Jika token perangkat dicabut/diputar, hentikan reconnect menggunakan token lama dan lakukan provisioning ulang secara aman.

### Menghindari _race condition_

Event bisa tiba saat fetch snapshot berjalan. Jangan mengizinkan respons dari fetch lama menimpa snapshot lebih baru. Gunakan satu fetch aktif per layanan dan penanda _dirty_ untuk memicu fetch tambahan setelah permintaan sebelumnya selesai. Setelah koneksi baru berhasil, registrasi/otorisasi Socket.IO dilakukan sebelum snapshot awal agar jendela kehilangan pembaruan lebih kecil.

Perubahan yang dilewatkan selama offline tidak disediakan sebagai log replay. **REST Snapshot tetap sumber kebenaran**.

## 9. TTS Browser berbahasa Indonesia

Backend menghasilkan `pengumumanTerakhir` dengan `peristiwaId`, `aksi`, `teks`, dan `bahasa: "id-ID"`. Frontend menggunakan Web Speech API atau mesin suara platform.

Aturan yang disarankan untuk frontend:

1. Setelah bootstrap/refresh awal, simpan `peristiwaId` terakhir sebagai baseline. Jangan langsung membacakan pengumuman historis.
2. Setelah `display:updated` aksi CALL/RECALL, ambil snapshot. Ucapkan teks hanya jika `peristiwaId` **berbeda** dari yang terakhir berhasil dijadwalkan/diputar dan event masih relevan.
3. Toleransi `pengumumanTerakhir: null`. Jangan membuat teks sendiri dengan tebakan nomor antrean.
4. Hindari antrean suara bertumpuk; tetapkan kebijakan cancel/queue secara eksplisit di aplikasi.
5. Perhatikan batasan browser: TTS otomatis dapat memerlukan interaksi awal pengguna untuk mengaktifkan audio.
6. Simpan deduplikasi yang aman untuk tampilan kiosk jika perlu. **Jangan** menyimpan token perangkat sebagai bagian dari data deduplikasi.

`peristiwaId` adalah ID peristiwa audit. `eventId` pada sinyal realtime adalah ID notifikasi, **bukan pengganti** `peristiwaId` untuk menentukan pengulangan pengumuman.

## 10. REST: Authentication dan manajemen sesi (terverifikasi)

Semua path pada tabel berikut diawali `/api/v1`. Operasi autentikasi menggunakan JSON. `register`, `login`, `refresh`, dan `logout` menerima data melalui body. Token untuk endpoint `me` dikirim pada header `Authorization: Bearer <access_token>`.

| Method | Path             | Body              | Status sukses                                       | Throttle per IP / route\*                      |
| ------ | ---------------- | ----------------- | --------------------------------------------------- | ---------------------------------------------- |
| `POST` | `/auth/register` | `RegisterDto`     | `201` (default NestJS untuk POST tanpa `@HttpCode`) | 3 permintaan / 60 detik                        |
| `POST` | `/auth/login`    | `LoginDto`        | `200`                                               | 5 permintaan / 60 detik                        |
| `GET`  | `/auth/me`       | Tidak ada         | `200`                                               | Tidak dipasang ThrottlerGuard pada handler ini |
| `POST` | `/auth/refresh`  | `RefreshTokenDto` | `200`                                               | 10 permintaan / 60 detik                       |
| `POST` | `/auth/logout`   | `RefreshTokenDto` | `200`                                               | 30 permintaan / 60 detik                       |

_Angka throttle berasal dari dekorator `@Throttle` pada controller. Identitas kunci pelacakan permintaan mengikuti konfigurasi `ThrottlerGuard` / infrastruktur aktual. Bila proxy berada di depan API, konfigurasi `trust proxy` harus diperiksa sebelum mengandalkan identifikasi IP._

### 10.1 Register

**DTO input `RegisterDto`:**

| Field       | Tipe     | Validasi                                   |
| ----------- | -------- | ------------------------------------------ |
| `nama`      | `string` | wajib; panjang 3–150 karakter              |
| `email`     | `string` | wajib; format email; maksimal 150 karakter |
| `kataSandi` | `string` | wajib; panjang 8–72 karakter               |

```http
POST /api/v1/auth/register HTTP/1.1
Content-Type: application/json

{
  "nama": "Contoh Pengguna",
  "email": "contoh@example.com",
  "kataSandi": "ContohSandiKuat123!"
}
```

Contoh **struktur** respons sukses (nilai ilustratif):

```json
{
  "id": "11111111-1111-4111-8111-111111111111",
  "nama": "Contoh Pengguna",
  "email": "contoh@example.com",
  "peran": "USER"
}
```

`register()` mengubah email ke huruf kecil, merapikan spasi awal/akhir pada nama dan email, membuat hash kata sandi, lalu mengembalikan `id`, `nama`, `email`, `peran`. **`UsersService.create()` secara eksplisit menetapkan `peran: 'USER'`**, sehingga nilai `USER` pada contoh sesuai kontrak registrasi saat ini. Endpoint register tidak menyediakan field untuk memilih peran ADMIN/PETUGAS. Mekanisme provisioning akun ADMIN/PETUGAS tidak dapat ditentukan dari berkas yang telah diperiksa; jangan menganggap register dapat dipakai untuk itu. Email yang sudah terdaftar menghasilkan `409 Conflict`.

### 10.2 Login

**DTO input `LoginDto`:**

| Field           | Tipe     | Validasi                                      |
| --------------- | -------- | --------------------------------------------- |
| `email`         | `string` | wajib; format email                           |
| `kataSandi`     | `string` | wajib; tidak ada panjang minimum di DTO login |
| `namaPerangkat` | `string` | opsional; maksimal 150 karakter               |

```http
POST /api/v1/auth/login HTTP/1.1
Content-Type: application/json

{
  "email": "contoh@example.com",
  "kataSandi": "ContohSandiKuat123!",
  "namaPerangkat": "QueueB Android"
}
```

Respons sukses **berstruktur** berikut. Token dibuat contoh dan tidak bisa digunakan:

```json
{
  "accessToken": "<access-token-jwt>",
  "refreshToken": "<refresh-token-jwt>",
  "user": {
    "id": "11111111-1111-4111-8111-111111111111",
    "nama": "Contoh Pengguna",
    "email": "contoh@example.com",
    "peran": "USER"
  }
}
```

Login memverifikasi pengguna aktif dan kata sandinya. Jika kredensial atau status pengguna tidak memenuhi syarat, service melempar `UnauthorizedException` (HTTP 401). Setelah berhasil, server membuat ID sesi baru, menyimpan **hash SHA-256 refresh token** beserta masa berlaku sesi, serta mengembalikan pasangan token. `namaPerangkat` dicatat pada sesi jika dikirim. Tidak ada `expiresIn` atau `sessionId` sebagai field respons dari `AuthService` ini.

### 10.3 Current user (`/auth/me`)

```http
GET /api/v1/auth/me HTTP/1.1
Authorization: Bearer <access_token>
```

`GET /auth/me` dijaga oleh `JwtAuthGuard`. `JwtStrategy.validate()` mengambil pengguna dan sesi dari database; pengguna harus ada dan aktif, sedangkan sesi harus sesuai pengguna, belum dicabut, dan belum kedaluwarsa. Dekorator `@CurrentUser()` mengembalikan `request.user` yang diisi hasil validasi strategi tersebut.

**Kontrak respons HTTP 200 — objek langsung, bukan `{ "user": { ... } }`:**

```json
{
  "id": "11111111-1111-4111-8111-111111111111",
  "nama": "Contoh Pengguna",
  "email": "contoh@example.com",
  "peran": "USER"
}
```

Bentuknya mengikuti `AuthenticatedUser` yang berisi empat field: `id`, `nama`, `email`, dan `peran`. **Berbeda dari login dan refresh**, yang mengembalikan objek profil di dalam properti `user` bersama dua token. Nilai respons contoh bersifat ilustratif.

Jika access token salah/kedaluwarsa atau sesi dicabut/tidak valid, autentikasi ditolak (`401`). **Peran efektif dibaca dari record pengguna yang terbaru di database**, bukan sekadar mempercayai klaim `role` yang pernah disimpan saat JWT diterbitkan. Hal ini penting bila peran akun diubah oleh administrator.

### 10.4 Refresh token (rotasi wajib)

**DTO `RefreshTokenDto`:** `refreshToken` wajib bertipe string dengan panjang minimal 1 karakter.

```http
POST /api/v1/auth/refresh HTTP/1.1
Content-Type: application/json

{
  "refreshToken": "<refresh-token-lama>"
}
```

Respons sukses memiliki **struktur yang sama seperti login**, yakni `accessToken`, `refreshToken`, dan objek `user` dengan `id`, `nama`, `email`, `peran`.

**Perilaku server yang harus diikuti frontend:**

1. Memverifikasi tanda tangan JWT refresh, klaim `type: refresh`, `sub`, `sid`, dan `jti`.
2. Memeriksa sesi yang belum dicabut dan belum kedaluwarsa, kecocokan pengguna, serta pengguna masih aktif.
3. Memastikan hash refresh token yang digunakan cocok dengan hash yang tersimpan.
4. Menerbitkan access token baru dan **refresh token baru**. Pembaruan hash refresh token memakai `updateMany` dengan kondisi perbandingan hash lama dan sesi aktif, sehingga satu token lama hanya dapat menang dalam satu proses rotasi serentak.
5. Jika rotasi tidak berhasil, service mengembalikan kesalahan autentikasi (`401`), bukan pasangan token baru.

**Aturan klien:** setelah respons 200, ganti **kedua token** secara bersamaan pada penyimpanan kredensial. Hindari beberapa proses refresh paralel; gunakan satu refresh yang sedang berjalan (_single-flight_) agar request lain menunggu hasil yang sama. Jika refresh ditolak, bersihkan kredensial lokal dan minta pengguna masuk lagi.

### 10.5 Logout (pencabutan sesi)

```http
POST /api/v1/auth/logout HTTP/1.1
Content-Type: application/json

{
  "refreshToken": "<refresh-token-terbaru>"
}
```

Respons sukses:

```json
{ "message": "Logout berhasil" }
```

Server memverifikasi refresh token, menemukan sesi yang sesuai, membandingkan hash token, kemudian mencatat `dicabutPada`. Klien harus menghapus access dan refresh token lokal sesudah respons berhasil serta memutus koneksi Socket.IO terkait. `logout` bukan endpoint yang menggunakan header access token dalam controller ini; refresh token dikirim melalui body.

### 10.6 Klaim token dan aturan durasi

Klaim yang dibuat di `AuthService`:

| Jenis token   | Klaim aplikasi                                        |
| ------------- | ----------------------------------------------------- |
| Access token  | `sub` (ID pengguna), `sid` (ID sesi), `email`, `role` |
| Refresh token | `sub`, `sid`, `type: 'refresh'`, `jti`                |

JWT library menambahkan klaim waktu seperti `iat`/`exp` sesuai operasi tanda tangan dan pengaturan masa berlaku. Server membaca `JWT_ACCESS_EXPIRES_IN` dan `JWT_REFRESH_EXPIRES_IN` dari konfigurasi. Pada `env.validation.ts` yang ditinjau sebelumnya, nilai default masing-masing adalah `15m` dan `7d`, tetapi nilai lingkungan deployment dapat berbeda. Jangan mengasumsikan umur token dari respons login karena tidak ada field durasi di responsnya.

**Relasi token dan identitas HTTP:** access token memuat klaim `role`, tetapi objek `AuthenticatedUser` berisi `peran` dari record pengguna saat `JwtStrategy.validate()` dijalankan. Jangan memperlakukan field `role` di payload JWT sebagai izin mutlak: keputusan akses tetap berada pada guard dan service backend. Refresh token digunakan untuk rotasi atau logout, bukan untuk header `Authorization` endpoint `/auth/me`.

**Penyimpanan kredensial yang dianjurkan:**

- Web: pertimbangkan pola BFF atau cookie `HttpOnly`, `Secure`, `SameSite` dengan proteksi CSRF bila arsitektur diubah untuk mendukung cookie. **Authentication pengguna tetap mengirim JWT melalui JSON; cookie HttpOnly pada Bagian 20 khusus perangkat display, tidak mengubah sesi akun.** Untuk frontend yang memakai mekanisme sekarang, hindari menyimpan refresh token dalam `localStorage` jika memungkinkan.
- Android Flutter: gunakan penyimpanan rahasia platform, misalnya Keychain/Keystore melalui paket secure storage yang ditinjau keamanannya. Jangan tulis JWT ke log, analytics, atau URL.
- Setelah refresh token diputar, buat ulang autentikasi Socket.IO `/queue` bila token akses lama kedaluwarsa atau socket perlu reconnect.
- Pesan `401` dari login/refresh bukan bukti pengguna tidak berwenang pada layanan. Bedakan kegagalan autentikasi dengan `403` akses penugasan atau layanan.

### 10.7 Validasi, status error, dan cakupan yang belum dipastikan

| Kondisi                                                           | Hasil berdasarkan sumber                                                                                           |
| ----------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| Body tidak lolos DTO                                              | Ditolak oleh global `ValidationPipe` yang sudah diaktifkan; bentuk lengkap error belum ditetapkan sebagai kontrak  |
| Email saat register sudah ada                                     | `409 Conflict`                                                                                                     |
| Login salah / pengguna tidak aktif                                | `401 Unauthorized`                                                                                                 |
| Refresh invalid, kedaluwarsa, pernah digunakan, atau sesi dicabut | `401 Unauthorized` pada jalur yang ditunjukkan service                                                             |
| Logout dengan token atau sesi tidak valid                         | `401 Unauthorized`                                                                                                 |
| Rate limit terlampaui                                             | `ThrottlerGuard` terpasang; biasanya HTTP `429`, tetapi format respons harus diverifikasi dengan API yang berjalan |

**Sudah terverifikasi pada v1.0:** bentuk `GET /auth/me`, peran registrasi `USER`, dan pemeriksaan pengguna/sesi melalui `JwtStrategy`. Nilai enum peran yang digunakan di bagian ini adalah yang tampak dari controller dan service (`ADMIN`, `PETUGAS`, `USER`); daftar enum Prisma lengkap dan provisioning non-USER tidak diaudit sebagai bagian dari dokumen ini.

**Masih perlu diverifikasi sebelum produksi:** detail serializer/filter error global, kebijakan `trust proxy`, pengaturan cookie apabila frontend beralih ke BFF/cookie, dan tes keamanan pada deployment aktual.

### 10.8 Aturan integrasi Web dan Flutter yang terverifikasi

1. **Saat login:** simpan pasangan token secara aman dan baca profil dari `response.user`; `response.user.peran` dapat dipakai menentukan navigasi awal, tetapi izin operasi tetap divalidasi server.
2. **Saat aplikasi dibuka ulang:** setelah access token tersedia, gunakan `GET /auth/me` untuk mengambil profil terkini. JSON responsnya adalah profil **langsung**, bukan `response.user`. Jangan mengharapkan token baru pada `/auth/me`.
3. **Saat access token tidak berlaku:** lakukan paling banyak satu proses rotasi refresh yang berjalan bersamaan (_single-flight_), lalu simpan pasangan token **baru**. Request yang perlu retry harus memperhatikan sifat operasi (khususnya POST antrean/reservasi yang tidak terbukti idempoten).
4. **Saat logout:** kirim refresh token terakhir melalui body `POST /auth/logout`; setelah sukses, bersihkan kredensial lokal dan putuskan koneksi realtime. Jika server menolak token, klien tetap harus menghapus kredensial lokal yang tidak dapat dipakai dengan aman.
5. **Saat peran berubah:** data `JwtStrategy.validate()` berasal dari database. Segarkan profil `/auth/me` dan navigasi bila akses sudah berubah; tangani `403` dari endpoint domain dengan baik. Jangan menganggap akun yang dibuat melalui register bisa menjadi PETUGAS atau ADMIN tanpa mekanisme provisioning terpisah.

**Tipe profil untuk frontend (konseptual, sesuai `AuthenticatedUser`):**

```ts
type ProfilPengguna = {
  id: string;
  nama: string;
  email: string;
  peran: "ADMIN" | "PETUGAS" | "USER";
};

// login / refresh: response.user adalah ProfilPengguna
// GET /auth/me: response langsung adalah ProfilPengguna
```

Contoh union peran di atas sesuai peran yang dipakai dalam controller aplikasi yang sudah direview; bukan klaim bahwa enum Prisma tidak dapat memiliki nilai lain.

## 11. REST: Reservasi pengguna (`USER`, terverifikasi)

Kontrak di bagian ini bersumber dari `reservasi.controller.ts`, `reservasi.service.ts`, dan `dto/create-reservasi.dto.ts`. Semua path diawali `/api/v1`. Controller menerapkan `JwtAuthGuard`, `RolesGuard`, dan `@Roles(PeranPengguna.USER)` di tingkat kelas. `penggunaId` diperoleh dari identitas JWT lewat `@CurrentUser()`, **bukan dari body atau query**. Pengambilan riwayat/detail dibatasi menurut pemilik reservasi. Respons sukses tidak menyertakan `tokenQrHash`.

### 11.1 Daftar endpoint

| Method | Path             | Tujuan                                                | Body / parameter                              | Sukses yang berlaku                              |
| ------ | ---------------- | ----------------------------------------------------- | --------------------------------------------- | ------------------------------------------------ |
| `POST` | `/reservasi`     | Membuat reservasi untuk layanan pada tanggal tertentu | `CreateReservasiDto`                          | HTTP `201` default NestJS; objek tiket reservasi |
| `GET`  | `/reservasi`     | Riwayat reservasi milik pengguna login                | Tidak ada body                                | HTTP `200`; array reservasi                      |
| `GET`  | `/reservasi/:id` | Detail reservasi berdasarkan ID, khusus pemilik       | Path `id` yang diparse dengan `ParseUUIDPipe` | HTTP `200`; objek reservasi                      |

Akses token JWT dikirim pada `Authorization: Bearer <access_token>`. `POST /reservasi` **tidak** memiliki rate limit khusus yang dideklarasikan pada controller yang ditinjau. Jangan menganggap endpoint ini tidak memiliki pembatasan di lapisan lain tanpa memeriksa deployment.

### 11.2 DTO untuk membuat reservasi

| Field            | Tipe     | Aturan                                                                                                                                   |
| ---------------- | -------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| `layananId`      | `string` | Wajib, UUID versi 4 (`@IsUUID('4')`)                                                                                                     |
| `tanggalAntrean` | `string` | Wajib, pola tepat `YYYY-MM-DD`; service memeriksa tanggal kalender benar dan bukan hari yang telah lewat berdasarkan `SERVICE_TIME_ZONE` |

Tidak ada `penggunaId`, `nomorUrut`, `kodeTiket`, atau `status` pada body. Backend menghasilkan nilainya sendiri. Global `ValidationPipe` menolak properti yang tidak tercantum pada DTO (berdasarkan konfigurasi aplikasi yang telah ditinjau).

**Contoh request (ilustratif):**

```http
POST /api/v1/reservasi HTTP/1.1
Authorization: Bearer <access_token>
Content-Type: application/json

{
  "layananId": "22222222-2222-4222-8222-222222222222",
  "tanggalAntrean": "2026-10-15"
}
```

Tanggal pelayanan merupakan **tanggal kalender pada zona waktu layanan**, bukan timestamp yang dikirim klien. Jangan mengubahnya ke tanggal lokal browser yang mungkin bergeser karena offset UTC. Backend menyimpan hari tersebut sebagai representasi tanggal pukul `00:00:00.000Z` pada `tanggalAntrean`, lalu menggunakan konfigurasi `SERVICE_TIME_ZONE` (default `Asia/Jakarta`) untuk menentukan apakah tanggal sudah lewat.

### 11.3 Bentuk respons reservasi

Ketiga operasi mengembalikan pilihan field tiket yang sama dari `pilihTiket`. Contoh respons sukses berikut hanya memakai nilai ilustratif:

```json
{
  "id": "88888888-8888-4888-8888-888888888888",
  "penggunaId": "11111111-1111-4111-8111-111111111111",
  "layananId": "22222222-2222-4222-8222-222222222222",
  "tanggalAntrean": "2026-10-15T00:00:00.000Z",
  "nomorUrut": 25,
  "kodeTiket": "TK0123456789ABCDEF01234567",
  "status": "DIPESAN",
  "dibuatPada": "2026-10-12T09:00:00.000Z",
  "layanan": {
    "id": "22222222-2222-4222-8222-222222222222",
    "kode": "LAY-A",
    "nama": "Layanan A",
    "prefixAntrean": "A"
  }
}
```

**Perhatian pada identitas tiket:** `kodeTiket` dibuat sebagai `TK` diikuti 24 karakter heksadesimal uppercase acak (total 26 karakter). `nomorUrut` adalah nomor urut numerik. `prefixAntrean` berasal dari layanan. Jangan mengasumsikan `kodeTiket` sama dengan nomor antrean yang ditampilkan kepada pengguna (`A-025` pada contoh antarmuka). Format `nomorAntrean` kini terverifikasi pada `TiketService`: `prefixAntrean.trim() + "-" + String(nomorUrut).padStart(3, "0")`.

Bentuk JSON tanggal saat dikirim melalui NestJS/JSON mengikuti serialisasi `Date` pada Prisma menjadi timestamp ISO. Nama dan enum field di atas berasal dari pemilihan field service; contoh `DIPESAN` adalah status saat reservasi baru dibuat. Daftar nilai status lengkap harus diambil dari model/enum tiket terbaru, bukan ditebak dari contoh.

### 11.4 Membaca riwayat reservasi pengguna

```http
GET /api/v1/reservasi HTTP/1.1
Authorization: Bearer <access_token>
```

Respons adalah array dengan bentuk objek pada §11.3; jika tidak ada reservasi, array kosong. Service mengurutkan menurut `tanggalAntrean` **menurun**, lalu `nomorUrut` **menaik**. Controller tidak menyediakan query pagination atau filter tambahan. Frontend harus siap menangani seluruh array yang dikembalikan, tetapi tidak boleh menganggap paginasi server sudah tersedia.

### 11.5 Membaca satu reservasi

```http
GET /api/v1/reservasi/88888888-8888-4888-8888-888888888888 HTTP/1.1
Authorization: Bearer <access_token>
```

Pencarian selalu menambahkan filter `penggunaId` dari JWT. ID tidak ditemukan atau bukan milik pengguna akan menghasilkan `404 Not Found` dengan pesan `Reservasi tidak ditemukan`. Gunakan `id` tiket dari respons POST/GET sebagai parameter detail.

### 11.6 Aturan bisnis saat POST

1. Tanggal harus sesuai `YYYY-MM-DD`, merupakan tanggal kalender valid, dan tidak mendahului hari ini menurut zona waktu pelayanan.
2. `layananId` harus menunjuk layanan yang ada (`404` jika tidak ditemukan) dan sedang aktif (`400` jika tidak aktif).
3. Layanan harus mempunyai `jadwalLayanan` **aktif** untuk hari yang diminta (`400` jika tidak ada atau tidak aktif).
4. Satu pengguna hanya dapat mempunyai satu tiket dengan status **selain `DIBATALKAN`** pada layanan dan tanggal sama (`409` jika sudah ada).
5. Jumlah tiket yang statusnya **selain `DIBATALKAN`** tidak boleh mencapai `kapasitasHarian` (`409` jika penuh).
6. Nomor harian diambil secara atomik dari `urutanAntreanHarian` lewat `upsert` / `increment`. Tiket baru disimpan dalam status `DIPESAN`.
7. Semua pemeriksaan serta pembuatan tiket berlangsung dalam satu transaksi Prisma dengan isolasi `Serializable`. Konflik `P2034` atau `P2002` dapat diulang sampai **maksimal lima percobaan**, kemudian diubah menjadi `409` bila belum berhasil.

Nomor counter dinaikkan di dalam transaksi. Bila proses yang sama gagal sebelum commit, transaksi mengembalikan perubahan counter juga. Pembatalan reservasi, bila dilakukan melalui modul lain, tidak berarti nomor lama dipakai ulang. Service yang ditinjau belum menjamin nomor antrean selalu tanpa celah.

### 11.7 Error dan UX yang disarankan

| Kasus                                                  | Status menurut source                         | Penanganan frontend                                                |
| ------------------------------------------------------ | --------------------------------------------- | ------------------------------------------------------------------ |
| JWT kosong atau tidak sah                              | Otentikasi ditolak oleh guard (umumnya `401`) | Login atau refresh sesuai jenis kegagalan                          |
| Peran bukan `USER`                                     | Akses ditolak oleh RolesGuard (umumnya `403`) | Tampilkan tidak memiliki akses, jangan retry otomatis              |
| Format UUID/tanggal/body salah                         | `400` dari ValidationPipe atau service        | Tampilkan kesalahan input                                          |
| Tanggal sudah lewat                                    | `400`                                         | Minta tanggal hari ini atau mendatang                              |
| Layanan tidak ditemukan                                | `404`                                         | Muat ulang katalog layanan                                         |
| Layanan tidak aktif atau jadwal tidak aktif            | `400`                                         | Tampilkan alasan dan minta tanggal/layanan lain                    |
| Reservasi aktif ganda pada hari dan layanan sama       | `409`                                         | Tawarkan lihat reservasi yang sudah ada                            |
| Kapasitas harian penuh                                 | `409`                                         | Minta tanggal lain                                                 |
| Konflik serialisasi/unique setelah retry habis         | `409`                                         | Tampilkan opsi mencoba lagi, tanpa otomatis membuat banyak request |
| Detail reservasi bukan milik user atau tidak ditemukan | `404`                                         | Tampilkan tidak ditemukan tanpa mengungkap pemilik lain            |
| Referensi pengguna/layanan gagal (`P2003`/`P2025`)     | `400`                                         | Tampilkan permintaan tidak dapat diproses                          |

**Penting untuk aplikasi Flutter:** jangan mengulangi `POST /reservasi` secara otomatis ketika jaringan terputus **setelah request terkirim tetapi sebelum respons diterima**. Backend belum menunjukkan mekanisme idempotency key. Ambil `GET /reservasi` lebih dahulu untuk memeriksa apakah tiket sudah dibuat, lalu minta konfirmasi pengguna bila hendak mencoba lagi.

**Yang belum termasuk kontrak Reservasi ini:** pembatalan, pilihan jam pelayanan, pagination server, idempotency key, serta bentuk error JSON global yang rinci. Jangan membangun UI berdasarkan asumsi adanya fitur tersebut.

## 12. REST: Tiket Digital, penerbitan QR, dan QR Check-In (terverifikasi)

Kontrak ini diambil dari `TiketController`, `QrController`, `CheckInController`, `TiketService`, `QrService`, `CheckInService`, dan `ProsesCheckInDto`. Semua path diawali `/api/v1`. Contoh data hanya ilustrasi; jangan menganggapnya hasil request server. Penerbitan QR dilakukan oleh USER, sedangkan pemindaian/validasi QR oleh PETUGAS.

### 12.1 Endpoint dan peran

| Method | Path            | Peran          | Status sukses dari controller | Keterangan                                             |
| ------ | --------------- | -------------- | ----------------------------- | ------------------------------------------------------ |
| `GET`  | `/tiket/saya`   | `USER`, JWT    | `200`                         | Seluruh tiket milik pengguna                           |
| `GET`  | `/tiket/:id`    | `USER`, JWT    | `200`                         | Detail tiket milik pengguna, `id` diparse sebagai UUID |
| `POST` | `/tiket/:id/qr` | `USER`, JWT    | `201` default NestJS `POST`   | Terbitkan QR untuk tiket sendiri yang masih `DIPESAN`  |
| `POST` | `/check-in`     | `PETUGAS`, JWT | `200` (`@HttpCode`)           | Verifikasi QR lalu transisi `DIPESAN` → `CHECK_IN`     |

Keempat endpoint menggunakan `JwtAuthGuard` dan `RolesGuard`. Controller QR menggunakan prefix `tiket` yang sama dengan `TiketController`, tetapi memiliki route berbeda. Di level service, pencarian tiket selalu memakai `penggunaId` dari JWT untuk GET tiket dan penerbitan QR. Kode QR bukan identitas akun dan tidak digunakan sebagai token login.

### 12.2 Respons Tiket Digital: `GET /tiket/saya` dan `GET /tiket/:id`

`TiketService` mengambil data dari `ReservasiService`. Ia mempertahankan seluruh field reservasi pada §11.3, kemudian menambahkan `nomorAntrean` dan `tanggalPelayanan`. Respons `GET /tiket/saya` adalah array, sedangkan detail mengembalikan satu objek. Urutan array mengikuti `ReservasiService`: `tanggalAntrean` menurun lalu `nomorUrut` menaik. Tidak ada pagination atau filter tambahan pada controller yang diperiksa.

```http
GET /api/v1/tiket/saya HTTP/1.1
Authorization: Bearer <access_token>
```

**Contoh satu objek tiket** (ilustrasi; GET daftar mengembalikannya di dalam array):

```json
{
  "id": "88888888-8888-4888-8888-888888888888",
  "penggunaId": "11111111-1111-4111-8111-111111111111",
  "layananId": "22222222-2222-4222-8222-222222222222",
  "tanggalAntrean": "2026-10-12T00:00:00.000Z",
  "nomorUrut": 25,
  "kodeTiket": "TK0123456789ABCDEF01234567",
  "status": "DIPESAN",
  "dibuatPada": "2026-10-12T02:00:00.000Z",
  "layanan": {
    "id": "22222222-2222-4222-8222-222222222222",
    "kode": "LAY-A",
    "nama": "Layanan A",
    "prefixAntrean": "A"
  },
  "nomorAntrean": "A-025",
  "tanggalPelayanan": "2026-10-12"
}
```

`nomorAntrean` dibangun di backend dari `layanan.prefixAntrean.trim()` dan `nomorUrut` yang di-_pad_ minimal tiga digit. `tanggalPelayanan` dibuat dari `tanggalAntrean.toISOString().slice(0, 10)`. `kodeTiket` **bukan** `qrPayload`; endpoint ini tidak mengembalikan rahasia QR atau `tokenQrHash`. Tiket yang tidak ditemukan atau bukan milik pengguna ditolak dengan `404` oleh layanan Reservasi yang dipanggil dari TiketService.

### 12.3 Penerbitan QR: `POST /tiket/:id/qr`

```http
POST /api/v1/tiket/88888888-8888-4888-8888-888888888888/qr HTTP/1.1
Authorization: Bearer <access_token>
```

Tidak ada JSON body pada controller penerbitan QR. Tiket harus milik USER terautentikasi, memiliki status `DIPESAN`, dan tanggal antreannya **sama dengan hari pelayanan** menurut `SERVICE_TIME_ZONE`. Default zona waktu service: `Asia/Jakarta` jika variabel tersebut tidak diatur.

**Contoh respons sukses** (token ilustratif dan bukan kredensial aktif):

```json
{
  "tiketId": "88888888-8888-4888-8888-888888888888",
  "qrPayload": "SQ1.qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq",
  "berlakuHingga": "2026-10-12T03:10:00.000Z",
  "masaBerlakuDetik": 600,
  "status": "DIPESAN"
}
```

**Kontrak keamanan QR:**

- Payload literal berupa `SQ1.` ditambah string Base64URL acak sepanjang **43 karakter**, berasal dari 32 byte acak (`randomBytes(32)`), tanpa nama atau informasi pribadi.
- QR berlaku **10 menit (600 detik)** sejak diterbitkan. `berlakuHingga` adalah ISO timestamp; frontend menghitung sisa waktu dari nilai server, tidak mengandalkan hanya timer lokal.
- Backend menyimpan **hash SHA-256 dari seluruh `qrPayload`**, bukan token aslinya. Nilai asli hanya dikembalikan saat penerbitan.
- Penerbitan ulang saat tiket masih `DIPESAN` mengganti `tokenQrHash` dan tanggal kedaluwarsa; QR yang lama tidak lagi sesuai dengan hash pada database.
- Update penerbitan QR menggunakan `updateMany` dengan kondisi `id`, `penggunaId`, `status`, dan `versi` lalu menaikkan `versi`. Konflik konkurensi dikembalikan sebagai `409`.
- `qrPayload` **adalah teks untuk dienkode menjadi gambar QR oleh aplikasi**, bukan gambar PNG/SVG/Base64 gambar yang dikembalikan backend. Jangan menyimpan token ke log, URL, analytics, atau histori biasa.

### 12.4 Check-In QR PETUGAS: `POST /check-in`

```http
POST /api/v1/check-in HTTP/1.1
Authorization: Bearer <access_token_petugas>
Content-Type: application/json

{
  "qrPayload": "SQ1.qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq",
  "loketId": "11111111-1111-4111-8111-111111111111"
}
```

**Validasi `ProsesCheckInDto`:**

| Field       | Tipe   | Aturan                                |
| ----------- | ------ | ------------------------------------- |
| `qrPayload` | string | Pola tepat `^SQ1\.[A-Za-z0-9_-]{43}$` |
| `loketId`   | string | UUID versi 4                          |

`CheckInService` menghitung hash `qrPayload` dan mencari tiket yang memiliki hash tersebut. Check-in hanya diproses jika tiket masih `DIPESAN`, token belum kedaluwarsa, tanggal tiket sesuai hari pelayanan, layanan aktif, petugas masih memiliki penugasan aktif untuk loket/layanan tiket, serta jadwal hari itu aktif. Waktu check-in harus memenuhi **`jamBuka <= waktu lokal < jamTutup`**.

**Contoh respons sukses `200 OK`:**

```json
{
  "tiketId": "88888888-8888-4888-8888-888888888888",
  "layananId": "22222222-2222-4222-8222-222222222222",
  "nomorAntrean": "A-025",
  "status": "CHECK_IN",
  "checkInPada": "2026-10-12T03:05:00.000Z",
  "loketId": "11111111-1111-4111-8111-111111111111",
  "petugasId": "99999999-9999-4999-8999-999999999999"
}
```

Pada transaksi Prisma `Serializable`, service melakukan update kondisional `DIPESAN` → `CHECK_IN`, mengisi `checkInPada` dan `loketId`, **menghapus `tokenQrHash` dan `qrKedaluwarsaPada`**, menaikkan versi, lalu mencatat audit `CHECK_IN` dalam transaksi yang sama. Token yang telah dipakai tidak dapat dipakai lagi. Kegagalan update atau audit membatalkan transaksi.

### 12.5 Pemisahan status Check-In dan antrean

**Jangan langsung mengubah UI menjadi `MENUNGGU` setelah `POST /check-in` berhasil.** Backend masih mengembalikan `status: "CHECK_IN"`. PETUGAS kemudian perlu menjalankan operasi antrean terpisah:

```http
POST /api/v1/queue/88888888-8888-4888-8888-888888888888/masuk HTTP/1.1
Authorization: Bearer <access_token_petugas>
Content-Type: application/json

{
  "loketId": "11111111-1111-4111-8111-111111111111"
}
```

Operasi `masuk` adalah transisi `CHECK_IN` → `MENUNGGU` (ENQUEUE), dengan validasi dan audit Queue Engine. Jika langkah kedua gagal, **jangan menyatakan tiket sudah menunggu**; tampilkan status sebenarnya dan sediakan tindakan petugas untuk mencoba langkah yang belum berhasil dengan aman. Tidak ada bukti bahwa QR Check-In otomatis memanggil `masuk` atau bahwa kedua endpoint berada dalam satu transaksi.

### 12.6 Error dan panduan frontend

| Kasus                                                   | HTTP dari kode terkait          | Perilaku frontend                                                     |
| ------------------------------------------------------- | ------------------------------- | --------------------------------------------------------------------- |
| Tidak terautentikasi atau JWT tidak valid               | Umumnya `401` dari guard        | Arahkan ke login / refresh yang sah                                   |
| Peran salah untuk tiket, QR, atau Check-In              | Umumnya `403` dari `RolesGuard` | Jangan coba operasi dengan peran lain                                 |
| Tiket QR tidak ditemukan atau bukan milik USER          | `404`                           | Jangan tampilkan detail tiket milik akun lain                         |
| QR diminta saat status bukan `DIPESAN`                  | `409`                           | Muat ulang status tiket                                               |
| QR diminta bukan pada hari pelayanan                    | `400`                           | Tampilkan tanggal pelayanan                                           |
| Penerbitan QR bersamaan dan versi berubah               | `409`                           | Refresh tiket sebelum menerbitkan ulang                               |
| Format payload QR atau UUID tidak sah                   | `400` dari ValidationPipe       | Minta scan ulang; jangan modifikasi token                             |
| Token QR tidak ditemukan, sudah digunakan, atau diganti | `400`                           | Tampilkan QR tidak valid; minta QR terbaru jika tiket masih `DIPESAN` |
| Token QR masih tersimpan tetapi waktunya kedaluwarsa    | `410 Gone`                      | USER dapat menerbitkan QR baru jika tiket masih `DIPESAN`             |
| Tiket telah berubah status / konflik update             | `409`                           | Muat ulang tiket dan hindari check-in ganda                           |
| Petugas tidak ditugaskan pada loket dan layanan aktif   | `403`                           | Pilih loket sesuai penugasan                                          |
| Tanggal, layanan, atau jam pelayanan tidak sesuai       | `400`                           | Tampilkan pesan layanan/jadwal                                        |
| Konflik serialisasi PostgreSQL saat check-in            | `409`                           | Periksa status terbaru sebelum retry                                  |

**Panduan Flutter Android:** setelah reservasi dibuat, ambil `GET /tiket/saya` atau `GET /tiket/:id` untuk render kartu tiket. Izinkan USER menerbitkan QR pada hari pelayanan bila status `DIPESAN`. Render gambar QR lokal dari `qrPayload`; tampilkan hitung mundur menggunakan `berlakuHingga` dan opsi terbit ulang bila diperlukan. Setelah QR dipindai, UI PETUGAS menampilkan hasil check-in. Jalankan transisi ENQUEUE secara eksplisit, lalu ambil snapshot untuk memastikan tiket benar-benar masuk FIFO. Jangan melakukan _blind retry_ pada request check-in ketika respons hilang; periksa status tiket terlebih dahulu.

**Batas kontrak:** tidak ada endpoint pembatalan, unduh gambar QR dari backend, atau proses otomatis `CHECK_IN` → `MENUNGGU` dalam controller/service yang ditinjau. Bentuk respons error JSON global yang lengkap masih perlu diverifikasi; validasi `MasukAntreanDto` dan respons ENQUEUE kini telah diperiksa pada §4.

## 13. REST: Administrasi Layanan, Loket, Jadwal, dan Penugasan Petugas (terverifikasi)

Bagian ini diperiksa terhadap **empat controller, delapan DTO, dan empat service** pada 12 Oktober 2026. Semua endpoint mempunyai prefix `/api/v1`, menggunakan `JwtAuthGuard` dan `RolesGuard`, serta menerima JWT lewat `Authorization: Bearer <access_token>`. Data di bawah mengikuti field dan aturan yang benar-benar terlihat pada berkas sumber. Bentuk lengkap model Prisma (misalnya seluruh metadata tanggal) **belum dijamin** tanpa pemeriksaan skema database.

### 13.1 Daftar 20 endpoint dan matriks peran

| Modul     | HTTP     | Route sesudah `/api/v1`  | Diizinkan            | Keterangan                                          |
| --------- | -------- | ------------------------ | -------------------- | --------------------------------------------------- |
| Layanan   | `POST`   | `/layanan`               | ADMIN                | Buat layanan baru                                   |
| Layanan   | `GET`    | `/layanan`               | ADMIN, PETUGAS, USER | ADMIN melihat semua; peran lain hanya layanan aktif |
| Layanan   | `GET`    | `/layanan/:id`           | ADMIN, PETUGAS, USER | Filter `aktif` menurut peran                        |
| Layanan   | `PATCH`  | `/layanan/:id`           | ADMIN                | Ubah sebagian field                                 |
| Layanan   | `DELETE` | `/layanan/:id`           | ADMIN                | Soft delete: `aktif: false`                         |
| Loket     | `POST`   | `/loket`                 | ADMIN                | Buat loket pada layanan aktif                       |
| Loket     | `GET`    | `/loket`                 | ADMIN, PETUGAS, USER | Non-ADMIN hanya loket dan layanan induk aktif       |
| Loket     | `GET`    | `/loket/:id`             | ADMIN, PETUGAS, USER | Filter `aktif` menurut peran                        |
| Loket     | `PATCH`  | `/loket/:id`             | ADMIN                | Ubah sebagian field atau pindah layanan             |
| Loket     | `DELETE` | `/loket/:id`             | ADMIN                | Soft delete: `aktif: false`                         |
| Jadwal    | `POST`   | `/jadwal-layanan`        | ADMIN                | Tambah satu jadwal mingguan                         |
| Jadwal    | `GET`    | `/jadwal-layanan`        | ADMIN, PETUGAS, USER | Non-ADMIN hanya jadwal dan layanan induk aktif      |
| Jadwal    | `GET`    | `/jadwal-layanan/:id`    | ADMIN, PETUGAS, USER | Filter `aktif` menurut peran                        |
| Jadwal    | `PATCH`  | `/jadwal-layanan/:id`    | ADMIN                | Ubah sebagian field, termasuk jam dan kapasitas     |
| Jadwal    | `DELETE` | `/jadwal-layanan/:id`    | ADMIN                | Soft delete: `aktif: false`                         |
| Penugasan | `POST`   | `/penugasan-petugas`     | ADMIN                | Buat penugasan aktif                                |
| Penugasan | `GET`    | `/penugasan-petugas`     | ADMIN, PETUGAS       | ADMIN semua; PETUGAS hanya penugasan sendiri        |
| Penugasan | `GET`    | `/penugasan-petugas/:id` | ADMIN, PETUGAS       | PETUGAS tidak boleh membaca penugasan orang lain    |
| Penugasan | `PATCH`  | `/penugasan-petugas/:id` | ADMIN                | Ubah sebagian field/periode/loket                   |
| Penugasan | `DELETE` | `/penugasan-petugas/:id` | ADMIN                | Soft delete: `aktif: false`                         |

Seluruh `:id` di atas diproses menggunakan `ParseUUIDPipe`. Tidak terdapat endpoint paging/filter query tersendiri dalam empat controller yang ditinjau. `POST` pada empat controller tidak memiliki `@HttpCode` khusus (secara default NestJS mengembalikan 201 pada sukses), sedangkan `GET`, `PATCH`, dan `DELETE` memakai status sukses bawaan NestJS. Tidak ada response envelope khusus yang dideklarasikan di controller-controller tersebut.

**Perhatian untuk menu Petugas:** query `GET /penugasan-petugas` tidak hanya mengembalikan penugasan aktif; service memfilter berdasarkan `petugasId`, bukan `aktif` atau tanggal. Frontend perlu memeriksa `aktif`, `tanggalMulai`, `tanggalSelesai`, dan status loket/layanan ketika menawarkan loket yang siap digunakan. Otorisasi operasi check-in/antrean tetap ditentukan backend, bukan oleh filter frontend.

### 13.2 Layanan — DTO, respons, dan aturan

**Create** `POST /api/v1/layanan`:

| Field              | Tipe          | Aturan create                                          | Aturan PATCH              |
| ------------------ | ------------- | ------------------------------------------------------ | ------------------------- |
| `kode`             | string        | Wajib; regex `^[A-Z0-9]{2,20}$`                        | Opsional, aturan sama     |
| `nama`             | string        | Wajib; 3–150 karakter dan harus mengandung bukan-spasi | Opsional, aturan sama     |
| `deskripsi`        | string / null | Opsional; maksimal 1000 karakter                       | Opsional; `null` diterima |
| `prefixAntrean`    | string        | Wajib; 1–5 huruf kapital                               | Opsional, aturan sama     |
| `durasiDasarMenit` | integer       | Wajib; 1–240 menit                                     | Opsional, aturan sama     |
| `modeReservasi`    | enum string   | Opsional; ANTREAN_HARIAN (default), JANJI_TEMU_DOKTER atau HIBRIDA | Tidak diterima; perubahan mode existing belum tersedia |
| `aktif`            | boolean       | Otomatis `true`, tidak boleh dikirim dalam Create DTO  | Opsional                  |

```http
POST /api/v1/layanan
Authorization: Bearer <access_token_admin>
Content-Type: application/json
```

```json
{
  "kode": "CS01",
  "nama": "Layanan Informasi",
  "deskripsi": "Pelayanan informasi pengunjung",
  "prefixAntrean": "CS",
  "durasiDasarMenit": 10
}
```

`LayananService.create()` menyimpan `nama.trim()`, mengisi `deskripsi` kosong menjadi `null` bila tidak dikirim, `modeReservasi` menjadi ANTREAN_HARIAN bila tidak dikirim, dan `aktif: true`. Mode explicit hanya menerima tiga nilai enum; null atau nilai lain ditolak 400. Respons create/read/update/delete berasal langsung dari objek Prisma `layanan`, termasuk `id`, `modeReservasi`, `dibuatPada` dan `diperbaruiPada`. Request lama tanpa mode tetap kompatibel. ADMIN dapat membuat poli Hospital tanpa SQL manual; perubahan mode poli existing melalui PATCH sengaja tidak dibuka agar tidak mengubah interpretasi tiket yang sudah berjalan.

- `GET /layanan`: diurutkan menurut `kode` naik. ADMIN melihat data aktif maupun nonaktif; non-ADMIN hanya aktif.
- `GET /layanan/:id`: `404` jika ID tidak ditemukan atau, untuk non-ADMIN, layanan tidak aktif.
- `PATCH`: menerima subset field; `nama` dipangkas spasinya sebelum disimpan; ADMIN dapat mengubah `aktif`.
- `DELETE`: **tidak menghapus baris**; mengubah `aktif` menjadi `false` dan mengembalikan data layanan terbarui.
- Error khusus: duplikasi `kode` dari constraint database menghasilkan `409 Conflict` (`P2002`); record tidak ditemukan menghasilkan `404`.

### 13.3 Loket — DTO, relasi layanan, dan aturan

**Create** `POST /api/v1/loket`:

| Field       | Tipe          | Aturan create                                                                                          | Aturan PATCH                                    |
| ----------- | ------------- | ------------------------------------------------------------------------------------------------------ | ----------------------------------------------- |
| `layananId` | UUID v4       | Wajib; layanan harus ada dan aktif                                                                     | Opsional; perpindahan harus ke layanan aktif    |
| `kode`      | string        | Wajib; 2–20 karakter, huruf kapital/angka/tanda hubung antarsegmen; regex `^[A-Z0-9]+(?:-[A-Z0-9]+)*$` | Opsional, aturan sama                           |
| `nama`      | string        | Wajib; 3–100 karakter dan mengandung bukan-spasi                                                       | Opsional, aturan sama                           |
| `lokasi`    | string / null | Opsional; maksimal 150 karakter                                                                        | Opsional; bisa `null` untuk mengosongkan        |
| `aktif`     | boolean       | Otomatis `true`                                                                                        | Opsional; reaktivasi mensyaratkan layanan aktif |

```json
{
  "layananId": "22222222-2222-4222-8222-222222222222",
  "kode": "LK-01",
  "nama": "Loket Informasi Satu",
  "lokasi": "Lantai 1"
}
```

Service melakukan `nama.trim()` serta menyimpan `lokasi` hasil `trim()` atau `null`. Pada create/read/update/delete, objek Loket dari Prisma menyertakan relasi:

```json
{
  "layanan": {
    "id": "22222222-2222-4222-8222-222222222222",
    "kode": "CS01",
    "nama": "Layanan Informasi",
    "aktif": true
  }
}
```

Cuplikan di atas hanya menggambarkan **bagian `layanan` dari respons**, bukan seluruh objek respons Prisma. Loket sendiri memiliki setidaknya `id`, `layananId`, `kode`, `nama`, `lokasi`, dan `aktif` menurut implementasi service; metadata tambahan perlu dicek pada skema.

- `GET /loket`: ADMIN melihat semua; non-ADMIN hanya loket aktif yang layanan induknya aktif. Diurutkan `layananId`, kemudian `kode`, keduanya naik.
- `PATCH`: pemindahan layanan (`layananId`) dan/atau reaktivasi (`aktif: true`) memvalidasi layanan tujuan aktif. Field `lokasi` dapat dihapus dengan `null` atau string kosong.
- `DELETE`: soft delete (`aktif: false`); respons tetap mencakup relasi `layanan`.
- Error khusus: layanan tidak ditemukan `404`, layanan tidak aktif `400`, kode loket duplikat pada layanan `409`, loket tidak ditemukan `404`, relasi database tidak valid `400`.

### 13.4 Jadwal Layanan — DTO dan waktu operasional

**Create** `POST /api/v1/jadwal-layanan`:

| Field             | Tipe    | Aturan create                                                         | Aturan PATCH                      |
| ----------------- | ------- | --------------------------------------------------------------------- | --------------------------------- |
| `layananId`       | UUID v4 | Wajib, layanan harus aktif                                            | Opsional; pindah ke layanan aktif |
| `hari`            | enum    | Wajib; `SENIN`, `SELASA`, `RABU`, `KAMIS`, `JUMAT`, `SABTU`, `MINGGU` | Opsional                          |
| `jamBuka`         | string  | Wajib; jam 24 jam `HH:mm` (`00:00`–`23:59`)                           | Opsional; aturan sama             |
| `jamTutup`        | string  | Wajib; jam 24 jam `HH:mm`                                             | Opsional; aturan sama             |
| `kapasitasHarian` | integer | Wajib; minimal 1, tanpa maksimum eksplisit di DTO                     | Opsional                          |
| `aktif`           | boolean | Otomatis `true`                                                       | Opsional                          |

```json
{
  "layananId": "22222222-2222-4222-8222-222222222222",
  "hari": "SENIN",
  "jamBuka": "08:00",
  "jamTutup": "16:00",
  "kapasitasHarian": 100
}
```

- `jamTutup` harus **lebih akhir** dari `jamBuka`. Jadwal lewat tengah malam tidak didukung aturan saat ini. Ketika PATCH hanya mengubah satu jam, service menggunakan jam lama untuk memvalidasi kombinasi baru.
- Satu layanan tidak boleh memiliki dua jadwal pada hari yang sama; constraint duplikat memunculkan `409 Conflict`.
- Layanan induk wajib aktif saat membuat, memindahkan, atau mengaktifkan kembali jadwal.
- `GET` pada non-ADMIN mengembalikan hanya jadwal aktif dari layanan aktif; ADMIN melihat seluruh jadwal. Daftar diurutkan `layananId` dan `hari` secara urut leksikal enum (`asc`), bukan otomatis Senin–Minggu. Untuk UI, susun hari berdasarkan urutan kalender jika diperlukan.
- `DELETE` adalah soft delete (`aktif: false`), bukan penghapusan fisik.
- Respons Prisma menyertakan relasi `layanan: { id, kode, nama, aktif }` dan field jadwal. `jamBuka` serta `jamTutup` disimpan dalam PostgreSQL `TIME` melalui `Date` Prisma berbasis representasi `1970-01-01T...Z`; **respons serialisasi dapat berbentuk ISO 8601**, bukan `HH:mm` literal. Ketika mengisi kembali formulir PATCH, ambil komponen waktu UTC (`HH:mm`) tanpa konversi timezone perangkat.
- Error: jam salah atau jam tutup tidak lebih akhir `400`, layanan tidak aktif `400`, layanan tidak ditemukan `404`, duplikasi jadwal `409`, jadwal tidak ditemukan `404`.

### 13.5 Penugasan Petugas — DTO Create dan PATCH

**Create** `POST /api/v1/penugasan-petugas`:

| Field            | Tipe          | Aturan create                                                  | Aturan PATCH                              |
| ---------------- | ------------- | -------------------------------------------------------------- | ----------------------------------------- |
| `petugasId`      | UUID v4       | Wajib; pengguna harus berperan `PETUGAS`                       | Opsional; bila diubah, divalidasi kembali |
| `loketId`        | UUID v4       | Wajib; loket dan layanan induk harus aktif                     | Opsional; bila diubah, divalidasi kembali |
| `tanggalMulai`   | string        | Wajib; tanggal kalender valid `YYYY-MM-DD`                     | Opsional; aturan sama                     |
| `tanggalSelesai` | string / null | Opsional; `YYYY-MM-DD` valid atau `null` (tanpa tanggal akhir) | Opsional; `null` menghapus batas akhir    |
| `aktif`          | boolean       | Otomatis `true`                                                | Opsional                                  |

```http
POST /api/v1/penugasan-petugas
Authorization: Bearer <access_token_admin>
Content-Type: application/json
```

```json
{
  "petugasId": "99999999-9999-4999-8999-999999999999",
  "loketId": "11111111-1111-4111-8111-111111111111",
  "tanggalMulai": "2026-10-15",
  "tanggalSelesai": null
}
```

Contoh PATCH memperpanjang penugasan tanpa batas akhir:

```http
PATCH /api/v1/penugasan-petugas/33333333-3333-4333-8333-333333333333
Authorization: Bearer <access_token_admin>
Content-Type: application/json
```

```json
{ "tanggalSelesai": null }
```

DTO memeriksa pola tanggal, sedangkan service memeriksa **validitas tanggal kalender** (misalnya 2026-02-30 ditolak), serta `tanggalSelesai >= tanggalMulai` apabila batas akhir diberikan. Ketiadaan tanggal selesai berarti periode terbuka. Penyimpanan PostgreSQL `DATE` ditangani sebagai `Date` UTC tengah malam; frontend harus menampilkannya sebagai tanggal kalender `YYYY-MM-DD`, bukan menerapkan penyesuaian zona waktu perangkat.

### 13.6 Penugasan Petugas — konflik periode dan scope baca

**Aturan benturan:** satu `PETUGAS` tidak boleh mempunyai dua _penugasan aktif_ dengan periode tanggal yang saling beririsan, **termasuk jika loket berbeda**. Batas tanggal awal/akhir inklusif: periode A berakhir tanggal 20 dan periode B dimulai tanggal 20 tetap dihitung konflik. Penugasan dengan `tanggalSelesai: null` dianggap terbuka hingga tidak terbatas. Saat PATCH untuk penugasan aktif, pemeriksaan konflik mengecualikan ID penugasan yang sedang diperbarui; penugasan nonaktif tidak ikut deteksi bentrok. Pelanggaran memunculkan `409 Conflict` dengan pesan `Petugas sudah memiliki penugasan aktif pada periode tersebut`.

**Cakupan baca:**

- ADMIN (`GET /penugasan-petugas` / `:id`) dapat membaca semua penugasan, termasuk yang nonaktif atau lampau.
- PETUGAS hanya dapat membaca penugasan dengan `petugasId` sesuai ID JWT mereka; penugasan petugas lain tidak terungkap (detail akan mendapat `404`). Daftar petugas **tidak otomatis difilter tanggal/aktif**.
- USER tidak memperoleh akses kedua endpoint ini.
- Daftar diurutkan `tanggalMulai desc`, kemudian `dibuatPada desc`.

Respons dari Prisma mencakup relasi berikut (cuplikan struktur, bukan objek lengkap):

```json
{
  "petugas": {
    "id": "99999999-9999-4999-8999-999999999999",
    "nama": "Petugas Contoh",
    "email": "petugas@example.test",
    "peran": "PETUGAS"
  },
  "loket": {
    "id": "11111111-1111-4111-8111-111111111111",
    "kode": "LK-01",
    "nama": "Loket Informasi Satu",
    "aktif": true,
    "layanan": {
      "id": "22222222-2222-4222-8222-222222222222",
      "kode": "CS01",
      "nama": "Layanan Informasi",
      "aktif": true
    }
  }
}
```

Objek penugasan sendiri memiliki field yang dipakai service seperti `id`, `petugasId`, `loketId`, `tanggalMulai`, `tanggalSelesai`, `aktif`, dan `dibuatPada`. P0 ADMIN menambahkan syarat `peran: PETUGAS` dan `pengguna.aktif: true` pada pembuatan/perubahan penugasan aktif. Penonaktifan penugasan tetap boleh dilakukan ketika akun sudah nonaktif. Objek `petugas` kini juga memuat `aktif`; lihat Bagian 22.

**Error terkait:** pengguna petugas atau loket tidak ditemukan `404`; peran bukan PETUGAS `400`; loket atau layanan induk tidak aktif `400`; tanggal tidak sah/rentang terbalik `400`; konflik jadwal `409`; penugasan tidak ditemukan `404`; relasi/keunikan database dapat menghasilkan `400`/`409` melalui handler. `DELETE` melakukan soft delete dan mengembalikan objek penugasan yang diperbarui dengan relasi-relasinya.

### 13.7 Panduan integrasi Dashboard ADMIN dan PETUGAS

1. **Form administrasi:** gunakan `GET /layanan`, `GET /loket`, `GET /jadwal-layanan`, dan `GET /penugasan-petugas` dengan JWT berperan sesuai matriks, bukan request anonim. Saat membuat Loket/Jadwal/Penugasan, batasi pilihan dropdown ke layanan/loket yang aktif.
2. **Urutan setup:** buat Layanan → Loket dan Jadwal Layanan → Penugasan Petugas. Penugasan harus mengarah ke petugas berperan PETUGAS dan loket/layanan aktif.
3. **Tampilan status:** tombol "Hapus" seharusnya dipahami sebagai _nonaktifkan_. Setelah `DELETE`, periksa `aktif` pada respons dan perbarui tabel lokal. Saat mengaktifkan ulang, gunakan `PATCH` dengan `aktif: true`.
4. **Kelola tanggal:** gunakan kontrol tanggal kalender (`YYYY-MM-DD`) untuk Penugasan, dan jam 24 jam (`HH:mm`) untuk Jadwal. Jangan mengonversi field `DATE` atau `TIME` menjadi waktu lokal pengguna secara sembarang.
5. **Scope Petugas:** setelah login PETUGAS, ambil `GET /penugasan-petugas` dan tampilkan hanya data yang relevan saat ini; jangan menganggap hasil endpoint itu seluruhnya aktif. Semua keputusan final tentang izin room, antrean, dan check-in tetap berada di server.
6. **Penanganan error:** tampilkan kesalahan validasi `400`, tidak ditemukan `404`, konflik `409`, tanpa membuka data milik pengguna lain. Jika konflik penugasan, tampilkan periode bertabrakan kepada ADMIN berdasarkan data yang memang berhak dibaca.

### 13.8 Batas verifikasi administrasi dan catatan QA

- Keempat service melakukan pembatasan akses tambahan saat `GET` dan validasi domain pada mutasi. Pada P0 ADMIN, pemeriksaan benturan dan penyimpanan penugasan disatukan dalam transaksi READ COMMITTED dengan row lock akun petugas. Perubahan penugasan juga mengunci record penugasan; perpindahan petugas mengunci akun lama/baru dalam urutan stabil. Tidak ada perubahan schema atau aturan tanggal. Lihat Bagian 22 dan regresi paralel `admin-management-p0.e2e-spec.ts`.
- Kontrak 20 route, 8 DTO, 4 service, soft delete, dan aturan bisnis sudah diperiksa; metadata model Prisma, format envelope error global, dan kebijakan pagination masih berada di luar lingkup berkas ini.
- Dokumentasi ini **tidak mengubah source code** dan tidak merupakan bukti bahwa seluruh kombinasi administrasi telah diuji ulang.

## 14. Status QA dan batas kesiapan

**Checkpoint regresi terakhir yang disampaikan pengembang:** 424 Unit Test dan 169 E2E, seluruhnya lulus (593/593); lint tanpa warning/error; NestJS build lulus. Angka ini adalah hasil validasi yang dilaporkan dari terminal lokal dan **bukan pengujian ulang** yang dilakukan untuk dokumen ini.

Hal yang masih perlu dituntaskan sebelum deployment produksi: empat temuan _high_ pada dependency Prisma yang belum ditutup; konfigurasi origin dan reverse proxy sesuai domain aktual; pengamanan token display saat provisioning; verifikasi deployment/environment dan pengaturan multi-instance jika diaktifkan. Sebagian perlindungan handshake merupakan limiter memori per instance.

## 15. Batas verifikasi dan pekerjaan sebelum rilis produksi

| Area                                                  | Status v1.0 dan tindak lanjut                                                                                                                      | Dampak                                                                             |
| ----------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------- |
| `/auth/me`, peran default register, validasi sesi JWT | **Terverifikasi** dari empat file Authentication tambahan                                                                                          | Kontrak navigasi dan profil frontend dapat dipakai                                 |
| Skema Prisma dan konkurensi penugasan                 | Periksa `prisma/schema.prisma`, constraint anti-overlap, dan tes request bersamaan                                                                 | Risiko dua penugasan bertabrakan saat request paralel belum ditutup                |
| Dependency produksi                                   | Empat temuan `high` pada jalur Prisma masih terbuka menurut hasil audit terdahulu; evaluasi patch, mitigasi, dan ulangi audit environment produksi | **Blokir keputusan siap produksi** sampai risiko dinilai/diselesaikan secara resmi |
| Konfigurasi deployment                                | Cocokkan CORS/Origin, reverse proxy, IP forwarding/trust proxy, WebSocket handshake limit dan penyimpanan token display                            | Keamanan pada satu instance lokal bukan bukti keamanan deployment produksi         |
| Pengujian kontrak live / error global                 | Jalankan smoke test JWT, status HTTP, rate limit, REST Queue, Socket.IO, dan verifikasi bentuk error pada branch yang akan di-merge                | Dokumen ini berasal dari source review, bukan rekaman HTTP live setiap endpoint    |
| Provisioning akun ADMIN/PETUGAS                       | Mekanisme akun non-USER belum ditelusuri dari sumber yang tersedia                                                                                 | Frontend Admin dan Petugas memerlukan akun berperan tepat sebelum UAT              |

**Kriteria penggunaan:** panduan v1.0 ini merupakan **baseline kontrak untuk mulai mengerjakan frontend**, bukan sertifikasi rilis produksi. Saat membandingkan kontrak dengan server berjalan, utamakan implementasi yang telah diuji dan catat perubahan pada dokumen. Jika ada perubahan source backend setelah checkpoint 593/593, jalankan regresi lagi sebelum merge.

## 16. Peta referensi sumber

| Sumber                                                                                                                                                                | Informasi yang digunakan                                                                                                                                           |
| --------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `src/queue/queue.controller.ts`, `queue.service.ts`, `dto/masuk-antrean.dto.ts`, `dto/panggil-berikutnya.dto.ts`                                                      | Route Queue, UUID v4 `loketId`, RBAC PETUGAS, respons ENQUEUE/CALL/RECALL/SKIP/REQUEUE/START/COMPLETE, FIFO, validasi domain, transaksi dan broadcast pasca-commit |
| `src/queue/queue-snapshot.types.ts`                                                                                                                                   | Kontrak `SnapshotAntrean`                                                                                                                                          |
| `src/display/display.controller.ts`                                                                                                                                   | Route display dan token header                                                                                                                                     |
| `src/display/display-snapshot.types.ts`, `src/display/display.service.ts`                                                                                             | Bentuk snapshot publik, aturan pemilihan pengumuman                                                                                                                |
| `src/realtime/realtime-events.types.ts`                                                                                                                               | Jenis aksi dan `QueueUpdatedEvent`                                                                                                                                 |
| `src/realtime/display-realtime.types.ts`                                                                                                                              | `DisplayReadyEvent` dan `DisplayUpdatedEvent`                                                                                                                      |
| Gateway `/queue` dan `/display` yang tersedia di sesi                                                                                                                 | Room, autentikasi, listener, broadcast                                                                                                                             |
| `src/auth/auth.controller.ts`, `src/auth/auth.service.ts` terbaru                                                                                                     | Route auth, session lifecycle, payload token, error, throttle                                                                                                      |
| `src/auth/auth.types.ts`, `src/auth/jwt.strategy.ts`, `src/auth/decorators/current-user.decorator.ts`, `src/users/users.service.ts`                                   | Bentuk tepat `/auth/me`, pemeriksaan sesi dan pengguna aktif, sumber peran efektif dari DB, registrasi default `USER`                                              |
| `src/auth/dto/register.dto.ts`, `login.dto.ts`, `refresh-token.dto.ts`                                                                                                | Field dan validasi request Authentication                                                                                                                          |
| `src/reservasi/reservasi.controller.ts`, `reservasi.service.ts`, `dto/create-reservasi.dto.ts`                                                                        | Endpoint USER, DTO, kepemilikan data, alokasi nomor harian, respons reservasi, dan penanganan konflik                                                              |
| `src/tiket/tiket.controller.ts`, `tiket.service.ts`                                                                                                                   | Daftar/detail tiket USER, field warisan Reservasi, `nomorAntrean`, `tanggalPelayanan`                                                                              |
| `src/qr/qr.controller.ts`, `qr.service.ts`                                                                                                                            | Penerbitan QR, status dan kepemilikan tiket, format QR, hash, kedaluwarsa, version check                                                                           |
| `src/check-in/check-in.controller.ts`, `check-in.service.ts`, `dto/proses-check-in.dto.ts`                                                                            | Body Check-In, izin penugasan/jadwal, waktu pelayanan, konsumsi token, respons dan error                                                                           |
| `src/layanan/layanan.controller.ts`, `layanan.service.ts`, `dto/create-layanan.dto.ts`, `dto/update-layanan.dto.ts`                                                   | CRUD layanan, filter aktif, kode/prefix/durasi, soft delete, error                                                                                                 |
| `src/loket/loket.controller.ts`, `loket.service.ts`, `dto/create-loket.dto.ts`, `dto/update-loket.dto.ts`                                                             | CRUD loket, validasi layanan aktif, relasi layanan, status dan kode                                                                                                |
| `src/jadwal-layanan/jadwal-layanan.controller.ts`, `jadwal-layanan.service.ts`, `dto/create-jadwal-layanan.dto.ts`, `dto/update-jadwal-layanan.dto.ts`                | CRUD jadwal, jam HH:mm, PostgreSQL TIME, kapasitas, hari, soft delete                                                                                              |
| `src/penugasan-petugas/penugasan-petugas.controller.ts`, `penugasan-petugas.service.ts`, `dto/create-penugasan-petugas.dto.ts`, `dto/update-penugasan-petugas.dto.ts` | CRUD dan scope akses penugasan, tanggal terbuka, interval bentrok, relasi petugas/loket                                                                            |

---

**Riwayat dokumen**

- **v0.1, 12 Oktober 2026:** kontrak inti Queue, Public Display, kedua namespace Socket.IO, dan panduan sinkronisasi/TTS.
- **v0.2, 12 Oktober 2026:** menambahkan kontrak lengkap register, login, refresh dengan rotasi token, logout, `/auth/me` yang ditandai perlu verifikasi bentuk respons, DTO, throttle, contoh payload, dan pedoman penyimpanan kredensial.
- **v0.3, 12 Oktober 2026:** menambahkan kontrak REST Reservasi khusus USER, DTO, contoh request/response, kepemilikan reservasi, zona waktu, kapasitas, konkurensi transaksi, error dan pedoman UX.
- **v0.4, 12 Oktober 2026:** menambahkan kontrak Tiket Digital, QR sekali pakai 600 detik, pemeriksaan dan hasil Check-In, transisi terpisah CHECK_IN → MENUNGGU, serta panduan frontend Flutter dan petugas.
- **v0.5, 12 Oktober 2026:** melengkapi 20 endpoint administrasi dari empat controller, delapan DTO, dan empat service; termasuk RBAC, validasi form, relasi, soft delete, aturan jam/tanggal/konflik penugasan, serta catatan risiko konkurensi.
- **v0.6, 12 Oktober 2026:** verifikasi dua DTO Queue dan `QueueService` terbaru; menambahkan request/respons tujuh mutasi, daftar FIFO, aturan transisi, status HTTP dan penanganan kegagalan, ketentuan timestamp/versi, dan panduan sinkronisasi dashboard.
- **v1.0, 12 Oktober 2026:** verifikasi Authentication akhir (`/auth/me`, `JwtStrategy`, default `USER` dari `UsersService`), pemetaan `role` versus `peran`, panduan navigasi/token frontend, dan daftar batas verifikasi sebelum rilis produksi. Finalisasi baseline integrasi tidak berarti risiko dependency/deployment telah ditutup.
- **v1.1, 14 Oktober 2026:** dokumentasi endpoint Doctor/Practice/Slot/Appointment, kapasitas semua mode, integrasi Hospital dan kebijakan HOSP-OPS-01. Metadata/filter baca disetujui Project Lead; resolusi manual MENUNGGU tetap gap yang tidak diaktifkan tanpa persetujuan tambahan.
- **v1.2, 14 Oktober 2026:** finalisasi Backend MVP untuk integrasi frontend, pilihan mode poli pada POST layanan dan urutan request kedua alur utama. Resolusi manual serta penyempurnaan nonkritis ditunda sesuai instruksi final Project Lead.

## 17. Kontrak Hospital dan HOSP-OPS-01 (Milestone 2)

Dokter tetap merupakan profil master yang dapat berdiri sendiri. Perluasan D1 menambahkan akun opsional dengan role JWT DOKTER; lihat Bagian 19. `Layanan` tetap poli, `Loket` tetap ruang operasional, `JadwalPraktik` merupakan sesi bertanggal, `SlotPraktik` merupakan interval konsultasi, dan `JanjiTemu` terkait satu tiket. Status operasional tetap pada tiket. Semua path berikut memakai `/api/v1` dan JWT.

### 17.1 Endpoint master dan appointment existing

| Method | Path | Akses | Keterangan |
|---|---|---|---|
| POST | /dokter | ADMIN | Body kode, nama, spesialisasi opsional |
| GET | /dokter, /dokter/:id | ADMIN/PETUGAS/USER | Non-ADMIN hanya dokter dengan rantai layanan aktif |
| PATCH | /dokter/:id | ADMIN | Perubahan parsial; aktif dan spesialisasi null didukung |
| DELETE | /dokter/:id | ADMIN | Soft delete |
| GET | /dokter/:id/layanan | ADMIN/PETUGAS/USER | Relasi poli sesuai scope baca |
| POST | /dokter/:id/layanan | ADMIN | Body layananId; upsert/reaktivasi relasi |
| DELETE | /dokter/:id/layanan/:layananId | ADMIN | Nonaktifkan relasi |
| POST | /jadwal-praktik | ADMIN | dokterLayananId, loketId, tanggal, mulaiPada, selesaiPada |
| GET | /jadwal-praktik, /jadwal-praktik/:id | ADMIN/PETUGAS/USER | Filter daftar opsional dokterId, layananId, tanggal |
| PATCH, DELETE | /jadwal-praktik/:id | ADMIN | Jadwal dengan slot tidak boleh digeser/dinonaktifkan |
| POST | /slot-praktik | ADMIN | jadwalPraktikId, mulaiPada, selesaiPada, kapasitas |
| GET | /slot-praktik | ADMIN/PETUGAS/USER | Query jadwalPraktikId wajib |
| GET | /slot-praktik/:id | ADMIN/PETUGAS/USER | Detail dan ketersediaan |
| PATCH, DELETE | /slot-praktik/:id | ADMIN | Slot dengan histori appointment tidak boleh digeser/dinonaktifkan; kapasitas dibatasi jumlah histori |
| POST | /janji-temu | USER | Body slotPraktikId; pemilik dari JWT |
| GET | /janji-temu, /janji-temu/:id | USER | Hanya milik sendiri |
| POST | /janji-temu/:id/batalkan | USER | Hanya DIPESAN milik sendiri; sukses 201, audit dan histori dipertahankan |

GET/PATCH/DELETE sukses 200; POST pada tabel sukses 201. Dokter kode 2–30 karakter `[A-Z0-9-]`, nama 3–150, spesialisasi maksimal 150. Waktu sesi/slot wajib ISO 8601 berzona dan tepat menit penuh; tanggal sesi harus sesuai tanggal lokal `SERVICE_TIME_ZONE`. Sesi harus berada dalam jam poli, dokter/ruang tidak overlap dan slot berada dalam sesi. Referensi UUID dan field asing divalidasi DTO.

POST appointment mengembalikan objek janji dengan `id`, `tiket`, `slotPraktik`, `nomorAntrean`, dan `tanggalPelayanan`. **ID appointment berbeda dari tiket.id**: GET tiket dan penerbitan QR memakai `tiket.id`, pembatalan appointment memakai ID janji. Riwayat tiket existing tetap dapat dibaca melalui `/tiket/saya`; konteks dokter/slot diperoleh melalui `/janji-temu`.

### 17.2 Mode, booking dan ketersediaan

- ANTREAN_HARIAN: POST /reservasi tetap FIFO harian; tidak menerima booking dokter.
- JANJI_TEMU_DOKTER: POST /janji-temu; POST /reservasi ditolak 400.
- HIBRIDA: kedua kanal menerima reservasi dan berbagi nomor serta kuota poli/tanggal.
- **Kedua mode appointment** memeriksa slot/sesi/dokter/relasi/poli/ruang aktif, kesesuaian tanggal/rentang waktu, jadwal poli aktif, kapasitas slot dan kapasitas harian. Booking hanya sebelum awal slot.
- Satu pasien hanya satu tiket non-DIBATALKAN per poli/tanggal, lintas kanal/dokter/slot. Semua tiket non-DIBATALKAN, termasuk SELESAI, dihitung terhadap kuota harian sebagaimana baseline.
- Lock sesi dan slot menggunakan advisory transaction lock bersama. Counter harian, tiket, appointment dan audit dibuat dalam transaksi Serializable; konflik P2034/P2002 di-retry terbatas sebelum 409.
- Slot mengembalikan `jumlahJanjiTemu`, `sisaKapasitas`, `tersedia`. Sisa kapasitas adalah kapasitas **slot**; `tersedia` bisa false walaupun sisa slot positif karena kuota harian penuh, mode tidak menerima appointment, jadwal poli nonaktif/berubah, waktu atau relasi tidak valid.
- Pembacaan slot dan kuota dilakukan dalam satu RepeatableRead snapshot; daftar memakai satu pembacaan kuota per poli/tanggal. Metadata relasi slot kini juga memuat loketId, layananId dan modeReservasi secara aditif.
- Ketersediaan bersifat global dan sementara, bukan jaminan booking personal: POST tetap memeriksa duplikasi pasien, keadaan terbaru dan konkurensi. Tetap hindari blind retry; idempotency key belum tersedia.

### 17.3 QR CHECK_IN dan ENQUEUE Hospital

QR dan DTO existing tetap. USER menerbitkan QR pada hari pelayanan; PETUGAS memindai pada ruang yang ditugaskan. CHECK_IN tetap DIPESAN → CHECK_IN, lalu ENQUEUE terpisah CHECK_IN → MENUNGGU.

Untuk appointment, backend memeriksa rantai slot/sesi/dokter/relasi/poli/ruang, tanggal lokal sesi terhadap tiket, interval slot dalam sesi dan ruang tujuan yang ditetapkan sesi. Sesi yang telah berakhir menolak penerimaan baru. Akhir slot sendiri tidak menolak CHECK_IN/ENQUEUE selama sesi relevan. Check-in sebelum awal sesi/slot diperbolehkan selama jam poli buka; tidak ada toleransi menit tambahan. CALL tetap menunggu awal sesi/slot.

Untuk walk-in HIBRIDA, CHECK_IN memakai otorisasi, tanggal, poli dan jam operasional existing. ENQUEUE Hospital harus dilakukan pada ruang CHECK_IN yang sama. CALL walk-in hanya berjalan bila ruang tersebut memiliki sesi dokter aktif pada tanggal dan waktu pelayanan; tidak mengubah walk-in menjadi appointment.

QR yang gagal validasi tidak dikonsumsi; ENQUEUE yang ditolak tidak menambah counter atau audit. Transaksi, update status/versi kondisional dan audit existing tetap dipertahankan. Ruang appointment salah: 403; konteks Hospital invalid pada CHECK_IN: 400; pada ENQUEUE: 409. Expiry QR tetap 410 dan konflik QR tetap 409.

### 17.4 CALL, daftar menunggu dan alasan ketidaklayakan

Ketiga jalur memakai select/selector Hospital yang sama. Urutan: appointment layak → walk-in layak → kandidat belum/tidak layak; appointment menurut awal slot; lalu waktu REQUEUE terbaru atau CHECK_IN jika belum pernah antre ulang, urutan masuk, dan ID. Prioritas slot tetap dipertahankan sesudah REQUEUE sesuai keputusan Project Lead.

Appointment layak hanya jika check-in, semua relasi aktif/konsisten, tanggal sesuai, ruang sama, sesi berlangsung (`mulaiPada <= sekarang < selesaiPada`), dan slot sudah mulai. Akhir slot bukan kedaluwarsa hak pelayanan. Walk-in membutuhkan sesi aktif yang sesuai pada ruang peminta. Tidak ada kandidat layak menghasilkan 404 meskipun ada tiket MENUNGGU yang belum/tidak layak.

Field aditif pada tiket Hospital di GET /queue/menunggu dan `snapshot.menunggu.tiket[]`:

| Field | Tipe | Arti |
|---|---|---|
| jenisAntrean | JANJI_TEMU atau WALK_IN | Kanal tiket |
| layakDipanggil | boolean | Kelayakan untuk ruang peminta saat snapshot dibaca |
| slotMulaiPada | ISO string atau null | Awal slot appointment |
| alasanTidakLayak | string atau null | null jika layak; kode alasan jika belum/tidak layak |

Kode alasan: BELUM_CHECK_IN, SLOT_BELUM_DIMULAI, SESI_BELUM_DIMULAI, SESI_BERAKHIR, RUANG_BERBEDA, TANGGAL_TIDAK_SESUAI, RELASI_TIDAK_AKTIF, RELASI_TIDAK_SESUAI, JADWAL_TIDAK_VALID, APPOINTMENT_TIDAK_ADA, SESI_WALK_IN_TIDAK_TERSEDIA. Ini metadata API, bukan status/enum database. Tidak semua alasan memerlukan pembatalan; slot mendatang cukup ditunggu. Klien perlu menerima kode baru secara defensif.

Filter baca yang disetujui:

```http
GET /api/v1/queue/menunggu?loketId=<uuid-v4>&hanyaTidakLayak=true
Authorization: Bearer <access_token_petugas>
```

Query opsional menerima true/false literal; tanpa query tetap perilaku daftar default. Filter diterapkan sebelum batas 100 sehingga kandidat tidak layak tidak tersisih oleh kandidat layak. Hanya mode Hospital; pemakaian true pada ANTREAN_HARIAN ditolak 400. JWT dan penugasan tetap wajib. Respons tetap array dengan maksimum 100; bukan pagination. `snapshot.menunggu.total` tetap menghitung seluruh MENUNGGU layanan/tanggal, termasuk yang tidak layak. Field Hospital tidak ditambahkan ke mode harian dan versiSkema tetap 1.

Kelayakan dapat berubah hanya karena waktu berlalu. Tidak ada event persisten khusus batas slot/sesi; klien perlu menyegarkan snapshot ketika batas waktu tercapai atau sebelum memanggil, selain pola event/reconnect existing.

### 17.5 HOSP-OPS-01 dan gap resolusi manual

Appointment MENUNGGU setelah sesi berakhir **tetap MENUNGGU**, tercatat dalam database dan daftar dengan alasan SESI_BERAKHIR. CALL normal tidak mengambilnya dari sesi atau ruang lain. Pembacaan kelayakan tidak mengubah versi/status, tidak membuat audit mutasi semu dan tidak melakukan auto-cancel, reschedule, requeue atau perpindahan hari.

PETUGAS berwenang memeriksa daftar/filter lalu berkoordinasi dengan pasien dan pihak berwenang. Tiket DIPANGGIL/DILAYANI sebelum akhir sesi tetap dapat START/COMPLETE sesuai State Machine dan otorisasi existing; berakhirnya sesi tidak menambahkan penolakan baru pada pelayanan yang telah berjalan.

**Gap belum diselesaikan:** tidak ada mutasi sah untuk menutup MENUNGGU yang tidak dapat dilayani; POST pembatalan existing hanya USER/DIPESAN. PATCH jadwal existing juga melarang perubahan sesi yang sudah memiliki slot. Perluasan pembatalan PETUGAS atau perpanjangan resmi sesi belum disetujui dan belum diimplementasikan. Jangan membuat tombol/aksi frontend berdasarkan usulan ini dan jangan menyatakan resolusi manual telah selesai. Rincian usulan tersedia pada `HOSP_OPS_01_GAP_DAN_USULAN.md`.

### 17.6 Timezone, kompatibilitas dan checklist integrasi

REST Hospital dan otorisasi room Socket.IO menggunakan SERVICE_TIME_ZONE; tanggal PostgreSQL DATE tetap UTC midnight representasi hari kalender. Room PETUGAS tidak lagi mengasumsikan Asia/Jakarta jika konfigurasi layanan berbeda. Konfigurasi timezone merupakan konfigurasi server, bukan nilai bebas dari klien.

Checklist API untuk Web/Flutter, tanpa implementasi frontend:

1. Gunakan role JWT dan penugasan yang tepat; register tetap USER.
2. Pilih alur menurut modeReservasi dari katalog layanan; dokter → jadwal bertanggal → slot tersedia → POST janji-temu, atau POST reservasi untuk walk-in.
3. Gunakan tiket.id untuk QR/tiket dan id appointment untuk pembatalan USER; jangan menukar kedua ID.
4. Tampilkan status aktual CHECK_IN sebelum ENQUEUE berhasil; bedakan akhir slot dari akhir sesi.
5. Refresh snapshot sesudah event/reconnect dan batas waktu; gunakan layakDipanggil serta alasan untuk keputusan tampilan, tetapi backend tetap menentukan izin CALL.
6. Untuk tindak lanjut petugas gunakan filter baca; jangan menganggap tersedia endpoint resolusi manual.
7. Tangani 400/403/404/409/410 dan kemungkinan response hilang sesudah commit; hindari blind retry booking/queue.
8. Public Display, versi snapshot, QR sekali pakai, privacy dan best-effort Socket.IO tetap sesuai baseline. Tidak ada endpoint atau field pasien/medis publik baru.

Temuan dependency historis, reverse proxy/origin, multi-instance Socket.IO, provisioning akun/perangkat dan race administrasi penugasan tetap memerlukan gate rilis terpisah. Mode poli baru sudah dapat ditetapkan ADMIN melalui POST layanan. Backend MVP tidak mengubah dependency/schema/migration atau mengesahkan deployment produksi.

## 18. Urutan integrasi dua alur MVP

Gunakan basis `/api/v1`, header JSON untuk POST, dan Bearer access token sesuai kolom aktor. Semua ID di bawah diperoleh dari respons API, bukan nomor antrean. Tanggal pelayanan adalah tanggal kalender dalam SERVICE_TIME_ZONE. Bagian Authentication menjelaskan bootstrap/login akun, refresh dan pemisahan role; pembuatan akun ADMIN/PETUGAS pertama merupakan provisioning server, bukan register publik dengan pilihan role.

### 18.1 Persiapan data operasional oleh ADMIN

1. `POST /layanan` dengan kode, nama, prefixAntrean, durasiDasarMenit dan modeReservasi. Pilih HIBRIDA untuk poli yang menerima appointment dan walk-in; JANJI_TEMU_DOKTER untuk appointment saja. Simpan `id` sebagai layananId.
2. `POST /jadwal-layanan`: layananId, hari enum (misalnya KAMIS), jamBuka/jamTutup HH:mm dan kapasitasHarian. Siapkan seluruh hari praktik yang digunakan, bukan hanya hari booking dibuat.
3. `POST /loket`: layananId, kode dan nama. Simpan id ruang sebagai loketId.
4. `POST /penugasan-petugas`: petugasId dari akun PETUGAS aktif, loketId, tanggalMulai YYYY-MM-DD dan tanggalSelesai opsional. Pastikan penugasan mencakup tanggal pelayanan.
5. `POST /dokter`: kode, nama dan spesialisasi opsional. Simpan id sebagai dokterId.
6. `POST /dokter/:dokterId/layanan` dengan layananId. **ID respons adalah dokterLayananId**, berbeda dari dokterId dan layananId.
7. `POST /jadwal-praktik`: dokterLayananId, loketId, tanggal YYYY-MM-DD, mulaiPada/selesaiPada ISO berzona. Sesi harus dalam jam poli dan tidak overlap dokter/ruang.
8. `POST /slot-praktik`: jadwalPraktikId dari id sesi, mulaiPada/selesaiPada ISO berzona dan kapasitas. Slot berada dalam sesi, tidak overlap, dan waktu tepat menit penuh. Kapasitas slot tidak menggantikan kuota harian poli.

Contoh body membuat poli yang menerima kedua alur:

```json
{
  "kode": "POLI01",
  "nama": "Poliklinik Umum",
  "prefixAntrean": "PU",
  "durasiDasarMenit": 15,
  "modeReservasi": "HIBRIDA"
}
```

### 18.2 Pemilihan dan booking oleh USER

| Alur | Request | Field/ID yang dipakai selanjutnya |
|---|---|---|
| Katalog poli | GET /layanan | id → layananId; modeReservasi menentukan kanal |
| Appointment: dokter | GET /dokter | id → dokterId; dokterLayanan memuat relasi poli |
| Appointment: jadwal | GET /jadwal-praktik?dokterId=…&layananId=…&tanggal=YYYY-MM-DD | id → jadwalPraktikId; loketId adalah ruang tujuan |
| Appointment: slot | GET /slot-praktik?jadwalPraktikId=… | id → slotPraktikId; periksa tersedia, kapasitas dan interval |
| Appointment: booking | POST /janji-temu dengan {"slotPraktikId":"UUID slot"} | id → appointmentId; tiket.id → tiketId |
| Walk-in: reservasi | POST /reservasi dengan {"layananId":"UUID poli","tanggalAntrean":"YYYY-MM-DD"} | id → tiketId |
| Tiket digital | GET /tiket/saya atau GET /tiket/:tiketId | Status/nomorAntrean aktual; appointment detail melalui GET /janji-temu/:appointmentId |
| QR pada hari pelayanan | POST /tiket/:tiketId/qr dengan JWT USER pemilik | qrPayload dan berlakuHingga; render payload persis, tanpa membangun token sendiri |

Booking appointment harus sebelum awal slot; QR diterbitkan pada hari pelayanan dan berlaku 600 detik. USER tidak mengirim penggunaId atau role. Jika QR perlu diperbarui sebelum check-in, gunakan endpoint QR existing; payload lama menjadi tidak valid. Tidak ada pasien/rekam medis klinis. Role DOKTER read-only dijelaskan pada Bagian 19.

### 18.3 Check-in dan pelayanan oleh PETUGAS

| Langkah | Request/body | Hasil sukses |
|---|---|---|
| CHECK_IN | POST /check-in {"qrPayload":"payload SQ1 dari USER","loketId":"UUID ruang"} | 200; DIPESAN → CHECK_IN, QR dikonsumsi sekali |
| ENQUEUE | POST /queue/:tiketId/masuk {"loketId":"UUID ruang"} | 200; CHECK_IN → MENUNGGU |
| Baca antrean | GET /queue/menunggu?loketId=… dan GET /queue/snapshot?loketId=… | 200; baca status dan kelayakan aktual |
| CALL | POST /queue/panggil {"loketId":"UUID ruang"} | 200; tiketId pada respons adalah tiket yang berhasil DIPANGGIL |
| START | POST /queue/:tiketId/mulai-pelayanan {"loketId":"UUID ruang"} | 200; DIPANGGIL → DILAYANI |
| COMPLETE | POST /queue/:tiketId/selesaikan-pelayanan {"loketId":"UUID ruang"} | 200; DILAYANI → SELESAI |

CALL menentukan tiket di server; klien tidak mengirim pilihan tiket untuk melewati prioritas. Untuk appointment, CHECK_IN/ENQUEUE dan CALL harus sesuai ruang sesi. Walk-in HIBRIDA membutuhkan sesi dokter aktif pada ruang CALL. Mode ANTREAN_HARIAN tetap FIFO tanpa syarat sesi dokter.

Tidak ada kandidat layak menghasilkan 404, busy/conflict 409, otorisasi ruang 403, QR expired 410, DTO invalid 400. Gunakan status backend sebagai sumber kebenaran; setelah event Socket.IO, reconnect atau respons mutasi yang tidak pasti, baca ulang snapshot. Jangan mengulang booking secara buta setelah timeout karena idempotency key belum tersedia. Public Display tetap memakai token perangkat, bukan token pasien/PETUGAS.

### 18.4 Revisi berikutnya yang tidak menghalangi dua alur utama

Resolusi manual HOSP-OPS-01, perpanjangan sesi berisi slot, toleransi menit keterlambatan, fairness lanjutan, pagination/backlog historis dan perubahan mode poli existing belum tersedia. Jangan membuat aksi frontend yang mengasumsikan endpoint tersebut. Metadata ketidaklayakan dan filter baca sudah tersedia; tiket MENUNGGU setelah akhir sesi tetap dicatat tanpa auto-cancel. Kesiapan integrasi MVP dibedakan dari persetujuan deployment produksi.


## 19. Doctor Portal — D1–D4 (18 Oktober 2026)

Role efektif kini ADMIN, PETUGAS, USER, DOKTER. Register publik tetap USER dan menolak field peran. Login/refresh/auth/me memakai JWT, hash bcrypt dan sesi database existing; untuk DOKTER juga wajib ada profil Dokter aktif yang ditautkan ke akun aktif. Akun tanpa tautan/profil nonaktif ditolak 401. Penonaktifan akun/profil dan pencabutan sesi berlaku pada request berikutnya; klaim role token bukan sumber kewenangan mutlak.

### 19.1 Provisioning ADMIN dan relasi opsional

Tidak ada endpoint HTTP manajemen pengguna umum existing yang dapat dipakai untuk provisioning DOKTER. Tambahan minimal berada pada controller dokter existing:

`POST /api/v1/dokter/:id/akun` — JWT ADMIN, sukses 201.

Pilih **salah satu** body:

```json
{"email":"dokter@example.org","kataSandi":"contoh-kata-sandi-awal"}
```

atau `{"penggunaId":"UUID-akun-DOKTER-existing"}`. Pembuatan mengambil nama dari profil dokter, menormalkan email menjadi lowercase dan memakai PasswordService existing. Email valid maksimal 150 karakter; kata sandi 8–72 karakter, sama dengan fondasi autentikasi existing. Penautan hanya menerima akun DOKTER aktif, bukan promosi USER/PETUGAS/ADMIN. Profil harus aktif dan belum bertaut akun. Tidak ada penggantian tautan atau self-link. Jangan kirim kedua bentuk sekaligus (400).

Respons: `{dokterId, akun:{id,nama,email,peran,aktif}}`, tanpa hash/password/token. Email, akun atau profil yang sudah bertaut mengakibatkan 409; profil/akun tidak aktif atau role akun salah 422; dokter tidak ditemukan 404. Unique constraint database dan update bersyarat dalam transaksi memastikan satu akun ↔ satu profil dan rollback akun baru bila perlombaan provisioning kalah.

GET `/dokter` dan `/dokter/:id` memberi `penggunaId` nullable hanya kepada ADMIN sebagai indikator tautan. Katalog non-ADMIN tetap menghilangkan field tersebut. Penambahan ini tidak mengubah relasi dokter–poli, jadwal, slot, appointment, tiket atau kontrak booking.

### 19.2 Endpoint baca DOKTER

Semua endpoint berikut hanya JWT DOKTER. Backend menurunkan dokter dari akun terautentikasi; tidak menerima dokterId/penggunaId arbitrer. Query tambahan pada DTO ditolak 400.

| Method | Path | Query | Respons |
|---|---|---|---|
| GET | `/portal-dokter/profil` | — | `{id,kode,nama,spesialisasi,aktif,poliklinik:[{id,kode,nama}]}` |
| GET | `/portal-dokter/jadwal` | `tanggal=YYYY-MM-DD` opsional, default hari pelayanan | Array `{id,tanggal,mulaiPada,selesaiPada,aktif,ruang:{id,kode,nama,lokasi},poliklinik:{id,kode,nama}}` |
| GET | `/portal-dokter/janji-temu` | tanggal seperti jadwal | Array `{nomorAntrean,tanggalPelayanan,mulaiPada,selesaiPada,status,poliklinik,ruang,jadwalPraktikId}` |
| GET | `/portal-dokter/antrean/snapshot` | `jadwalPraktikId=UUID` wajib | Snapshot sesi aktif di bawah |

Path berawalan `/api/v1`. Tanggal harus tanggal kalender nyata, bukan timestamp. Instan mulai/selesai memakai ISO 8601 UTC; tanggal pelayanan mengikuti SERVICE_TIME_ZONE. Jadwal sendiri termasuk jadwal nonaktif agar statusnya terlihat; appointment sendiri tetap menampilkan status tiket termasuk pembatalan. Daftar kosong ialah `[]`, bukan data ilustratif atau error. Tidak ada nama/ID pasien, email/telepon pasien, ID tiket, kode tiket, QR/hash QR atau data klinis pada respons portal.

Snapshot hanya diizinkan untuk sesi **milik dokter, hari ini, sudah mulai dan belum berakhir**, dengan rantai profil/relasi/poli/ruang/sesi aktif. Sesi orang lain, ruang berbeda, tanggal lain, belum mulai, berakhir/nonaktif menghasilkan 403. Klien memilih ID dari jadwal sendiri, bukan ID ruang sembarang.

```json
{
  "versiSkema": 1,
  "diperolehPada": "2026-10-18T03:00:00.000Z",
  "tanggalPelayanan": "2026-10-18",
  "sesi": {"id":"UUID-sesi-sendiri","mulaiPada":"2026-10-18T01:00:00.000Z","selesaiPada":"2026-10-18T05:00:00.000Z"},
  "ruang": {"id":"UUID-ruang","kode":"R1","nama":"Ruang 1","lokasi":null},
  "poliklinik": {"id":"UUID-poli","kode":"MAT","nama":"Poli Mata"},
  "totalMenunggu": 1,
  "menunggu": [{"nomorAntrean":"A-001","status":"MENUNGGU","jenisAntrean":"JANJI_TEMU","layakDipanggil":true}],
  "aktif": [{"nomorAntrean":"A-002","status":"DIPANGGIL"}]
}
```

Contoh tersebut ilustratif. `aktif` memuat DIPANGGIL/DILAYANI. `totalMenunggu` adalah jumlah dalam **scope sesi dokter**; `menunggu` maksimal 100. Appointment harus terkait slot sesi sendiri; appointment dokter lain tetap disembunyikan meskipun tiket mengarah ke ruang yang sama. Walk-in HIBRIDA hanya metadata operasional minimum untuk ruang/tanggal/sesi aktif yang berwenang. Walk-in tidak diberi dokterId buatan. Status dan urutan bersumber dari tiket serta selector Hospital existing (termasuk urutan REQUEUE), tanpa perubahan Queue Engine atau kebijakan numerik.

Untuk **ANTREAN_HARIAN**, dokter dengan sesi praktik aktif yang sah juga memantau tiket non-appointment MENUNGGU pada poli dan tanggal pelayanan yang sama. Daftar tunggu harian merupakan pool bersama per poli, sehingga `loketId` kosong setelah REQUEUE tidak menyembunyikan tiket. Urutannya tetap `urutanMasukAntrean ASC, id ASC`, sama dengan CALL harian; bukan urutan check-in/slot Hospital. Metadata `jenisAntrean=WALK_IN` dan `layakDipanggil=true` diberikan untuk entri MENUNGGU dengan urutan masuk yang valid. Tiket aktif DIPANGGIL/DILAYANI tetap hanya terlihat pada ruang sesi dokter tersebut. Sesi milik dokter, tanggal, waktu mulai/selesai dan seluruh relasi aktif tetap wajib; tidak ada perluasan ke poli lain atau akses tanpa sesi.

### 19.3 Matriks pembatasan DOKTER

| Operasi | DOKTER |
|---|---|
| Empat GET portal milik sendiri | Diizinkan |
| Katalog profesional non-ADMIN (dokter/poli/jadwal/slot aktif) | Mengikuti izin baca katalog existing; tanpa data appointment/pasien |
| GET portal milik role lain / sesi tidak berwenang | Ditolak oleh guard/scope |
| POST CHECK_IN, ENQUEUE, CALL, RECALL, SKIP, REQUEUE, START, COMPLETE | 403 |
| Booking/QR pasien, appointment pasien lewat `/janji-temu` | 403 |
| Master create/update/delete, provisioning akun, penugasan | 403 |
| Snapshot PETUGAS `/queue/snapshot` dan namespace `/queue` | Ditolak |

ADMIN/PETUGAS/USER tidak memperoleh empat GET portal DOKTER (403); ADMIN mengelola master melalui endpoint ADMIN existing. Tidak ada penambahan mutasi status antrean atau data medis untuk DOKTER.

### 19.4 Socket.IO `/doctor`

Handshake `io(socketOrigin + '/doctor', {transports:['websocket'],auth:{token:accessToken}})`. Token akses wajib, dibatasi Origin dan rate handshake existing, diverifikasi bersama sesi/akun/profil. Hanya DOKTER dapat terhubung. Tidak ada pesan join room atau parameter dokterId/loketId dari klien; tidak menggunakan room PETUGAS.

- `doctor:ready {versiSkema:1}` → baca ulang REST.
- `doctor:updated {versiSkema:1,eventId,jenis:'ANTREAN',terjadiPada:UTCISO}` → baca ulang REST.

Event hanya invalidasi, tanpa nomor antrean, ID sesi/pasien/tiket atau identitas. QueueService mengirim setelah transaksi commit melalui broadcast existing. Booking/pembatalan appointment dan CHECK_IN sukses juga memicu invalidasi. Pada setiap event backend menghitung ulang sesi aktif hari pelayanan, dokter pemilik slot atau ruang walk-in HIBRIDA; sesi DB, akun, profil dan kedaluwarsa JWT diperiksa sebelum pengiriman. Appointment dan HIBRIDA tetap dibatasi sesi/ruang masing-masing. Untuk tiket non-appointment ANTREAN_HARIAN, semua dokter dengan sesi aktif yang sah pada poli tersebut menerima invalidasi pool bersama, termasuk ketika tiket belum memiliki loket dan ketika CALL mengeluarkannya dari daftar tunggu. Ini tidak memberi akses tiket aktif ruang dokter lain: setiap klien tetap mengambil ulang snapshot REST dengan scope sesinya. Poli lain tidak menerima event. Socket sesi dicabut diputus ketika menjadi kandidat pengiriman; JWT kedaluwarsa diputus oleh timer.

Flutter menggunakan satu feed per halaman dengan lifecycle/token rotation, dedup event, debounce dan REST RefreshGate existing. Reconnect/resume memuat ulang; saat socket terputus, rekonsiliasi berkala 30 detik, saat tersambung maksimal dua menit. Perubahan katalog/admin tidak disiarkan lewat `/doctor`: terbaca pada rekonsiliasi berkala atau Muat ulang. Ini kanal invalidasi best effort satu instance, tanpa replay/outbox/adapter multi-instance. HTTPS, reverse proxy dan topologi Socket.IO produksi tetap perlu konfigurasi.

### 19.5 Migration dan urutan deployment

Migration baru: `20261018_doctor_portal_identity`. Menambah nilai enum DOKTER, kolom `dokter.pengguna_id` nullable, unique index dan foreign key RESTRICT. Dokter existing tetap NULL dan dapat dipakai tanpa akun. Tidak ada migration historis diubah atau data master dihapus.

**Database development/produksi belum dimigrasikan oleh pekerjaan ini. Penerapan memerlukan persetujuan Project Lead.** Setelah persetujuan: verifikasi DATABASE_URL dan database aktual secara privat, periksa status/pending migration, jalankan `prisma migrate deploy` memakai konfigurasi lingkungan tujuan, `prisma generate`, build/deploy backend, lalu deploy Flutter dan provision akun melalui ADMIN. Jangan menjalankan migrate reset/db push atau menurunkan enum dengan drop. Deploy migration sebelum backend baru karena query Prisma memakai schema baru. Dokter belum dapat login pada backend lama; tiga role existing tetap didukung.

Runner QA `node test/run-doctor-portal.cjs --migrate-test-db` hanya mengizinkan satu migration baru tersebut pada koneksi paksa `127.0.0.1:5433/capstone_antrean_test`; `--all` menjalankan seluruh E2E. Port internal container ialah 5432, host tetap 5433. Fingerprint semua record existing dibandingkan setelah tes; cleanup hanya fixture unik. Hasil aktual dan panduan demo tercatat pada `docs/frontend/DOCTOR_PORTAL.md`.


## 20. Manajemen perangkat Public Display dan pairing (v1.5)

Satu perangkat terikat satu layanan/poliklinik; beberapa perangkat boleh memakai layanan sama. Semua path di bawah berprefix `/api/v1`. Endpoint manajemen wajib JWT **ADMIN** dengan sesi aktif; TV tidak login akun. UI ADMIN menampilkan nama dan kategori poliklinik, bukan UUID/hash sebagai label utama.

| Method | Path | Input | Sukses |
| --- | --- | --- | --- |
| GET | `/perangkat-display` | JWT ADMIN | 200 array metadata perangkat |
| POST | `/perangkat-display` | `{nama,layananId}` | 201 metadata perangkat baru |
| POST | `/perangkat-display/:id/aktivasi` | JWT ADMIN, UUID v4 | 200 `{kode,berlakuHingga}`; kode hanya ditampilkan sekali |
| POST | `/perangkat-display/:id/nonaktifkan` | JWT ADMIN, UUID v4 | 200 `{id,aktif:false}` |
| POST | `/display/pairing` | `{kode}` string tepat 12 digit | 200 metadata + Set-Cookie HttpOnly, tanpa token dalam JSON |
| GET | `/display/sesi` | Cookie perangkat | 200 metadata perangkat aktif; 401 jika perlu aktivasi |
| POST | `/display/putuskan` | Cookie perangkat | 200 `{ok:true}`, mencabut kredensial dan menghapus cookie |
| GET | `/display/:layananId/snapshot` | Cookie perangkat atau x-display-token existing | 200 `DisplaySnapshot` existing |

Metadata: `{id,nama,layananId,aktif,terakhirAktifPada,dibuatPada,diperbaruiPada,layanan:{id,kode,nama,aktif}}`. Tidak mengandung token, hash, kode aktivasi, session secret, identitas atau tiket pasien. `aktif` menunjukkan izin administratif, **bukan online presence**. `terakhirAktifPada` nullable, diperbarui saat pairing/pemeriksaan sesi (maksimal sekali per menit), bukan jaminan heartbeat realtime. Daftar belum memakai pagination; pencarian/kategori dilakukan Flutter. Nama perangkat 3–100 karakter dengan karakter nonspasi; poliklinik harus aktif. Binding poliklinik tetap sepanjang umur perangkat; untuk memindah TV, nonaktifkan identitas lama lalu buat identitas di poliklinik tujuan.

### 20.1 Keamanan dan lifecycle

- Kode acak kriptografis 12 digit (pertahankan nol di depan), berlaku **5 menit**, sekali pakai. Hanya HMAC-SHA256 dengan domain `queueb:display:activation:v1:` yang tersimpan; kunci berasal dari `JWT_REFRESH_SECRET` server existing. Rotasi secret server membatalkan kode yang masih pending, tidak membuka kode asli. Kredensial perangkat acak 32 byte disimpan sebagai SHA256 pada `tokenHash` existing.
- Klaim kode memakai transaksi dan `updateMany` bersyarat kode/expiry/belum digunakan/perangkat/layanan aktif. Balapan hanya menghasilkan satu sukses. Kode salah/diganti/nonaktif 401; kedaluwarsa/sudah digunakan 410; kalah balapan atau layanan nonaktif 409. Kode yang diganti/nonaktifkan sengaja memakai pesan umum karena kode lama tak lagi tersimpan. Validasi format 400, rate limit 429; gangguan jaringan ditangani tanpa retry mutasi otomatis. Sesudah respons pairing hilang, periksa `/display/sesi` sebelum meminta kode baru.
- Exception database/driver pada route display ditangani filter khusus: tidak mencetak detail constraint yang dapat memuat hash, mengembalikan pesan aman 503. Error HTTP domain/validasi mempertahankan status dan pesan publik.
- Pairing dibatasi **5 percobaan/IP/60 detik**; penerbitan kode ADMIN **20/IP/60 detik**, memakai Throttler existing. Handshake Socket.IO tetap memakai limiter existing. Limiter memori per proses; production multi-instance perlu storage/edge limiter bersama dan konfigurasi proxy yang ditinjau. Jangan mempercayai X-Forwarded-For dari klien secara langsung.
- Sesi cookie `queueb_display`: **HttpOnly**, **SameSite=Strict**, host-only, `Path=/` agar berlaku untuk REST dan `/socket.io`, umur **30 hari**, expiry juga diperiksa server pada REST dan socket. `Secure` wajib saat NODE_ENV=production. Development HTTP localhost memakai cookie tanpa Secure untuk demo lokal. Jangan memakai HTTP terbuka untuk pemasangan produksi.
- Flutter Web memakai client HTTP khusus display dengan `withCredentials=true`, Socket.IO WebSocket juga memakai cookie; token tidak masuk localStorage/sessionStorage/URL/log. Android memakai secure storage terenkripsi existing untuk cookie perangkat, terpisah dari sesi akun dan terikat API_BASE_URL; native lain hanya memori proses. Token manual existing hanya memori dan tetap didukung.
- `/display/pairing` dan `/display/putuskan` memeriksa Origin browser terhadap daftar CORS persis sebelum mutasi. Cookie Strict dan request JSON/CORS ikut mencegah CSRF; klien native tanpa Origin tetap harus memiliki kode atau cookie. Null/untrusted Origin ditolak. Endpoint cookie tidak menyediakan mutasi antrean.
- Menghasilkan kode baru merupakan **rotasi/reaktivasi**: kredensial dan kode lama langsung tidak berlaku, perangkat menjadi aktif; socket lama diputus. Penonaktifan juga menghapus pending code dan memutar token. Mengaktifkan kembali tidak memulihkan token lama. Ganti perangkat memanggil putuskan, bukan sekadar membersihkan UI. Pencabutan berlaku REST dan socket, tanpa menunggu CALL.
- Instance tunggal memutus socket segera; deployment beberapa instance tetap memerlukan adapter/invalidation lintas instance. Pemeriksaan kewenangan sebelum emit dan REST snapshot menolak token dicabut, tetapi pemutusan segera di instance lain bukan jaminan tanpa infrastruktur tersebut.

### 20.2 Origin, deployment dan pemulihan TV

Prioritas deployment: Web dan API **satu origin HTTPS** melalui reverse proxy (termasuk upgrade `/socket.io`), atau satu situs HTTPS pada subdomain yang sama dengan CORS origin Web yang spesifik dan credentials diaktifkan. Cookie Strict tidak mendukung Web/API lintas situs. Untuk localhost gunakan host yang sama pada kedua URL, misalnya `http://127.0.0.1:8080` → `http://127.0.0.1:3001/api/v1`; jangan campur localhost/127.0.0.1. Origin CORS harus termasuk port Web. Native tidak bergantung CORS tetapi produksi tetap HTTPS. Satu profil browser menyimpan satu identitas TV per host API; gunakan profil terpisah untuk TV berbeda.

Buka `/#/display` untuk kiosk: sesi cookie dipulihkan tanpa memasukkan kode lagi. Browser private/clear cookies/expiry meminta aktivasi ulang; mode token manual tetap meminta token setelah reload. Bootstrap, refresh, resume dan reconnect **senyap**; hanya CALL/RECALL baru dari snapshot diumumkan setelah event, deduplikasi berdasarkan peristiwaId. Audio browser perlu aktivasi pengguna lagi setelah reload. Fullscreen dan suara id-ID tetap bergantung browser/OS. Tidak ada perubahan Queue Engine, status tiket, prioritas atau payload snapshot.

### 20.3 Migration dan urutan pemasangan

Migration **`20261019_display_device_pairing`** hanya menambah empat kolom nullable pada `perangkat_tampilan`: kode_aktivasi_hash (unique), kode_berlaku_hingga, kode_digunakan_pada dan sesi_berakhir_pada. Token/perangkat existing tetap berfungsi karena expiry null berarti jalur token lama. Tidak ada perubahan migration historis atau penghapusan data.

**Database development utama belum diberi migration ini. Persetujuan Project Lead diperlukan sebelum memasangnya.** Review SQL dan backup, validasi DATABASE_URL dan current_database(), periksa seluruh migration pending, baru `prisma migrate deploy` sesuai persetujuan; kemudian generate client, deploy API baru, deploy Flutter. Query Prisma baru memerlukan kolom tersebut, sehingga migration harus mendahului deployment API. Jangan reset/db push/restore/drop. Runner `node test/run-display-pairing.cjs --deploy-test-migration` hanya menerima kredensial lokal dan memaksa target `127.0.0.1:5433/capstone_antrean_test`, memeriksa pending migration dan fingerprint data existing; tidak dapat memasang ke development utama.


## Penghapusan permanen data ADMIN

Endpoint Nonaktifkan existing tetap berlaku. `DELETE /:id` pada layanan, dokter, loket, jadwal layanan, jadwal praktik, slot dan penugasan **tidak berubah menjadi hard delete**. Perangkat display tetap memakai `POST /perangkat-display/:id/nonaktifkan` untuk mencabut akses tanpa menghapus perangkat.

Endpoint aditif berikut membutuhkan JWT role **ADMIN**:

| Metode | Path relatif `/api/v1` | Fungsi |
|---|---|---|
| DELETE | `/layanan/:id/permanen` | Hapus poliklinik yang belum dipakai dan tidak memiliki konfigurasi turunan |
| DELETE | `/dokter/:id/permanen` | Hapus profil dokter tanpa jadwal dan akun; relasi poliklinik konfigurasi yang belum dipakai ikut dibersihkan secara eksplisit |
| DELETE | `/loket/:id/permanen` | Hapus ruang tanpa tiket, jadwal atau penugasan |
| DELETE | `/jadwal-layanan/:id/permanen` | Hapus jam/kapasitas bila poliklinik belum memiliki tiket atau sesi praktik |
| DELETE | `/jadwal-praktik/:id/permanen` | Hapus sesi tanpa appointment, slot, atau tiket terkait tanggal/ruang |
| DELETE | `/slot-praktik/:id/permanen` | Hapus slot tanpa appointment, termasuk appointment dibatalkan |
| DELETE | `/penugasan-petugas/:id/permanen` | Hapus penugasan bila belum ada tiket di loket dalam periodenya |
| DELETE | `/perangkat-display/:id/permanen` | Hapus perangkat dan cabut koneksi/kode/kredensialnya |
| PATCH | `/perangkat-display/:id` | Ubah nama perangkat, body `{ "nama": "TV Ruang Tunggu" }`; tidak memindahkan poliklinik atau merotasi akses |

DELETE tidak memerlukan body. ID harus UUID v4. Sukses `200`: `{ "id": "UUID", "dihapus": true }`. Tidak ada token, profil pasien, atau row database lengkap dalam respons hapus.

- `401`: sesi belum sah/berakhir. `403`: role selain ADMIN. `400`: format ID tidak valid. `404`: data tidak ada/sudah dihapus.
- `409 DATA_MASIH_DIGUNAKAN`: `message` dan `alasan` menyebut relasi penghalang, serta `bolehNonaktifkan: true`. Frontend menampilkan alasan dan menawarkan Nonaktifkan untuk data aktif.
- `409 KONFLIK_PERUBAHAN`: ada transaksi paralel, deadlock atau batas tunggu lock. Muat ulang status sebelum mencoba lagi; jangan retry operasi destruktif otomatis.

Semua status historis diperhitungkan, termasuk record nonaktif dan appointment dibatalkan. Relasi konfigurasi turunan poliklinik harus dihapus dahulu jika belum digunakan; tidak ada cascade terhadap booking, tiket, audit atau pengguna. Dokter yang sudah ditautkan ke akun tetap dilindungi; akun tidak dihapus.

Transaksi Serializable memakai row lock dan FK PostgreSQL. Penghapusan jam/kapasitas serta penugasan memakai lock tabel singkat karena keterkaitan operasional tidak memiliki FK langsung; lock timeout 5 detik dan transaksi maksimum 10 detik. Konflik Prisma maupun SQLSTATE adapter dipetakan ke 409, bukan 500. Socket perangkat diputus melalui gateway existing setelah commit; pemeriksaan kredensial REST/realtime tetap membaca database.

Audit antrean di database dipertahankan. Karena belum tersedia tabel audit master-data generik, keberhasilan hapus dicatat melalui logger `AdminDeleteAudit` berisi aksi, resource, id, aktorId dan timestamp, tanpa nama pasien/token/hash. Pengelola deployment perlu mempertahankan log tersebut pada penyimpanan log server. Tidak ada perubahan schema/migration.

Flutter menampilkan dialog **Hapus Data?**, tombol **Batal** dan **Hapus Permanen**; poliklinik/dokter memerlukan pengetikan kode atau nama yang tepat. Konfirmasi tidak menggantikan pemeriksaan RBAC/referensi backend. Sesudah sukses, daftar dimuat ulang dengan pencarian/filter yang masih aktif. Tombol Nonaktifkan tetap tersedia terpisah.


## 22. ADMIN Management P0 — akun dan penugasan (24 Oktober 2026)

Bagian ini memperbarui catatan historis tentang provisioning PETUGAS dan konkurensi penugasan pada Bagian 13–18. Akun ADMIN awal tetap disediakan pengelola server. Register publik tetap hanya membuat USER; tidak menerima input role. Tidak ada migration/schema baru.

### 22.1 Akun PETUGAS — khusus JWT ADMIN

| Method | Path (prefix `/api/v1`) | Request / hasil |
|---|---|---|
| GET | `/akun-petugas` | Array seluruh akun PETUGAS aktif/nonaktif, diurutkan nama/email; pencarian nama/email dilakukan Flutter pada array ini |
| POST | `/akun-petugas` | `{nama,email,kataSandi}` → 201, metadata akun; role PETUGAS dan aktif ditetapkan server |
| PATCH | `/akun-petugas/:id` | `{aktif:boolean}` → 200; hanya status akun PETUGAS yang dapat diubah |

Metadata: `{id,nama,email,peran,aktif}`. Tidak ada hash, kata sandi atau token dalam respons/log audit. Nama 3–150 karakter, email valid maksimal 150, kata sandi awal 8–72 karakter memakai PasswordService existing. Email dinormalisasi lowercase; duplikat 409. Body tambahan (termasuk peran) ditolak 400. Tanpa JWT 401; USER/PETUGAS/DOKTER 403; akun tidak ditemukan atau ID milik role lain pada PATCH 404. Tidak ada endpoint hapus akun atau promosi role.

Penonaktifan akun dan pencabutan seluruh sesi yang belum dicabut dilakukan dalam satu transaksi, tanpa menghapus pengguna atau penugasan. JWT/refresh lama ditolak; reaktivasi tidak menghidupkan sesi lama sehingga pengguna harus login ulang. Penugasan aktif yang masih berada dalam periode berlaku dapat dipakai kembali setelah akun diaktifkan. Mengakhiri penugasan tidak menonaktifkan akun. Log administratif mencatat aksi, ID, aktor ADMIN dan waktu; tidak mencatat kredensial.

### 22.2 Penugasan loket

Kontrak POST/PATCH/DELETE `/penugasan-petugas` tetap. Petugas dipilih dari `/akun-petugas` berdasarkan nama/email; hanya akun aktif ditawarkan untuk penugasan baru. Ruang/loket baru harus aktif dan berada pada poliklinik aktif. UUID tetap digunakan dalam body API sebagai identifier internal; Flutter tidak lagi meminta input atau clipboard UUID.

Create/update memvalidasi peran dan akun aktif, mengunci akun petugas lalu memeriksa benturan dan menyimpan dalam transaksi READ COMMITTED. Update juga mengunci record penugasan. Akun lama/baru dikunci dalam urutan stabil ketika dipindahkan. Row lock akun yang sama dipakai oleh mutasi status akun. Dua request beririsan tidak dapat sama-sama berhasil; konflik tanggal 409. Akun nonaktif 400. Penonaktifan penugasan via DELETE tetap tersedia walaupun akun sudah nonaktif.

Tanggal awal/akhir tetap inklusif, `tanggalSelesai:null` tanpa batas akhir. Tidak ada shift jam atau batas satu petugas per loket. Respons relasi petugas menambahkan `aktif`. Flutter membedakan status NONAKTIF, AKUN NONAKTIF, AKAN BERLAKU, BERLAKU, dan BERAKHIR dari flag/periode pada zona pelayanan. Status ini tidak mengubah data atau keputusan otorisasi server.

### 22.3 Identitas dan akun DOKTER

Provisioning tetap `POST /dokter/:id/akun` dengan salah satu body existing (email/kataSandi atau penggunaId). Tambahan baca khusus ADMIN: `GET /dokter/akun-tersedia` mengembalikan akun DOKTER aktif yang belum tertaut, berbentuk array `{id,nama,email,aktif}`, untuk pemilihan nama/email. Route ini ditempatkan sebelum `GET /dokter/:id`.

`GET /dokter` dan `GET /dokter/:id` menambahkan `pengguna:{nama,email,aktif}|null` **hanya untuk ADMIN**. Non-ADMIN tidak memperoleh metadata akun ini maupun penggunaId. Metadata tidak menyertakan password/hash/token.

Flutter membedakan profil dokter dan akun login serta memberi alur Buat profil → Hubungkan poliklinik → Buat akun login. Penyimpanan profil, hubungan poli, dan provisioning tetap operasi terpisah; kegagalan langkah lanjutan tidak membuat ulang profil/akun. Profil nonaktif memblokir akses portal melalui validasi JWT existing. Pelepasan/penggantian akun dan perubahan status akun DOKTER secara terpisah tetap di luar P0.

### 22.4 Regresi dan QA

`admin-management-p0.e2e-spec.ts` memeriksa RBAC semua role, metadata aman, fixed role, email duplikat, pencabutan sesi, reaktivasi, akun nonaktif, batas tanggal inklusif, create/update paralel, serta provisioning dan privasi DOKTER. Seluruh E2E yang menulis data hanya dijalankan pada `127.0.0.1:5433/capstone_antrean_test` setelah pemeriksaan koneksi. Runner membandingkan integritas record existing dan hanya membersihkan fixture milik tes.

Smoke browser melalui `node apps/client/tool/run-live.cjs --admin-p0` memakai server API test port 3001 dan build Web dengan API_BASE_URL test. Alur ini menjalankan Flutter hasil kompilasi dan API nyata, bukan stub REST; screenshot disimpan pada `docs/frontend/images/admin-p0`.

## 23. P1 — Foto profesional dan biografi dokter

Aktivasi memerlukan migration aditif `20261024_doctor_professional_profile`. **Jangan
menjalankan build backend ini pada database yang belum dimigrasi.** Penerapan pada
development utama harus melalui persetujuan Project Lead; QA menulis hanya ke
`127.0.0.1:5433/capstone_antrean_test`.

### 23.1 Field dan akses

Entitas Dokter menambahkan dua field opsional:

| Field JSON | Kolom PostgreSQL | Kontrak |
| --- | --- | --- |
| `fotoProfil` | `foto_profil VARCHAR(200) NULL` | Referensi API relatif `/media/dokter/<uuid>.webp`, dikelola endpoint foto |
| `tentangDokter` | `tentang_dokter VARCHAR(1500) NULL` | Teks biasa maksimal 1.500 karakter; string kosong dinormalisasi menjadi null |

`POST /dokter` dan `PATCH /dokter/:id` menerima `tentangDokter` opsional, termasuk
`null` untuk mengosongkan. PATCH tanpa field tersebut mempertahankan deskripsi.
`fotoProfil` tidak dapat diisi manual melalui body create/update. Referensi tidak
pernah menerima URL eksternal atau path filesystem dari klien.

`GET /dokter`, `GET /dokter/:id`, dan `GET /portal-dokter/profil` menyertakan field
baru. Scope profil/poliklinik aktif dan privasi metadata akun tetap mengikuti
kontrak existing. Hanya ADMIN dapat mengubah profil atau foto; DOKTER membaca
profil profesionalnya dan tidak dapat mengubahnya pada P1. Foto ini terpisah dari
avatar akun Pengguna; tidak ada perubahan registrasi, autentikasi atau Queue Engine.
Pada Flutter, DOKTER membuka **Profil akun → Profil profesional** untuk melihat
foto dan deskripsi sendiri tanpa kontrol edit.

Contoh PATCH ADMIN:

```json
{"tentangDokter":"Dokter spesialis anak yang melayani konsultasi di poliklinik anak."}
```

### 23.2 Upload dan hapus foto

Semua path berikut relatif terhadap API base `/api/v1`.

| Endpoint | Hak akses | Request / response |
| --- | --- | --- |
| `POST /dokter/:id/foto` | JWT ADMIN | `multipart/form-data`, satu field file bernama `foto`; 201 `{id,fotoProfil}` |
| `DELETE /dokter/:id/foto` | JWT ADMIN | 200 `{id,fotoProfil:null}`; idempoten untuk profil tanpa foto |
| `GET /media/dokter/:filename` | Publik, hanya foto profesional yang masih direferensikan | `image/webp`; tidak menerima token dalam URL |

Input dibatasi 2 MiB (2.097.152 byte), JPEG/PNG/WebP statis dan maksimal 16 juta
piksel. Backend memeriksa signature dan hasil decoding, bukan ekstensi/MIME klien.
Gambar didecode, orientasi diterapkan, dikecilkan hingga 640×640 tanpa memperbesar,
metadata dibuang dan diencode ulang ke WebP. Nama file UUID v4 dibuat server;
file asli tidak pernah disajikan atau disimpan sebagai base64 di PostgreSQL.
Decoder memakai Sharp 0.35.5; parser multipart dipin ke Multer 2.5.0 melalui npm
override untuk patch [GHSA-q7qp-rjg7-q26m](https://github.com/expressjs/multer/security/advisories/GHSA-q7qp-rjg7-q26m).

401 tanpa JWT, 403 role selain ADMIN, 404 dokter/foto tidak ditemukan, 400 file
rusak/format tidak didukung/field salah atau deskripsi terlalu panjang, 413 file
terlalu besar, 409 konflik transaksi yang terdeteksi, 503 penyimpanan tidak tersedia.
Validasi gagal mempertahankan foto existing. Penggantian/penghapusan referensi
dikunci per record dokter dalam transaksi; file lama dibersihkan sesudah commit
dan tidak dapat dibaca lagi melalui referensi lama. Kegagalan pembersihan tidak
membatalkan update yang sudah commit; log tidak memuat path internal atau isi file.

Endpoint media tidak membuka direktori statis, hanya nama UUID WebP yang valid
dan masih direferensikan database. Header `nosniff`, CSP terbatas dan `no-cache`
diterapkan. Foto profesional memang dapat dibaca publik; jangan mengunggah dokumen,
foto pasien, atau media privat.

### 23.3 Storage dan integrasi Flutter

Default direktori media adalah `.queueb-media/dokter` relatif terhadap working
directory proses API (jalankan dari `apps/api`). Gunakan `DOCTOR_MEDIA_DIR` berisi
path absolut untuk lokasi persisten deployment. Direktori tidak dipasang sebagai
web root dan harus hanya dapat ditulis proses API. Semua file upload di bawah
`apps/api/.queueb-media` diabaikan Git.

Solusi P1 adalah filesystem persisten satu instance. Backup PostgreSQL harus
disertai backup volume media; deployment ephemeral atau beberapa instance memerlukan
shared volume/storage tersendiri. Hard delete profil atau kegagalan disk dapat
menyisakan file tanpa referensi; file tersebut tidak disajikan oleh API. Pembersihan
operasional file yatim tidak termasuk endpoint/fitur P1.

Flutter membentuk URL dari `API_BASE_URL + fotoProfil`, termasuk prefix reverse
proxy. Gunakan origin API yang dapat dijangkau Android (localhost pada HP bukan
localhost laptop), HTTPS sesuai deployment, CORS Flutter Web dan persistensi
volume yang sesuai. Token tidak dimasukkan URL foto. Avatar fallback digunakan
saat foto null, sedang dimuat atau gagal dimuat. Tidak ada rating/pengalaman dummy.

ADMIN memilih file melalui file selector Web/Android, melihat preview, lalu
menekan Simpan untuk menyimpan metadata dan foto. Profil baru dibuat lebih dulu;
jika upload gagal, retry menggunakan ID profil yang sudah tersimpan, tanpa duplikat.
Menutup form memperbarui katalog meski langkah foto gagal. Poliklinik dan akun
login tetap ditautkan melalui aksi existing pada tabel.

Pasien melihat foto, spesialisasi, poliklinik dan ringkasan jadwal dari API; detail
menambahkan biografi dengan Baca Selengkapnya serta jadwal/ruang dan alur booking
slot existing. Endpoint slot dan appointment tidak berubah.

Smoke browser P1: build Web dengan
`--dart-define=API_BASE_URL=http://127.0.0.1:3001/api/v1`, lalu
`node apps/client/tool/run-live.cjs --doctor-profile`. Runner memvalidasi database
test, memakai API nyata serta media/fixture unik, kemudian memeriksa integritas dan
membersihkan fixture milik run. Screenshot: `docs/frontend/images/doctor-profile-p1`.

## 24. Profil Saya dan keamanan akun (P2)

`GET /auth/me` tetap menjadi sumber identitas akun, dengan tambahan `aktif`,
`avatarProfil: string|null`, dan `dibuatPada`. Email, role, status, ID, penugasan,
serta relasi dokter tidak dapat diedit sendiri.

| Metode | Endpoint | Request / hasil |
| --- | --- | --- |
| PATCH | `/auth/me` | `{nama}` 3–150 karakter setelah trim → metadata profil |
| POST | `/auth/me/avatar` | Multipart `foto`, satu JPEG/PNG/WebP statis ≤2 MiB, ≤16 juta piksel → 201 `{id,avatarProfil}` |
| GET | `/auth/me/avatar` | WebP privat akun sendiri dengan JWT; 404 jika kosong |
| DELETE | `/auth/me/avatar` | Idempoten → 200 `{id,avatarProfil:null}` |
| POST | `/auth/me/password` | `{kataSandiLama,kataSandiBaru}` → 200 `{message,loginUlang:true}` |

Seluruh endpoint memerlukan JWT dan memakai identitas server. Field tambahan
(termasuk userId, email, peran, aktif, avatarProfil) pada body profil ditolak 400.
Avatar akun terpisah dari foto profesional Dokter P1; referensi avatar bukan URL
publik. Baca byte melalui GET `/auth/me/avatar` dengan JWT; respons memakai
`private, no-store` dan `nosniff`. Nama/avatar baru diperbarui pada header melalui
state akun, tanpa logout.

Password baru minimal 8 karakter, maksimal 72 karakter dan 72 byte UTF-8. Password
lama salah atau password baru sama ditolak 400; 401 tetap berarti masalah sesi.
Perubahan password dibatasi 5/menit per akun dan upload avatar 10/menit per akun
(429 jika terlampaui). Setelah hash diganti, seluruh sesi dicabut secara atomik;
Flutter menghapus token tersimpan dan meminta login ulang. Login in-flight dengan
password lama diperiksa kembali di bawah row lock. Password/token tidak dicatat.

Informasi penugasan PETUGAS dan profil/jadwal profesional DOKTER tetap memakai
endpoint role existing secara read-only. Tidak ada field kesehatan baru.

Migration aditif `20261024_user_profile_p2` menambah satu kolom nullable
`pengguna.avatar_profil`. Deployment memerlukan storage persisten
`USER_AVATAR_DIR` (default `.queueb-media/avatar`), terpisah dari
`DOCTOR_MEDIA_DIR`. **Migration development masih memerlukan backup dan persetujuan
Project Lead; implementasi P2 tidak otomatis memberi izin aktivasi database.**
Rincian sesi, storage, pengujian dan batas: [USER_PROFILE_P2.md](USER_PROFILE_P2.md).


## 25. Public Display Monitor V3 (v1.6)

`GET /api/v1/display/:layananId/snapshot` mempertahankan `versiSkema: 1`, autentikasi perangkat, cookie HttpOnly/header token, `Cache-Control: no-store`, dan seluruh field existing. Field aditif:

- `modeNama`: `SAMAR` (default), `LENGKAP`, atau `TANPA_NAMA`.
- `menunggu`: maksimal 100 objek `{nomorAntrean, namaPasien}`; hanya tiket **MENUNGGU dan sudah ENQUEUE**, tanggal pelayanan dan layanan perangkat yang sama. `totalMenunggu` tetap total sebenarnya, bukan panjang array.
- `loket[].tiketAktif[].namaPasien` dan `pengumumanTerakhir.namaPasien`: proyeksi yang sama, nullable. Tidak ada nama mentah tambahan, ID akun/tiket, email, telepon, NIK, alamat, QR atau informasi medis.

Field baru menggantikan pembatasan lama pada Bagian 5 yang hanya menyediakan angka tanpa nama. Nama tetap informasi terbatas, termasuk bentuk tersamar; fasilitas harus menetapkan kebijakan pengumuman publiknya. Browser tidak dapat meminta mode nama lain melalui query/body/pairing.

Konfigurasi **server** (tidak ada migration):

```text
DISPLAY_PATIENT_NAME_MODE=SAMAR
# Hanya setelah fasilitas menyatakan dasar persetujuan/kebijakan yang sesuai:
# DISPLAY_PATIENT_NAME_MODE=LENGKAP
# DISPLAY_FULL_NAMES_APPROVED=true
# Untuk tidak menampilkan atau menyuarakan nama sama sekali:
# DISPLAY_PATIENT_NAME_MODE=TANPA_NAMA
```

Mode `LENGKAP` tanpa konfirmasi server `DISPLAY_FULL_NAMES_APPROVED=true` tetap menghasilkan SAMAR. `Yusran Abdullah` menjadi `Yusran A.`; satu kata menjadi inisial. Nama kosong/null tidak diganti dengan nama buatan. Konfigurasi berlaku bagi seluruh Display pada instance server tersebut; pengelola harus mengoordinasikan kebijakan antar-instance. Perubahan konfigurasi memerlukan deployment/restart sesuai mekanisme lingkungan.

Urutan ANTREAN_HARIAN tetap FIFO `urutanMasukAntrean, id`. HIBRIDA/JANJI_TEMU_DOKTER menggunakan selector Hospital existing untuk kelayakan pada ruang appointment masing-masing, lalu comparator bersama: prioritas, slot, waktu REQUEUE/check-in, urutan masuk, id. Ini merupakan daftar konsolidasi poliklinik, **bukan janji urutan CALL tunggal lintas ruang**. CALL tetap memeriksa ruang/sesi dan hak petugas melalui Queue Engine existing. Pasien yang belum layak tetap termasuk total/list dengan prioritas server; frontend tidak mengurutkan ulang atau membuat estimasi.

Teks pengumuman baru bersumber dari snapshot:

> Panggilan nomor antrean A, nol nol dua atas nama Yusran A., silakan menuju ke Poliklinik Anak, terima kasih.

`nomorAntrean` tetap `A-002`. Ejaan huruf/digit mempertahankan nol di depan; `teks` pada layar dan yang dikirim ke TTS **identik**. Tanpa nama, frasa `atas nama` dihilangkan. Hanya peristiwa CALL/RECALL baru yang boleh menyuarakan teks; `peristiwaId` adalah kunci deduplikasi. Bahasa tetap `id-ID`. Tidak ada chime existing pada implementasi ini dan tidak ditambahkan layanan suara berbayar.

Namespace `/display`, room `display:layanan:<id>`, `display:ready` dan `display:updated` tidak berubah; payload socket tetap invalidasi minimal tanpa nama. Snapshot REST adalah sumber kebenaran. Setelah setiap sinyal, reconnect dan polling fallback, ambil ulang snapshot. Bootstrap/reconnect/manual refresh/resume membentuk baseline senyap sehingga tidak memutar ulang panggilan lama.

Pembatalan existing hanya menerima appointment DIPESAN, sehingga tidak pernah termasuk daftar MENUNGGU Display. Tidak ditambahkan mutasi pembatalan pasien MENUNGGU atau event CANCEL baru. Tiket DIBATALKAN tetap dikecualikan dari snapshot. Event operasional ENQUEUE/CALL/RECALL/SKIP/REQUEUE/START/COMPLETE tetap menginvalidasi Display.

Lihat [panduan monitor dan hasil QA V3](../frontend/PUBLIC_DISPLAY_V3.md).


## 26. One-Scan QR Check-in dan Auto-Enqueue

### Endpoint baru (aditif)

`POST /api/v1/check-in/auto-antrean`, JWT dan RBAC **PETUGAS aktif**. Penugasan harus aktif dan inklusif pada tanggal pelayanan, loket/poli sesuai tiket. Format DTO sama dengan endpoint check-in legacy; tidak menerima penggunaId/role/status dari klien.

```json
{"qrPayload":"SQ1.<token acak 43 karakter base64url>","loketId":"UUID v4 loket"}
```

200 menghasilkan data server aktual, misalnya:

```json
{
  "tiketId":"UUID tiket",
  "layananId":"UUID poliklinik",
  "nomorAntrean":"AN-001",
  "status":"MENUNGGU",
  "checkInPada":"2026-10-26T03:00:00.000Z",
  "loketId":"UUID ruang",
  "petugasId":"UUID petugas",
  "versi":4,
  "urutanMasukAntrean":12,
  "masukAntreanPada":"2026-10-26T03:00:00.000Z",
  "namaPasien":"Pasien Contoh",
  "namaPoliklinik":"Poliklinik Anak",
  "sudahTerdaftar":false,
  "pesan":"Check-in berhasil. Pasien masuk antrean."
}
```

Nama pasien hanya dikembalikan pada respons PETUGAS berwenang, bukan pada event socket. Contoh di atas ilustratif. Tidak ada token/hash QR dalam respons.

### Atomisitas dan scan ulang

Satu transaksi **Serializable** memakai callback CHECK_IN dan ENQUEUE existing pada TransactionClient yang sama. Validasi QR, tanggal SERVICE_TIME_ZONE, jam poli, assignment, rantai Hospital/ruang/sesi, status dan counter FIFO tetap berlaku. Tercatat dua audit: DIPESAN → CHECK_IN dan CHECK_IN → MENUNGGU. Kegagalan mana pun me-rollback seluruh transaksi termasuk konsumsi QR dan counter. P2034 dicoba ulang maksimal tiga percobaan; tidak menambah kebijakan prioritas/fairness baru.

Token aktif tetap dikonsumsi (`tokenQrHash` dan expiry aktif dikosongkan). Audit CHECK_IN baru menyimpan **hash bukti QR** dan expiry semula pada JSON internal `dataTambahan.buktiQrHash` / `qrBerlakuHingga`. Token mentah tidak disimpan atau dicatat. Bukti bukan QR baru: hanya boleh mengenali scan ulang tiket CHECK_IN/MENUNGGU, masih dalam expiry semula, setelah otorisasi dan validasi konteks. MENUNGGU menghasilkan `sudahTerdaftar: true`, urutan tetap, tanpa audit/event ENQUEUE baru. CHECK_IN valid dilanjutkan satu kali. DIPANGGIL/DILAYANI/SELESAI/DIBATALKAN/DILEWATI ditolak; SKIP/REQUEUE tetap melalui operasi existing.

**Kompatibilitas rollout:** `POST /check-in` tetap hanya CHECK_IN dan tetap menolak replay; `POST /queue/:id/masuk` tetap tersedia. CHECK_IN legacy yang terjadi setelah update ini memiliki bukti hash sehingga dapat dilanjutkan dengan QR semula sebelum expiry. CHECK_IN historis sebelum update yang tidak memiliki bukti hash tidak dapat dicocokkan secara aman dari token yang telah dikonsumsi; gunakan pemulihan ID tiket existing untuk enqueue. Tidak ada bypass QR, rekonstruksi token atau migration data historis. Jika bukti QR telah expired tetapi tiket sudah CHECK_IN, gunakan pemulihan tiket berwenang; QR baru hanya diterbitkan untuk DIPESAN sesuai kontrak lama.

### Error dan realtime

- 400: format/token tidak valid, tanggal/jam/konteks Hospital tidak sesuai.
- 401: JWT/sesi/akun tidak sah; 403: role/assignment/poli/ruang ditolak.
- 409: status akhir/telah dipanggil, data/counter tidak konsisten, atau konflik serialisasi setelah retry.
- 410: QR atau bukti QR expired. Tidak ada masa berlaku baru akibat scan ulang.

Setelah commit, kirim **ENQUEUE** melalui broadcaster existing ke `/queue` dan `/display` serta invalidasi dokter. Interceptor existing menginvalidasi pasien dan dokter dari hasil yang telah commit. Event socket tidak memuat nama/hash/payload QR. Tidak ada event CALL/TTS baru akibat scan check-in. Duplikasi invalidasi dapat dikoaleskan oleh loader existing; tidak menghasilkan mutasi tiket baru. Kegagalan broadcast tidak membatalkan transaksi tersimpan; REST snapshot dan polling fallback tetap sumber kebenaran.

Flutter PETUGAS langsung memproses deteksi QR lengkap tanpa konfirmasi kedua, mengunci request, menahan frame QR sama, dan siap membaca QR pasien berbeda. Input Manual tetap memakai tombol **Proses QR & Masuk Antrean**. Status sukses hanya tampil setelah respons MENUNGGU; error tidak membuat status lokal palsu. Kamera ditutup/dilepas saat keluar dan dihentikan ketika aplikasi tidak aktif. Bunyi sistem bersifat opsional/nonblocking sesuai dukungan platform dan izin audio.

Lihat [panduan dan QA One-Scan](../frontend/ONE_SCAN_QR.md).


## 27. Public Display — Antrian Pasien dan Status (26 Oktober 2026)

GET /display/:layananId/snapshot menambahkan field opsional berikut tanpa mengubah versiSkema=1 atau field menunggu existing:

- totalDilewati: jumlah tiket DILEWATI di poliklinik perangkat pada tanggal pelayanan SERVICE_TIME_ZONE.
- totalAntrianPasien: totalMenunggu + totalDilewati; tidak mencakup DIPESAN, CHECK_IN, DIPANGGIL, DILAYANI, SELESAI atau DIBATALKAN.
- antrianPasien: objek {nomorAntrean, namaPasien, status}. Status hanya MENUNGGU atau DILEWATI. Maksimum 100 MENUNGGU mengikuti comparator existing, kemudian maksimum 100 DILEWATI menurut urutanMasukAntrean/id. Urutan tampilan tidak mengubah kelayakan atau urutan CALL. SKIP tidak otomatis REQUEUE.

menunggu dan totalMenunggu mempertahankan arti semula. Semua daftar tetap dibatasi token/perangkat aktif, poliklinik dan tanggal yang sama. Hanya nama diproyeksikan; tidak ada ID akun, email, rekam medis atau data pribadi tambahan.

Nama lengkap memakai mekanisme server existing: DISPLAY_PATIENT_NAME_MODE=LENGKAP dan DISPLAY_FULL_NAMES_APPROVED=true. Permintaan operator pada revisi ini menyetujui aktivasi development; default source tetap SAMAR untuk instalasi lain. Flutter tidak membuka nama tersamar sendiri. Browser harus memakai backend terbaru dan snapshot baru. TTS mengikuti kebijakan nama yang sama, sementara deduplikasi peristiwaId tetap berlaku.

Tabel monitor berjudul **Antrian pasien**, dengan kolom NOMOR, NAMA PASIEN, STATUS. Angka header adalah total kedua status. Baris berganti halaman setiap 12 detik jika tidak muat; batas snapshot dan total tetap diinformasikan. Flutter lama tetap dapat membaca menunggu; Flutter baru fallback ke menunggu jika backend belum mengirim antrianPasien.


## 28. Multi-monitor Public Display dan isolasi pairing

POST /display/pairing menerima field opsional boolean isolasiSesi. Nilai true menulis HttpOnly cookie queueb_display_<UUID perangkat>; tanpa field mempertahankan cookie legacy queueb_display. Respons metadata perangkat tidak berubah dan tidak memuat raw token. Kode tetap sekali pakai/5 menit; sesi tetap 30 hari; JWT/RBAC ADMIN untuk provisioning/rotasi/pencabutan tidak berubah.

Klien Web baru menyimpan hanya UUID perangkat di sessionStorage, terpisah per tab dan API_BASE_URL. GET /display/sesi, GET /display/:layananId/snapshot dan POST /display/putuskan mengirim header opsional x-display-device-id; Socket.IO /display memakai auth.perangkatId bersama auth.layananId. Header/selector tidak memberikan hak akses sendiri: hanya cookie yang namanya sesuai selector dipakai, hash token harus menunjuk ID perangkat yang sama dan scope layanan diverifikasi kembali. Tidak ada fallback ke cookie perangkat lain. Token header/manual legacy tetap kompatibel.

Rotasi/nonaktifkan/forget sasaran A tidak memengaruhi perangkat B/C. Tab baru tidak mengambil cookie ambient milik monitor lain. Upgrade API dan Flutter bersama; tab Web lama tanpa selector perlu pairing ulang satu kali. Detail trade-off sessionStorage, duplicate tab, kuota cookies, keamanan same-origin dan hasil/batas pengujian ada di docs/frontend/PUBLIC_DISPLAY_MULTI_MONITOR.md. Tidak ada migration atau perubahan Queue Engine.
