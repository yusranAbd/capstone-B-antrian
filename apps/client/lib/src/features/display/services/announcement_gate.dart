import '../../../config.dart';

class AnnouncementGate {
  bool _initialized = false;
  final _seen = <String>{};
  void rebase() => _initialized = false;
  String? observe(Json? announcement, {required bool callSignal}) {
    final id = announcement?['peristiwaId'] as String?;
    final seen = id != null && _seen.contains(id);
    if (id != null) {
      _seen.add(id);
      if (_seen.length > 256) _seen.remove(_seen.first);
    }
    if (!_initialized) {
      _initialized = true;
      return null;
    }
    if (id == null || seen || !callSignal) return null;
    if (announcement?['aksi'] != null &&
        !['CALL', 'RECALL'].contains(announcement?['aksi'])) {
      return null;
    }
    return announcement?['teks'] as String?;
  }
}
