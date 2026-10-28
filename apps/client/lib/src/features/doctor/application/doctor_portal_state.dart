import '../models/doctor_portal_data.dart';

enum DoctorPortalStatus {
  initialLoading,
  loaded,
  refreshing,
  error,
  sessionEnded,
}

class DoctorPortalState {
  DoctorPortalState({
    required this.selectedDate,
    this.status = DoctorPortalStatus.initialLoading,
    DoctorPortalData? data,
    this.loadedDate,
    this.error,
  }) : data = data ?? DoctorPortalData();
  final String selectedDate;
  final DoctorPortalStatus status;
  final DoctorPortalData data;
  final String? loadedDate;
  final Object? error;
  bool get loading =>
      status == DoctorPortalStatus.initialLoading ||
      status == DoctorPortalStatus.refreshing;
  bool get available => loadedDate == selectedDate && error == null;
}
