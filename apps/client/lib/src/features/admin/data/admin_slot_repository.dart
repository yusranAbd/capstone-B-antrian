import '../../../api.dart';
import '../../../config.dart';
import '../models/admin_slot_models.dart';
import 'admin_catalog_repository.dart';

/// Transport and write guards only. Each session Cubit owns its slot snapshot.
class AdminSlotRepository {
  AdminSlotRepository(this.catalog);
  final AdminCatalogRepository catalog;
  final _writing = <String>{}, _unverified = <String>{};

  void check() {
    if (!catalog.active) throw const ApiException(401, 'Sesi ADMIN berubah.');
  }

  Future<List<Json>> read(String sessionId) async {
    check();
    final result = await catalog.api.request(
      'GET',
      '/slot-praktik',
      query: {'jadwalPraktikId': sessionId},
    );
    check();
    if (result is! List ||
        result.any(
          (r) =>
              r is! Map ||
              (r['jadwalPraktikId'] != null &&
                  r['jadwalPraktikId'] != sessionId),
        )) {
      throw const ApiException(
        0,
        'Respons slot tidak sesuai sesi. Muat ulang slot.',
      );
    }
    final snapshot = immutableSlotRows(rows(result));
    _unverified.remove(sessionId);
    return snapshot;
  }

  Future<Json> write(
    String sessionId,
    String method, {
    String? id,
    Json? body,
    bool permanent = false,
  }) async {
    check();
    if (_unverified.contains(sessionId) || !_writing.add(sessionId)) {
      throw const ApiException(
        409,
        'Muat ulang slot dan tunggu proses sebelumnya sebelum melanjutkan.',
      );
    }
    try {
      if (method == 'POST' && body?['jadwalPraktikId'] != sessionId) {
        throw const ApiException(400, 'Sesi slot tidak sesuai formulir.');
      }
      final result = await catalog.api.request(
        method,
        '/slot-praktik${id == null ? '' : '/$id'}${permanent ? '/permanen' : ''}',
        body: body,
      );
      check();
      if (result is! Map) {
        throw const ApiException(
          0,
          'Hasil penyimpanan slot belum dapat diverifikasi.',
        );
      }
      return immutableSlotRows([object(result)]).single;
    } catch (error) {
      if (error is! ApiException || error.status == 0 || error.status >= 500) {
        _unverified.add(sessionId);
      }
      rethrow;
    } finally {
      _writing.remove(sessionId);
    }
  }
}
