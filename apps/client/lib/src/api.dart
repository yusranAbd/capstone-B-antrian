import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'config.dart';
import 'display_client.dart';
import 'session_store.dart';

enum SessionPhase { ready, restoring, offline, storageError, signingOut }

class ApiException implements Exception {
  const ApiException(this.status, this.message);
  final int status;
  final String message;
  @override
  String toString() => message;
}

class QueueApi extends ChangeNotifier {
  QueueApi({
    required this.config,
    http.Client? client,
    http.Client? displayClient,
    SessionStore? sessionStore,
    this.requestTimeout = const Duration(seconds: 20),
  }) : _client = client ?? http.Client(),
       _displayClient =
           displayClient ?? client ?? createDisplayClient(config.apiBase),
       _store = sessionStore ?? MemorySessionStore();
  final AppConfig config;
  final http.Client _client, _displayClient;
  final Duration requestTimeout;
  final SessionStore _store;
  SessionPhase sessionPhase = SessionPhase.ready;
  String? sessionMessage;
  Json? user;
  String? accessToken;
  String? _refreshToken;
  Future<void>? _refreshing;
  Future<void>? _restoring;
  Future<void> _storageTail = Future.value();
  SessionCredentials? _pendingPersistence;
  int? _refreshGeneration, _logoutGeneration;
  String? _logoutToken;
  bool _disposed = false, _storageNeedsClear = false, _refreshUncertain = false;
  Timer? _renew;
  int _generation = 0;
  Uri uri(String path, [Map<String, String>? query]) =>
      Uri.parse('${config.apiBase}$path').replace(queryParameters: query);
  Future<dynamic> request(
    String method,
    String path, {
    Json? body,
    Map<String, String>? query,
    bool authenticated = true,
    String? displayToken,
  }) async {
    if (authenticated &&
        sessionPhase != SessionPhase.ready &&
        !(sessionPhase == SessionPhase.restoring && path == '/auth/me')) {
      throw const ApiException(0, 'Pulihkan koneksi sesi sebelum melanjutkan.');
    }
    final generation = _generation;
    final token = accessToken;
    final response = await _send(
      method,
      path,
      body,
      query,
      authenticated ? token : null,
      displayToken,
    );
    if (authenticated && generation != _generation) {
      throw const ApiException(401, 'Sesi berubah. Silakan masuk kembali.');
    }
    if (response.statusCode == 401 && authenticated && _refreshToken != null) {
      // Retry only guard rejection; never retry timeout or domain mutation errors.
      if (token == accessToken) await refresh();
      if (generation != _generation || accessToken == null) {
        throw const ApiException(401, 'Sesi berakhir. Silakan masuk kembali.');
      }
      final retry = await _send(
        method,
        path,
        body,
        query,
        accessToken,
        displayToken,
      );
      if (generation != _generation) {
        throw const ApiException(401, 'Sesi berubah. Silakan masuk kembali.');
      }
      if (retry.statusCode == 401) await clearSession();
      return _decode(retry);
    }
    if (response.statusCode == 401 && authenticated) await clearSession();
    return _decode(response);
  }

  Future<http.Response> _send(
    String method,
    String path,
    Json? body,
    Map<String, String>? query,
    String? token,
    String? displayToken,
  ) async {
    final request = http.Request(method, uri(path, query));
    request.headers.addAll({
      'Accept': 'application/json',
      if (body != null) 'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
      'x-display-token': ?displayToken,
    });
    if (body != null) request.body = jsonEncode(body);
    try {
      return await (() async {
        final transport = path.startsWith('/display/') && displayToken == null
            ? _displayClient
            : _client;
        final response = await transport.send(request);
        return http.Response.fromStream(response);
      })().timeout(requestTimeout);
    } on TimeoutException {
      throw const ApiException(
        0,
        'Koneksi melewati batas waktu. Periksa status terbaru sebelum mengulangi tindakan.',
      );
    } on http.ClientException {
      throw const ApiException(
        0,
        'API tidak dapat dihubungi. Periksa koneksi, alamat API dan izin origin Web. Muat ulang data sebelum mengulang tindakan.',
      );
    }
  }

  dynamic _decode(http.Response response) {
    dynamic data;
    try {
      data = jsonDecode(response.body);
    } on FormatException {
      data = null;
    }
    if (response.statusCode >= 200 && response.statusCode < 300) return data;
    final message = object(data)['message'];
    throw ApiException(
      response.statusCode,
      message is List
          ? message.join('\n')
          : message is String
          ? message
          : 'Permintaan gagal (${response.statusCode}).',
    );
  }

