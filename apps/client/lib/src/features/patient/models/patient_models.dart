import '../../../api.dart';
import '../../../config.dart';
import '../../shared/safe_snapshot.dart';

enum PatientLoad { initial, loading, loaded, refreshing, failure, sessionEnded }

enum PatientMutation { idle, submitting, success, failure, unknown }

Object? freezePatient(Object? value) => safeSnapshot(value);

Json patientObject(Object? value) {
  if (value is! Map) {
    throw const ApiException(0, 'Respons belum terverifikasi.');
  }
  return freezePatient(value) as Json;
}

List<Json> patientRows(Object? value) {
  if (value is! List || value.any((row) => row is! Map)) {
    throw const ApiException(0, 'Respons daftar belum terverifikasi.');
  }
  return List<Json>.unmodifiable(value.map(patientObject));
}

class PatientSnapshot {
  PatientSnapshot([Map<String, List<Json>> collections = const {}])
    : collections = Map.unmodifiable(collections);
  final Map<String, List<Json>> collections;
  List<Json> rows(String path) => collections[path] ?? const [];
  List<Json> get services => rows('/layanan');
  List<Json> get doctors => rows('/dokter');
  List<Json> get schedules => rows('/jadwal-praktik');
  List<Json> get tickets => rows('/tiket/saya');
  List<Json> get appointments => rows('/janji-temu');
  Json? ticket(String id) => tickets.where((t) => t['id'] == id).firstOrNull;
}

ApiException patientError(Object error) {
  final status = error is ApiException ? error.status : 0;
  return ApiException(status, switch (status) {
    400 => 'Permintaan ditolak. Periksa pilihan dan aturan pelayanan.',
    401 => 'Sesi berakhir. Silakan masuk kembali.',
    403 => 'Anda tidak memiliki akses untuk tindakan ini.',
    404 => 'Data tidak ditemukan. Muat ulang data pelayanan.',
    409 =>
      'Data atau ketersediaan berubah. Periksa reservasi dan pilih kembali.',
    410 => 'Masa berlaku telah berakhir. Muat ulang sebelum melanjutkan.',
    429 => 'Terlalu banyak permintaan. Tunggu sebelum mencoba lagi.',
    _ when status >= 500 =>
      'Layanan sedang mengalami gangguan. Muat ulang data dan coba lagi nanti.',
    _ => 'Hasil permintaan belum dapat dipastikan. Muat ulang data sebelum melanjutkan.',
  });
}

bool uncertainPatient(Object error) =>
    error is! ApiException || error.status == 0 || error.status >= 500;

/// Only the dialog receives this temporary value. It is never emitted or cached.
class PatientQr {
  PatientQr(this.ticketId, this._payload, this.expiresAt);
  final String ticketId;
  final DateTime expiresAt;
  String? _payload;
  String? get payload => _payload;
  void clear() => _payload = null;
}
