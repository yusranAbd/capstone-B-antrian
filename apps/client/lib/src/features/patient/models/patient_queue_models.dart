import '../../../api.dart';

bool validPatientQueueDate(String value) {
  if (!RegExp(r'^(?!0000)\d{4}-\d{2}-\d{2}$').hasMatch(value)) return false;
  return DateTime.tryParse('${value}T00:00:00Z')
          ?.toIso8601String()
          .substring(0, 10) ==
      value;
}

class PatientServingNumber {
  const PatientServingNumber(this.roomId, this.roomCode, this.number);
  final String roomId, roomCode, number;
}

class PatientQueueSummary {
  PatientQueueSummary(
    this.serviceId,
    this.date,
    this.obtainedAt,
    this.checkedInTotal,
    this.waitingCount,
    List<PatientServingNumber> serving,
  ) : serving = List.unmodifiable(serving);
  final String serviceId, date;
  final DateTime obtainedAt;
  final int? checkedInTotal, waitingCount;
  final List<PatientServingNumber> serving;

  static Map<String, PatientQueueSummary> parseBatch(
    Object? raw,
    Set<String> ids,
    String date,
  ) {
    Never invalid() =>
        throw const ApiException(0, 'Informasi antrean belum terverifikasi.');
    if (raw is! Map ||
        raw['versiSkema'] != 1 ||
        raw['tanggalPelayanan'] != date ||
        !validPatientQueueDate(date)) {
      invalid();
    }
    final timestamp = raw['diperolehPada'];
    final obtained = timestamp is String && timestamp.contains('T')
        ? DateTime.tryParse(timestamp)
        : null;
    final rows = raw['layanan'];
    if (obtained == null ||
        !obtained.isUtc ||
        rows is! List ||
        rows.length != ids.length) {
      invalid();
    }
    final result = <String, PatientQueueSummary>{};
    int? count(Object? value) {
      if (value == null) return null;
      if (value is! int || value < 0) invalid();
      return value;
    }

    String text(Object? value) {
      if (value is! String || value.trim().isEmpty) invalid();
      return value;
    }

    for (final row in rows) {
      if (row is! Map) invalid();
      if (!row.containsKey('totalCheckIn') ||
          !row.containsKey('jumlahMenunggu') ||
          !row.containsKey('sedangDilayani')) {
        invalid();
      }
      final id = text(row['layananId']);
      if (!ids.contains(id) || result.containsKey(id)) invalid();
      final total = count(row['totalCheckIn']),
          waiting = count(row['jumlahMenunggu']);
      final active = row['sedangDilayani'];
      if (active is! List ||
          (total != null && waiting != null && waiting > total)) {
        invalid();
      }
      final serving = <PatientServingNumber>[];
      final seen = <(String, String)>{};
      for (final item in active) {
        if (item is! Map) invalid();
        final room = text(item['loketId']), number = text(item['nomorAntrean']);
        if (!seen.add((room, number))) invalid();
        serving.add(
          PatientServingNumber(room, text(item['kodeLoket']), number),
        );
      }
      if (total != null && serving.length > total) invalid();
      // Explicit projection: extra fields, including PII, are never retained.
      result[id] = PatientQueueSummary(
        id,
        date,
        obtained,
        total,
        waiting,
        serving,
      );
    }
    return Map.unmodifiable(result);
  }
}

class PatientQueueView {
  const PatientQueueView({
    this.summary,
    this.loading = false,
    this.error = false,
    this.live = false,
  });
  final PatientQueueSummary? summary;
  final bool loading, error, live;
  String get freshness => summary == null
      ? loading
            ? 'Memuat antrean…'
            : error
            ? 'Tidak dapat dimuat'
            : 'Belum tersedia'
      : live
      ? 'Live'
      : 'Data terakhir';
}

class PatientQueueState {
  PatientQueueState({
    this.date = '',
    Map<String, PatientQueueSummary> summaries = const {},
    Set<String> loading = const {},
    Set<String> errors = const {},
    this.connected = false,
  }) : summaries = Map.unmodifiable(summaries),
       loading = Set.unmodifiable(loading),
       errors = Set.unmodifiable(errors);
  final String date;
  final Map<String, PatientQueueSummary> summaries;
  final Set<String> loading, errors;
  final bool connected;
  PatientQueueView forService(String id, String today, {DateTime? now}) {
    if (date != today) return const PatientQueueView();
    final age = summaries[id] == null
        ? null
        : (now ?? DateTime.now()).difference(summaries[id]!.obtainedAt);
    return PatientQueueView(
      summary: summaries[id],
      loading: loading.contains(id),
      error: errors.contains(id),
      live:
          connected &&
          summaries.containsKey(id) &&
          age != null &&
          age >= const Duration(seconds: -30) &&
          age <= const Duration(minutes: 3) &&
          !loading.contains(id) &&
          !errors.contains(id),
    );
  }
}
