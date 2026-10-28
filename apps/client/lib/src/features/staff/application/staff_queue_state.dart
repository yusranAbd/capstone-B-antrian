import '../../../config.dart';
import '../models/staff_queue_models.dart';

enum StaffLoad { initial, loading, loaded, refreshing, failed, ended }

enum StaffCommandStatus {
  idle,
  sending,
  reconciling,
  confirmed,
  failed,
  uncertain,
  unsynced,
}

class StaffQueueState {
  StaffQueueState({
    List<Json> assignments = const [],
    this.roomId,
    this.date,
    Json? snapshot,
    List<Json> schedules = const [],
    this.page = 1,
    this.load = StaffLoad.initial,
    this.scheduleLoading = false,
    this.scheduleFailed = false,
    this.synchronized = false,
    this.command = StaffCommandStatus.idle,
    this.mutationConfirmed = false,
    this.pending,
    this.error,
    this.errorStatus,
    this.message,
    this.liveStatus = 'Menghubungkan realtime…',
  }) : assignments = staffRows(assignments),
       schedules = staffRows(schedules),
       snapshot = snapshot == null ? null : staffObject(snapshot);
  final List<Json> assignments, schedules;
  final Json? snapshot;
  final String? roomId, date, error, message;
  final int page;
  final int? errorStatus;
  final StaffLoad load;
  final StaffCommandStatus command;
  final bool mutationConfirmed;
  final StaffOperation? pending;
  final bool scheduleLoading, scheduleFailed, synchronized;
  final String liveStatus;
  bool get busy =>
      command == StaffCommandStatus.sending ||
      command == StaffCommandStatus.reconciling;
  bool get blocked =>
      busy ||
      !synchronized ||
      command == StaffCommandStatus.uncertain ||
      command == StaffCommandStatus.unsynced;
  bool get loading => load == StaffLoad.initial || load == StaffLoad.loading;
  Json? get room => assignments
      .where((a) => a['loketId'] == roomId)
      .map((a) => a['loket'] as Json)
      .firstOrNull;
  List<Json> get active => List.unmodifiable(
    rows(snapshot?['loket'])
        .where((l) => l['id'] == roomId)
        .expand((l) => rows(l['tiketAktif']))
        .map(staffObject),
  );
  List<Json> get patients {
    final source = snapshot?['daftarPasien'] is Map
        ? rows(object(snapshot?['daftarPasien'])['tiket'])
        : rows(object(snapshot?['menunggu'])['tiket'])
              .map((t) => {'status': 'MENUNGGU', ...t});
    final unique = <String, Json>{};
    for (final t in source) {
      unique.putIfAbsent('${t['tiketId'] ?? t['id']}', () => staffObject(t));
    }
    return List.unmodifiable(unique.values);
  }

  StaffQueueState copy({
    List<Json>? assignments,
    String? roomId,
    String? date,
    Json? snapshot,
    bool clearSnapshot = false,
    List<Json>? schedules,
    int? page,
    StaffLoad? load,
    bool? scheduleLoading,
    bool? scheduleFailed,
    bool? synchronized,
    StaffCommandStatus? command,
    bool? mutationConfirmed,
    StaffOperation? pending,
    bool clearPending = false,
    String? error,
    int? errorStatus,
    String? message,
    bool clearFeedback = false,
    String? liveStatus,
  }) => StaffQueueState(
    assignments: assignments ?? this.assignments,
    roomId: roomId ?? this.roomId,
    date: date ?? this.date,
    snapshot: clearSnapshot ? null : snapshot ?? this.snapshot,
    schedules: schedules ?? this.schedules,
    page: page ?? this.page,
    load: load ?? this.load,
    scheduleLoading: scheduleLoading ?? this.scheduleLoading,
    scheduleFailed: scheduleFailed ?? this.scheduleFailed,
    synchronized: synchronized ?? this.synchronized,
    command: command ?? this.command,
    mutationConfirmed: mutationConfirmed ?? this.mutationConfirmed,
    pending: clearPending ? null : pending ?? this.pending,
    error: clearFeedback ? null : error ?? this.error,
    errorStatus: clearFeedback ? null : errorStatus ?? this.errorStatus,
    message: clearFeedback ? null : message ?? this.message,
    liveStatus: liveStatus ?? this.liveStatus,
  );
}
