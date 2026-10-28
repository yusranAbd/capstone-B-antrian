import '../../../config.dart';
import '../models/admin_slot_models.dart';

enum SlotLoadStatus {
  initial,
  loading,
  loaded,
  empty,
  refreshing,
  failure,
  sessionEnded,
  sessionRemoved,
}

enum SlotMutationStatus { idle, submitting, success, failure, unknown }

class SlotSessionState {
  SlotSessionState({
    required this.sessionId,
    this.load = SlotLoadStatus.initial,
    List<Json> slots = const [],
    this.hasLoaded = false,
    this.mutation = SlotMutationStatus.idle,
    this.loadError,
    this.mutationError,
    this.needsReconciliation = false,
  }) : slots = immutableSlotRows(slots);
  final String sessionId;
  final SlotLoadStatus load;
  final List<Json> slots;
  final bool hasLoaded, needsReconciliation;
  final SlotMutationStatus mutation;
  final Object? loadError, mutationError;
  bool get loading =>
      load == SlotLoadStatus.loading || load == SlotLoadStatus.refreshing;
  bool get mutating => mutation == SlotMutationStatus.submitting;
  Object? get error => mutationError ?? loadError;

  SlotSessionState copyWith({
    SlotLoadStatus? load,
    List<Json>? slots,
    bool? hasLoaded,
    SlotMutationStatus? mutation,
    Object? loadError,
    Object? mutationError,
    bool clearLoadError = false,
    bool clearMutationError = false,
    bool? needsReconciliation,
  }) => SlotSessionState(
    sessionId: sessionId,
    load: load ?? this.load,
    slots: slots ?? this.slots,
    hasLoaded: hasLoaded ?? this.hasLoaded,
    mutation: mutation ?? this.mutation,
    loadError: clearLoadError ? null : loadError ?? this.loadError,
    mutationError: clearMutationError
        ? null
        : mutationError ?? this.mutationError,
    needsReconciliation: needsReconciliation ?? this.needsReconciliation,
  );
}
