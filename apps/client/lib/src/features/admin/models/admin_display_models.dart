import '../../../api.dart';
import '../../../config.dart';

const adminDisplayPath = '/perangkat-display';
const _deviceFields = {
  'id',
  'nama',
  'layananId',
  'aktif',
  'terakhirAktifPada',
  'dibuatPada',
  'diperbaruiPada',
};
Json displayMetadata(Json source) => {
  for (final key in _deviceFields)
    if (source.containsKey(key) &&
        (key == 'aktif'
            ? source[key] is bool
            : source[key] == null || source[key] is String))
      key: source[key],
  if (source['layanan'] is Map)
    'layanan': {
      for (final key in ['id', 'kode', 'nama', 'aktif'])
        if (key == 'aktif'
            ? object(source['layanan'])[key] is bool
            : object(source['layanan'])[key] is String)
          key: object(source['layanan'])[key],
    },
};
List<Json> displayCollection(Object? response) {
  if (response is! List || response.any((row) => row is! Map)) {
    throw const ApiException(
      0,
      'Respons daftar perangkat belum dapat diverifikasi. Muat ulang daftar.',
    );
  }
  return rows(response).map(displayMetadata).toList();
}

/// A short-lived return value for the UI only. Never placed in Cubit state,
/// repository fields, catalog, persistence, logging, or exception text.
class DisplayActivation {
  DisplayActivation(this.deviceId, this._code, this.expiresAt);
  final String deviceId;
  final DateTime expiresAt;
  String? _code;
  String? get code => _code;
  void clear() => _code = null;
}

ApiException safeDisplayError(Object error) {
  final status = error is ApiException ? error.status : 0;
  return ApiException(status, switch (status) {
    400 => 'Data perangkat ditolak. Periksa nama dan poliklinik aktif.',
    401 => 'Sesi ADMIN berakhir. Silakan masuk kembali.',
    403 => 'Manajemen perangkat hanya diizinkan untuk ADMIN.',
    404 => 'Perangkat tidak ditemukan. Muat ulang daftar.',
    409 => 'Perangkat ditolak karena relasi atau perubahan bersamaan. Muat ulang sebelum melanjutkan.',
    429 => 'Batas permintaan perangkat tercapai. Tunggu sebelum mencoba lagi.',
    _ => 'Hasil tindakan perangkat belum dapat dipastikan. Muat ulang metadata; kode aktivasi sekali tampil tidak dapat dipulihkan.',
  });
}
