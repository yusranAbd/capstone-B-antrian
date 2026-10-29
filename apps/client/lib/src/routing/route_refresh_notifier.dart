import 'package:flutter/foundation.dart';

import '../api.dart';

/// A filtered notification adapter, with no credentials or session storage.
class RouteRefreshNotifier extends ChangeNotifier {
  RouteRefreshNotifier(this.api) {
    _last = _snapshot;
    api.addListener(_changed);
  }
  final QueueApi api;
  late (SessionPhase, Object?, Object?) _last;
  int epoch = 0;
  (SessionPhase, Object?, Object?) get _snapshot =>
      (api.sessionPhase, api.user?['id'], api.user?['peran']);
  Object get scopeKey => (_snapshot.$2, _snapshot.$3, epoch);
  void _changed() {
    final next = _snapshot;
    if (next == _last) return;
    if (_last.$1 == SessionPhase.ready && _last.$2 != null) epoch++;
    _last = next;
    notifyListeners();
  }

  @override
  void dispose() {
    api.removeListener(_changed);
    super.dispose();
  }
}
