# Login desktop: satu viewport

Perbaikan pada branch `codex/fix-login-desktop-viewport` mempertahankan identitas visual PR #53 dan seluruh alur autentikasi.

## Penyebab scroll

Kartu login sebelumnya memakai minimum 740 logical px. Padding luar 2 x 28, padding frame 2 x 18 dan border 2 x 3 membuat kebutuhan tinggi minimum 838 px. Panel kiri menambahkan panel layanan digital dan gap ke hero minimum 550 px. Pada viewport 1366 x 768, keduanya dapat memaksa `SingleChildScrollView` memiliki extent positif. Resolusi fisik monitor tidak sama dengan viewport Flutter setelah DPR, browser chrome, zoom, SafeArea dan keyboard.

## Solusi

- `LoginSizing` mengambil `LayoutBuilder.constraints` sesudah SafeArea dan skala teks dari MediaQuery. Budget kartu = tinggi tersedia dikurangi padding luar, padding frame dan border.
- Desktop lebar >=1024 px dengan tinggi <900 px memakai spacing compact, padding form 24 px, tombol dengan minimumSize 48 px dan input Material, heading 34 px dan divider lebih rapat. Tidak ada FittedBox atau pengurangan skala seluruh form.
- Panel kiri menggunakan budget hero dan panel digital sesuai tinggi/lebarnya. Ilustrasi memakai BoxFit.contain dengan tinggi proporsional, tanpa posisi negatif atau clipping. Seluruh tiga manfaat dan panel digital tetap ada; copy promosi sekunder panel digital disederhanakan pada compact desktop.
- Tinggi adalah minimum yang dapat tumbuh, bukan batas maksimum. Viewport sangat pendek (<680 logical px), teks besar, atau pesan yang sangat panjang mendapat fallback scroll normal sehingga kontrol tidak terpotong. `SingleChildScrollView` tetap ada, dengan extent 0 pada viewport desktop normal yang diuji.
- Tablet/mobile tetap memakai subtree, padding, tipografi, input dan ukuran tombol existing. Tidak ada perubahan backend, API, sesi, RBAC, route Public Display atau dashboard role.

## File

- `apps/client/lib/src/login_ui.dart`: budget viewport dan panel desktop adaptif.
- `apps/client/lib/src/app.dart`: parameter spacing/input/tombol khusus compact desktop.
- `apps/client/test/login_desktop_viewport_test.dart`: tes extent scroll, bounds kontrol, error/loading/registrasi, DPR dan fallback pendek.
- `apps/client/test/fixtures/fonts/`: Roboto regular/medium/bold dan LICENSE, khusus tes.
- Laporan ini dan screenshot viewport.

## Pengujian

Tes viewport memuat fixture font Material Roboto dari Flutter SDK 3.47.5 yang disertakan di `test/fixtures/fonts/` beserta lisensi Apache 2.0. Fixture hanya dipakai tes; tidak didaftarkan pada pubspec atau dimasukkan ke aplikasi. Cache SDK pada runner CI tidak selalu menyediakan font ini, sehingga tes tidak bergantung pada path/cache SDK. Font Ahem bawaan widget test bersifat monospace dengan metrik berbeda dari produksi; regresi existing tetap berjalan dengan font test-nya untuk memeriksa fallback tanpa overflow. Tes baru mengukur ScrollPosition.maxScrollExtent dan bounds semua kontrol penting, bukan hanya ukuran HTML canvas.

Target: 1280x720, 1366x768, 1440x900, 1536x864, 1920x1080 serta breakpoint 1024x768. Kondisi: awal, validasi kosong, error login, registrasi, loading, DPR 1.25, dan desktop pendek 1280x500. DPR 1.25 mempertahankan viewport logis 1366x768; pengaturan skala Windows global tidak diubah. Screenshot 375 px adalah layout Flutter mobile pada browser, bukan bukti perangkat Android fisik.

- Format: 55 file, 0 perubahan.
- Analyze: PASS, tanpa masalah.
- Seluruh Flutter test: **234 PASS, 1 conditional integration SKIP**; termasuk sembilan tes viewport baru.
- Enam viewport desktop: extent scroll 0 dan bounds kontrol di dalam viewport pada initial/validation/error/registration. Loading, DPR 1.25 dan fallback pendek juga lulus.
- Build Web release: **PASS** (101,4 detik), tanpa entry point atau API client khusus QA.
- Login, Public Display, registrasi, keyboard Tab/Enter, sesi, role, error dan loading tercakup regresi existing.


## Hasil browser

Pada kelima viewport target, `scrollHeight == clientHeight` dan `scrollWidth == clientWidth` pada document root. Bounds seluruh tombol (Masuk, Public Display, Daftar, toggle sandi) berada di dalam viewport. Pengukuran Flutter ScrollPosition dari tes di atas memastikan hasil ini bukan sekadar canvas HTML berukuran tetap sementara konten Flutter masih scroll.

Keyboard Tab berpindah dari email ke sandi dan Enter memicu validasi. Login kosong serta registrasi dengan tiga error masih menampilkan seluruh tombol dalam viewport 1366x768. Public Display membuka route aktivasi existing tanpa login. Tidak ada error runtime browser.

Screenshot mobile 375x900 dibandingkan dengan `images/login-web/04-mobile-375.jpg` dari PR #53: **berkas JPEG identik byte demi byte** (32.846 byte). Spacing, komposisi, ukuran kontrol dan hierarki mobile tidak berubah.

## Screenshot viewport

- [1280x720](images/login-viewport/01-1280x720.jpg)
- [1366x768](images/login-viewport/02-1366x768.jpg)
- [1440x900](images/login-viewport/03-1440x900.jpg)
- [1536x864](images/login-viewport/04-1536x864.jpg)
- [1920x1080](images/login-viewport/05-1920x1080.jpg)
- [Mobile 375px](images/login-viewport/06-mobile-375.jpg)

## Batas verifikasi

Tidak ada kredensial nyata dikirim, akun diubah, atau data database ditulis. Login/error/role/sesi diuji dengan mock API dan regresi existing. QA browser mengecek layout dan navigasi tanpa login. Pengaturan Windows 125% nyata dan perangkat Android fisik tidak diubah/digunakan; simulasi DPR dan screenshot viewport dicatat terpisah agar tidak dianggap tes perangkat.
