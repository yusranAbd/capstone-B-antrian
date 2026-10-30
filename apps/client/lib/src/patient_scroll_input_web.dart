import 'dart:js_interop';

@JS('document')
external _Document get _document;

extension type _Document(JSObject _) implements JSObject {
  external void addEventListener(
    String type,
    JSFunction callback,
    bool capture,
  );
  external void removeEventListener(
    String type,
    JSFunction callback,
    bool capture,
  );
}

extension type _InputEvent(JSObject _) implements JSObject {
  external bool get isTrusted;
  external double? get deltaX;
  external double? get deltaY;
  external _Touches? get touches;
  external String? get key;
  external _Target? get target;
}

extension type _Touches(JSObject _) implements JSObject {
  external int get length;
  external _Touch item(int index);
}

extension type _Touch(JSObject _) implements JSObject {
  external double get clientX;
  external double get clientY;
}

extension type _Target(JSObject _) implements JSObject {
  external JSObject? closest(String selector);
}

/// Observe trusted input only. Native Web semantics scrolling becomes jumpTo;
/// scroll events alone cannot distinguish that from a programmatic jump.
/// No event is prevented, no DOM state is changed, and all listeners are removed.
void Function() observePatientScrollInput(void Function(double) onDirection) {
  double? x, y;
  final wheel = ((_InputEvent event) {
    if (!event.isTrusted) return;
    final dx = event.deltaX ?? 0, dy = event.deltaY ?? 0;
    if (dy.abs() > dx.abs() && dy != 0) onDirection(dy.sign);
  }).toJS;
  final start = ((_InputEvent event) {
    if (!event.isTrusted || event.touches?.length != 1) return;
    x = event.touches!.item(0).clientX;
    y = event.touches!.item(0).clientY;
  }).toJS;
  final move = ((_InputEvent event) {
    if (!event.isTrusted ||
        x == null ||
        y == null ||
        event.touches?.length != 1) {
      return;
    }
    final touch = event.touches!.item(0);
    final dx = x! - touch.clientX, dy = y! - touch.clientY;
    x = touch.clientX;
    y = touch.clientY;
    if (dy.abs() > dx.abs() && dy.abs() > 2) onDirection(dy.sign);
  }).toJS;
  final end = ((_InputEvent _) {
    x = y = null;
  }).toJS;
  final key = ((_InputEvent event) {
    if (!event.isTrusted ||
        event.target?.closest(
              'input,textarea,button,[contenteditable="true"],[role="button"],[role="tab"]',
            ) !=
            null) {
      return;
    }
    switch (event.key) {
      case 'ArrowDown' || 'PageDown' || 'End' || ' ':
        onDirection(1);
      case 'ArrowUp' || 'PageUp' || 'Home':
        onDirection(-1);
    }
  }).toJS;
  final handlers = {
    'wheel': wheel,
    'touchstart': start,
    'touchmove': move,
    'touchend': end,
    'touchcancel': end,
    'keydown': key,
  };
  for (final entry in handlers.entries) {
    _document.addEventListener(entry.key, entry.value, true);
  }
  return () {
    for (final entry in handlers.entries) {
      _document.removeEventListener(entry.key, entry.value, true);
    }
  };
}
