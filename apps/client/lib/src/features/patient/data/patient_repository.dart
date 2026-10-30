import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../api.dart';
import '../../../config.dart';
import '../../../patient_sync.dart';
import '../models/patient_models.dart';
import '../models/patient_queue_models.dart';

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
    this.updates.queueSubscribed.addListener(_queueFeedChanged);
    this.updates.status.addListener(_queueFeedChanged);
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
  final queueState = ValueNotifier(PatientQueueState());
  Set<String> _queueIds = const {};
  String _queueDate = '';
  final _queueValues = <String, PatientQueueSummary>{};
  final _queueDirty = <String>{}, _queueErrors = <String>{};
  Set<String> _queueReading = const {};
  Future<void>? _queuePending;
  int _queueEpoch = 0, _queueRevision = 0;

  /// Presentation configures the visible Home service identities outside build.
  void configureQueueScope(Iterable<String> services, String date) {
    if (!active || !validPatientQueueDate(date)) return;
    final ids = services.where((id) => id.isNotEmpty).toSet();
    if (setEquals(ids, _queueIds) && date == _queueDate) {
      updates.watchQueue(ids, date);
      return;
    }
    _queueEpoch++;
    _queueRevision++;
    if (date != _queueDate) _queueValues.clear();
    _queueValues.removeWhere((id, _) => !ids.contains(id));
    _queueIds = Set.unmodifiable(ids);
    _queueDate = date;
    _queueDirty.clear();
    _queueReading = const {};
    _queueErrors.clear();
    _queueDirty.addAll(ids);
    _publishQueue();
    updates.watchQueue(ids, date);
    unawaited(refreshQueue());
  }

  void _queueFeedChanged() {
    if (active) _publishQueue();
  }

  void _publishQueue() {
    if (!active) return;
    queueState.value = PatientQueueState(
      date: _queueDate,
      summaries: _queueValues,
      loading: {..._queueReading, ..._queueDirty},
      errors: _queueErrors,
      connected: updates.queueConnected,
    );
  }

  Future<void> refreshQueue([Iterable<String>? services]) {
    if (!active || _queueIds.isEmpty || _queueDate.isEmpty) {
      return Future.value();
    }
    final ids = (services ?? _queueIds).where(_queueIds.contains).toSet();
    if (ids.isEmpty) return Future.value();
    _queueDirty.addAll(ids);
    _queueRevision++;
    _publishQueue();
    return _queuePending ??= _drainQueue().whenComplete(() async {
      _queuePending = null;
      if (active && _queueDirty.isNotEmpty) {
        await refreshQueue(Set.of(_queueDirty));
      }
    });
  }

  Future<void> _drainQueue() async {
    while (active && _queueDirty.isNotEmpty) {
      final ids = Set<String>.of(_queueDirty),
          epoch = _queueEpoch,
          revision = _queueRevision,
          date = _queueDate;
      _queueDirty.clear();
      _queueReading = ids;
      _publishQueue();
      try {
        final path = Uri(
          path: '/layanan/antrean',
          queryParameters: {
            'tanggal': date,
            'layananId': (ids.toList()..sort()).join(','),
          },
        ).toString();
        final raw = await api.request('GET', path);
        if (!active) return;
        if (epoch != _queueEpoch) continue;
        if (revision != _queueRevision) {
          _queueDirty.addAll(ids);
          continue;
        }
        final summaries = PatientQueueSummary.parseBatch(raw, ids, date);
        _queueValues.addAll(summaries);
        _queueErrors.removeAll(ids);
      } catch (_) {
        if (!active) return;
        if (epoch != _queueEpoch) continue;
        if (revision != _queueRevision) {
          _queueDirty.addAll(ids);
          continue;
        }
        _queueErrors.addAll(ids);
      }
      if (epoch == _queueEpoch && active) {
        _queueReading = const {};
        _publishQueue();
      }
    }
  }

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
    _queueEpoch++;
    _queueDirty.clear();
    _queueValues.clear();
    queueState.value = PatientQueueState();
    _closeFeed();
    notifyListeners();
  }

  void _closeFeed() {
    if (_feedDisposed) return;
    _feedDisposed = true;
    updates.removeListener(_invalidated);
    updates.queueSubscribed.removeListener(_queueFeedChanged);
    updates.status.removeListener(_queueFeedChanged);
    updates.dispose();
  }

  void _invalidated() {
    if (!active) return;
    final kinds = updates.lastKinds;
    if (kinds.contains('ANTREAN') || kinds.contains('KATALOG')) {
      unawaited(
        refreshQueue(
          kinds.contains('KATALOG') || updates.lastQueueIds.isEmpty
              ? null
              : updates.lastQueueIds,
        ),
      );
    }
    final visitKinds = kinds.intersection({'TIKET', 'KATALOG'});
    if (visitKinds.isEmpty) return;
    refresh({
      if (kinds.contains('TIKET')) ...patientVisitPaths,
      if (kinds.contains('KATALOG')) ...patientCatalogPaths,
    });
    invalidations.value = (invalidations.value.$1 + 1, visitKinds);
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
    queueState.dispose();
    invalidations.dispose();
    super.dispose();
  }
}
