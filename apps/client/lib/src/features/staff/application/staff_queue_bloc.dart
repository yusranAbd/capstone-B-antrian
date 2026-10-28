import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../api.dart';
import '../../../config.dart';
import '../data/staff_queue_repository.dart';
import '../models/staff_queue_models.dart';
import 'staff_queue_event.dart';
import 'staff_queue_state.dart';

/// One feature owner. Every mutation enters the same synchronous admission gate.
class StaffQueueBloc extends Bloc<StaffQueueEvent, StaffQueueState> {
  StaffQueueBloc(
    this.repository, {
    bool polling = true,
    Timer Function(Duration, void Function(Timer))? periodicTimer,
  }) : super(StaffQueueState()) {
    repository.addListener(_sessionChanged);
    on<StaffQueueEvent>((event, emit) async {
      switch (event) {
        case StaffRefresh():
          await _refresh(emit: emit, assignments: event.assignments);
          if (!event.completion.isCompleted) event.completion.complete();
        case StaffRoomSelected():
          if (_running ||
              !_active ||
              !state.assignments.any((a) => a['loketId'] == event.roomId)) {
            return;
          }
          _changeRoom(event.roomId, emit);
          await _refresh(emit: emit);
        case StaffPageSelected():
          if (_running || !_active || event.page < 1) return;
          final max =
              object(
                state.snapshot?['daftarPasien'],
              )['jumlahHalamanTindakLanjut'] ??
              1;
          if (event.page > max) return;
          _generation++;
          _pending = null;
          emit(
            state.copy(
              page: event.page,
              clearSnapshot: true,
              synchronized: false,
            ),
          );
          await _refresh(emit: emit);
        case StaffSessionEnded():
          emit(
            StaffQueueState(
              load: StaffLoad.ended,
              liveStatus: 'Sesi petugas berakhir.',
            ),
          );
          if (!_closing) unawaited(close());
        case StaffRealtimeStatus():
          if (_active) emit(state.copy(liveStatus: event.status));
        case StaffCommand():
          await _command(event, emit);
      }
    });
    if (polling) {
      _poll = (periodicTimer ?? Timer.periodic)(const Duration(seconds: 15), (
        _,
      ) {
        if (_active) unawaited(refresh());
      });
    }
  }
  final StaffQueueRepository repository;
  Timer? _poll;
  int _generation = 0;
  bool _running = false, _ended = false, _closing = false;
  bool _dirty = false, _assignmentsDirty = false;
  Future<void>? _pending;
  Future<void>? _closeFuture;
  _StaffRecovery? _recovery;
  final _commands = <StaffCommand>{};
  bool get _active => !_closing && !isClosed && !_ended && repository.active;
  bool _current(int generation) => _active && generation == _generation;
  void _sessionChanged() {
    if (_active || _ended) return;
    _ended = true;
    _generation++;
    _poll?.cancel();
    _recovery = null;
    if (!_closing && !isClosed) add(StaffSessionEnded());
    for (final event in _commands) {
      event.takeQr();
      _fail(event, const ApiException(401, 'Sesi petugas berubah.'));
    }
  }

  Future<void> refresh({bool assignments = false}) {
    if (!_active) return Future.value();
    final event = StaffRefresh(assignments: assignments);
    add(event);
    return event.completion.future;
  }

  Future<Json> execute(
    StaffOperation operation, {
    String? ticketId,
    String? qr,
  }) {
    final event = StaffCommand(operation, ticketId: ticketId, qr: qr);
    // Observe even if a caller abandons a dialog while the HTTP request finishes.
    unawaited(
      event.completion.future.then<void>(
        (_) {},
        onError: (Object _, StackTrace _) {},
      ),
    );
    if (!_active) {
      event.takeQr();
      _fail(event, const ApiException(401, 'Sesi petugas berubah.'));
    } else {
      _commands.add(event);
      add(event);
    }
    return event.completion.future;
  }

