import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'config.dart';

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
    this.requestTimeout = const Duration(seconds: 20),
  }) : _client = client ?? http.Client();
  final AppConfig config;
  final http.Client _client;
  final Duration requestTimeout;
  Json? user;
  String? accessToken;
  String? _refreshToken;
  Future<void>? _refreshing;
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
      if (retry.statusCode == 401) clearSession();
      return _decode(retry);
    }
    if (response.statusCode == 401 && authenticated) clearSession();
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
        final response = await _client.send(request);
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
    _generation++;
    _accept(data, publish: false);
    try {
      user = object(await request('GET', '/auth/me'));
      if (!['ADMIN', 'PETUGAS', 'USER'].contains(user?['peran'])) {
        throw const ApiException(403, 'Peran akun tidak didukung.');
      }
      notifyListeners();
    } catch (_) {
      clearSession();
      rethrow;
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

  void _accept(Json data, {bool publish = true}) {
    accessToken = data['accessToken'] as String;
    _refreshToken = data['refreshToken'] as String;
    if (publish) user = object(data['user']);
    _renew?.cancel();
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
    if (publish) notifyListeners();
  }

  Future<void> refresh() =>
      _refreshing ??= _rotate().whenComplete(() => _refreshing = null);
  Future<void> _rotate() async {
    final token = _refreshToken;
    final generation = _generation;
    if (token == null) throw const ApiException(401, 'Silakan masuk kembali.');
    try {
      final data = object(
        await request(
          'POST',
          '/auth/refresh',
          authenticated: false,
          body: {'refreshToken': token},
        ),
      );
      if (generation == _generation) _accept(data);
    } catch (_) {
      // Rotated token may be lost after timeout; do not reuse it blindly.
      if (generation == _generation) clearSession();
      rethrow;
    }
  }

  Future<void> logout() async {
    final token = _refreshToken;
    clearSession();
    if (token != null) {
      await request(
        'POST',
        '/auth/logout',
        authenticated: false,
        body: {'refreshToken': token},
      );
    }
  }

  void clearSession() {
    _generation++;
    _renew?.cancel();
    user = null;
    accessToken = null;
    _refreshToken = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _renew?.cancel();
    _client.close();
    super.dispose();
  }
}
