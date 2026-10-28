import 'package:flutter/foundation.dart';

import '../../../api.dart';
import '../../../config.dart';
import '../../../display_selection.dart';
import '../../../realtime.dart';
import '../models/display_models.dart';

/// Scoped device transport; credentials never leave this adapter or QueueApi.
class DisplayDeviceRepository extends ChangeNotifier {
  DisplayDeviceRepository(this.api, this.selection);
  final QueueApi api;
  final DisplaySelection selection;
  DisplayScope? _scope;
  DisplayScope? get scope => _scope;
  ApiException? _rejection;
  ApiException? get rejection => _rejection;
  Future<void> _selectionTail = Future.value();
  String? _legacyToken;
  int _epoch = 0;
  bool _disposed = false;
  int begin({ApiException? failure}) {
    _epoch++;
    _scope = null;
    _rejection = failure;
    _legacyToken = null;
    if (!_disposed) notifyListeners();
    return _epoch;
  }

  bool current(int epoch) => !_disposed && epoch == _epoch;
  void check(int epoch) {
    if (!current(epoch)) throw DisplayStale();
  }

  Future<void> _store(Future<void> Function() action) {
    final result = _selectionTail.then((_) => action());
    _selectionTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  Future<Json> session(String? id, int epoch) async {
    final data = displayDevice(
      await api.request(
        'GET',
        '/display/sesi',
        authenticated: false,
        displayDeviceId: id,
      ),
    );
    check(epoch);
    if (id != null && data['id'] != id) {
      throw const ApiException(403, 'Sesi perangkat tidak cocok.');
    }
    return data;
  }

  Future<Json?> restore(int epoch) async {
    final id = await selection.read();
    check(epoch);
    if (selection.isolated && id == null) return null;
    return session(id, epoch);
  }

  Future<Json> pair(String code, int epoch) async {
    final device = displayDevice(
      await api.request(
        'POST',
        '/display/pairing',
        authenticated: false,
        body: {'kode': code, if (selection.isolated) 'isolasiSesi': true},
      ),
    );
    check(epoch);
    if (selection.isolated) {
      await _store(() async {
        check(epoch);
        await selection.write(device['id']);
        if (!current(epoch)) {
          if (await selection.read() == device['id']) await selection.clear();
          throw DisplayStale();
        }
      });
    }
    final stored = await session(
      selection.isolated ? device['id'] : null,
      epoch,
    );
    if (stored['id'] != device['id'] ||
        stored['layananId'] != device['layananId']) {
      throw const ApiException(403, 'Sesi perangkat tidak cocok.');
    }
    return stored;
  }

  DisplayScope activate(Json device, int epoch) {
    check(epoch);
    _scope = DisplayScope(
      device['id'],
      device['layananId'],
      epoch,
      '${api.config.apiBase}',
      selector: selection.isolated ? device['id'] : null,
    );
    notifyListeners();
    return scope!;
  }

  DisplayScope legacy(String service, String token, int epoch) {
    check(epoch);
    _legacyToken = token;
    _scope = DisplayScope(
      null,
      service,
      epoch,
      '${api.config.apiBase}',
      paired: false,
    );
    notifyListeners();
    return scope!;
  }

  bool owns(DisplayScope value) =>
      !_disposed && identical(scope, value) && current(value.epoch);
  Future<void> disconnect(DisplayScope? value) async {
    var epoch = _epoch;
    var confirmed = false;
    bool valid() =>
        current(epoch) || (!_disposed && scope == null && rejection != null);
    if (value != null && value.paired && rejection == null) {
      await api.request(
        'POST',
        '/display/putuskan',
        authenticated: false,
        displayDeviceId: value.selector,
      );
      if (!valid()) throw DisplayStale();
      confirmed = true;
      epoch = begin(); // Acknowledged revocation immediately retires the scope.
    }
    await _store(() async {
      if (!valid()) throw DisplayStale();
      if (selection.isolated &&
          value?.selector != null &&
          await selection.read() != value!.selector) {
        throw DisplayStale();
      }
      try {
        await selection.clear();
      } catch (_) {
        if (confirmed) throw DisplayDisconnectPartial();
        rethrow;
      }
    });
    if (!valid()) throw DisplayStale();
    begin();
  }

  Future<Json> snapshot(DisplayScope value) async {
    if (!owns(value)) throw DisplayStale();
    final response = await api.request(
      'GET',
      '/display/${Uri.encodeComponent(value.serviceId)}/snapshot',
      authenticated: false,
      displayToken: value.paired ? null : _legacyToken,
      displayDeviceId: value.paired ? value.selector : null,
    );
    if (!owns(value)) throw DisplayStale();
    return displaySnapshot(response, value);
  }

  VoidCallback openFeed(
    DisplayScope value,
    VoidCallback refresh,
    ValueChanged<String> status,
    ValueChanged<Json> event,
  ) {
    if (!owns(value)) throw DisplayStale();
    final feed = RealtimeFeed(
      api: api,
      layananId: value.serviceId,
      displaySession: value.paired,
      displayToken: value.paired ? null : _legacyToken,
      displayDeviceId: value.selector,
      onRefresh: refresh,
      onStatus: status,
      onEvent: event,
    );
    return feed.dispose;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    begin();
    super.dispose();
  }
}