  void _changeRoom(String? room, Emitter<StaffQueueState> emit) {
    _generation++;
    _pending = null;
    repository.stopFeed();
    emit(
      StaffQueueState(
        assignments: state.assignments,
        roomId: room,
        date: repository.today,
        load: room == null ? StaffLoad.loaded : StaffLoad.loading,
        command: _recovery == null
            ? StaffCommandStatus.idle
            : StaffCommandStatus.uncertain,
        error: _recovery == null ? null : staffUncertain,
        scheduleLoading: room != null,
      ),
    );
    if (room != null) {
      repository.connect(
        '${object(state.room?['layanan'])['id']}',
        () {
          if (_active) unawaited(refresh());
        },
        (status) {
          if (_active) add(StaffRealtimeStatus(status));
        },
      );
    }
  }

  /// All callers await the drain, including invalidations received mid-fetch.
  Future<void> _refresh({
    required Emitter<StaffQueueState> emit,
    bool assignments = false,
  }) {
    if (!_active) return Future.value();
    _assignmentsDirty |= assignments || state.load == StaffLoad.initial;
    final valid = state.assignments
        .where((a) => assignmentValid(a, repository.today))
        .toList();
    if (state.date != null &&
        (state.date != repository.today ||
            valid.length != state.assignments.length)) {
      emit(state.copy(assignments: valid));
      _changeRoom(
        valid.any((a) => a['loketId'] == state.roomId)
            ? state.roomId
            : valid.firstOrNull?['loketId'],
        emit,
      );
    }
    _dirty = true;
    emit(
      state.copy(
        load: state.snapshot == null ? StaffLoad.loading : StaffLoad.refreshing,
        synchronized: false,
      ),
    );
    if (_pending != null) return _pending!;
    final completion = Completer<void>();
    final future = _pending = completion.future;
    unawaited(() async {
      try {
        final generation = _generation;
        do {
          await _drain(generation, emit);
        } while (_dirty && _current(generation));
      } catch (error) {
        if (_active && !emit.isDone) _readFailed(error, emit);
      } finally {
        if (identical(_pending, future)) _pending = null;
        completion.complete();
      }
    }());
    return future;
  }

  Future<void> _drain(int generation, Emitter<StaffQueueState> emit) async {
    while (_dirty && _current(generation)) {
      _dirty = false;
      if (_assignmentsDirty) {
        _assignmentsDirty = false;
        try {
          final all = await repository.assignments();
          if (!_current(generation)) return;
          final valid = all
              .where((a) => assignmentValid(a, repository.today))
              .toList();
          final selected = valid.any((a) => a['loketId'] == state.roomId)
              ? state.roomId
              : valid.firstOrNull?['loketId'] as String?;
          final oldRoom = state.room;
          emit(
            state.copy(
              assignments: valid,
              clearFeedback: !_running && _recovery == null,
            ),
          );
          if (selected != state.roomId ||
              object(oldRoom?['layanan'])['id'] !=
                  object(state.room?['layanan'])['id']) {
            _changeRoom(selected, emit);
            await _refresh(emit: emit);
            return;
          }
        } catch (error) {
          if (!_current(generation)) return;
          _readFailed(error, emit, assignments: true);
          return;
        }
      }
      if (state.room == null) {
        emit(
          state.copy(
            load: StaffLoad.loaded,
            clearSnapshot: true,
            schedules: [],
            synchronized: false,
          ),
        );
        return;
      }
      final room = state.roomId!,
          service = '${object(state.room!['layanan'])['id']}';
      final page = state.page;
      Json data;
      try {
        data = await repository.snapshot(room, page);
        if (!_current(generation)) return;
        if (data['tanggalPelayanan'] != repository.today) {
          throw const ApiException(0, 'Tanggal pelayanan belum terverifikasi.');
        }
        final max =
            object(data['daftarPasien'])['jumlahHalamanTindakLanjut'] ?? 1;
        if (max is! int || max < 1) {
          throw const ApiException(0, 'Halaman belum terverifikasi.');
        }
        if (page > max) {
          emit(state.copy(page: max, clearSnapshot: true));
          _dirty = true;
          continue;
        }
        if ((object(data['daftarPasien'])['halamanTindakLanjut'] ?? page) !=
            page) {
          throw const ApiException(0, 'Halaman belum terverifikasi.');
        }
        emit(
          state.copy(
            snapshot: data,
            date: '${data['tanggalPelayanan']}',
            load: StaffLoad.loaded,
            scheduleLoading: state.schedules.isEmpty,
            clearFeedback: !_running && _recovery == null,
          ),
        );
      } catch (error) {
        if (!_current(generation)) return;
        _readFailed(error, emit);
        // A burst already queued still gets its trailing attempt.
        continue;
      }
      try {
        final schedules = await repository.schedules(
          service,
          room,
          '${data['tanggalPelayanan']}',
        );
        if (!_current(generation)) return;
        emit(
          state.copy(
            schedules: schedules,
            scheduleLoading: false,
            scheduleFailed: false,
          ),
        );
      } catch (error) {
        if (!_current(generation)) return;
        final failure = staffError(error);
        if ([401, 403].contains(failure.status)) {
          _readFailed(failure, emit);
          continue;
        }
        emit(
          state.copy(
            schedules: [],
            scheduleLoading: false,
            scheduleFailed: true,
          ),
        );
      }
      if (!_dirty) {
        emit(state.copy(synchronized: true, load: StaffLoad.loaded));
        if (!_running) _resolveRecovery(emit);
      }
    }
  }

