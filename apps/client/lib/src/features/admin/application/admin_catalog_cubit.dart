import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../api.dart';
import '../../../config.dart';
import '../data/admin_catalog_repository.dart';
import 'admin_catalog_state.dart';

/// Per-module operation state; the shared repository is the only dataset owner.
abstract class AdminCatalogCubit extends Cubit<AdminCatalogState> {
  AdminCatalogCubit(this.repository, this.path)
    : super(AdminCatalogState(snapshot: repository.snapshot)) {
    repository.addListener(_catalogChanged);
  }
  final AdminCatalogRepository repository;
  final String path;
  bool _closing = false;
  Future<void>? _refresh;
  Future<Json>? _mutation;
  List<Json> get rows => state.snapshot.rowsFor(path);
  bool get _current => !_closing && !isClosed && repository.active;

  void _catalogChanged() {
    if (_closing || isClosed) return;
    if (!repository.active) {
      emit(
        AdminCatalogState(
          snapshot: repository.snapshot,
          load: CatalogLoadStatus.sessionEnded,
        ),
      );
      return;
    }
    emit(
      AdminCatalogState(
        snapshot: repository.snapshot,
        load:
            state.load == CatalogLoadStatus.initial &&
                repository.snapshot.collections.containsKey(path)
            ? CatalogLoadStatus.loaded
            : state.load,
        mutation: state.mutation,
        loadError: state.loadError,
        mutationError: state.mutationError,
        recordId: state.recordId,
        needsReconciliation: state.needsReconciliation,
        recoveredMutation: state.recoveredMutation,
      ),
    );
  }

  Future<void> refresh({Iterable<String>? paths}) {
    if (!_current) return Future.value();
    // Forward every invalidation to the repository even when this Cubit waits.
    final read = refreshRecords(paths ?? {...adminMasterPaths, path});
    if (_refresh != null) {
      // Adapters may wrap the same catalog drain in distinct Futures. Observe
      // every wrapper's failure while the first waiter publishes the outcome.
      unawaited(read.catchError((Object _) {}));
      return _refresh!;
    }
    emit(
      AdminCatalogState(
        snapshot: repository.snapshot,
        load: state.snapshot.collections.containsKey(path)
            ? CatalogLoadStatus.refreshing
            : CatalogLoadStatus.loading,
        mutation: state.mutation == CatalogMutationStatus.submitting
            ? state.mutation
            : CatalogMutationStatus.idle,
        recordId: state.recordId,
        needsReconciliation: state.needsReconciliation,
      ),
    );
    return _refresh = (() async {
      try {
        await read;
        if (_current) {
          emit(
            AdminCatalogState(
              snapshot: repository.snapshot,
              load: CatalogLoadStatus.loaded,
              mutation: state.mutation,
              mutationError: state.mutationError,
              recordId: state.recordId,
            ),
          );
        }
      } catch (error) {
        if (_current) {
          emit(
            AdminCatalogState(
              snapshot: repository.snapshot,
              load: CatalogLoadStatus.failure,
              loadError: error,
              mutation: state.mutation,
              mutationError: state.mutationError,
              recordId: state.recordId,
              needsReconciliation: state.needsReconciliation,
            ),
          );
        }
      } finally {
        _refresh = null;
      }
    })();
  }

  Future<Json> save(Json body, {String? id}) =>
      _write(id == null ? 'POST' : 'PATCH', id: id, body: body);
  Future<Json> delete(String id) => _write('DELETE', id: id, permanent: true);
  Future<Json> deactivate(String id) => _write('DELETE', id: id);

  /// Resource adapters may share the catalog without duplicating its cache.
  Future<Json> writeRecord(
    String method, {
    String? id,
    Json? body,
    bool permanent = false,
  }) =>
      repository.write(path, method, id: id, body: body, permanent: permanent);
  Future<void> reconcileAfterMutation() => repository.reconcile();
  Future<void> refreshRecords(Iterable<String> paths) =>
      repository.refresh(paths);
  Json? recoverMutation(String method, {String? id, Json? body}) => null;
  CatalogMutationStatus failureStatus(Object error) =>
      CatalogMutationStatus.failure;

  Future<Json> _write(
    String method, {
    String? id,
    Json? body,
    bool permanent = false,
  }) {
    if (!_current) {
      return Future.error(const ApiException(401, 'Sesi ADMIN berubah.'));
    }
    if (_mutation != null || state.needsReconciliation) {
      return Future.error(
        const ApiException(
          409,
          'Muat ulang katalog sebelum melanjutkan tindakan.',
        ),
      );
    }
    emit(
      AdminCatalogState(
        snapshot: repository.snapshot,
        load: state.load,
        mutation: CatalogMutationStatus.submitting,
        recordId: id,
      ),
    );
    return _mutation = (() async {
      Json? result;
      Object? failure, refreshError;
      try {
        result = await writeRecord(
          method,
          id: id,
          body: body,
          permanent: permanent,
        );
      } catch (error) {
        failure = error;
      }
      final uncertain =
          failure is ApiException &&
          (failure.status == 0 || failure.status >= 500);
      bool recovered = false;
      // Re-read after success or an uncertain outcome. Never retry a mutation.
      if (failure == null || uncertain) {
        try {
          if (repository.active) await reconcileAfterMutation();
          if (_current && uncertain) {
            final verified = recoverMutation(method, id: id, body: body);
            if (verified != null) {
              result = verified;
              failure = null;
              recovered = true;
            }
          }
        } catch (error) {
          refreshError = error;
        }
      }
      if (_current) {
        emit(
          AdminCatalogState(
            snapshot: repository.snapshot,
            load: refreshError != null
                ? CatalogLoadStatus.failure
                : failure == null || uncertain
                ? CatalogLoadStatus.loaded
                : state.load,
            loadError: refreshError,
            mutation: failure == null
                ? CatalogMutationStatus.success
                : failureStatus(failure),
            mutationError: failure,
            recordId: id,
            needsReconciliation: refreshError != null,
            recoveredMutation: recovered,
          ),
        );
      }
      if (failure != null) throw failure;
      if (!_current) throw const ApiException(401, 'Sesi ADMIN berubah.');
      return result!;
    })().whenComplete(() => _mutation = null);
  }

  @override
  Future<void> close() {
    _closing = true;
    repository.removeListener(_catalogChanged);
    return super.close();
  }
}

class PolyclinicCubit extends AdminCatalogCubit {
  PolyclinicCubit(AdminCatalogRepository repository)
    : super(repository, '/layanan');
}

class DoctorCatalogCubit extends AdminCatalogCubit {
  DoctorCatalogCubit(AdminCatalogRepository repository)
    : super(repository, '/dokter');
}

class RoomCubit extends AdminCatalogCubit {
  RoomCubit(AdminCatalogRepository repository) : super(repository, '/loket');
}
