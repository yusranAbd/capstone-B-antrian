import 'package:flutter/foundation.dart';

import '../../../config.dart';
import '../models/display_models.dart';
import 'display_device_repository.dart';

typedef DisplayFeedFactory = VoidCallback Function(
  DisplayScope scope,
  VoidCallback refresh,
  ValueChanged<String> status,
  ValueChanged<Json> event,
);

class DisplayMonitorRepository {
  DisplayMonitorRepository(this.devices, {DisplayFeedFactory? feedFactory}) {
    _factory = feedFactory;
  }
  final DisplayDeviceRepository devices;
  late final DisplayFeedFactory? _factory;
  VoidCallback? _stop;
  int _epoch = 0;
  Future<Json> snapshot(DisplayScope scope) => devices.snapshot(scope);
  void connect(
    DisplayScope scope,
    VoidCallback refresh,
    ValueChanged<String> status,
    ValueChanged<Json> event,
  ) {
    disconnect();
    final epoch = _epoch;
    var eventRefresh = false;
    bool valid() => epoch == _epoch && devices.owns(scope);
    void refreshScoped() {
      if (eventRefresh) {
        eventRefresh = false;
        return;
      }
      if (valid()) refresh();
    }

    void statusScoped(String value) {
      if (valid()) status(value);
    }

    void eventScoped(Json value) {
      // RealtimeFeed calls onRefresh immediately after onEvent. The BLoC event
      // owns that refresh so one notification cannot start two REST reads.
      eventRefresh = true;
      if (valid() &&
          value['versiSkema'] == 1 &&
          value['layananId'] == scope.serviceId) {
        event({
          'versiSkema': 1,
          'layananId': scope.serviceId,
          'eventId': value['eventId'],
          'aksi': value['aksi'],
          'perluPeriksaPengumuman': value['perluPeriksaPengumuman'],
        });
      }
    }

    _stop =
        _factory?.call(scope, refreshScoped, statusScoped, eventScoped) ??
        devices.openFeed(scope, refreshScoped, statusScoped, eventScoped);
  }

  void disconnect() {
    _epoch++;
    _stop?.call();
    _stop = null;
  }
}
