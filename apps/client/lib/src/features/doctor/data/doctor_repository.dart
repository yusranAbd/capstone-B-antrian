import 'package:flutter/foundation.dart';

import '../../../api.dart';
import '../../../config.dart';
import '../../../patient_sync.dart';
import '../models/doctor_portal_data.dart';

/// Portal-scoped invalidations; socket events never supply queue data.
abstract class DoctorRepository extends ChangeNotifier {
  bool get sessionActive;
  ValueListenable<String> get connectionStatus;
  Future<DoctorPortalData> load(String date);
}

class ApiDoctorRepository extends DoctorRepository {
  ApiDoctorRepository({required this.api, PatientUpdates? updates})
    : _identity = api.user?['id'],
      _ownsUpdates = updates == null,
      _updates =
          updates ??
          PatientUpdates(
            api: api,
            role: 'DOKTER',
            namespace: 'doctor',
            eventKinds: const ['ANTREAN'],
          ) {
    _updates.addListener(_invalidated);
    api.addListener(_sessionChanged);
    _active = _matchesSession;
  }
  final QueueApi api;
  final Object? _identity;
  final bool _ownsUpdates;
  final PatientUpdates _updates;
  bool _active = true, _disposed = false, _detached = false;
  bool get _matchesSession =>
      _identity != null &&
      api.user?['id'] == _identity &&
      api.user?['peran'] == 'DOKTER' &&
      api.sessionPhase == SessionPhase.ready;
  @override
  bool get sessionActive => !_disposed && _active && _matchesSession;
  @override
  ValueListenable<String> get connectionStatus => _updates.status;
  void _invalidated() {
    if (sessionActive) notifyListeners();
  }

  void _sessionChanged() {
    if (!_active || _matchesSession) return;
    _active = false;
    _detach();
    notifyListeners();
  }

  void _detach() {
    if (_detached) return;
    _detached = true;
    api.removeListener(_sessionChanged);
    _updates.removeListener(_invalidated);
    // Injected feeds remain owned by their caller, as before the migration.
    if (_ownsUpdates) _updates.dispose();
  }

  void _checkSession() {
    if (!sessionActive) {
      throw const ApiException(
        401,
        'Sesi dokter berubah. Silakan masuk kembali.',
      );
    }
  }

  @override
  Future<DoctorPortalData> load(String date) async {
    _checkSession();
    final values = await Future.wait([
      api.request('GET', '/portal-dokter/profil'),
      api.request('GET', '/portal-dokter/jadwal', query: {'tanggal': date}),
      api.request('GET', '/portal-dokter/janji-temu', query: {'tanggal': date}),
    ]);
    _checkSession();
    final schedules = rows(values[1]), now = api.config.now;
    final live = schedules.where(
      (s) =>
          s['aktif'] == true &&
          date == api.config.today &&
          DateTime.tryParse('${s['mulaiPada']}')?.isAfter(now) == false &&
          DateTime.tryParse('${s['selesaiPada']}')?.isAfter(now) == true,
    );
    final snapshots = <Json>[];
    for (final session in live) {
      _checkSession();
      try {
        snapshots.add(
          object(
            await api.request(
              'GET',
              '/portal-dokter/antrean/snapshot',
              query: {'jadwalPraktikId': '${session['id']}'},
            ),
          ),
        );
      } on ApiException catch (e) {
        // Preserve the contract for a session ending between the two reads.
        if (e.status != 403) rethrow;
      }
    }
    _checkSession();
    return DoctorPortalData(
      profile: object(values[0]),
      schedules: schedules,
      appointments: rows(values[2]),
      snapshots: snapshots,
    );
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _detach();
    super.dispose();
  }
}
