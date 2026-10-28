import '../models/admin_catalog_models.dart';
import 'admin_catalog_state.dart';

class DisplayManagementState {
  DisplayManagementState({
    required this.snapshot,
    this.load = CatalogLoadStatus.initial,
    this.mutation = CatalogMutationStatus.idle,
    this.action,
    this.deviceId,
    this.loadError,
    this.mutationError,
    this.needsReconciliation = false,
    this.awaitingDisclosure = false,
    Set<String> uncertainActivations = const {},
  }) : uncertainActivations = Set.unmodifiable(uncertainActivations);
  final AdminCatalogSnapshot snapshot;
  final CatalogLoadStatus load;
  final CatalogMutationStatus mutation;
  final String? action, deviceId;
  final Object? loadError, mutationError;
  final bool needsReconciliation, awaitingDisclosure;
  final Set<String> uncertainActivations;
  bool get busy =>
      load == CatalogLoadStatus.loading ||
      load == CatalogLoadStatus.refreshing ||
      mutation == CatalogMutationStatus.submitting ||
      awaitingDisclosure;
  Object? get error => mutationError ?? loadError;
  DisplayManagementState copyWith({
    AdminCatalogSnapshot? snapshot,
    CatalogLoadStatus? load,
    CatalogMutationStatus? mutation,
    String? action,
    String? deviceId,
    Object? loadError,
    Object? mutationError,
    bool clearLoadError = false,
    bool clearMutationError = false,
    bool? needsReconciliation,
    bool? awaitingDisclosure,
    Set<String>? uncertainActivations,
  }) => DisplayManagementState(
    snapshot: snapshot ?? this.snapshot,
    load: load ?? this.load,
    mutation: mutation ?? this.mutation,
    action: action ?? this.action,
    deviceId: deviceId ?? this.deviceId,
    loadError: clearLoadError ? null : loadError ?? this.loadError,
    mutationError: clearMutationError
        ? null
        : mutationError ?? this.mutationError,
    needsReconciliation: needsReconciliation ?? this.needsReconciliation,
    awaitingDisclosure: awaitingDisclosure ?? this.awaitingDisclosure,
    uncertainActivations: uncertainActivations ?? this.uncertainActivations,
  );
}
