import '../../../api.dart';
import '../../../config.dart';
import '../../shared/safe_snapshot.dart';

enum StaffOperation {
  call('panggil', 'DIPANGGIL'),
  recall('panggil-ulang', 'DIPANGGIL'),
  skip('lewati', 'DILEWATI'),
  requeue('antre-ulang', 'MENUNGGU'),
  start('mulai-pelayanan', 'DILAYANI'),
  complete('selesaikan-pelayanan', 'SELESAI'),
  enqueue('masuk', 'MENUNGGU'),
  scan('auto-antrean', 'MENUNGGU');

  const StaffOperation(this.route, this.expectedStatus);
  final String route, expectedStatus;
}

Json staffObject(dynamic value) {
  if (value is! Map) {
    throw const ApiException(0, 'Respons belum terverifikasi.');
  }
  return safeSnapshot(value) as Json;
}

List<Json> staffRows(dynamic value) {
  if (value is! List || value.any((e) => e is! Map)) {
    throw const ApiException(0, 'Respons belum terverifikasi.');
  }
  return List.unmodifiable(value.map(staffObject));
}

ApiException staffError(Object error) {
  final status = error is ApiException ? error.status : 0;
  return ApiException(status, switch (status) {
    400 => 'Data atau QR tidak valid untuk pelayanan ini.',
    401 => 'Sesi petugas berakhir. Silakan masuk kembali.',
    403 => 'Akses atau penugasan pelayanan ditolak.',
    404 => 'Tiket atau antrean belum tersedia. Muat ulang antrean.',
    409 => 'Antrean berubah. Muat ulang sebelum melakukan tindakan.',
    410 => 'QR telah kedaluwarsa. Gunakan QR yang masih berlaku.',
    429 => 'Terlalu banyak permintaan. Tunggu sebelum mencoba kembali.',
    _ => 'Koneksi pelayanan belum dapat dipastikan. Muat ulang antrean.',
  });
}

bool uncertainStaff(ApiException error) =>
    error.status == 0 || error.status >= 500;

const staffUncertain =
    'Hasil tindakan belum dapat dipastikan. Tidak dikirim ulang. Muat ulang untuk memeriksa antrean.';
const staffUnsynced =
    'Tindakan dikonfirmasi server; antrean belum tersinkron. Muat ulang antrean sebelum tindakan berikutnya.';
