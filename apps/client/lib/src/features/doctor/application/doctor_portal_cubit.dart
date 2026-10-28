import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/doctor_repository.dart';
import '../models/doctor_portal_data.dart';
import 'doctor_portal_state.dart';

/// Owns the repository and its single invalidation subscription.
class DoctorPortalCubit extends Cubit<DoctorPortalState> {
  DoctorPortalCubit({required this.repository, required String date})
    : super(DoctorPortalState(selectedDate: date)) {
    repository.addListener(_invalidated);
  }
  final DoctorRepository repository;
  Future<void>? _pending;
  bool _dirty = false, _closing = false;
  int _epoch = 0;
  void _invalidated() {
    if (_closing || isClosed) return;
    if (!repository.sessionActive) {
      _epoch++;
      _dirty = false;
      emit(
        DoctorPortalState(
          selectedDate: state.selectedDate,
          status: DoctorPortalStatus.sessionEnded,
        ),
      );
    } else {
      unawaited(refresh());
    }
  }

  Future<void> selectDate(String date) {
    if (_closing || isClosed) {
      return Future.value();
    }
    _epoch++;
    emit(DoctorPortalState(selectedDate: date));
    return refresh();
  }

  Future<void> refresh() {
    if (_closing || isClosed) return Future.value();
    if (!repository.sessionActive) {
      _invalidated();
      return Future.value();
    }
    _dirty = true;
    // Later callers also await the trailing read; events only mark data dirty.
    return _pending ??= _drain().whenComplete(() {
      _pending = null;
      // A state-stream listener may invalidate between the last emit and this
      // completion microtask. Retain that read as well.
      if (_dirty && !_closing && repository.sessionActive) return refresh();
    });
  }

  Future<void> _drain() async {
    while (_dirty && !_closing && repository.sessionActive) {
      _dirty = false;
      final epoch = _epoch, date = state.selectedDate;
      final previous = state.data;
      emit(
        DoctorPortalState(
          selectedDate: date,
          data: previous,
          loadedDate: state.loadedDate,
          status: state.available
              ? DoctorPortalStatus.refreshing
              : DoctorPortalStatus.initialLoading,
        ),
      );
      bool current() =>
          !_closing && !isClosed && repository.sessionActive && epoch == _epoch;
      try {
        final data = await repository.load(date);
        if (current()) {
          emit(
            DoctorPortalState(
              selectedDate: date,
              data: data,
              loadedDate: date,
              status: DoctorPortalStatus.loaded,
            ),
          );
        }
      } catch (error) {
        if (current()) {
          // Existing UI hides stale queue/schedules on error; profile is unavailable.
          emit(
            DoctorPortalState(
              selectedDate: date,
              data: DoctorPortalData(profile: previous.profile),
              status: DoctorPortalStatus.error,
              error: error,
            ),
          );
        }
      }
    }
  }

  @override
  Future<void> close() {
    _closing = true;
    _epoch++;
    _dirty = false;
    repository.removeListener(_invalidated);
    repository.dispose();
    return super.close();
  }
}
