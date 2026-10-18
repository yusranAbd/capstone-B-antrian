import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class DisplayFullscreen extends ChangeNotifier {
  bool _active = false;
  bool _disposed = false;
  bool get supported => defaultTargetPlatform == TargetPlatform.android;
  bool get active => _active;
  Future<void> toggle() async {
    if (!supported || _disposed) return;
    await SystemChrome.setEnabledSystemUIMode(
      _active ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky,
    );
    if (_disposed) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      return;
    }
    _active = !_active;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    if (_active) SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }
}
