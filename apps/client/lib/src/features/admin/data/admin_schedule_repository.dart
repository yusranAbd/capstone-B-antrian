import '../../../api.dart';
import '../../../config.dart';
import '../models/admin_schedule_models.dart';
import 'admin_catalog_repository.dart';

const adminSchedulePaths = {'/jadwal-layanan', '/jadwal-praktik'};

/// Scheduling transport/operation coordinator; the 2A catalog remains the owner
/// of every list. Locks cover both ordinary CRUD and the multi-day dialog.
class AdminScheduleRepository {
  AdminScheduleRepository(this.catalog);
  final AdminCatalogRepository catalog;
  final _writing = <String>{}, _unverified = <String>{};
  void _check() {
    if (!catalog.active) throw const ApiException(401, 'Sesi ADMIN berubah.');
  }

  void _acquire(String path) {
    _check();
    if (!adminSchedulePaths.contains(path)) {
      throw ArgumentError.value(path, 'path');
    }
    if (_unverified.contains(path) || !_writing.add(path)) {
      throw const ApiException(
        409,
        'Tunggu proses jadwal atau muat ulang untuk memeriksa hasil sebelumnya.',
      );
    }
  }

  void acknowledgeRefresh(String path) => _unverified.remove(path);
  Future<void> reconcile(String path) async {
    _check();
    await catalog.refresh({
      ...catalog.snapshot.collections.keys,
      ...adminMasterPaths,
      ..._unverified,
      path,
    });
    _check();
    _unverified.clear();
  }

  Future<Json> write(
    String path,
    String method, {
    String? id,
    Json? body,
    bool permanent = false,
  }) async {
    _acquire(path);
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
          'Respons jadwal belum dapat diverifikasi. Muat ulang daftar.',
        );
      }
      return object(result);
    } catch (error) {
      if (error is! ApiException || error.status == 0 || error.status >= 500) {
        _unverified.add(path);
      }
      rethrow;
    } finally {
      _writing.remove(path);
    }
  }

  Future<List<ScheduleResult>> createDays({
    required String clinicId,
    required Set<String> days,
    required String opens,
    required String closes,
    required int capacity,
    required bool Function() current,
    void Function(List<ScheduleResult>)? onProgress,
  }) async {
    const path = '/jadwal-layanan';
    // An explicit new attempt begins with a verified REST preflight. It never
    // resends existing/successful days, including inactive configurations.
    _check();
    if (_writing.contains(path)) {
      throw const ApiException(409, 'Proses jadwal masih berjalan.');
    }
    _writing.add(path);
    try {
      final results = await createScheduleDays(
        catalog.api,
        clinicId: clinicId,
        days: Set.of(days),
        opens: opens,
        closes: closes,
        capacity: capacity,
        onProgress: onProgress,
        current: () => catalog.active && current(),
        readSchedules: () async {
          await catalog.refresh([path]);
          _check();
          _unverified.remove(path);
          return catalog.snapshot.rowsFor(path);
        },
      );
      try {
        await reconcile(path);
      } catch (_) {
        _unverified.add(path);
        rethrow;
      }
      return results;
    } finally {
      _writing.remove(path);
    }
  }
}

/// Existing sequential/preflight contract retained for compatibility callers.
Future<List<ScheduleResult>> createScheduleDays(
  QueueApi api, {
  required String clinicId,
  required Set<String> days,
  required String opens,
  required String closes,
  required int capacity,
  void Function(List<ScheduleResult>)? onProgress,
  bool Function()? current,
  Future<List<Json>> Function()? readSchedules,
}) async {
  void check() {
    if (current != null && !current()) {
      throw const ApiException(401, 'Scope jadwal telah ditutup.');
    }
  }

  Future<List<Json>> read() async => readSchedules != null
      ? readSchedules()
      : rows(await api.request('GET', '/jadwal-layanan'));
  check();
  final existing = await read();
  check();
  final results = <ScheduleResult>[];
  for (final day in scheduleDays.where(Set.of(days).contains)) {
    check();
    if (existing.any((r) => r['layananId'] == clinicId && r['hari'] == day)) {
      results.add(
        ScheduleResult(
          day,
          ScheduleOutcome.existing,
          'Jadwal sudah ada (termasuk yang nonaktif). Gunakan Ubah pada daftar.',
        ),
      );
    } else {
      try {
        await api.request(
          'POST',
          '/jadwal-layanan',
          body: {
            'layananId': clinicId,
            'hari': day,
            'jamBuka': opens,
            'jamTutup': closes,
            'kapasitasHarian': capacity,
          },
        );
        results.add(
          ScheduleResult(day, ScheduleOutcome.created, 'Berhasil disimpan.'),
        );
      } catch (error) {
        check();
        bool found = false;
        try {
          final latest = await read();
          found = latest.any(
            (r) => r['layananId'] == clinicId && r['hari'] == day,
          );
        } catch (_) {
          /* Keep the uncertain result; never retry POST. */
        }
        final uncertain =
            error is! ApiException || error.status == 0 || error.status >= 500;
        results.add(
          ScheduleResult(
            day,
            found
                ? ScheduleOutcome.existing
                : uncertain
                ? ScheduleOutcome.uncertain
                : ScheduleOutcome.failed,
            found
                ? 'Jadwal ditemukan setelah pemeriksaan ulang. Gunakan Ubah untuk memeriksanya.'
                : uncertain
                ? '$error Hasil belum terverifikasi. Muat ulang daftar sebelum mencoba lagi.'
                : '$error',
          ),
        );
      }
    }
    check();
    onProgress?.call(List.unmodifiable(results));
  }
  return List.unmodifiable(results);
}
