import '../../../config.dart';
import '../data/admin_schedule_repository.dart';
import 'admin_catalog_cubit.dart';
import 'admin_catalog_state.dart';

abstract class AdminScheduleCubit extends AdminCatalogCubit {
  AdminScheduleCubit(this.schedules, String path)
    : super(schedules.catalog, path);
  final AdminScheduleRepository schedules;
  @override
  Future<Json> writeRecord(
    String method, {
    String? id,
    Json? body,
    bool permanent = false,
  }) => schedules.write(path, method, id: id, body: body, permanent: permanent);
  @override
  Future<void> reconcileAfterMutation() => schedules.reconcile(path);
  @override
  Future<void> refresh({Iterable<String>? paths}) async {
    await super.refresh(paths: paths);
    if (!isClosed &&
        state.load == CatalogLoadStatus.loaded &&
        (paths == null || paths.contains(path))) {
      schedules.acknowledgeRefresh(path);
    }
  }
}

class PracticeScheduleCubit extends AdminScheduleCubit {
  PracticeScheduleCubit(AdminScheduleRepository schedules)
    : super(schedules, '/jadwal-praktik');
}

class ServiceScheduleCubit extends AdminScheduleCubit {
  ServiceScheduleCubit(AdminScheduleRepository schedules)
    : super(schedules, '/jadwal-layanan');
}
