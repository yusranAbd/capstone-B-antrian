import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../api.dart';
import '../../../config.dart';
import '../data/display_monitor_repository.dart';
import '../models/display_models.dart';
import '../services/announcement_gate.dart';
import '../services/display_audio_controller.dart';

sealed class DisplayMonitorEvent {
  @override
  String toString() => runtimeType.toString();
}

final class DisplayRefresh extends DisplayMonitorEvent {
  DisplayRefresh({this.silent = false});
  final bool silent;
  final completion = Completer<void>();
}

final class DisplayScopeChanged extends DisplayMonitorEvent {
  DisplayScopeChanged(this.generation);
  final int generation;
}

final class DisplayMonitorClosed extends DisplayMonitorEvent {}

final class DisplayConnectionChanged extends DisplayMonitorEvent {
  DisplayConnectionChanged(this.value);
  final String value;
}

final class DisplayInvalidated extends DisplayMonitorEvent {
  DisplayInvalidated(this.value);
  final Json value;
}

class DisplayMonitorBloc
    extends Bloc<DisplayMonitorEvent, DisplayMonitorState> {
  DisplayMonitorBloc(
    this.repository,
    this.audio, {
    bool polling = true,
    Timer Function(Duration, void Function(Timer))? periodicTimer,
  }) : super(DisplayMonitorState()) {
    repository.devices.addListener(_scopeChanged);
    on<DisplayMonitorEvent>((event, emit) async {
      switch (event) {
        case DisplayScopeChanged():
          if (_closing || event.generation != _generation) return;
          repository.disconnect();
          _pending = null;
          _dirty = false;
          _signals = _consumed = 0;
          _gate = AnnouncementGate();
          final scope = repository.devices.scope,
              failure = repository.devices.rejection;
          emit(
            DisplayMonitorState(
              scope: scope,
              loading: scope != null,
              rejected: failure != null,
              error: failure?.message,
              errorStatus: failure?.status,
              status: repository.devices.api.config.realtime
                  ? 'Menghubungkan…'
                  : 'Sinkronisasi berkala',
            ),
          );
          if (scope != null && !_closing) {
            audio.context(true);
            final generation = _generation;
            repository.connect(
              scope,
              () {
                if (_valid(generation, scope)) unawaited(refresh());
              },
              (status) {
                if (_valid(generation, scope)) {
                  add(DisplayConnectionChanged(status));
                }
              },
              (value) {
                if (_valid(generation, scope)) add(DisplayInvalidated(value));
              },
            );
            if (!repository.devices.api.config.realtime) await _refresh(emit);
          }
        case DisplayRefresh():
          if (event.silent) _rebase();
          await _refresh(emit);
          if (!event.completion.isCompleted) event.completion.complete();
        case DisplayConnectionChanged():
          if (!_active) return;
          _rebase();
          if (event.value.startsWith('Token perangkat ditolak')) {
            repository.devices.begin(
              failure: displayError(const ApiException(401, '')),
            );
          } else {
            emit(state.copy(status: event.value));
          }
        case DisplayInvalidated():
          if (!_active) return;
          final id = event.value['eventId'];
          if (id is String && !_events.add(id)) return;
          if (_events.length > 256) _events.remove(_events.first);
          if (event.value['perluPeriksaPengumuman'] == true &&
              ['CALL', 'RECALL'].contains(event.value['aksi'])) {
            _signals++;
          }
          await _refresh(emit);
        case DisplayMonitorClosed():
          emit(DisplayMonitorState());
      }
    });
    if (polling) {
      _poll = (periodicTimer ?? Timer.periodic)(const Duration(seconds: 15), (
        _,
      ) {
        if (_active) unawaited(refresh());
      });
    }
    if (repository.devices.scope != null) _scopeChanged();
  }
  final DisplayMonitorRepository repository;
  final DisplayAudioController audio;
  Timer? _poll;
  int _generation = 0, _connection = 0, _signals = 0, _consumed = 0;
  bool _closing = false, _dirty = false;
  Future<void>? _pending, _closeFuture;
  AnnouncementGate _gate = AnnouncementGate();
  final _events = <String>{};
  bool get _active =>
      !_closing &&
      !isClosed &&
      state.scope != null &&
      repository.devices.owns(state.scope!);
  bool _valid(int generation, DisplayScope scope) =>
      !_closing &&
      !isClosed &&
      generation == _generation &&
      repository.devices.owns(scope);
  void _scopeChanged() {
    if (_closing || isClosed) return;
    _generation++;
    _connection++;
    _events.clear();
    audio.context(false);
    repository.disconnect();
    add(DisplayScopeChanged(_generation));
  }

  void _rebase() {
    _connection++;
    _signals = _consumed = 0;
    _gate.rebase();
    audio.rebase();
    if (_pending != null) _dirty = true;
  }

  void pause() {
    if (_active) {
      _rebase();
      audio.suspend();
    }
  }

  Future<void> resume() {
    audio.resume();
    return refresh(silent: true);
  }

  Future<void> refresh({bool silent = false}) {
    if (_closing || isClosed) return Future.value();
    final event = DisplayRefresh(silent: silent);
    add(event);
    return event.completion.future;
  }

  Future<void> _refresh(Emitter<DisplayMonitorState> emit) {
    if (!_active) return Future.value();
    _dirty = true;
    emit(
      state.copy(
        loading: state.snapshot == null,
        refreshing: state.snapshot != null,
      ),
    );
    if (_pending != null) return _pending!;
    final done = Completer<void>(),
        scope = state.scope!,
        generation = _generation;
    final future = _pending = done.future;
    unawaited(() async {
      try {
        do {
          await _drain(emit, scope, generation);
        } while (_dirty && _valid(generation, scope));
      } finally {
        if (identical(_pending, future)) _pending = null;
        done.complete();
      }
    }());
    return future;
  }

  Future<void> _drain(
    Emitter<DisplayMonitorState> emit,
    DisplayScope scope,
    int generation,
  ) async {
    while (_dirty && _valid(generation, scope)) {
      _dirty = false;
      final connection = _connection, signals = _signals;
      try {
        final data = await repository.snapshot(scope);
        if (!_valid(generation, scope)) return;
        if (connection != _connection) continue;
        final announcement = data['pengumumanTerakhir'] == null
            ? null
            : object(data['pengumumanTerakhir']);
        final speech = signals == _signals
            ? _gate.observe(announcement, callSignal: signals > _consumed)
            : null;
        _consumed = signals;
        emit(
          state.copy(
            snapshot: data,
            loading: false,
            refreshing: _dirty,
            clearError: true,
          ),
        );
        if (speech != null) unawaited(audio.announce(speech));
      } catch (error) {
        if (!_valid(generation, scope) || error is DisplayStale) return;
        final failure = displayError(error);
        if ([401, 403].contains(failure.status)) {
          repository.devices.begin(failure: failure);
          return;
        }
        final trailing = _dirty;
        _rebase();
        // A failed read is not a new event; wait for manual/poll/reconnect retry.
        _dirty = trailing;
        emit(
          state.copy(
            loading: false,
            refreshing: false,
            error: 'Snapshot belum dapat dimuat. Periksa koneksi perangkat.',
            errorStatus: failure.status,
          ),
        );
      }
    }
  }

  @override
  Future<void> close() {
    if (_closeFuture != null) return _closeFuture!;
    if (!isClosed) add(DisplayMonitorClosed());
    _closing = true;
    _generation++;
    _connection++;
    _poll?.cancel();
    repository.devices.removeListener(_scopeChanged);
    repository.disconnect();
    audio.context(false);
    return _closeFuture = super.close();
  }
}
