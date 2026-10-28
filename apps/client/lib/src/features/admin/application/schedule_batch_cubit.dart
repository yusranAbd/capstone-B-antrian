import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/admin_schedule_repository.dart';
import '../models/admin_schedule_models.dart';
import 'schedule_batch_state.dart';

/// Dialog-scoped batch state; list/CRUD state stays in ServiceScheduleCubit.
/// One completed dialog cannot replay its batch. Reopening performs a new
/// preflight which skips previously successful/existing days.
class ScheduleBatchCubit extends Cubit<ScheduleBatchState> {
  ScheduleBatchCubit(this.repository) : super(ScheduleBatchState()) {
    repository.catalog.addListener(_catalogChanged);
  }
  final AdminScheduleRepository repository;
  bool _closing = false;
  void _catalogChanged() {
    if (_closing || isClosed) return;
    if (!repository.catalog.active) {
      emit(ScheduleBatchState(status: ScheduleBatchStatus.sessionEnded));
    } else {
      emit(
        ScheduleBatchState(
          status: state.status,
          results: state.results,
          error: state.error,
          finished: state.finished,
        ),
      );
    }
  }

  Future<void> submit({
    required String clinicId,
    required Set<String> days,
    required String opens,
    required String closes,
    required int capacity,
  }) async {
    if (_closing ||
        isClosed ||
        state.busy ||
        state.finished ||
        !repository.catalog.active) {
      return;
    }
    emit(ScheduleBatchState(status: ScheduleBatchStatus.submitting));
    bool current() => !_closing && !isClosed && repository.catalog.active;
    try {
      final results = await repository.createDays(
        clinicId: clinicId,
        days: Set.of(days),
        opens: opens,
        closes: closes,
        capacity: capacity,
        current: current,
        onProgress: (results) {
          if (current()) {
            emit(
              ScheduleBatchState(
                status: ScheduleBatchStatus.submitting,
                results: results,
              ),
            );
          }
        },
      );
      if (current()) {
        final rejected = results
            .where(
              (r) =>
                  r.outcome == ScheduleOutcome.failed ||
                  r.outcome == ScheduleOutcome.uncertain,
            )
            .length;
        emit(
          ScheduleBatchState(
            results: results,
            finished: true,
            status: rejected == 0
                ? ScheduleBatchStatus.success
                : rejected == results.length
                ? ScheduleBatchStatus.failure
                : ScheduleBatchStatus.partial,
          ),
        );
      }
    } catch (error) {
      if (current()) {
        emit(
          ScheduleBatchState(
            status: state.results.isEmpty
                ? ScheduleBatchStatus.failure
                : ScheduleBatchStatus.partial,
            results: state.results,
            finished: state.results.isNotEmpty,
            error: state.results.isEmpty
                ? 'Tidak dapat memeriksa jadwal. Tidak ada jadwal baru dikirim. $error'
                : 'Hasil per hari dipertahankan. Daftar belum dapat direkonsiliasi. $error',
          ),
        );
      }
    }
  }

  @override
  Future<void> close() {
    _closing = true;
    repository.catalog.removeListener(_catalogChanged);
    return super.close();
  }
}
