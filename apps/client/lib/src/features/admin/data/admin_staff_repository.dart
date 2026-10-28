import '../../../api.dart';
import '../../../config.dart';
import '../models/admin_catalog_models.dart';
import '../models/admin_staff_models.dart';
import 'admin_catalog_repository.dart';

/// One portal-owned transport adapter. The existing catalog owns both lists.
class AdminStaffRepository {
  AdminStaffRepository(this.catalog);
  final AdminCatalogRepository catalog;
  bool _writing = false;
  final _unverified = <String>{};
  void _check() {
    if (!catalog.active) throw const ApiException(401, 'Sesi ADMIN berubah.');
  }

  void acknowledgeRefresh(Iterable<String> paths) =>
      _unverified.removeAll(paths);
  Future<void> refresh(Iterable<String> paths) async {
    _check();
    final targets = paths.toSet();
    await catalog.refresh(targets);
    _check();
    acknowledgeRefresh(targets);
  }

  Future<void> reconcile(String path) async {
    _check();
    try {
      await catalog.refresh({
        ...catalog.snapshot.collections.keys,
        ...adminMasterPaths,
        ...adminStaffPaths,
      });
      _check();
      _unverified.clear();
    } catch (_) {
      _unverified.add(path);
      rethrow;
    }
  }

  Future<Json> write(
    String path,
    String method, {
    String? id,
    Json? body,
    bool permanent = false,
  }) async {
    _check();
    if (!adminStaffPaths.contains(path) ||
        (path == '/akun-petugas' &&
            (method != 'POST' && method != 'PATCH' || permanent))) {
      throw const ApiException(400, 'Tindakan akun/penugasan tidak didukung.');
    }
    if (_writing || _unverified.isNotEmpty) {
      throw const ApiException(
        409,
        'Muat ulang data petugas dan tunggu proses sebelumnya sebelum melanjutkan.',
      );
    }
    _writing = true;
    try {
      final result = await catalog.api.request(
        method,
        '$path${id == null ? '' : '/$id'}${permanent ? '/permanen' : ''}',
        body: body,
      );
      _check();
      if (result is! Map) {
        throw const ApiException(
          0,
          'Respons tindakan petugas belum dapat diverifikasi.',
        );
      }
      Json value = object(result);
      if (path == '/akun-petugas') {
        value = staffAccountMetadata(value);
        if (value['id'] is! String || value['peran'] != 'PETUGAS') {
          throw const ApiException(
            0,
            'Metadata akun belum dapat diverifikasi.',
          );
        }
      } else {
        value = staffCollection(path, [value]).single;
      }
      return AdminCatalogSnapshot({
        path: [value],
      }).rowsFor(path).single;
    } catch (error) {
      if (error is! ApiException || error.status == 0 || error.status >= 500) {
        _unverified.add(path);
      }
      if (path == '/akun-petugas' && method == 'POST') {
        throw safeAccountCreateError(error);
      }
      rethrow;
    } finally {
      _writing = false;
    }
  }
}
