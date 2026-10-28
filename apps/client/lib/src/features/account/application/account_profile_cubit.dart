import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../config.dart';
import '../../../patient_sync.dart';
import '../data/account_profile_repository.dart';

enum AccountProfileMutation {
  idle,
  submitting,
  success,
  partial,
  failure,
  unknown,
}

class AccountProfileState {
  const AccountProfileState({
    this.profile = const {},
    this.roleData,
    this.loading = true,
    this.roleLoading = false,
    this.ended = false,
    this.error,
    this.message,
    this.roleError,
    this.mutation = AccountProfileMutation.idle,
    this.operation,
    this.needsReconciliation = false,
    this.credentialUnknown = false,
  });
  final Json profile;
  final Object? roleData;
  final bool loading,
      roleLoading,
      ended,
      needsReconciliation,
      credentialUnknown;
  final String? error, message, roleError, operation;
  final AccountProfileMutation mutation;
  bool get busy => mutation == AccountProfileMutation.submitting;
}

class AccountProfileCubit extends Cubit<AccountProfileState> {
  AccountProfileCubit(this.repository)
    : super(AccountProfileState(profile: repository.profile)) {
    _reader = RefreshGate(_load);
    repository.api.addListener(_changed);
  }
  final AccountProfileRepository repository;
  late final RefreshGate _reader;
  bool _closing = false, _writing = false;
  bool get current =>
      !_closing && !isClosed && !state.ended && repository.active;
  void _publish({
    bool? loading,
    bool? roleLoading,
    Object? roleData,
    bool clearRoleData = false,
    String? roleError,
    String? error,
    String? message,
    AccountProfileMutation? mutation,
    String? operation,
    bool? needsReconciliation,
    bool? credentialUnknown,
  }) {
    if (!current) return;
    emit(
      AccountProfileState(
        profile: repository.profile,
        roleData: clearRoleData ? null : roleData ?? state.roleData,
        loading: loading ?? state.loading,
        roleLoading: roleLoading ?? state.roleLoading,
        error: error,
        message: message,
        roleError: roleError,
        mutation: mutation ?? state.mutation,
        operation: operation ?? state.operation,
        needsReconciliation: needsReconciliation ?? state.needsReconciliation,
        credentialUnknown: credentialUnknown ?? state.credentialUnknown,
      ),
    );
  }

  void _changed() {
    if (_closing || isClosed) return;
    if (!repository.active) {
      _reader.dispose();
      emit(const AccountProfileState(loading: false, ended: true));
      return;
    }
    if (current) {
      _publish(
        error: state.error,
        message: state.message,
        roleError: state.roleError,
      );
    }
  }

  Future<void> load() =>
      current && !_writing ? _reader.refresh() : Future.value();
  Future<void> _load() async {
    if (!current) return;
    _publish(loading: true, roleLoading: true);
    try {
      await repository.reload();
      if (!current) return;
      Object? data;
      String? roleError;
      try {
        data = await repository.roleData();
      } catch (error) {
        roleError = '${profileError(error)}';
      }
      if (current) {
        _publish(
          loading: false,
          roleLoading: false,
          roleData: data,
          clearRoleData: data == null,
          roleError: roleError,
          needsReconciliation: state.credentialUnknown,
        );
      }
    } catch (error) {
      if (current) {
        _publish(
          loading: false,
          roleLoading: false,
          error: '${profileError(error)}',
        );
      }
    }
  }

  void clearFeedback() => _publish(roleError: state.roleError);
  Future<bool> updateName(String value) => _run(
    'name',
    () => repository.name(value.trim()),
    'Nama berhasil diperbarui.',
    expectedName: value.trim(),
  );
  Future<bool> uploadAvatar(List<int> bytes) => _run(
    'avatar',
    () => repository.avatar(bytes),
    'Foto profil berhasil diperbarui.',
  );
  Future<bool> removeAvatar() =>
      _run('avatar', () => repository.avatar(null), 'Foto profil dihapus.');
  Future<bool> changePassword(String oldValue, String newValue) =>
      _run('password', () => repository.password(oldValue, newValue), '');
  Future<bool> logout() => _run('logout', repository.api.logout, '');
  Future<bool> _run(
    String operation,
    Future<void> Function() action,
    String success, {
    String? expectedName,
  }) async {
    if (!current ||
        _writing ||
        (operation != 'logout' && state.needsReconciliation)) {
      return false;
    }
    _writing = true;
    _publish(mutation: AccountProfileMutation.submitting, operation: operation);
    try {
      await action();
      if (!current) return operation == 'password' || operation == 'logout';
      _publish(mutation: AccountProfileMutation.success, message: success);
      return true;
    } on AccountProfilePartial catch (error) {
      if (current) {
        _publish(
          mutation: AccountProfileMutation.partial,
          error: '$error',
          needsReconciliation: true,
        );
      }
      return current;
    } catch (error) {
      if (!current) return false;
      final failure = profileError(error, operation: operation);
      final uncertain = failure.status == 0 || failure.status >= 500;
      if (uncertain && operation == 'name') {
        try {
          await repository.reload();
          if (current && repository.profile['nama'] == expectedName) {
            _publish(
              mutation: AccountProfileMutation.success,
              message: success,
            );
            return true;
          }
        } catch (_) {
          /* Keep unknown; never replay the command. */
        }
      }
      if (current) {
        _publish(
          mutation: uncertain
              ? AccountProfileMutation.unknown
              : AccountProfileMutation.failure,
          error: '$failure',
          needsReconciliation: uncertain,
          credentialUnknown: uncertain && operation == 'password',
        );
      }
      return false;
    } finally {
      _writing = false;
    }
  }

  @override
  Future<void> close() {
    _closing = true;
    _reader.dispose();
    repository.api.removeListener(_changed);
    return super.close();
  }
}
