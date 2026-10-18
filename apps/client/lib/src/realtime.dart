import 'package:socket_io_client/socket_io_client.dart' as io;

import 'api.dart';
import 'config.dart';

class RealtimeFeed {
  RealtimeFeed({
    required this.api,
    required this.layananId,
    required this.onRefresh,
    required this.onStatus,
    this.onEvent,
    this.displayToken,
  }) {
    if (displayToken == null) api.addListener(_credentialsChanged);
    _connect();
  }
  final QueueApi api;
  final String layananId;
  final String? displayToken;
  final void Function() onRefresh;
  final void Function(String) onStatus;
  final void Function(Json)? onEvent;
  io.Socket? _socket;
  String? _usedToken;
  bool _disposed = false, _renewing = false;
  void _credentialsChanged() {
    if (!_disposed && api.accessToken != _usedToken) _connect();
  }

  void _connect() {
    _socket?.dispose();
    _usedToken = displayToken ?? api.accessToken;
    if (_usedToken == null || !api.config.realtime || _disposed) return;
    final isDisplay = displayToken != null;
    final socket = _socket = io.io(
      '${api.config.socketOrigin}/${isDisplay ? 'display' : 'queue'}',
      io.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .enableForceNew()
          .setAuth({'token': _usedToken, if (isDisplay) 'layananId': layananId})
          // TV reconnects after prolonged outages; denied tokens still stop
          // explicitly in onConnectError. Staff behavior stays unchanged.
          .setReconnectionAttempts(isDisplay ? double.infinity : 8)
          .build(),
    );
    socket.onConnect((_) {
      if (!isDisplay) {
        socket.emitWithAck(
          'queue:join',
          {'layananId': layananId},
          ack: (dynamic ack) {
            if (_disposed || socket != _socket) return;
            if (object(ack)['ok'] == true) {
              onStatus('Realtime terhubung');
              onRefresh();
            } else {
              socket.disconnect();
              onStatus('Izin realtime ditolak. Gunakan muat ulang.');
            }
          },
        );
      }
    });
    if (isDisplay) {
      socket.on('display:ready', (dynamic event) {
        final data = object(event);
        if (!_disposed &&
            socket == _socket &&
            data['layananId'] == layananId &&
            data['versiSkema'] == 1) {
          onStatus('Realtime terhubung');
          onRefresh();
        }
      });
    }
    socket.on(isDisplay ? 'display:updated' : 'queue:updated', (dynamic event) {
      if (_disposed || socket != _socket) return;
      final data = object(event);
      if (data['layananId'] != layananId || data['versiSkema'] != 1) return;
      onEvent?.call(data);
      onRefresh();
    });
    socket.onDisconnect((_) {
      if (!_disposed && socket == _socket) {
        onStatus('Realtime terputus · sinkronisasi berkala aktif');
      }
    });
    socket.onConnectError((dynamic error) async {
      if (_disposed || socket != _socket) return;
      final text = '$error'.toLowerCase();
      if (text.contains('unauthorized') ||
          text.contains('forbidden') ||
          text.contains('token')) {
        socket.disconnect();
        onStatus(
          isDisplay
              ? 'Token perangkat ditolak. Hubungkan ulang dengan token sah.'
              : 'Autentikasi realtime ditolak.',
        );
        if (!isDisplay && !_renewing && !text.contains('forbidden')) {
          _renewing = true;
          try {
            await api.refresh();
          } catch (_) {
            /* Login handles expired session. */
          } finally {
            _renewing = false;
          }
        }
      } else {
        onStatus('Realtime belum tersambung · sinkronisasi berkala aktif');
      }
    });
    socket.connect();
  }

  void dispose() {
    _disposed = true;
    if (displayToken == null) api.removeListener(_credentialsChanged);
    _socket?.dispose();
  }
}

/// Coalesce events while fetching, then read again if changes arrived mid-request.
class SnapshotLoader {
  SnapshotLoader({
    required this.fetch,
    required this.onData,
    required this.onError,
  });
  final Future<Json> Function() fetch;
  final void Function(Json) onData;
  final void Function(Object) onError;
  bool _running = false, _dirty = false, _disposed = false;
  Future<void> refresh() async {
    if (_disposed) return;
    _dirty = true;
    if (_running) return;
    _running = true;
    try {
      while (_dirty && !_disposed) {
        _dirty = false;
        try {
          final data = await fetch();
          if (!_disposed) onData(data);
        } catch (e) {
          if (!_disposed) onError(e);
        }
      }
    } finally {
      _running = false;
    }
  }

  void dispose() {
    _disposed = true;
  }
}
