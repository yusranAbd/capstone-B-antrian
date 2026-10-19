import 'display_client_native.dart';

Future<Map<String, String>> displaySocketHeaders(Uri apiBase) =>
    nativeDisplayHeaders(apiBase);
