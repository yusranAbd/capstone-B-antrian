import '../../../api.dart';
import '../../../config.dart';
import '../data/admin_staff_repository.dart';
import '../data/admin_catalog_repository.dart';
import '../models/admin_staff_models.dart';
import 'admin_catalog_cubit.dart';
import 'admin_catalog_state.dart';

abstract class AdminStaffCubit extends AdminCatalogCubit {
  AdminStaffCubit(this.staff, String path) : super(staff.catalog, path);
  final AdminStaffRepository staff;
  @override
  Future<Json> writeRecord(
    String method, {
    String? id,
    Json? body,
    bool permanent = false,
  }) => staff.write(path, method, id: id, body: body, permanent: permanent);
  @override
  Future<void> reconcileAfterMutation() => staff.reconcile(path);
  @override
  Future<void> refreshRecords(Iterable<String> paths) => staff.refresh(paths);
  @override
  CatalogMutationStatus failureStatus(Object error) =>
      error is ApiException && (error.status == 0 || error.status >= 500)
      ? CatalogMutationStatus.unknown
      : CatalogMutationStatus.failure;
  @override
  Future<void> refresh({Iterable<String>? paths}) async {
    final targets = paths?.toSet() ?? {...adminMasterPaths, ...adminStaffPaths};
    await super.refresh(paths: targets);
  }
}

class StaffAccountCubit extends AdminStaffCubit {
  StaffAccountCubit(AdminStaffRepository staff) : super(staff, '/akun-petugas');
  Future<Json> createAccount({
    required String name,
    required String email,
    required String password,
  }) => save({'nama': name, 'email': email, 'kataSandi': password});
  Future<Json> setStatus(String id, bool active) =>
      save({'aktif': active}, id: id);
  @override
  Json? recoverMutation(String method, {String? id, Json? body}) {
    if (method != 'POST') return null;
    final email = '${body?['email']}'.trim().toLowerCase();
    return this.rows
        .where(
          (r) =>
              '${r['email']}'.toLowerCase() == email &&
              r['peran'] == 'PETUGAS' &&
              r['id'] is String,
        )
        .firstOrNull;
  }
}

class AssignmentCubit extends AdminStaffCubit {
  AssignmentCubit(AdminStaffRepository staff)
    : super(staff, '/penugasan-petugas');
}
