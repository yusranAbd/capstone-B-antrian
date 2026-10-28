import '../models/admin_catalog_models.dart';

enum CatalogLoadStatus {
  initial,
  loading,
  loaded,
  refreshing,
  failure,
  sessionEnded,
}

enum CatalogMutationStatus { idle, submitting, success, failure }

class AdminCatalogState {
  const AdminCatalogState({
    required this.snapshot,
    this.load = CatalogLoadStatus.initial,
    this.mutation = CatalogMutationStatus.idle,
    this.loadError,
    this.mutationError,
    this.recordId,
    this.needsReconciliation = false,
  });
  final AdminCatalogSnapshot snapshot;
  final CatalogLoadStatus load;
  final CatalogMutationStatus mutation;
  final Object? loadError, mutationError;
  final String? recordId;
  final bool needsReconciliation;
  bool get busy =>
      load == CatalogLoadStatus.loading ||
      load == CatalogLoadStatus.refreshing ||
      mutation == CatalogMutationStatus.submitting;
  Object? get error => mutationError ?? loadError;
}
