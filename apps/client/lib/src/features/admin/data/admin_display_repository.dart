import '../../../api.dart';
import '../../../config.dart';
import '../models/admin_catalog_models.dart';
import '../models/admin_display_models.dart';
import 'admin_catalog_repository.dart';

class AdminDisplayRepository {
  AdminDisplayRepository(this.catalog);
  final AdminCatalogRepository catalog;
  bool _writing = false;
  void check() {
    if (!catalog.active) throw const ApiException(401, 'Sesi ADMIN berubah.');
  }

  Future<void> refresh({Iterable<String>? paths}) async {
    check();
    try {
      await catalog.refresh(paths ?? {adminDisplayPath, '/layanan'});
      check();
    } catch (error) {
      throw safeDisplayError(error);
    }
  }

  Future<Object> command(String action, {String? id, Json? body}) async {
    check();
    if (_writing) {
      throw const ApiException(409, 'Tindakan perangkat masih berjalan.');
    }
    _writing = true;
    try {
      final (method, path) = switch (action) {
        'create' => ('POST', adminDisplayPath),
        'update' => ('PATCH', '$adminDisplayPath/$id'),
        'delete' => ('DELETE', '$adminDisplayPath/$id/permanen'),
        'revoke' => ('POST', '$adminDisplayPath/$id/nonaktifkan'),
        'activate' => ('POST', '$adminDisplayPath/$id/aktivasi'),
        _ => throw const ApiException(
          400,
          'Tindakan perangkat tidak didukung.',
        ),
      };
      final response = await catalog.api.request(method, path, body: body);
      check();
      if (response is! Map) {
        throw const ApiException(0, 'Respons tindakan belum terverifikasi.');
      }
      final result = object(response);
      if (action == 'activate') {
        final code = result['kode'],
            expiry = DateTime.tryParse('${result['berlakuHingga']}');
        if (code is! String ||
            !RegExp(r'^\d{12}$').hasMatch(code) ||
            expiry == null ||
            !expiry.isAfter(catalog.api.config.now)) {
          throw const ApiException(
            0,
            'Kode aktivasi belum dapat diverifikasi.',
          );
        }
        return DisplayActivation(id!, code, expiry);
      }
      return AdminCatalogSnapshot({
        adminDisplayPath: [displayMetadata(result)],
      }).rowsFor(adminDisplayPath).single;
    } catch (error) {
      throw safeDisplayError(error);
    } finally {
      _writing = false;
    }
  }
}
