import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import 'api.dart';
import 'config.dart';

/// Serialize reads and retain one trailing read if invalidated mid-request.
class RefreshGate {
  RefreshGate(this.fetch);
  final Future<void> Function() fetch;
  Future<void>? _pending;
  bool _dirty = false, _disposed = false;
  Future<void> refresh() {
    if (_disposed) return Future.value();
    _dirty = true;
    return _pending ??= _drain().whenComplete(() {
      _pending = null;
      if (_dirty && !_disposed) refresh();
    });
  }

  Future<void> _drain() async {
    while (_dirty && !_disposed) {
      _dirty = false;
      await fetch();
    }
  }

  void dispose() {
    _disposed = true;
  }
}

typedef PatientSocketFactory = io.Socket Function(String, Map<String, dynamic>);

/// One socket per patient page, shared by the list and any open ticket dialog.
/// Events never supply UI state: every change is re-read from owned REST APIs.
class PatientUpdates extends ChangeNotifier with WidgetsBindingObserver {
  PatientUpdates({
    required this.api,
    this.role = 'USER',
    this.namespace = 'patient',
    this.eventKinds = const ['TIKET', 'KATALOG'],
    PatientSocketFactory? socketFactory,
    this.debounce = const Duration(milliseconds: 250),
    this.fallbackInterval = const Duration(seconds: 30),
    this.reconcileInterval = const Duration(minutes: 2),
  }) : _factory = socketFactory ?? io.io {
    WidgetsBinding.instance.addObserver(this);
    api.addListener(_credentialsChanged);
    _connect();
    _poll = Timer.periodic(fallbackInterval, (_) {
      if (!_foreground) return;
      if (!_connected) _socket?.connect();
      if (!_connected ||
          DateTime.now().difference(_lastRefresh) >= reconcileInterval) {
        invalidate();
      }
    });
  }
  final QueueApi api;
  final String role, namespace;
  final List<String> eventKinds;
  final PatientSocketFactory _factory;
  final Duration debounce, fallbackInterval, reconcileInterval;
  final status = ValueNotifier('Menghubungkan realtime…');
  final _seen = <String>{};
  io.Socket? _socket;
  Timer? _poll, _debouncer;
  String? _token;
  bool _disposed = false,
      _renewing = false,
      _connected = false,
      _foreground = true;
  DateTime _lastRefresh = DateTime.now();
  void _credentialsChanged() {
    if (!_disposed && api.accessToken != _token) _connect();
  }

  void _connect() {
    _socket?.dispose();
    _socket = null;
    _connected = false;
    _token = api.accessToken;
    if (_disposed ||
        !api.config.realtime ||
        _token == null ||
        api.user?['peran'] != role) {
      status.value = 'Sinkronisasi berkala aktif';
      return;
    }
    final socket = _socket = _factory(
      '${api.config.socketOrigin}/$namespace',
      io.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .enableForceNew()
          .setAuth({'token': _token})
          .setReconnectionAttempts(8)
          .build(),
    );
    bool current() => !_disposed && socket == _socket;
    socket.on('$namespace:ready', (dynamic value) {
      if (!current() || object(value)['versiSkema'] != 1) return;
      _connected = true;
      status.value = 'Realtime terhubung';
      invalidate();
    });
    socket.on('$namespace:updated', (dynamic value) {
      if (!current()) return;
      final event = object(value), id = object(value)['eventId'];
      if (event['versiSkema'] != 1 ||
          !eventKinds.contains(event['jenis']) ||
          id is! String ||
          id.isEmpty ||
          !_seen.add(id)) {
        return;
      }
      if (_seen.length > 256) _seen.remove(_seen.first);
      invalidate();
    });
    socket.on('disconnect', (dynamic reason) {
      if (!current()) return;
      _connected = false;
      status.value = 'Realtime terputus · sinkronisasi berkala aktif';
      if (reason == 'io server disconnect') _renew();
    });
    socket.on('connect_error', (dynamic error) {
      if (!current()) return;
      _connected = false;
      status.value = 'Realtime belum tersambung · sinkronisasi berkala aktif';
      if ('$error'.toUpperCase().contains('UNAUTHORIZED')) _renew();
    });
    socket.connect();
  }

  Future<void> _renew() async {
    if (_disposed || _renewing) return;
    _renewing = true;
    try {
      await api.refresh();
    } catch (_) {
      /* QueueApi clears invalid sessions; the root returns to login. */
    } finally {
      _renewing = false;
    }
  }

  void invalidate() {
    if (_disposed || !_foreground || _debouncer?.isActive == true) return;
    _debouncer = Timer(debounce, () {
      if (!_disposed && _foreground) {
        _lastRefresh = DateTime.now();
        notifyListeners();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _debouncer?.cancel();
      return;
    }
    if (!_connected) _connect();
    invalidate();
  }

  @override
  void dispose() {
    _disposed = true;
    _poll?.cancel();
    _debouncer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    api.removeListener(_credentialsChanged);
    _socket?.dispose();
    status.dispose();
    super.dispose();
  }
}
