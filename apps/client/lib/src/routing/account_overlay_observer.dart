import 'dart:async';

import 'package:flutter/material.dart';

import 'route_refresh_notifier.dart';

/// Owns only captured pageless account overlays, never declarative router Pages.
/// Scope changes can keep the same URL (e.g. ADMIN A -> ADMIN B).
class AccountOverlayObserver extends NavigatorObserver {
  AccountOverlayObserver(this.refresh, this.accountLocation, this.location) {
    refresh.addListener(_changed);
  }
  final RouteRefreshNotifier refresh;
  final bool Function() accountLocation;
  final String Function() location;
  final _owned = <Route<dynamic>, (Object, String)>{};
  Listenable? _locationChanges;
  bool _disposed = false;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route.settings is! Page && accountLocation()) {
      _owned[route] = (refresh.scopeKey, location());
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _owned.remove(route);
  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _owned.remove(route);

  void _changed() {
    final stale = _owned.entries
        .where((e) => e.value != (refresh.scopeKey, location()))
        .map((e) => e.key)
        .toList();
    scheduleMicrotask(() {
      if (_disposed) return;
      for (final route in stale) {
        if (_owned.remove(route) != null &&
            route.settings is! Page &&
            route.isActive) {
          route.navigator?.removeRoute(route);
        }
      }
    });
  }

  void watchLocation(Listenable changes) {
    _locationChanges = changes;
    changes.addListener(_changed);
  }

  void dispose() {
    _disposed = true;
    refresh.removeListener(_changed);
    _locationChanges?.removeListener(_changed);
    _owned.clear();
  }
}
