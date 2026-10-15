import 'package:timezone/timezone.dart' as tz;

class AppConfig {
  AppConfig({
    required String apiBaseUrl,
    this.serviceTimeZone = 'Asia/Jakarta',
    this.realtime = true,
  }) : apiBase = Uri.parse(apiBaseUrl.replaceAll(RegExp(r'/+$'), '')) {
    if (!['http', 'https'].contains(apiBase.scheme) ||
        apiBase.host.isEmpty ||
        apiBase.hasQuery ||
        apiBase.hasFragment ||
        apiBase.userInfo.isNotEmpty) {
      throw ArgumentError(
        'API_BASE_URL harus URL HTTP(S) tanpa kredensial/query.',
      );
    }
    location = tz.getLocation(serviceTimeZone);
  }
  factory AppConfig.fromEnvironment() => AppConfig(
    apiBaseUrl: const String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://localhost:3000/api/v1',
    ),
    serviceTimeZone: const String.fromEnvironment(
      'SERVICE_TIME_ZONE',
      defaultValue: 'Asia/Jakarta',
    ),
  );
  final Uri apiBase;
  final String serviceTimeZone;
  final bool realtime;
  late final tz.Location location;
  String get socketOrigin => apiBase.origin;
  tz.TZDateTime get now => tz.TZDateTime.now(location);
  String get today => calendarDate(now);
  String instantLabel(Object? value) {
    final parsed = DateTime.tryParse('$value');
    if (parsed == null) return '—';
    final local = tz.TZDateTime.from(parsed, location);
    return '${calendarDate(local)} ${two(local.hour)}:${two(local.minute)}';
  }

  String localInput(Object? value) =>
      instantLabel(value).replaceFirst(' ', 'T');
  String toInstant(String input) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$').hasMatch(input)) {
      throw const FormatException(
        'Gunakan YYYY-MM-DDTHH:mm pada zona pelayanan.',
      );
    }
    final date = DateTime.parse(input);
    final zoned = tz.TZDateTime(
      location,
      date.year,
      date.month,
      date.day,
      date.hour,
      date.minute,
    );
    if (localInput(zoned.toUtc().toIso8601String()) != input) {
      throw const FormatException(
        'Waktu lokal tidak valid pada zona pelayanan.',
      );
    }
    return zoned.toUtc().toIso8601String();
  }
}

String two(int value) => value.toString().padLeft(2, '0');
String calendarDate(DateTime value) =>
    '${value.year}-${two(value.month)}-${two(value.day)}';
String dateOnly(Object? value) =>
    value == null ? '' : '$value'.split('T').first;
String clockOnly(Object? value) {
  final text = '$value';
  return text.contains('T')
      ? text.substring(11, 16)
      : text.length >= 5
      ? text.substring(0, 5)
      : '';
}

typedef Json = Map<String, dynamic>;
Json object(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : {};
List<Json> rows(Object? value) =>
    value is List ? value.map(object).toList() : [];
String label(Json value) =>
    '${value['nama'] ?? value['nomorAntrean'] ?? value['kode'] ?? value['id'] ?? '—'}';
bool assignmentValid(Json assignment, String today) {
  final room = object(assignment['loket']);
  final service = object(room['layanan']);
  return assignment['aktif'] == true &&
      room['aktif'] == true &&
      service['aktif'] == true &&
      dateOnly(assignment['tanggalMulai']).compareTo(today) <= 0 &&
      (assignment['tanggalSelesai'] == null ||
          dateOnly(assignment['tanggalSelesai']).compareTo(today) >= 0);
}
