import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../api.dart';
import '../../../config.dart';
import '../data/patient_repository.dart';
import '../models/patient_models.dart';

class PatientTicketState {
  const PatientTicketState({
    required this.snapshot,
    this.load = PatientLoad.initial,
    this.mutation = PatientMutation.idle,
    this.error,
  });
  final PatientSnapshot snapshot;
  final PatientLoad load;
  final PatientMutation mutation;
  final String? error;
}

class PatientTicketCubit extends Cubit<PatientTicketState> {
  PatientTicketCubit(this.repository, this.ticketId)
    : super(PatientTicketState(snapshot: repository.snapshot)) {
    repository.addListener(_changed);
    repository.invalidations.addListener(_invalidated);
  }
  final PatientRepository repository;
  final String ticketId;
  bool _closing = false, _issuing = false;
  Future<void>? _pending;
  String get path => '/tiket/$ticketId';
  bool get current => !_closing && !isClosed && repository.active;
  Json? get ticket => state.snapshot.ticket(ticketId);
  bool get canIssue =>
      current &&
      state.load != PatientLoad.failure &&
      ticket?['status'] == 'DIPESAN' &&
      dateOnly(ticket?['tanggalPelayanan'] ?? ticket?['tanggalAntrean']) ==
          repository.api.config.today;
  void _changed() {
    if (_closing || isClosed) return;
    emit(
      PatientTicketState(
        snapshot: repository.snapshot,
        load: !repository.active
            ? PatientLoad.sessionEnded
            : repository.errors.containsKey(path)
            ? PatientLoad.failure
            : PatientLoad.loaded,
        mutation: repository.active ? state.mutation : PatientMutation.idle,
        error: repository.active
            ? (repository.errors[path]?.toString() ?? state.error)
            : null,
      ),
    );
  }

  void _invalidated() {
    if (current && repository.invalidations.value.$2.contains('TIKET')) {
      refresh();
    }
  }

  Future<void> refresh() {
    if (!current) return Future.value();
    final read = repository.refresh([path]);
    if (_pending != null) return _pending!;
    emit(
      PatientTicketState(
        snapshot: repository.snapshot,
        load: ticket == null ? PatientLoad.loading : PatientLoad.refreshing,
        mutation: state.mutation,
      ),
    );
    return _pending = (() async {
      await read;
      _changed();
      _pending = null;
    })();
  }

  Future<PatientQr?> issue() async {
    repository.check();
    if (!canIssue || _issuing || _pending != null) {
      throw const ApiException(
        409,
        'QR tersedia untuk tiket DIPESAN pada hari pelayanan.',
      );
    }
    _issuing = true;
    emit(
      PatientTicketState(
        snapshot: repository.snapshot,
        load: state.load,
        mutation: PatientMutation.submitting,
      ),
    );
    PatientQr? result;
    try {
      result = await repository.issueQr(ticketId);
      if (!current || !canIssue) {
        result.clear();
        return null;
      }
      emit(
        PatientTicketState(
          snapshot: repository.snapshot,
          load: state.load,
          mutation: PatientMutation.success,
        ),
      );
      return result;
    } catch (error) {
      if (current) {
        await refresh();
        if (current) {
          emit(
            PatientTicketState(
              snapshot: repository.snapshot,
              load: state.load,
              mutation: uncertainPatient(error)
                  ? PatientMutation.unknown
                  : PatientMutation.failure,
              error: error is ApiException && error.status == 410
                  ? 'QR sudah kedaluwarsa. Terbitkan QR baru untuk melanjutkan.'
                  : '${patientError(error)}',
            ),
          );
        }
      }
      result?.clear();
      return null;
    } finally {
      _issuing = false;
    }
  }

  @override
  Future<void> close() {
    _closing = true;
    repository.removeListener(_changed);
    repository.invalidations.removeListener(_invalidated);
    return super.close();
  }
}
