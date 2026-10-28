import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

abstract interface class DisplaySpeechEngine {
  void errors(void Function(dynamic)? callback);
  Future<dynamic> stop();
  Future<dynamic> available(String language);
  Future<dynamic> language(String language);
  Future<dynamic> speak(String text);
}

class FlutterDisplaySpeech implements DisplaySpeechEngine {
  final _tts = FlutterTts();
  @override
  void errors(void Function(dynamic)? callback) => _tts.errorHandler = callback;
  @override
  Future<dynamic> stop() => _tts.stop();
  @override
  Future<dynamic> available(String language) =>
      _tts.isLanguageAvailable(language);
  @override
  Future<dynamic> language(String language) => _tts.setLanguage(language);
  @override
  Future<dynamic> speak(String text) => _tts.speak(text);
}

/// Per monitor, no backlog. A user gesture must successfully activate speech.
class DisplayAudioController extends ChangeNotifier {
  DisplayAudioController({DisplaySpeechEngine? engine})
    : engine = engine ?? FlutterDisplaySpeech() {
    this.engine.errors((message) {
      if (!['canceled', 'interrupted'].contains('$message')) _failed();
    });
  }
  final DisplaySpeechEngine engine;
  bool enabled = false, busy = false, _active = false, _disposed = false;
  String? error;
  int _epoch = 0, _toggleEpoch = 0;
  bool _suspended = false;
  Future<bool>? _speechPending;
  Future<void> get settled async {
    await _speechPending;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void context(bool active) {
    _toggleEpoch++;
    _active = active;
    enabled = false;
    busy = false;
    error = null;
    rebase();
    _notify();
  }

  void suspend() {
    _suspended = true;
    _toggleEpoch++;
    busy = false;
    rebase();
    _notify();
  }

  void resume() {
    _suspended = false;
    rebase();
  }

  void rebase() {
    _epoch++;
    unawaited(_stop());
  }

  Future<void> _stop() async {
    try {
      await engine.stop();
    } catch (_) {
      /* Visual fallback remains available. */
    }
  }

  void _failed() {
    if (_disposed || !_active) return;
    _epoch++;
    enabled = false;
    busy = false;
    error = 'Suara tidak tersedia. Gunakan pengumuman visual.';
    unawaited(_stop());
    _notify();
  }

  Future<bool> _speak(String text) async {
    final epoch = ++_epoch;
    bool current() => !_disposed && _active && !_suspended && epoch == _epoch;
    try {
      await _stop();
      if (!current()) return false;
      final available = await engine.available('id-ID');
      if (!current()) return false;
      if (available != true && available != 1) {
        throw StateError('Voice unavailable');
      }
      final language = await engine.language('id-ID');
      if (!current()) return false;
      if (language == 0 || language == false) {
        throw StateError('Language rejected');
      }
      final result = await engine.speak(text);
      if (!current()) return false;
      if (result == 0 || result == false) throw StateError('Speech rejected');
      return true;
    } catch (_) {
      if (current()) _failed();
      return false;
    }
  }

  Future<void> announce(String text) async {
    if (_disposed || !_active || _suspended || !enabled || text.isEmpty) return;
    await (_speechPending = _speak(text));
  }

  Future<void> toggle() async {
    if (_disposed || !_active || _suspended || busy) return;
    final operation = ++_toggleEpoch;
    busy = true;
    _notify();
    final epoch = _epoch;
    try {
      if (enabled) {
        enabled = false;
        _epoch++;
        await _stop();
      } else if (await (_speechPending = _speak(
        'Suara pengumuman QueueB aktif.',
      ))) {
        if (!_disposed && _active && _epoch == epoch + 1) {
          enabled = true;
          error = null;
        }
      }
    } finally {
      if (!_disposed && operation == _toggleEpoch) {
        busy = false;
        _notify();
      }
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _active = false;
    enabled = false;
    _epoch++;
    engine.errors(null);
    unawaited(_stop());
    super.dispose();
  }
}
