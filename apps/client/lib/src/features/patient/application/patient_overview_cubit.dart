import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/foundation.dart';

import '../data/patient_repository.dart';
import '../models/patient_models.dart';
import '../models/patient_queue_models.dart';

class PatientOverviewState {
  const PatientOverviewState(this.snapshot, this.load, this.errors);
  final PatientSnapshot snapshot;
  final PatientLoad load;
  final Map<String, Object> errors;
  String? get error => errors.entries
      .where((e) => !{'/jadwal-praktik', '/jadwal-layanan'}.contains(e.key))
      .firstOrNull
      ?.value
      .toString();
  String? get scheduleError => errors['/jadwal-praktik'] == null
      ? null
      : 'Jadwal praktik belum dapat dimuat.';
}

class PatientOverviewCubit extends Cubit<PatientOverviewState> {
  PatientOverviewCubit(this.repository)
    : super(
        PatientOverviewState(
          repository.snapshot,
          PatientLoad.initial,
          const {},
        ),
      ) {
    repository.addListener(_changed);
  }
  final PatientRepository repository;
  ValueListenable<PatientQueueState> get queueState => repository.queueState;
  bool _closing = false;
  Future<void>? _pending;
  void _changed() {
    if (isClosed || _closing) return;
    final errors = Map<String, Object>.unmodifiable({
      for (final entry in repository.errors.entries)
        if (patientOverviewPaths.contains(entry.key)) entry.key: entry.value,
    });
    emit(
      PatientOverviewState(
        repository.snapshot,
        !repository.active
            ? PatientLoad.sessionEnded
            : errors.isEmpty
            ? PatientLoad.loaded
            : PatientLoad.failure,
        errors,
      ),
    );
  }

  Future<void> refresh({Iterable<String> paths = patientOverviewPaths}) {
    if (!repository.active || _closing || isClosed) return Future.value();
    final read = repository.refresh(paths);
    if (_pending != null) return _pending!;
    emit(
      PatientOverviewState(
        state.snapshot,
        state.snapshot.collections.isEmpty
            ? PatientLoad.loading
            : PatientLoad.refreshing,
        const {},
      ),
    );
    return _pending = (() async {
      await read;
      _changed();
      _pending = null;
    })();
  }

  @override
  Future<void> close() {
    _closing = true;
    repository.removeListener(_changed);
    return super.close();
  }
}
