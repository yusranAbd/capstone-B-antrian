# QueueB Hospital — project instructions

## UI/UX

- Baca `docs/frontend/QUEUEB_UI_UX_GUIDELINES.md` sebelum mengubah tampilan Flutter. Panduan tersebut adalah acuan desain proyek yang mandiri.
- Gunakan kebutuhan operasional QueueB dan arahan pengguna sebagai dasar keputusan. Jangan menggunakan skill, skor evaluasi, atau panduan desain pihak ketiga sebagai acuan proyek. Dasarkan keputusan pada panduan QueueB dan arahan pengguna.
- Pertahankan branding, tema dan komponen reusable existing. Gunakan skala berbeda untuk portal operasional, pasien mobile, dan Public Display.
- Fokus pada perubahan terarah; jangan redesign total, menambahkan dekorasi/aset generatif, atau mengecilkan seluruh tema secara global.
- Pertahankan accessibility/text scaling, auth, realtime, QR, pagination dan cleanup resource. Jangan menampilkan data atau metrik buatan.

## Integritas dan pengujian

- Ikuti kontrak `docs/backend/API_INTEGRATION_GUIDE.md`. Pekerjaan visual tidak mengubah API, RBAC, Queue Engine, database atau migration.
- Pertahankan perubahan lokal, backup, dan file rahasia. Stage file/hunk terkait tugas secara eksplisit; jangan memakai `git add -A`, reset destruktif, clean massal atau force push.
- Ikuti otorisasi Git dalam permintaan pengguna yang aktif; jangan membuat commit/push/merge di luar cakupan tersebut.
- Jalankan format pada file berubah, Flutter analyze, regresi yang relevan, dan build Web sebelum menyatakan perubahan UI selesai. Laporkan hasil aktual dan batas pengujian.
- Tes database yang menulis hanya boleh pada PostgreSQL lokal `127.0.0.1:5433/capstone_antrean_test` dengan validasi target dan cleanup fixture unik. Jangan gunakan data development untuk pengujian destruktif.
