import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../api.dart';
import '../../../config.dart';
import '../data/admin_display_repository.dart';
import '../models/admin_display_models.dart';
import 'admin_catalog_state.dart';
import 'display_management_state.dart';

class DisplayManagementCubit extends Cubit<DisplayManagementState> {
  DisplayManagementCubit(this.repository)
    : super(
        DisplayManagementState(
          snapshot: repository.catalog.snapshot,
          load:
              repository.catalog.snapshot.collections.containsKey(
                adminDisplayPath,
              )
              ? CatalogLoadStatus.loaded
              : CatalogLoadStatus.initial,
        ),
      ) {
    repository.catalog.addListener(_catalogChanged);
  }
  final AdminDisplayRepository repository;
  bool _closing = false;
  Future<void>? _refresh;
  List<Json> get devices => state.snapshot.rowsFor(adminDisplayPath);
  List<Json> get clinics => state.snapshot.rowsFor('/layanan');
  bool get _current => !_closing && !isClosed && repository.catalog.active;
  void _catalogChanged() {
    if (_closing || isClosed) return;
    if (!repository.catalog.active) {
      emit(
        DisplayManagementState(
          snapshot: repository.catalog.snapshot,
          load: CatalogLoadStatus.sessionEnded,
        ),
      );
      return;
    }
    emit(
      state.copyWith(
        snapshot: repository.catalog.snapshot,
        load:
            state.load == CatalogLoadStatus.initial &&
                repository.catalog.snapshot.collections.containsKey(
                  adminDisplayPath,
                )
            ? CatalogLoadStatus.loaded
            : state.load,
      ),
    );
  }

  Future<void> refresh() {
    if (!_current) return Future.value();
    final read = repository.refresh();
    if (_refresh != null) {
      unawaited(read.catchError((Object _) {}));
      return _refresh!;
    }
    emit(
      state.copyWith(
        load: state.snapshot.collections.containsKey(adminDisplayPath)
            ? CatalogLoadStatus.refreshing
            : CatalogLoadStatus.loading,
        clearLoadError: true,
      ),
    );
    return _refresh = (() async {
      try {
        await read;
        if (_current) {
          emit(
            state.copyWith(
              snapshot: repository.catalog.snapshot,
              load: CatalogLoadStatus.loaded,
              clearLoadError: true,
              needsReconciliation: false,
            ),
          );
        }
      } catch (error) {
        if (_current) {
          emit(
            state.copyWith(
              load: CatalogLoadStatus.failure,
              loadError: safeDisplayError(error),
            ),
          );
        }
      } finally {
        _refresh = null;
      }
    })();
  }

  Future<void> create(Json body) async {
    await _command('create', body: body);
  }

  Future<void> update(String id, String name) async {
    await _command('update', id: id, body: {'nama': name});
  }

  Future<void> revoke(String id) async {
    await _command('revoke', id: id);
  }

  Future<void> delete(String id) async {
    await _command('delete', id: id);
  }

  Future<DisplayActivation> activate(
    String id, {
    bool confirmedReplacement = false,
  }) async => await _command(
    'activate',
    id: id,
    confirmedReplacement: confirmedReplacement,
  ) as DisplayActivation;
  void finishDisclosure() {
    if (_current && state.awaitingDisclosure) {
      emit(state.copyWith(awaitingDisclosure: false));
    }
  }

  Future<Object> _command(
    String action, {
    String? id,
    Json? body,
    bool confirmedReplacement = false,
  }) async {
    if (!_current) throw const ApiException(401, 'Sesi ADMIN berubah.');
    if (state.mutation == CatalogMutationStatus.submitting ||
        state.awaitingDisclosure ||
        state.needsReconciliation) {
      throw const ApiException(
        409,
        'Tutup informasi aktivasi atau muat ulang metadata sebelum melanjutkan.',
      );
    }
    if (action == 'activate' &&
        state.uncertainActivations.contains(id) &&
        !confirmedReplacement) {
      throw const ApiException(
        409,
        'Rotasi sebelumnya belum pasti. Kode tidak dapat dipulihkan; konfirmasikan penerbitan kode baru secara eksplisit.',
      );
    }
    emit(
      state.copyWith(
        mutation: CatalogMutationStatus.submitting,
        action: action,
        deviceId: id,
        clearMutationError: true,
      ),
    );
    Object? result, failure;
    try {
      result = await repository.command(action, id: id, body: body);
    } catch (error) {
      failure = safeDisplayError(error);
    }
    final uncertain =
        failure is ApiException &&
        (failure.status == 0 || failure.status >= 500);
    if (_current && (failure == null || uncertain)) await refresh();
    if (!_current) {
      if (result is DisplayActivation) result.clear();
      throw const ApiException(401, 'Sesi ADMIN berubah.');
    }
    final unknown = Set<String>.of(state.uncertainActivations);
    if (action == 'activate' && uncertain && id != null) unknown.add(id);
    if (failure == null &&
        id != null &&
        ['activate', 'revoke', 'delete'].contains(action)) {
      unknown.remove(id);
    }
    emit(
      state.copyWith(
        mutation: failure == null
            ? CatalogMutationStatus.success
            : uncertain
            ? CatalogMutationStatus.unknown
            : CatalogMutationStatus.failure,
        mutationError: failure,
        clearMutationError: failure == null,
        needsReconciliation:
            (failure == null || uncertain) &&
            state.load == CatalogLoadStatus.failure,
        uncertainActivations: unknown,
        awaitingDisclosure: result is DisplayActivation,
      ),
    );
    if (failure != null) throw failure;
    return result!;
  }

  @override
  Future<void> close() {
    _closing = true;
    repository.catalog.removeListener(_catalogChanged);
    return super.close();
  }
}
