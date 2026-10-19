import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// Cookie transport for native clients. Android persists in its encrypted store;
/// other native platforms retain credentials only for the process lifetime.
final _cookies = <String, String>{};
Future<Map<String, String>> nativeDisplayHeaders(Uri apiBase) async {
  final key = 'queueb.display.cookie.$apiBase';
  final cookie =
      _cookies[key] ??
      (defaultTargetPlatform == TargetPlatform.android
          ? await const FlutterSecureStorage().read(key: key)
          : null);
  return cookie == null ? {} : {'Cookie': cookie};
}

http.Client createDisplayClient(Uri apiBase) => _DisplayClient(apiBase);

class _DisplayClient extends http.BaseClient {
  _DisplayClient(this.apiBase);
  final Uri apiBase;
  final _inner = http.Client();
  final _storage = const FlutterSecureStorage();
  String? _cookie;
  bool _loaded = false;
  String get _key => 'queueb.display.cookie.$apiBase';
  bool get _persist =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.origin != apiBase.origin ||
        !request.url.path.startsWith('${apiBase.path}/display/')) {
      throw http.ClientException(
        'Transport perangkat hanya untuk endpoint display.',
      );
    }
    request.followRedirects = false;
    if (!_loaded) {
      _cookie = _cookies[_key];
      if (_persist) _cookie = await _storage.read(key: _key);
      _loaded = true;
    }
    if (_cookie != null) request.headers['Cookie'] = _cookie!;
    final response = await _inner.send(request);
    final setCookie = response.headers['set-cookie'];
    if (setCookie != null && setCookie.startsWith('queueb_display=')) {
      final value = setCookie.split(';').first;
      _cookie = RegExp(r'^queueb_display=[a-f0-9]{64}$').hasMatch(value)
          ? value
          : null;
      if (_cookie == null) {
        _cookies.remove(_key);
      } else {
        _cookies[_key] = _cookie!;
      }
      if (_persist) {
        if (_cookie == null) {
          await _storage.delete(key: _key);
        } else {
          await _storage.write(key: _key, value: _cookie);
        }
      }
    }
    return response;
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}
