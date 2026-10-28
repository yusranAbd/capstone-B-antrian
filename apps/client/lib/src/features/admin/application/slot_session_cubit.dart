import 'dart:async';
import 'dart:convert';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../api.dart';
import '../../../config.dart';
import '../data/admin_slot_repository.dart';
import '../models/admin_slot_models.dart';
import 'slot_session_state.dart';

/// One immutable slot owner per practice session, with one active read and one
/// coalesced trailing invalidation. No fetch is started by construction/build.
class SlotSessionCubit extends Cubit<SlotSessionState> {
  SlotSessionCubit(this.repository, Json session)
    : _session = immutableSlotRows([session]).single,
      super(SlotSessionState(sessionId: '${session['id']}')) {
    _dependencies = _fingerprint();
    repository.catalog.addListener(_catalogChanged);
  }
  final AdminSlotRepository repository;
  Json _session;
  late String _dependencies;
  bool _closing = false, _ended = false, _expanded = false, _dirty = true;
  int _epoch = 0, _invalidationRevision = 0;
  int get invalidationRevision => _invalidationRevision;
  Completer<void>? _pending;
  bool get expanded => _expanded;
  Future<void> get settled => _pending?.future ?? Future.value();
  bool get _current =>
      !_closing && !isClosed && !_ended && repository.catalog.active;

  String _fingerprint() {
    final data = repository.catalog.snapshot;
    final link = object(_session['dokterLayanan']);
    final clinic =
        link['layananId'] ??
        object(link['layanan'])['id'] ??
        _session['layananId'];
    final doctor = link['dokterId'] ?? object(link['dokter'])['id'];
    final room = _session['loketId'] ?? object(_session['loket'])['id'];
    return jsonEncode([
      _session,
      data.rowsFor('/layanan').where((r) => r['id'] == clinic).toList(),
      data.rowsFor('/dokter').where((r) => r['id'] == doctor).toList(),
      data.rowsFor('/loket').where((r) => r['id'] == room).toList(),
      data
          .rowsFor('/jadwal-layanan')
          .where((r) => r['layananId'] == clinic)
          .toList(),
    ]);
  }

  String _context(Json session) {
    final link = object(session['dokterLayanan']);
    return jsonEncode([
      session['dokterLayananId'],
      link['layananId'],
      link['dokterId'] ?? object(link['dokter'])['id'],
      session['loketId'],
    ]);
  }

  void _end(SlotLoadStatus status) {
    _ended = true;
    _epoch++;
    _dirty = false;
    emit(SlotSessionState(sessionId: state.sessionId, load: status));
    unawaited(close());
  }

  void _catalogChanged() {
    if (_closing || isClosed || _ended) return;
    if (!repository.catalog.active) {
      _end(SlotLoadStatus.sessionEnded);
      return;
    }
    final data = repository.catalog.snapshot;
    if (data.collections.containsKey('/jadwal-praktik')) {
      final session = data
          .rowsFor('/jadwal-praktik')
          .where((r) => r['id'] == state.sessionId)
          .firstOrNull;
      if (session == null) {
        _end(SlotLoadStatus.sessionRemoved);
        return;
      }
      if (_context(_session) != _context(session)) {
        emit(
          state.copyWith(
            slots: [],
            hasLoaded: false,
            load: SlotLoadStatus.initial,
          ),
        );
      }
      _session = session;
    }
    final next = _fingerprint();
    if (next == _dependencies) return;
    _dependencies = next;
    _epoch++;
    invalidate();
  }

  void setExpanded(bool value) {
    _expanded = value;
    if (value && _dirty && _current) unawaited(refresh());
  }

  void invalidate() {
    if (!_current) return;
    _invalidationRevision++;
    _dirty = true;
    if (_expanded) unawaited(refresh());
  }

  Future<void> refresh() {
    if (!_current) return Future.value();
    _dirty = true;
    if (_pending != null) return _pending!.future;
    final completion = Completer<void>();
    _pending = completion;
    unawaited(_drain(completion));
    return completion.future;
  }

  Future<void> _drain(Completer<void> completion) async {
    try {
      // Backpressure: one HTTP read at a time and at most one dirty follow-up.
      // A sustained stream can keep the drain alive, but never adds parallel
      // reads or automatic failure retries. Every waiter observes the drain.
      while (_dirty && _current) {
        _dirty = false;
        final epoch = _epoch;
        emit(
          state.copyWith(
            load: state.hasLoaded
                ? SlotLoadStatus.refreshing
                : SlotLoadStatus.loading,
            clearLoadError: true,
          ),
        );
        try {
          final slots = await repository.read(state.sessionId);
          if (!_current) break;
          if (epoch != _epoch || _dirty) continue;
          emit(
            state.copyWith(
              slots: slots,
              hasLoaded: true,
              load: slots.isEmpty
                  ? SlotLoadStatus.empty
                  : SlotLoadStatus.loaded,
              clearLoadError: true,
              needsReconciliation: false,
            ),
          );
        } catch (error) {
          if (!_current) break;
          if (epoch != _epoch || _dirty) continue;
          emit(state.copyWith(load: SlotLoadStatus.failure, loadError: error));
        }
      }
    } finally {
      _pending = null;
      completion.complete();
    }
  }

  Future<Json> save(Json body, {String? id}) =>
      _write(id == null ? 'POST' : 'PATCH', id: id, body: body);
  Future<Json> delete(String id) => _write('DELETE', id: id, permanent: true);
  Future<Json> deactivate(String id) => _write('DELETE', id: id);

  Future<Json> _write(
    String method, {
    String? id,
    Json? body,
    bool permanent = false,
  }) async {
    if (!_current) {
      throw const ApiException(401, 'Scope sesi slot telah berakhir.');
    }
    if (state.mutating || state.needsReconciliation) {
      throw const ApiException(
        409,
        'Muat ulang slot sebelum melanjutkan tindakan.',
      );
    }
    emit(
      state.copyWith(
        mutation: SlotMutationStatus.submitting,
        clearMutationError: true,
      ),
    );
    Json? result;
    Object? failure;
    try {
      result = await repository.write(
        state.sessionId,
        method,
        id: id,
        body: body,
        permanent: permanent,
      );
    } catch (error) {
      failure = error;
    }
    final uncertain =
        failure != null &&
        (failure is! ApiException ||
            failure.status == 0 ||
            failure.status >= 500);
    if (_current && (failure == null || uncertain)) await refresh();
    if (!_current) {
      throw const ApiException(401, 'Scope sesi slot telah berakhir.');
    }
    emit(
      state.copyWith(
        mutation: failure == null
            ? SlotMutationStatus.success
            : uncertain
            ? SlotMutationStatus.unknown
            : SlotMutationStatus.failure,
        mutationError: failure,
        clearMutationError: failure == null,
        needsReconciliation:
            (failure == null || uncertain) &&
            state.load == SlotLoadStatus.failure,
      ),
    );
    if (failure != null) throw failure;
    return result!;
  }

  @override
  Future<void> close() {
    _closing = true;
    _epoch++;
    repository.catalog.removeListener(_catalogChanged);
    return super.close();
  }
}
