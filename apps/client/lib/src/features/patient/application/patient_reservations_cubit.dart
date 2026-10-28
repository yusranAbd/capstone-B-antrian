import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../api.dart';
import '../../../config.dart';
import '../data/patient_repository.dart';
import '../models/patient_models.dart';

class PatientReservationsState {
  PatientReservationsState({
    required this.snapshot,
    this.load = PatientLoad.initial,
    this.mutation = PatientMutation.idle,
    this.error,
    this.appointmentId,
    this.needsReconciliation = false,
    Set<String> unknown = const {},
  }) : unknown = Set.unmodifiable(unknown);
  final PatientSnapshot snapshot;
  final PatientLoad load;
  final PatientMutation mutation;
  final String? error, appointmentId;
  final bool needsReconciliation;
  final Set<String> unknown;
  bool get busy => mutation == PatientMutation.submitting;
}

class PatientReservationsCubit extends Cubit<PatientReservationsState> {
  PatientReservationsCubit(this.repository)
    : super(PatientReservationsState(snapshot: repository.snapshot)) {
    repository.addListener(_changed);
  }
  final PatientRepository repository;
  bool _closing = false, _writing = false;
  bool get busy => _writing || state.busy;
  bool get current => !_closing && !isClosed && repository.active;
  bool get _readFailed =>
      repository.errors.keys.any(patientVisitPaths.contains);
  Json? appointment(String id) =>
      repository.snapshot.appointments.where((a) => a['id'] == id).firstOrNull;
  Json ticket(Json appointment) =>
      repository.snapshot.ticket('${object(appointment['tiket'])['id']}') ??
      object(appointment['tiket']);
  void _changed() {
    if (_closing || isClosed) return;
    if (!repository.active) {
      emit(
        PatientReservationsState(
          snapshot: repository.snapshot,
          load: PatientLoad.sessionEnded,
        ),
      );
      return;
    }
    final unknown = Set<String>.of(state.unknown);
    var mutation = state.mutation;
    String? error = state.error;
    for (final id in state.unknown) {
      final row = appointment(id);
      if (row == null || _readFailed) continue;
      final status = ticket(row)['status'];
      if (status == 'DIBATALKAN') {
        unknown.remove(id);
        mutation = PatientMutation.success;
        error = null;
      } else if (status != null && status != 'DIPESAN') {
        unknown.remove(id);
        mutation = PatientMutation.failure;
        error = 'Status tiket sudah berubah; pembatalan ditolak.';
      }
    }
    emit(
      PatientReservationsState(
        snapshot: repository.snapshot,
        load: _readFailed ? PatientLoad.failure : PatientLoad.loaded,
        mutation: mutation,
        error: error,
        appointmentId: state.appointmentId,
        unknown: unknown,
        needsReconciliation: state.needsReconciliation && _readFailed,
      ),
    );
  }

  Future<void> refresh() async {
    if (!current) return;
    await repository.refresh(patientVisitPaths);
    _changed();
  }

  Future<void> cancel(String id) async {
    repository.check();
    if (_writing || state.unknown.contains(id) || state.needsReconciliation) {
      throw const ApiException(
        409,
        'Periksa hasil pembatalan sebelumnya sebelum melanjutkan.',
      );
    }
    final row = appointment(id);
    if (row == null || ticket(row)['status'] != 'DIPESAN') {
      throw const ApiException(
        409,
        'Pembatalan hanya tersedia untuk reservasi DIPESAN.',
      );
    }
    _writing = true;
    emit(
      PatientReservationsState(
        snapshot: repository.snapshot,
        load: state.load,
        mutation: PatientMutation.submitting,
        appointmentId: id,
        unknown: state.unknown,
      ),
    );
    Object? failure;
    try {
      try {
        await repository.cancelAppointment(id);
      } catch (error) {
        failure = patientError(error);
      }
      if (!current) throw const ApiException(401, 'Sesi pasien berubah.');
      final unknown = Set<String>.of(state.unknown);
      if (failure != null && uncertainPatient(failure)) unknown.add(id);
      emit(
        PatientReservationsState(
          snapshot: repository.snapshot,
          load: state.load,
          mutation: failure == null
              ? PatientMutation.submitting
              : uncertainPatient(failure)
              ? PatientMutation.unknown
              : PatientMutation.failure,
          error: failure == null
              ? null
              : uncertainPatient(failure)
              ? 'Hasil pembatalan belum pasti. Periksa reservasi; tindakan tidak diulang otomatis.'
              : 'Status tiket sudah berubah; pembatalan ditolak. Muat ulang reservasi.',
          appointmentId: id,
          unknown: unknown,
        ),
      );
      await repository.refresh(patientVisitPaths);
      if (!current) throw const ApiException(401, 'Sesi pasien berubah.');
      if (failure != null && state.mutation != PatientMutation.success) {
        throw failure;
      }
      emit(
        PatientReservationsState(
          snapshot: repository.snapshot,
          load: _readFailed ? PatientLoad.failure : PatientLoad.loaded,
          mutation: PatientMutation.success,
          appointmentId: id,
          unknown: state.unknown,
          needsReconciliation: _readFailed,
        ),
      );
    } finally {
      _writing = false;
    }
  }

  @override
  Future<void> close() {
    _closing = true;
    repository.removeListener(_changed);
    return super.close();
  }
}