  void _readFailed(
    Object error,
    Emitter<StaffQueueState> emit, {
    bool assignments = false,
  }) {
    final failure = staffError(error);
    final denied = [401, 403].contains(failure.status);
    emit(
      state.copy(
        load: StaffLoad.failed,
        synchronized: false,
        error: failure.message,
        errorStatus: failure.status,
        clearSnapshot: denied,
        schedules: denied ? [] : null,
        scheduleLoading: false,
      ),
    );
    if (assignments && denied) {
      repository.stopFeed();
      emit(
        StaffQueueState(
          load: StaffLoad.failed,
          error: failure.message,
          errorStatus: failure.status,
        ),
      );
    }
  }

  bool _allowed(StaffCommand event) {
    final id = event.ticketId;
    final active = state.active
        .where((t) => (t['tiketId'] ?? t['id']) == id)
        .firstOrNull;
    final row = state.patients
        .where((t) => (t['tiketId'] ?? t['id']) == id)
        .firstOrNull;
    return switch (event.operation) {
      StaffOperation.call => state.active.isEmpty,
      StaffOperation.scan => true,
      StaffOperation.recall ||
      StaffOperation.skip ||
      StaffOperation.start => active?['status'] == 'DIPANGGIL',
      StaffOperation.complete => active?['status'] == 'DILAYANI',
      StaffOperation.requeue =>
        row?['status'] == 'DILEWATI' && row?['bisaAntreUlang'] == true,
      StaffOperation.enqueue =>
        row?['status'] == 'CHECK_IN' && row?['bisaMasukAntrean'] == true,
    };
  }

  Future<void> _command(
    StaffCommand event,
    Emitter<StaffQueueState> emit,
  ) async {
    var qr = event.takeQr();
    if (!_active ||
        _running ||
        state.blocked ||
        state.room == null ||
        state.date != repository.today ||
        !assignmentValid(
          state.assignments.firstWhere((a) => a['loketId'] == state.roomId),
          repository.today,
        ) ||
        !_allowed(event)) {
      qr = null;
      _fail(
        event,
        const ApiException(
          409,
          'Tunggu proses atau muat ulang antrean sebelum tindakan berikutnya.',
        ),
      );
      _commands.remove(event);
      return;
    }
    if (event.operation == StaffOperation.scan &&
        (qr == null || !RegExp(r'^SQ1\.[A-Za-z0-9_-]{43}$').hasMatch(qr))) {
      qr = null;
      _fail(
        event,
        const ApiException(400, 'Format QR tidak lengkap atau tidak valid.'),
      );
      _commands.remove(event);
      return;
    }
    _running = true; // No await before the shared admission lock.
    final generation = _generation, room = state.roomId!, date = state.date!;
    final before = [
      ...state.active,
      ...state.patients,
    ].where((t) => (t['tiketId'] ?? t['id']) == event.ticketId).firstOrNull;
    emit(
      state.copy(
        command: StaffCommandStatus.sending,
        mutationConfirmed: false,
        pending: event.operation,
        clearFeedback: true,
      ),
    );
    Json? result;
    ApiException? failure;
    try {
      try {
        result = await repository.command(
          event.operation,
          room,
          ticketId: event.ticketId,
          qr: qr,
        );
      } catch (error) {
        failure = staffError(error);
      } finally {
        qr = null;
      }
      if (!_current(generation)) {
        _fail(
          event,
          const ApiException(
            401,
            'Konteks pelayanan berubah. Periksa antrean kembali.',
          ),
        );
        return;
      }
      if (result != null || (failure != null && uncertainStaff(failure))) {
        _recovery = _StaffRecovery(
          event.operation,
          room,
          date,
          event.ticketId,
          before,
          result,
        );
      }
      emit(
        state.copy(
          command: StaffCommandStatus.reconciling,
          mutationConfirmed: result != null,
          synchronized: false,
        ),
      );
      await _refresh(emit: emit);
      if (!_current(generation)) {
        _fail(
          event,
          const ApiException(
            401,
            'Konteks pelayanan berubah. Periksa antrean kembali.',
          ),
        );
        return;
      }
      if (_recovery != null) {
        _resolveRecovery(emit);
      } else {
        emit(
          state.copy(
            command: StaffCommandStatus.failed,
            clearPending: true,
            error: failure?.message,
            errorStatus: failure?.status,
          ),
        );
      }
      if (state.command == StaffCommandStatus.confirmed && result != null) {
        if (!event.completion.isCompleted) event.completion.complete(result);
      } else {
        _fail(
          event,
          ApiException(failure?.status ?? 0, state.error ?? staffUnsynced),
        );
      }
    } finally {
      _running = false;
      _commands.remove(event);
    }
  }

