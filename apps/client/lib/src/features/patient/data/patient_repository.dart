import 'package:flutter/foundation.dart';

import '../../../api.dart';
import '../../../config.dart';
import '../../../patient_sync.dart';
import '../models/patient_models.dart';

const patientCatalogPaths = {'/layanan', '/dokter', '/jadwal-praktik'};
const patientVisitPaths = {'/tiket/saya', '/janji-temu'};
const patientOverviewPaths = {...patientCatalogPaths, ...patientVisitPaths};

/// One portal owner for catalog and owned visits, and one shared realtime feed.
class PatientRepository extends ChangeNotifier {
  PatientRepository(this.api, {PatientUpdates? updates})
    : _identity = (api.user?['id'], api.user?['peran']),
      updates = updates ?? PatientUpdates(api: api) {
    api.addListener(_sessionChanged);
    this.updates.addListener(_invalidated);
  }
  final QueueApi api;
  final PatientUpdates updates;
  final (Object?, Object?) _identity;
  final invalidations = ValueNotifier<(int, Set<String>)>((0, const {}));
  PatientSnapshot _snapshot = PatientSnapshot();
  PatientSnapshot get snapshot => _snapshot;
  final _dirty = <String>{};
  final _errors = <String, ApiException>{};
  Map<String, ApiException> get errors => Map.unmodifiable(_errors);
  Future<void>? _pending;
  final _cancelling = <String>{}, _issuing = <String>{};
  bool _ended = false, _disposed = false, _feedDisposed = false;
  int _epoch = 0;
  bool get active =>
      !_disposed &&
      !_ended &&
      api.sessionPhase == SessionPhase.ready &&
      _identity == (api.user?['id'], api.user?['peran']) &&
      api.user?['peran'] == 'USER';
  void check() {
    if (!active) throw const ApiException(401, 'Sesi pasien berubah.');
  }

  void _sessionChanged() {
    if (_ended || active) return;
    _ended = true;
    _epoch++;
    _dirty.clear();
    _errors.clear();
    _snapshot = PatientSnapshot();
    _closeFeed();
    notifyListeners();
  }

  void _closeFeed() {
    if (_feedDisposed) return;
    _feedDisposed = true;
    updates.removeListener(_invalidated);
    updates.dispose();
  }

  void _invalidated() {
    if (!active) return;
    final kinds = updates.lastKinds;
    refresh({
      if (kinds.contains('TIKET')) ...patientVisitPaths,
      if (kinds.contains('KATALOG')) ...patientCatalogPaths,
    });
    invalidations.value = (invalidations.value.$1 + 1, kinds);
  }

  /// All readers await the same drain, including every required trailing read.
  Future<void> refresh([Iterable<String> paths = patientOverviewPaths]) {
    if (!active) return Future.value();
    _dirty.addAll(paths);
    return _pending ??= _drain().whenComplete(() {
      _pending = null;
    });
  }

