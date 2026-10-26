import 'dart:js_interop';

import 'display_selection_types.dart';

@JS('sessionStorage')
external _Storage get _storage;

extension type _Storage(JSObject _) implements JSObject {
  external String? getItem(String key);
  external void setItem(String key, String value);
  external void removeItem(String key);
}

DisplaySelection createDisplaySelection(Uri apiBase) =>
    _TabSelection('queueb.display.device.v1.$apiBase');

class _TabSelection implements DisplaySelection {
  _TabSelection(this.key);
  final String key;
  @override
  bool get isolated => true;
  @override
  Future<String?> read() async {
    final value = _storage.getItem(key);
    return value != null &&
            RegExp(r'^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$')
                .hasMatch(value)
        ? value
        : null;
  }

  @override
  Future<void> write(String id) async {
    _storage.setItem(key, id);
    if (_storage.getItem(key) != id) {
      throw StateError('Identitas tab tidak dapat disimpan.');
    }
  }

  @override
  Future<void> clear() async => _storage.removeItem(key);
}