  Future<void> login(String email, String password) async {
    if (sessionPhase != SessionPhase.ready) {
      throw const ApiException(
        0,
        'Selesaikan pemulihan atau logout sesi dahulu.',
      );
    }
    final generation = ++_generation;
    sessionMessage = null;
    try {
      final data = object(
        await request(
          'POST',
          '/auth/login',
          authenticated: false,
          body: {
            'email': email.trim(),
            'kataSandi': password,
            'namaPerangkat': 'QueueB Flutter',
          },
        ),
      );
      await _accept(data, generation);
      final identity = _identity(await request('GET', '/auth/me'));
      if (generation != _generation) return;
      user = identity;
      _scheduleRenew();
      _notify();
    } catch (e) {
      if (generation == _generation) {
        if (_invalid(e)) {
          await clearSession();
        } else if (_refreshToken != null &&
            sessionPhase != SessionPhase.storageError) {
          _block(
            SessionPhase.offline,
            'Sesi tersimpan. Koneksi ke server belum dapat divalidasi. Periksa jaringan lalu coba lagi.',
          );
        }
      }
      rethrow;
    }
  }

  /// No cached role is trusted: only /auth/me may unlock the application's routes.
  Future<void> restoreSession() =>
      _restoring ??= _restore().whenComplete(() => _restoring = null);
  Future<void> _restore() async {
    if (sessionPhase == SessionPhase.signingOut) return;
    if (_storageNeedsClear) {
      await clearSession();
      return;
    }
    final generation = _generation;
    sessionPhase = SessionPhase.restoring;
    sessionMessage = null;
    _notify();
    try {
      if (_pendingPersistence != null) {
        await _persist(_pendingPersistence!, generation);
      } else if (_refreshToken == null) {
        SessionCredentials? saved;
        try {
          saved = await _storage(() => _store.read());
        } catch (_) {
          if (generation == _generation) {
            _block(
              SessionPhase.storageError,
              'Penyimpanan sesi aman belum dapat dibaca. Buka kunci perangkat lalu coba lagi.',
            );
          }
          return;
        }
        if (generation != _generation) return;
        if (saved == null) {
          sessionPhase = SessionPhase.ready;
          _notify();
          return;
        }
        accessToken = saved.accessToken;
        _refreshToken = saved.refreshToken;
      }
      if (generation != _generation) return;
      // An ambiguous network failure during rotation is retried only explicitly.
      if (_refreshUncertain) await refresh();
      final identity = _identity(await request('GET', '/auth/me'));
      if (generation != _generation) return;
      user = identity;
      sessionPhase = SessionPhase.ready;
      sessionMessage = null;
      _scheduleRenew();
      _notify();
    } catch (e) {
      if (generation != _generation) return;
      if (_invalid(e)) {
        await clearSession();
        sessionMessage = 'Sesi tidak dapat dipulihkan. Silakan masuk kembali.';
        _notify();
      } else if (sessionPhase != SessionPhase.storageError) {
        _block(
          SessionPhase.offline,
          'Sesi tersimpan. Koneksi ke server belum dapat divalidasi. Periksa jaringan lalu coba lagi.',
        );
      }
    }
  }

  Json _identity(dynamic value) {
    final identity = object(value);
    if (!['ADMIN', 'PETUGAS', 'USER', 'DOKTER'].contains(identity['peran']) ||
        identity['id'] is! String ||
        (identity['id'] as String).isEmpty) {
      throw const ApiException(403, 'Peran akun tidak didukung.');
    }
    return identity;
  }

  bool _invalid(Object e) =>
      e is ApiException && [400, 401, 403].contains(e.status);
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _block(SessionPhase phase, String message) {
    _renew?.cancel();
    user = null;
    sessionPhase = phase;
    sessionMessage = message;
    _notify();
  }

