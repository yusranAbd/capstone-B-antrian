# Portal PETUGAS — compact refinement

Perubahan hanya pada layout, tipografi, dan akses profil PETUGAS. Tidak ada perubahan backend, endpoint, RBAC, database/migration, FIFO, prioritas Queue Engine, ataupun lifecycle Socket.IO/polling.

## Penyebab overflow dan perbaikan

Layout sebelumnya menempatkan kartu jadwal dokter di atas daftar antrean pada kolom kiri yang memiliki tinggi tetap berdasarkan viewport. Dua jadwal dokter dalam satu ruang mengurangi tinggi daftar; header pencarian, header tabel, pagination lokal, pagination tindak lanjut server dan footer tidak lagi muat. Tes baru pada baseline mereproduksi `RenderFlex overflowed by 16 pixels on the bottom` di viewport 1280×640.

- Jadwal dokter kini berupa strip di atas kedua kolom, dengan dua item sejajar pada desktop. Grid tetap dibatasi tinggi dan dapat di-scroll jika jadwal banyak; nama panjang dibatasi dua baris dan ukuran baris mengikuti text scaler.
- Proporsi kolom berubah dari **65:35 menjadi 54:46**. Panel **Pelayanan ruang ini** memperoleh lebar lebih besar untuk nomor aktif serta tindakan utama.
- Budget tinggi area antrean/pelayanan dipangkas dan dibatasi; tidak mengorbankan tinggi daftar hanya karena jadwal dokter bertambah. Konten tambahan seperti pesan error/hasil QR atau formulir manual tetap dapat diakses melalui scroll halaman.
- Daftar mempertahankan pagination lokal dan server. Pada ruang vertikal yang sangat terbatas, seluruh isi daftar mendapat viewport scroll terikat, sehingga header/footer tidak menyebabkan RenderFlex overflow. Urutan dan kelayakan tindakan tetap bersumber dari snapshot backend.
- `StaffStyle` mengecilkan text theme khusus PETUGAS, tinggi input dan spacing panel. Warna, radius, avatar, label status dan kontrol existing tetap digunakan. Nomor aktif tetap menonjol.
- Outer padding desktop 16–20px, gap antar section 16px, padding card 12px, header 56px. Tablet/mobile mempertahankan alur satu kolom yang dapat di-scroll.
- Dropdown profil dan callback logout header dihapus. Seluruh area avatar/nama menjadi tombol yang langsung membuka `UserProfilePage`. Logout existing tetap tersedia pada **Profil Saya → Keluar Akun**, dengan session cleanup yang sama.

## Validasi aktual

- Format: enam file Dart yang berubah, 0 perubahan tersisa.
- `flutter analyze`: **PASS, 0 issues**.
- Tes terarah: **34 PASS** (12 regresi baru ditambah tes operasional PETUGAS existing).
- Seluruh suite lokal Flutter: **412 PASS, 1 SKIP**. Termasuk tes revisi Dashboard Dokter lokal pengguna yang dipertahankan di luar commit. Tes yang dilewati adalah integrasi backend live yang membutuhkan runner database test terisolasi.
- `flutter build web --release`: **PASS**. Artefak lokal mempertahankan revisi Dokter pengguna yang belum dikomit; perubahan tersebut tidak ikut staging.
- Chrome 155 dengan build release, API dan Socket.IO fixture sintetis: **9 kelompok alur PASS, 9 viewport PASS, 0 error browser**. Uji ini tidak mengakses database development/test dan tidak menggunakan kredensial pengguna.
- Alur Chrome: login/jadwal, pencarian pasien, SKIP/REQUEUE tanpa duplikasi, CALL/RECALL/START/COMPLETE, CHECK_IN legacy/Masuk Antrean, QR One-Scan manual, isolasi ruang, reconnect dan refresh snapshot melalui Socket.IO, profil langsung dan logout dari profil.
- Viewport utama **1280×720, 1366×768, 1440×900, 1920×1080**: kontrol utama dan QR dalam viewport, tanpa horizontal document overflow. Widget tests juga memeriksa tidak adanya exception RenderFlex, dua dokter satu ruang, dua lapis pagination, serta tombol pelayanan DIPANGGIL/DILAYANI.
- Tambahan: 1280×640, 768×1024, 320×740, 375×812, 414×896. Ukuran sempit tetap memakai scroll vertikal, bukan memaksakan seluruh konten dalam satu layar.
- Tes existing tetap memverifikasi nama panjang, pagination, respons jadwal lama, busy/error, polling/resume/dispose dan pencabutan penugasan. Tidak ada timer, stream, controller atau listener baru.

