import '../../../api.dart';
import '../../../config.dart';
import '../../shared/safe_snapshot.dart';

class AccountProfilePartial extends ApiException {
  const AccountProfilePartial()
    : super(
        0,
        'Perubahan tersimpan, tetapi profil terbaru belum dapat dimuat. Muat ulang profil sebelum melanjutkan.',
      );
}

/// Shared by every role. QueueApi continues to own identity and session storage.
class AccountProfileRepository {
  AccountProfileRepository(this.api)
    : identity = (api.user?['id'], api.user?['peran']);
  final QueueApi api;
  final (Object?, Object?) identity;
  bool get active =>
      api.sessionPhase == SessionPhase.ready &&
      api.user != null &&
      identity == (api.user?['id'], api.user?['peran']);
  Json get profile => safeSnapshot({
    for (final key in ['id', 'nama', 'email', 'peran', 'aktif', 'avatarProfil'])
      if (api.user?.containsKey(key) == true) key: api.user![key],
  }) as Json;
  void check() {
    if (!active) throw const ApiException(401, 'Sesi akun berubah.');
  }

  Future<void> reload() async {
    check();
    await api.reloadOwnProfile();
    check();
  }

  Future<Object?> roleData() async {
    check();
    final role = identity.$2;
    final Object? result = role == 'PETUGAS'
        ? await api.request('GET', '/penugasan-petugas')
        : role == 'DOKTER'
        ? await Future.wait([
            api.request('GET', '/portal-dokter/profil'),
            api.request(
              'GET',
              '/portal-dokter/jadwal',
              query: {'tanggal': api.config.today},
            ),
          ])
        : null;
    check();
    return safeSnapshot(result);
  }

  Future<void> name(String value) async {
    check();
    await api.updateOwnName(value);
    check();
  }

  Future<void> avatar(List<int>? bytes) async {
    check();
    await api.request(
      bytes == null ? 'DELETE' : 'POST',
      '/auth/me/avatar',
      photoBytes: bytes,
    );
    check();
    try {
      await api.reloadOwnProfile();
      check();
    } catch (_) {
      throw const AccountProfilePartial();
    }
  }

  Future<void> password(String oldValue, String newValue) async {
    check();
    await api.changeOwnPassword(oldValue, newValue);
  }
}

ApiException profileError(Object error, {String? operation}) {
  final status = error is ApiException ? error.status : 0;
  return ApiException(status, switch (status) {
    400 =>
      operation == 'password'
          ? 'Perubahan kata sandi ditolak. Periksa kata sandi lama dan baru.'
          : 'Perubahan profil ditolak. Periksa isian atau berkas foto.',
    401 => 'Sesi berakhir. Silakan masuk kembali.',
    403 => 'Anda tidak memiliki akses untuk perubahan ini.',
    429 => 'Batas perubahan akun tercapai. Tunggu sebelum mencoba lagi.',
    _ => 'Hasil perubahan belum dapat dipastikan. Muat ulang profil sebelum melanjutkan.',
  });
}
