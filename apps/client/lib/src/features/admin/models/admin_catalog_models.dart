import '../../../config.dart';

Object? _freeze(Object? value) {
  if (value is Map) {
    return Map<String, dynamic>.unmodifiable(
      value.map((key, item) => MapEntry(key as String, _freeze(item))),
    );
  }
  if (value is List) return List<dynamic>.unmodifiable(value.map(_freeze));
  return value;
}

/// One immutable catalog shared by migrated and legacy ADMIN consumers.
class AdminCatalogSnapshot {
  AdminCatalogSnapshot(Map<String, List<Json>> source)
    : collections = Map.unmodifiable(
        source.map(
          (path, items) => MapEntry(
            path,
            List<Json>.unmodifiable(items.map((row) => _freeze(row) as Json)),
          ),
        ),
      );
  final Map<String, List<Json>> collections;
  List<Json> rowsFor(String path) => collections[path] ?? const [];
}
