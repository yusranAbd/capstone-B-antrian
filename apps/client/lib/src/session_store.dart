import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A token pair is one value: rotation must never mix old/new credentials.
class SessionCredentials {
  const SessionCredentials(this.accessToken, this.refreshToken);
  final String accessToken, refreshToken;
  @override
  String toString() => 'SessionCredentials([redacted])';
}

abstract interface class SessionStore {
  Future<SessionCredentials?> read();
  Future<void> write(SessionCredentials credentials);
  Future<void> clear();
}

/// Web and unsupported platforms deliberately do not persist bearer tokens.
class MemorySessionStore implements SessionStore {
  SessionCredentials? value;
  @override
  Future<SessionCredentials?> read() async => value;
  @override
  Future<void> write(SessionCredentials credentials) async =>
      value = credentials;
  @override
  Future<void> clear() async => value = null;
}

class AndroidSessionStore implements SessionStore {
  AndroidSessionStore({required this.apiBase, FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(
              storageNamespace: 'queueb_session',
              resetOnError: false,
            ),
          );
  final String apiBase;
  final FlutterSecureStorage _storage;
  // Isolate API environments; switching API_BASE_URL must not forward old tokens.
  String get _key => 'session.v1.${base64Url.encode(utf8.encode(apiBase))}';
  @override
  Future<SessionCredentials?> read() async {
    final encoded = await _storage.read(key: _key);
    if (encoded == null) return null;
    try {
      final value = jsonDecode(encoded);
      if (value is Map && value['loggedOut'] == true) return null;
      if (value is! Map ||
          value['version'] != 1 ||
          value['apiBase'] != apiBase ||
          value['accessToken'] is! String ||
          value['refreshToken'] is! String ||
          (value['accessToken'] as String).isEmpty ||
          (value['refreshToken'] as String).isEmpty) {
        throw const FormatException('Invalid session envelope');
      }
      return SessionCredentials(
        value['accessToken'] as String,
        value['refreshToken'] as String,
      );
    } on FormatException {
      await clear(); // Corrupt credentials cannot authorize a user.
      return null;
    }
  }

  @override
  Future<void> write(SessionCredentials credentials) => _storage.write(
    key: _key,
    value: jsonEncode({
      'version': 1,
      'apiBase': apiBase,
      'accessToken': credentials.accessToken,
      'refreshToken': credentials.refreshToken,
    }),
  );
  @override
  Future<void> clear() async {
    // A credential-free tombstone prevents resurrection if deletion alone fails.
    try {
      await _storage.write(key: _key, value: '{"loggedOut":true}');
    } catch (_) {
      await _storage.delete(
        key: _key,
      ); // Successful deletion is also sufficient.
      return;
    }
    try {
      await _storage.delete(key: _key);
    } catch (_) {
      // Tombstone is durable and contains no credentials.
    }
  }
}

SessionStore platformSessionStore(String apiBase) =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android
    ? AndroidSessionStore(apiBase: apiBase)
    : MemorySessionStore();
