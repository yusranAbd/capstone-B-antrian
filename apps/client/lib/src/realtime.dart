import 'package:socket_io_client/socket_io_client.dart' as io;

import 'api.dart';
import 'config.dart';
import 'display_socket_headers.dart';

class RealtimeFeed {
  RealtimeFeed({
    required this.api,
    required this.layananId,
    required this.onRefresh,
    required this.onStatus,
    this.onEvent,
    this.displayToken,
    this.displaySession = false,
    this.displayDeviceId,
  }) {
    if (displayToken == null && !displaySession) {
      api.addListener(_credentialsChanged);
    }
    _connect();
  }
  final QueueApi api;
  final String layananId;
  final String? displayToken;
  final String? displayDeviceId;
  final bool displaySession;
  final void Function() onRefresh;
  final void Function(String) onStatus;
  final void Function(Json)? onEvent;
  io.Socket? _socket;
  String? _usedToken;
  bool _disposed = false, _renewing = false;
  void _credentialsChanged() {
    if (!_disposed && api.accessToken != _usedToken) _connect();
  }

  void _connect() async {
    _socket?.dispose();
    _usedToken = displayToken ?? api.accessToken;
    if ((!displaySession && _usedToken == null) ||
        !api.config.realtime ||
        _disposed) {
      return;
    }
    final isDisplay = displayToken != null || displaySession;
    var headers = <String, String>{};
    try {
      if (displaySession) {
        headers = await displaySocketHeaders(api.config.apiBase);
      }
    } catch (_) {
      if (!_disposed) {
        onStatus(
          'Realtime belum tersedia. Penyimpanan aman perangkat tidak dapat dibaca.',
        );
      }
      return;
    }
    if (_disposed) return;
    final options = io.OptionBuilder()
        .setTransports(['websocket'])
        .disableAutoConnect()
        .enableForceNew()
        .setAuth({
          if (!displaySession) 'token': _usedToken,
          if (isDisplay) 'layananId': layananId,
          if (displaySession && displayDeviceId != null)
            'perangkatId': displayDeviceId,
        })
        .setReconnectionAttempts(isDisplay ? double.infinity : 8);
    if (isDisplay) options.setExtraHeaders(headers).enableWithCredentials();
    final socket = _socket = io.io(
      '${api.config.socketOrigin}/${isDisplay ? 'display' : 'queue'}',
      options.build(),
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
    socket.onDisconnect((reason) {
      if (!_disposed && socket == _socket) {
        onStatus(
          isDisplay && reason == 'io server disconnect'
              ? 'Token perangkat ditolak. Aktifkan ulang dari ADMIN.'
              : 'Realtime terputus · sinkronisasi berkala aktif',
        );
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
    if (displayToken == null && !displaySession) {
      api.removeListener(_credentialsChanged);
    }
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
