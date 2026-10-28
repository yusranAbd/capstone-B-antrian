import 'package:flutter/foundation.dart';

import '../../../api.dart';
import '../../../config.dart';
import '../models/admin_catalog_models.dart';
import '../models/admin_staff_models.dart';

const adminMasterPaths = {'/layanan', '/dokter', '/loket'};

/// Owned by the ADMIN portal. Legacy modules only read/publish through this
/// catalog; no second parent cache and no socket or authentication manager.
class AdminCatalogRepository extends ChangeNotifier {
  AdminCatalogRepository(this.api)
    : _identity = (api.user?['id'], api.user?['peran']) {
    api.addListener(_sessionChanged);
  }
  final QueueApi api;
  final (Object?, Object?) _identity;
  AdminCatalogSnapshot _snapshot = AdminCatalogSnapshot({});
  AdminCatalogSnapshot get snapshot => _snapshot;
  bool _active = true, _disposed = false;
  int _epoch = 0;
  final _dirty = <String>{};
  Future<void>? _pending;
  bool get active =>
      !_disposed &&
      _active &&
      api.sessionPhase == SessionPhase.ready &&
      _identity == (api.user?['id'], api.user?['peran']);

  void _sessionChanged() {
    if (!_active || (active && api.user != null)) return;
    _active = false;
    _epoch++;
    _dirty.clear();
    _snapshot = AdminCatalogSnapshot({});
    notifyListeners();
  }

  void _check() {
    if (!active) {
      throw const ApiException(
        401,
        'Sesi ADMIN berubah. Silakan masuk kembali.',
      );
    }
  }

  Future<void> refresh(Iterable<String> paths) {
    _check();
    _dirty.addAll(paths);
    return _pending ??= _drain().whenComplete(() {
      _pending = null;
      if (_dirty.isNotEmpty && active) return refresh(const []);
    });
  }

  Future<void> _drain() async {
    while (_dirty.isNotEmpty && active) {
      final paths = _dirty.toList(), epoch = _epoch;
      _dirty.clear();
      final values = await Future.wait(
        paths.map((path) async {
          final result = await api.request('GET', path);
          return adminStaffPaths.contains(path)
              ? staffCollection(path, result)
              : rows(result);
        }),
      );
      if (!active || epoch != _epoch) return;
      _snapshot = AdminCatalogSnapshot({
        ..._snapshot.collections,
        for (var i = 0; i < paths.length; i++) paths[i]: values[i],
      });
      notifyListeners();
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
    if (!adminMasterPaths.contains(path)) {
      throw ArgumentError.value(path, 'path');
    }
    final result = await api.request(
      method,
      '$path${id == null ? '' : '/$id'}${permanent ? '/permanen' : ''}',
      body: body,
    );
    _check();
    if (result is! Map) {
      throw const ApiException(
        0,
        'Respons mutasi tidak valid. Muat ulang katalog sebelum mencoba lagi.',
      );
    }
    return object(result);
  }

  Future<void> reconcile() =>
      refresh({...snapshot.collections.keys, ...adminMasterPaths});

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _epoch++;
    _dirty.clear();
    api.removeListener(_sessionChanged);
    super.dispose();
  }
}
