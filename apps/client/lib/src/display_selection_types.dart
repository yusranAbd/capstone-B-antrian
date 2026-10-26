/// Stores only public metadata. The credential remains in an HttpOnly cookie.
abstract interface class DisplaySelection {
  bool get isolated;
  Future<String?> read();
  Future<void> write(String id);
  Future<void> clear();
}

class MemoryDisplaySelection implements DisplaySelection {
  MemoryDisplaySelection({this.value, this.isolated = true});
  String? value;
  @override
  final bool isolated;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String id) async => value = id;
  @override
  Future<void> clear() async => value = null;
}
