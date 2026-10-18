import 'dart:js_interop';

import 'package:flutter/foundation.dart';

@JS('document')
external _Document get _document;

extension type _Document(JSObject _) implements JSObject {
  external bool? get fullscreenEnabled;
  external JSObject? get fullscreenElement;
  external _Element get documentElement;
  external JSPromise<JSAny?> exitFullscreen();
  external void addEventListener(String type, JSFunction callback);
  external void removeEventListener(String type, JSFunction callback);
}

extension type _Element(JSObject _) implements JSObject {
  external JSPromise<JSAny?> requestFullscreen();
}

class DisplayFullscreen extends ChangeNotifier {
  DisplayFullscreen() {
    _listener = (() => notifyListeners()).toJS;
    _document.addEventListener('fullscreenchange', _listener);
  }
  late final JSFunction _listener;
  bool _owned = false;
  bool _disposed = false;
  bool get supported => _document.fullscreenEnabled == true;
  bool get active => _document.fullscreenElement != null;
  Future<void> toggle() async {
    if (!supported || _disposed) return;
    if (active) {
      await _document.exitFullscreen().toDart;
      _owned = false;
    } else {
      await _document.documentElement.requestFullscreen().toDart;
      _owned = true;
      if (_disposed && active) {
        await _document.exitFullscreen().toDart;
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _document.removeEventListener('fullscreenchange', _listener);
    if (_owned && active) {
      _document.exitFullscreen().toDart.catchError((_) => null);
    }
    super.dispose();
  }
}
