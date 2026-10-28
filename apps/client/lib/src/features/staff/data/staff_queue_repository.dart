import 'package:flutter/foundation.dart';

import '../../../api.dart';
import '../../../config.dart';
import '../../../realtime.dart';
import '../models/staff_queue_models.dart';

typedef StaffFeedFactory = void Function() Function(
  String serviceId,
  VoidCallback refresh,
  ValueChanged<String> status,
);

/// Transport and one realtime adapter only. Feature snapshots live in the BLoC.
class StaffQueueRepository extends ChangeNotifier {
  StaffQueueRepository(this.api, {StaffFeedFactory? feedFactory})
    : _identity = (api.user?['id'], api.user?['peran']) {
    _feedFactory = feedFactory;
    api.addListener(_sessionChanged);
  }
  final QueueApi api;
  final (Object?, Object?) _identity;
  late final StaffFeedFactory? _feedFactory;
  bool _ended = false, _disposed = false, _writing = false;
  VoidCallback? _disposeFeed;
  String? _service;
  int _feedEpoch = 0;
  bool get active =>
      !_ended &&
      !_disposed &&
      api.sessionPhase == SessionPhase.ready &&
      _identity == (api.user?['id'], api.user?['peran']) &&
      api.user?['peran'] == 'PETUGAS';
  String get today => api.config.today;
  void check() {
    if (!active) throw const ApiException(401, 'Sesi petugas berubah.');
  }

  void _sessionChanged() {
    if (_ended || active) return;
    _ended = true;
    stopFeed();
    notifyListeners();
  }

  void connect(
    String service,
    VoidCallback refresh,
    ValueChanged<String> status,
  ) {
    if (_service == service && _disposeFeed != null) return;
    stopFeed();
    check();
    _service = service;
    final epoch = _feedEpoch;
    void invalidated() {
      if (active && epoch == _feedEpoch) refresh();
    }

    void changed(String value) {
      if (active && epoch == _feedEpoch) status(value);
    }

    if (_feedFactory != null) {
      _disposeFeed = _feedFactory(service, invalidated, changed);
    } else {
      final feed = RealtimeFeed(
        api: api,
        layananId: service,
        onRefresh: invalidated,
        onStatus: changed,
      );
      _disposeFeed = feed.dispose;
    }
  }

  void stopFeed() {
    _feedEpoch++;
    _disposeFeed?.call();
    _disposeFeed = null;
    _service = null;
  }

  Future<List<Json>> assignments() async {
    check();
    return staffRows(await api.request('GET', '/penugasan-petugas'));
  }

  Future<Json> snapshot(String room, int page) async {
    check();
    final result = staffObject(
      await api.request(
        'GET',
        '/queue/snapshot',
        query: {'loketId': room, 'halamanTindakLanjut': '$page'},
      ),
    );
    if (result['tanggalPelayanan'] is! String ||
        result['loket'] is! List ||
        result['menunggu'] is! Map ||
        (result['daftarPasien'] != null && result['daftarPasien'] is! Map) ||
        (result['loketPeminta'] != null &&
            object(result['loketPeminta'])['id'] != room)) {
      throw const ApiException(0, 'Snapshot belum terverifikasi.');
    }
    staffRows(object(result['menunggu'])['tiket']);
    if (result['daftarPasien'] != null) {
      staffRows(object(result['daftarPasien'])['tiket']);
    }
    for (final row in staffRows(result['loket'])) {
      staffRows(row['tiketAktif']);
    }
    return result;
  }

  Future<List<Json>> schedules(String service, String room, String date) async {
    check();
    final list = staffRows(
      await api.request(
        'GET',
        '/jadwal-praktik',
        query: {'layananId': service, 'tanggal': date},
      ),
    );
    return List.unmodifiable(
      list.where(
        (s) =>
            (s['loketId'] ?? object(s['loket'])['id']) == room &&
            dateOnly(s['tanggal']) == date &&
            s['aktif'] != false,
      ),
    );
  }

  Future<Json> command(
    StaffOperation operation,
    String room, {
    String? ticketId,
    String? qr,
  }) async {
    check();
    if (_writing) throw const ApiException(409, 'Tunggu proses sebelumnya.');
    _writing = true;
    try {
      final path = operation == StaffOperation.scan
          ? '/check-in/auto-antrean'
          : operation == StaffOperation.call
          ? '/queue/panggil'
          : '/queue/${Uri.encodeComponent(ticketId!)}/${operation.route}';
      final result = staffObject(
        await api.request(
          'POST',
          path,
          body: {
            'loketId': room,
            if (operation == StaffOperation.scan) 'qrPayload': qr,
          },
        ),
      );
      if ((result['tiketId'] ?? result['id']) is! String ||
          '${result['tiketId'] ?? result['id']}'.isEmpty ||
          (ticketId != null &&
              (result['tiketId'] ?? result['id']) != ticketId) ||
          result['status'] != operation.expectedStatus) {
        throw const ApiException(0, 'Hasil tindakan belum terverifikasi.');
      }
      return result;
    } finally {
      _writing = false;
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    stopFeed();
    api.removeListener(_sessionChanged);
    super.dispose();
  }
}