Laporan browser: [staff-compact-browser-qa.json](staff-compact-browser-qa.json).

## Screenshot release dengan data sintetis

- [1280×720](images/staff-compact/staff-1280x720.png)
- [1366×768](images/staff-compact/staff-1366x768.png)
- [1440×900](images/staff-compact/staff-1440x900.png)
- [1920×1080](images/staff-compact/staff-1920x1080.png)
- [Viewport pendek](images/staff-compact/staff-1280x640.png)
- [Tablet](images/staff-compact/staff-768x1024.png)
- [320px](images/staff-compact/staff-320x740.png), [375px](images/staff-compact/staff-375x812.png), [414px](images/staff-compact/staff-414x896.png)

## File utama

- `apps/client/lib/src/staff_v4.dart`: header langsung ke profil, strip dokter dan tabel pasien compact/scroll fallback.
- `apps/client/lib/src/staff_ui.dart`: theme PETUGAS, padding dan hierarchy panel.
- `apps/client/lib/src/queue.dart`: komposisi section, proporsi kolom, tinggi area pelayanan dan QR.
- `apps/client/lib/src/app.dart`: hanya wiring header PETUGAS; tidak mengubah session/auth flow.
- `apps/client/test/staff_compact_test.dart`: reproduksi/regresi dua jadwal, pagination, viewport pendek, aksi pelayanan dan profil/logout.
- `apps/client/test/login_ui_test.dart`: logout PETUGAS mengikuti rute profil existing.
- `apps/client/tool/browser-staff-v4.cjs`: mode `compact: true`, fixture dua dokter satu ruang, matriks resolusi dan pemeriksaan profil langsung; mode default sebelumnya dipertahankan.

## Reproduksi

```powershell
Set-Location apps/client
flutter analyze
flutter test
flutter build web --release --dart-define=API_BASE_URL=http://localhost:3000/api/v1 --dart-define=SERVICE_TIME_ZONE=Asia/Jakarta
```

Runner Chrome memakai dependensi QA existing `@playwright/test` dan `socket.io`, ditambah CanvasKit serta Roboto cache SDK Flutter. Dari root repository, atur `NODE_PATH` ke node_modules tooling dan apps/api, `QUEUEB_CANVASKIT_DIR` serta `QUEUEB_ROBOTO_FILE` ke cache SDK, lalu:

```powershell
node -e "require('./apps/client/tool/browser-staff-v4.cjs')({build:'apps/client/build/web',output:'tmp/staff-compact-browser',compact:true,engineRoot:process.env.QUEUEB_CANVASKIT_DIR,fontFile:process.env.QUEUEB_ROBOTO_FILE}).then(r=>console.log(JSON.stringify(r))).catch(e=>{console.error(e.message);process.exitCode=1})"
```

`localhost:5173` saat pemeriksaan masih merupakan server Flutter debug. Source baru membutuhkan **hot restart** pada proses `flutter run` yang aktif lalu refresh browser. Build release tidak otomatis menggantikan runtime debug; proses pengguna tidak dihentikan atau diganti secara diam-diam.

Sembilan entri file/direktori lokal pengguna tetap dipertahankan dan file yang memiliki checksum tetap identik. Tidak ada branch baru/PR; commit serta push normal langsung ke main mengikuti instruksi pengguna. Backend/database tidak disentuh pada task ini.