  void _resolveRecovery(Emitter<StaffQueueState> emit) {
    final recovery = _recovery;
    if (recovery == null) return;
    final same = state.roomId == recovery.room && state.date == recovery.date;
    bool proven = false;
    if (same &&
        state.synchronized &&
        recovery.result == null &&
        recovery.id != null) {
      final row = [
        ...state.active,
        ...state.patients,
      ].where((t) => (t['tiketId'] ?? t['id']) == recovery.id).firstOrNull;
      final beforeVersion = recovery.before?['versi'],
          afterVersion = row?['versi'];
      proven =
          row?['status'] == recovery.operation.expectedStatus &&
          (recovery.operation != StaffOperation.recall ||
              (beforeVersion is int &&
                  afterVersion is int &&
                  afterVersion > beforeVersion));
    }
    if (same && state.synchronized && (recovery.result != null || proven)) {
      _recovery = null;
      emit(
        state.copy(
          command: recovery.result != null
              ? StaffCommandStatus.confirmed
              : StaffCommandStatus.idle,
          clearPending: true,
          clearFeedback: true,
        ),
      );
      if (recovery.result != null) {
        emit(
          state.copy(
            message:
                '${recovery.result!['nomorAntrean']} · ${recovery.result!['status']}',
          ),
        );
      } else {
        emit(
          state.copy(
            message: 'Status tiket telah diverifikasi dari antrean terbaru.',
          ),
        );
      }
    } else {
      emit(
        state.copy(
          command: recovery.result != null
              ? StaffCommandStatus.unsynced
              : StaffCommandStatus.uncertain,
          clearPending: true,
          error: recovery.result != null ? staffUnsynced : staffUncertain,
        ),
      );
    }
  }

  void _fail(StaffCommand event, ApiException error) {
    if (!event.completion.isCompleted) event.completion.completeError(error);
  }

  @override
  Future<void> close() {
    if (_closeFuture != null) return _closeFuture!;
    if (!_ended && !isClosed) add(StaffSessionEnded());
    _ended = true;
    _closing = true;
    _generation++;
    _poll?.cancel();
    repository.removeListener(_sessionChanged);
    repository.stopFeed();
    _recovery = null;
    for (final event in _commands) {
      event.takeQr();
      _fail(event, const ApiException(401, 'Portal petugas ditutup.'));
    }
    // In-flight transport cannot be cancelled; handlers ignore its late result.
    return _closeFuture = super.close();
  }
}

class _StaffRecovery {
  _StaffRecovery(
    this.operation,
    this.room,
    this.date,
    this.id,
    this.before,
    this.result,
  );
  final StaffOperation operation;
  final String room, date;
  final String? id;
  final Json? before, result;
}
