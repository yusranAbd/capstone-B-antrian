/// Recursively immutable metadata. Credentials and one-time QR stay outside it.
Object? safeSnapshot(Object? value) {
  if (value is Map) {
    return Map<String, dynamic>.unmodifiable({
      for (final entry in value.entries)
        if (!_secret('${entry.key}')) '${entry.key}': safeSnapshot(entry.value),
    });
  }
  if (value is List) {
    return List<dynamic>.unmodifiable(value.map(safeSnapshot));
  }
  return value;
}

bool _secret(String key) {
  final name = key.toLowerCase().replaceAll('_', '');
  return name.contains('password') ||
      name.contains('katasandi') ||
      name.contains('token') ||
      name.contains('qrhash') ||
      name == 'qrpayload' ||
      name == 'cookie' ||
      name == 'authorization';
}
