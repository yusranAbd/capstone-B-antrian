import '../../../config.dart';

/// Recursively copies JSON so neither API callers nor widgets can mutate state.
Object? _freeze(Object? value) {
  if (value is Map) {
    return Map<String, dynamic>.unmodifiable(
      value.map((key, value) => MapEntry(key as String, _freeze(value))),
    );
  }
  if (value is List) return List<dynamic>.unmodifiable(value.map(_freeze));
  return value;
}

class DoctorPortalData {
  DoctorPortalData({
    Json profile = const {},
    List<Json> schedules = const [],
    List<Json> appointments = const [],
    List<Json> snapshots = const [],
  }) : profile = _freeze(profile) as Json,
       schedules = List<Json>.unmodifiable(
         schedules.map((v) => _freeze(v) as Json),
       ),
       appointments = List<Json>.unmodifiable(
         appointments.map((v) => _freeze(v) as Json),
       ),
       snapshots = List<Json>.unmodifiable(
         snapshots.map((v) => _freeze(v) as Json),
       );
  final Json profile;
  final List<Json> schedules, appointments, snapshots;
}