  // Ordered writes/deletes + generation checks prevent late login/rotation
  // from resurrecting credentials after logout or an account change.
  Future<T> _storage<T>(Future<T> Function() operation) {
    final result = _storageTail.then((_) => operation());
    _storageTail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<void> _persist(SessionCredentials credentials, int generation) async {
    try {
      await _storage(() async {
        if (generation == _generation) await _store.write(credentials);
      });
      if (generation == _generation) _pendingPersistence = null;
    } catch (_) {
      if (generation == _generation) {
        _block(
          SessionPhase.storageError,
          'Pasangan token baru belum tersimpan aman. Coba lagi sebelum melanjutkan.',
        );
      }
      throw const ApiException(0, 'Penyimpanan sesi aman belum tersedia.');
    }
  }

  Future<void> register(String name, String email, String password) async {
    await request(
      'POST',
      '/auth/register',
      authenticated: false,
      body: {'nama': name.trim(), 'email': email.trim(), 'kataSandi': password},
    );
  }

  Future<void> _accept(Json data, int generation) async {
    final access = data['accessToken'], refresh = data['refreshToken'];
    if (access is! String ||
        access.isEmpty ||
        refresh is! String ||
        refresh.isEmpty) {
      throw const ApiException(502, 'Respons sesi server tidak lengkap.');
    }
    if (generation != _generation) {
      if (_logoutGeneration == generation) _logoutToken = refresh;
      return;
    }
    accessToken = access;
    _refreshToken = refresh;
    _pendingPersistence = SessionCredentials(access, refresh);
    _refreshUncertain = false;
    _renew?.cancel();
    await _persist(_pendingPersistence!, generation);
  }

  void _scheduleRenew() {
    _renew?.cancel();
    if (sessionPhase != SessionPhase.ready || user == null) return;
    try {
      final claims = object(
        jsonDecode(
          utf8.decode(
            base64Url.decode(base64Url.normalize(accessToken!.split('.')[1])),
          ),
        ),
      );
      final expiry = DateTime.fromMillisecondsSinceEpoch(
        (claims['exp'] as num).toInt() * 1000,
      );
      final delay =
          expiry.difference(DateTime.now()) - const Duration(seconds: 30);
      _renew = Timer(delay.isNegative ? const Duration(seconds: 1) : delay, () {
        refresh().catchError((Object _) {});
      });
    } catch (_) {
      /* Token remains server validated; 401 also triggers refresh. */
    }
  }

  Future<void> refresh() {
    if (_refreshing != null && _refreshGeneration == _generation) {
      return _refreshing!;
    }
    _refreshGeneration = _generation;
    late final Future<void> pending;
    pending = _rotate().whenComplete(() {
      if (identical(_refreshing, pending)) _refreshing = null;
    });
    return _refreshing = pending;
  }

  Future<void> _rotate() async {
    final token = _refreshToken;
    final generation = _generation;
    if (token == null) throw const ApiException(401, 'Silakan masuk kembali.');
    if (![SessionPhase.ready, SessionPhase.restoring].contains(sessionPhase)) {
      throw const ApiException(0, 'Pulihkan koneksi sesi sebelum melanjutkan.');
    }
    if (_pendingPersistence != null) {
      await _persist(_pendingPersistence!, generation);
      return;
    }
    try {
      final data = object(
        await request(
          'POST',
          '/auth/refresh',
          authenticated: false,
          body: {'refreshToken': token},
        ),
      );
      await _accept(data, generation);
      if (generation == _generation &&
          user != null &&
          sessionPhase == SessionPhase.ready) {
        user = _identity(data['user']);
        _scheduleRenew();
        _notify(); // Realtime listeners reconnect only after the pair is saved.
      }
    } catch (e) {
      if (generation == _generation) {
        if (_invalid(e)) {
          await clearSession();
        } else if (sessionPhase != SessionPhase.storageError) {
          _refreshUncertain = true;
          _block(
            SessionPhase.offline,
            'Sesi tersimpan. Refresh belum terkonfirmasi karena gangguan koneksi. Coba lagi saat tersambung.',
          );
        }
      }
      rethrow;
    }
  }

  Future<void> logout() async {
    if (sessionPhase == SessionPhase.signingOut) return;
    _logoutGeneration = _generation;
    _logoutToken = _refreshToken;
    final pending = _refreshing;
    sessionPhase = SessionPhase.signingOut;
    try {
      Object? localError;
      try {
        await clearSession(nextPhase: SessionPhase.signingOut);
      } catch (e) {
        localError = e;
      }
      // If rotation had already committed, revoke the returned replacement.
      if (pending != null) {
        try {
          await pending;
        } catch (_) {}
      }
      if (_logoutToken != null) {
        try {
          await request(
            'POST',
            '/auth/logout',
            authenticated: false,
            body: {'refreshToken': _logoutToken},
          );
        } catch (_) {
          sessionMessage = localError == null
              ? 'Sesi lokal sudah dihapus. Pencabutan sesi di server belum terkonfirmasi; periksa koneksi.'
              : '${sessionMessage ?? 'Kredensial lokal belum dapat dihapus.'} Pencabutan sesi di server juga belum terkonfirmasi.';
          if (localError != null) _notify();
        }
      }
      if (localError != null) throw localError;
      sessionPhase = SessionPhase.ready;
      _notify();
    } finally {
      _logoutGeneration = null;
      _logoutToken = null;
    }
  }

  Future<void> clearSession({
    SessionPhase nextPhase = SessionPhase.ready,
  }) async {
    _generation++;
    _renew?.cancel();
    user = null;
    accessToken = null;
    _refreshToken = null;
    _pendingPersistence = null;
    _refreshUncertain = false;
    sessionPhase = nextPhase;
    sessionMessage = null;
    _notify();
    try {
      await _storage(() => _store.clear());
      _storageNeedsClear = false;
    } catch (_) {
      _storageNeedsClear = true;
      _block(
        SessionPhase.storageError,
        'Kredensial lokal belum dapat dihapus. Coba lagi agar sesi tidak pulih saat aplikasi dibuka ulang.',
      );
      throw const ApiException(0, 'Penyimpanan sesi aman belum tersedia.');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _renew?.cancel();
    _client.close();
    if (!identical(_client, _displayClient)) _displayClient.close();
    super.dispose();
  }
}
