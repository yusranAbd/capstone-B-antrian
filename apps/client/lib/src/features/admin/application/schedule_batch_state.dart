import '../models/admin_schedule_models.dart';

enum ScheduleBatchStatus {
  idle,
  submitting,
  success,
  partial,
  failure,
  sessionEnded,
}

class ScheduleBatchState {
  ScheduleBatchState({
    this.status = ScheduleBatchStatus.idle,
    List<ScheduleResult> results = const [],
    this.error,
    this.finished = false,
  }) : results = List.unmodifiable(results);
  final ScheduleBatchStatus status;
  final List<ScheduleResult> results;
  final String? error;
  final bool finished;
  bool get busy => status == ScheduleBatchStatus.submitting;
}
