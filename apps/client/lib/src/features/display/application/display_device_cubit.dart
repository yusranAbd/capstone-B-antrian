import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../api.dart';
import '../../../config.dart';
import '../data/display_device_repository.dart';
import '../models/display_models.dart';

class DisplayDeviceCubit extends Cubit<DisplayDeviceState> {
  DisplayDeviceCubit(this.repository) : super(DisplayDeviceState()) {
    repository.addListener(_changed);
  }
  final DisplayDeviceRepository repository;
  bool _busy = false, _closed = false, _uncertain = false;
  bool _current(int epoch) =>
      !_closed && !isClosed && repository.current(epoch);
  void _changed() {
    final failure = repository.rejection;
    if (_closed || isClosed || failure == null) return;
    emit(
      DisplayDeviceState(
        phase: DisplayDevicePhase.rejected,
        device: state.device,
        scope: state.scope,
        error: failure.message,
        errorStatus: failure.status,
      ),
    );
  }

  void _ready(Json? device, int epoch) {
    if (!_current(epoch)) return;
    if (device == null) {
      emit(
        DisplayDeviceState(
          phase: _uncertain
              ? DisplayDevicePhase.uncertain
              : DisplayDevicePhase.unpaired,
          error: _uncertain
              ? 'Hasil aktivasi belum dapat dipastikan. Periksa sesi tersimpan; jangan mengirim kode yang sama berulang.'
              : null,
        ),
      );
    } else {
      _uncertain = false;
      final scope = repository.activate(device, epoch);
      emit(
        DisplayDeviceState(
          phase: DisplayDevicePhase.ready,
          device: device,
          scope: scope,
        ),
      );
    }
  }

  Future<void> restore() async {
    if (_busy || _closed) return;
    _busy = true;
    final epoch = repository.begin();
    emit(DisplayDeviceState(phase: DisplayDevicePhase.restoring));
    try {
      _ready(await repository.restore(epoch), epoch);
    } catch (error) {
      if (!_current(epoch) || error is DisplayStale) return;
      final failure = displayError(error);
      if (failure.status == 401) _uncertain = false;
      emit(
        DisplayDeviceState(
          phase: failure.status == 401
              ? DisplayDevicePhase.unpaired
              : _uncertain
              ? DisplayDevicePhase.uncertain
              : DisplayDevicePhase.failed,
          error: failure.status == 401 && !repository.selection.isolated
              ? null
              : failure.message,
          errorStatus: failure.status,
        ),
      );
    } finally {
      _busy = false;
    }
  }

  Future<void> pair(String code) async {
    if (_busy || _closed || _uncertain) return;
    if (!RegExp(r'^\d{12}$').hasMatch(code)) {
      emit(
        DisplayDeviceState(
          phase: DisplayDevicePhase.failed,
          error: displayError(const ApiException(400, '')).message,
          errorStatus: 400,
        ),
      );
      return;
    }
    _busy = true;
    final epoch = repository.begin();
    emit(DisplayDeviceState(phase: DisplayDevicePhase.pairing));
    try {
      _ready(await repository.pair(code, epoch), epoch);
    } catch (error) {
      if (!_current(epoch) || error is DisplayStale) return;
      final failure = displayError(error);
      _uncertain = failure.status == 0 || failure.status >= 500;
      emit(
        DisplayDeviceState(
          phase: _uncertain
              ? DisplayDevicePhase.uncertain
              : DisplayDevicePhase.failed,
          error: failure.message,
          errorStatus: failure.status,
        ),
      );
    } finally {
      _busy = false;
    }
  }

  void legacy(String service, String token) {
    if (_busy || _closed) return;
    if (!RegExp(r'^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$')
            .hasMatch(service) ||
        !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(token)) {
      return;
    }
    final epoch = repository.begin();
    final scope = repository.legacy(service, token, epoch);
    _uncertain = false;
    emit(DisplayDeviceState(phase: DisplayDevicePhase.ready, scope: scope));
  }

  Future<void> disconnect() async {
    if (_busy || _closed) return;
    _busy = true;
    final previous = state, epoch = state.scope?.epoch;
    emit(
      DisplayDeviceState(
        phase: DisplayDevicePhase.disconnecting,
        device: previous.device,
        scope: previous.scope,
      ),
    );
    try {
      await repository.disconnect(repository.scope);
      if (!_closed && !isClosed) {
        _uncertain = false;
        emit(DisplayDeviceState());
      }
    } catch (error) {
      if (error is DisplayDisconnectPartial && !_closed && !isClosed) {
        emit(
          DisplayDeviceState(
            phase: DisplayDevicePhase.failed,
            error: 'Sesi telah dicabut server, tetapi identitas tab belum dapat dihapus. Periksa penyimpanan tab.',
            errorStatus: 0,
          ),
        );
        return;
      }
      if (_closed ||
          isClosed ||
          (epoch != null && !repository.current(epoch))) {
        return;
      }
      emit(
        DisplayDeviceState(
          phase: previous.phase,
          device: previous.device,
          scope: previous.scope,
          error: 'Belum dapat mencabut sesi perangkat. Periksa koneksi lalu coba Ganti perangkat lagi.',
          errorStatus: displayError(error).status,
        ),
      );
    } finally {
      _busy = false;
    }
  }

  @override
  Future<void> close() {
    if (!isClosed) emit(DisplayDeviceState());
    _closed = true;
    repository.removeListener(_changed);
    repository.begin();
    return super.close();
  }
}