  Future<void> _drain() async {
    while (_dirty.isNotEmpty && active) {
      final paths = _dirty.toList(), epoch = _epoch;
      _dirty.clear();
      final values = <String, List<dynamic>>{};
      Future<void> fetch(String path) async {
        try {
          final response = await api.request('GET', path);
          if (path.startsWith('/tiket/') &&
              path != '/tiket/saya' &&
              (response is! Map ||
                  response['id'] != path.substring('/tiket/'.length))) {
            throw const ApiException(0, 'Identitas tiket belum terverifikasi.');
          }
          values[path] = path.startsWith('/tiket/') && path != '/tiket/saya'
              ? [patientObject(response)]
              : patientRows(response);
          if (active && epoch == _epoch) _errors.remove(path);
        } catch (error) {
          if (active && epoch == _epoch) _errors[path] = patientError(error);
        }
      }

      bool detail(String path) =>
          path.startsWith('/tiket/') && path != '/tiket/saya';
      await Future.wait(paths.where((p) => !detail(p)).map(fetch));
      // Detail follows list reads so one canonical ticket cannot be overwritten
      // by an older list response from the same drain.
      for (final path in paths.where(detail)) {
        await fetch(path);
      }
      if (!active || epoch != _epoch) return;
      final next = {..._snapshot.collections};
      for (final entry in values.entries) {
        if (entry.key.startsWith('/tiket/') && entry.key != '/tiket/saya') {
          final ticket = patientObject(entry.value.single);
          next['/tiket/saya'] = List.unmodifiable([
            ...(next['/tiket/saya'] ?? const <Json>[]).where(
              (t) => t['id'] != ticket['id'],
            ),
            ticket,
          ]);
          next['/janji-temu'] = patientRows([
            for (final appt in next['/janji-temu'] ?? const [])
              if (object(appt['tiket'])['id'] == ticket['id'])
                {...appt, 'tiket': ticket}
              else
                appt,
          ]);
        } else {
          next[entry.key] = List<Json>.unmodifiable(entry.value.cast<Json>());
        }
      }
      // Keep one ticket status across list, appointment, agenda and detail views.
      if (values.containsKey('/janji-temu') &&
          !values.containsKey('/tiket/saya')) {
        final tickets = {
          for (final row in next['/tiket/saya'] ?? const <Json>[])
            row['id']: row,
        };
        for (final appointment in next['/janji-temu'] ?? const <Json>[]) {
          final ticket = object(appointment['tiket']);
          if (ticket['id'] is String) {
            tickets[ticket['id']] = patientObject({
              ...?tickets[ticket['id']],
              ...ticket,
            });
          }
        }
        if (tickets.isNotEmpty || next.containsKey('/tiket/saya')) {
          next['/tiket/saya'] = List.unmodifiable(tickets.values);
        }
      }
      final tickets = {
        for (final row in next['/tiket/saya'] ?? const <Json>[]) row['id']: row,
      };
      if (next.containsKey('/janji-temu')) {
        next['/janji-temu'] = patientRows([
          for (final appointment in next['/janji-temu']!)
            if (tickets.containsKey(object(appointment['tiket'])['id']))
              {
                ...appointment,
                'tiket': tickets[object(appointment['tiket'])['id']],
              }
            else
              appointment,
        ]);
      }
      _snapshot = PatientSnapshot(next);
      notifyListeners();
    }
  }

  Future<void> cancelAppointment(String id) async {
    check();
    if (!_cancelling.add(id)) {
      throw const ApiException(409, 'Pembatalan masih berjalan.');
    }
    try {
      patientObject(
        await api.request('POST', '/janji-temu/$id/batalkan', body: {}),
      );
      check();
    } catch (error) {
      throw patientError(error);
    } finally {
      _cancelling.remove(id);
    }
  }

  Future<PatientQr> issueQr(String ticketId) async {
    check();
    if (!_issuing.add(ticketId)) {
      throw const ApiException(409, 'Penerbitan QR masih berjalan.');
    }
    try {
      final result = object(
        await api.request('POST', '/tiket/$ticketId/qr', body: {}),
      );
      check();
      final payload = result['qrPayload'],
          expiry = DateTime.tryParse('${result['berlakuHingga']}');
      if (expiry != null && !expiry.isAfter(api.config.now)) {
        throw const ApiException(410, 'QR sudah kedaluwarsa.');
      }
      if (result['tiketId'] != ticketId ||
          payload is! String ||
          !payload.startsWith('SQ1.') ||
          payload.length <= 4 ||
          expiry == null ||
          !expiry.isAfter(api.config.now)) {
        throw const ApiException(
          0,
          'QR sudah kedaluwarsa atau belum dapat diverifikasi.',
        );
      }
      return PatientQr(ticketId, payload, expiry);
    } catch (error) {
      throw patientError(error);
    } finally {
      _issuing.remove(ticketId);
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _epoch++;
    _dirty.clear();
    api.removeListener(_sessionChanged);
    _closeFeed();
    invalidations.dispose();
    super.dispose();
  }
}
