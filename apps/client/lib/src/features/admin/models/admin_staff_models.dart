import '../../../api.dart';
import '../../../config.dart';

const adminStaffPaths = {'/akun-petugas', '/penugasan-petugas'};
const _accountFields = {'id', 'nama', 'email', 'peran', 'aktif'};
Json staffAccountMetadata(Json source) => {
  for (final key in _accountFields)
    if (key == 'aktif' ? source[key] is bool : source[key] is String)
      key: source[key],
};

Object? _withoutSecrets(Object? value) {
  if (value is List) return value.map(_withoutSecrets).toList();
  if (value is Map) {
    return {
      for (final entry in value.entries)
        if (!RegExp(
          r'password|katasandi|token|secret|hash',
          caseSensitive: false,
        ).hasMatch('${entry.key}'))
          '${entry.key}': _withoutSecrets(entry.value),
    };
  }
  return value;
}

/// Sanitize before publishing into the shared catalog, including legacy reads.
List<Json> staffCollection(String path, Object? response) {
  if (response is! List || response.any((r) => r is! Map)) {
    throw const ApiException(
      0,
      'Respons data petugas belum dapat diverifikasi. Muat ulang daftar.',
    );
  }
  if (path == '/akun-petugas') {
    return rows(response)
        .where((r) => r['peran'] == 'PETUGAS')
        .map(staffAccountMetadata)
        .toList();
  }
  return rows(_withoutSecrets(response));
}

/// Credential-bearing requests never publish arbitrary server text or causes.
ApiException safeAccountCreateError(Object error) {
  final status = error is ApiException ? error.status : 0;
  return ApiException(status, switch (status) {
    400 => 'Data akun ditolak. Periksa nama, email, dan ketentuan kata sandi.',
    401 => 'Sesi ADMIN berakhir. Silakan masuk kembali.',
    403 => 'Pembuatan akun PETUGAS hanya diizinkan untuk ADMIN.',
    409 => 'Email sudah digunakan atau akun berubah. Muat ulang daftar akun sebelum melanjutkan.',
    _ => 'Hasil pembuatan akun belum dapat dipastikan. Muat ulang daftar akun sebelum mencoba lagi.',
  });
}
