import '../../../api.dart';
import '../../../config.dart';
import '../../shared/safe_snapshot.dart';

class DisplayScope {
  const DisplayScope(
    this.deviceId,
    this.serviceId,
    this.epoch,
    this.apiBase, {
    this.paired = true,
    this.selector,
  });
  final String? selector;
  final String? deviceId;
  final String serviceId, apiBase;
  final int epoch;
  final bool paired;
}

enum DisplayDevicePhase {
  unpaired,
  restoring,
  pairing,
  ready,
  disconnecting,
  rejected,
  failed,
  uncertain,
}

class DisplayDeviceState {
  DisplayDeviceState({
    this.phase = DisplayDevicePhase.unpaired,
    Json? device,
    this.scope,
    this.error,
    this.errorStatus,
  }) : device = device == null ? null : safeSnapshot(device) as Json;
  final DisplayDevicePhase phase;
  final Json? device;
  final DisplayScope? scope;
  final String? error;
  final int? errorStatus;
  bool get busy => [
    DisplayDevicePhase.restoring,
    DisplayDevicePhase.pairing,
    DisplayDevicePhase.disconnecting,
  ].contains(phase);
  bool get connected =>
      scope != null &&
      [
        DisplayDevicePhase.ready,
        DisplayDevicePhase.disconnecting,
        DisplayDevicePhase.rejected,
      ].contains(phase);
}

class DisplayMonitorState {
  DisplayMonitorState({
    DisplayScope? scope,
    Json? snapshot,
    bool loading = false,
    bool refreshing = false,
    bool rejected = false,
    String? error,
    int? errorStatus,
    String status = 'Menghubungkan…',
  }) : this._(
         scope: scope,
         snapshot: snapshot == null ? null : safeSnapshot(snapshot) as Json,
         loading: loading,
         refreshing: refreshing,
         rejected: rejected,
         error: error,
         errorStatus: errorStatus,
         status: status,
       );
  DisplayMonitorState._({
    this.scope,
    this.snapshot,
    required this.loading,
    required this.refreshing,
    required this.rejected,
    this.error,
    this.errorStatus,
    required this.status,
  });
  final DisplayScope? scope;
  final Json? snapshot;
  final bool loading, refreshing, rejected;
  final String? error;
  final int? errorStatus;
  final String status;
  DisplayMonitorState copy({
    Json? snapshot,
    bool? loading,
    bool? refreshing,
    bool? rejected,
    String? error,
    int? errorStatus,
    bool clearError = false,
    String? status,
  }) => DisplayMonitorState._(
    scope: scope,
    snapshot: snapshot == null ? this.snapshot : safeSnapshot(snapshot) as Json,
    loading: loading ?? this.loading,
    refreshing: refreshing ?? this.refreshing,
    rejected: rejected ?? this.rejected,
    error: clearError ? null : error ?? this.error,
    errorStatus: clearError ? null : errorStatus ?? this.errorStatus,
    status: status ?? this.status,
  );
}

class DisplayStale implements Exception {}

class DisplayDisconnectPartial implements Exception {}

ApiException displayError(Object error) {
  final code = error is ApiException ? error.status : 0;
  return ApiException(code, switch (code) {
    400 => 'Kode aktivasi atau konfigurasi perangkat tidak valid.',
    401 => 'Sesi perangkat berakhir, dinonaktifkan atau akses dicabut. Minta kode baru dari ADMIN.',
    403 =>
      'Akses perangkat atau poliklinik ditolak. Minta kode baru dari ADMIN.',
    409 => 'Konfigurasi perangkat berubah. Periksa sesi atau minta kode baru dari ADMIN.',
    410 => 'Kode aktivasi sudah digunakan atau kedaluwarsa. Minta kode baru dari ADMIN.',
    429 => 'Terlalu banyak percobaan. Tunggu sebelum mencoba kembali.',
    _ => 'Sesi perangkat belum dapat diperiksa. Periksa koneksi atau penyimpanan tab lalu coba lagi.',
  });
}

Json _pick(Json value, Set<String> fields) => {
  for (final field in fields)
    if (value.containsKey(field)) field: value[field],
};
Json displayDevice(dynamic value) {
  if (value is! Map ||
      value['id'] is! String ||
      '${value['id']}'.isEmpty ||
      value['layananId'] is! String ||
      '${value['layananId']}'.isEmpty) {
    throw const ApiException(0, 'Identitas perangkat belum terverifikasi.');
  }
  if (value['aktif'] == false) {
    throw const ApiException(403, 'Perangkat dinonaktifkan.');
  }
  final data = _pick(object(value), {
    'id',
    'nama',
    'layananId',
    'aktif',
    'terakhirAktifPada',
    'dibuatPada',
    'diperbaruiPada',
  });
  if (value['layanan'] is Map) {
    data['layanan'] = _pick(object(value['layanan']), {
      'id',
      'kode',
      'nama',
      'aktif',
    });
  }
  return safeSnapshot(data) as Json;
}

/// Only the server's public projection. Never enrich names from account APIs.
Json displaySnapshot(dynamic value, DisplayScope scope) {
  if (value is! Map ||
      value['versiSkema'] != 1 ||
      value['loket'] is! List ||
      (object(value['layanan'])['id'] != null &&
          object(value['layanan'])['id'] != scope.serviceId)) {
    throw const ApiException(0, 'Snapshot tidak sesuai scope.');
  }
  List<Json> list(dynamic input, Set<String> fields) {
    if (input is! List || input.any((v) => v is! Map)) {
      throw const ApiException(0, 'Snapshot belum lengkap.');
    }
    return input.map((v) => _pick(object(v), fields)).toList();
  }

  const patients = {'nomorAntrean', 'namaPasien', 'status'};
  final data = _pick(object(value), {
    'versiSkema',
    'tanggalPelayanan',
    'diperolehPada',
    'modeNama',
    'totalMenunggu',
    'totalDilewati',
    'totalAntrianPasien',
  });
  data['layanan'] = _pick(object(value['layanan']), {'id', 'kode', 'nama'});
  data['loket'] = [
    for (final room in value['loket'])
      {
        ..._pick(object(room), {'id', 'kode', 'nama'}),
        'tiketAktif': list(object(room)['tiketAktif'] ?? [], {
          ...patients,
          'dipanggilPada',
          'pelayananDimulaiPada',
          'urutanMasukAntrean',
          'versi',
        }),
      },
  ];
  for (final key in ['menunggu', 'antrianPasien']) {
    if (value.containsKey(key)) data[key] = list(value[key], patients);
  }
  if (value['pengumumanTerakhir'] != null) {
    data['pengumumanTerakhir'] = _pick(object(value['pengumumanTerakhir']), {
      'peristiwaId',
      'aksi',
      'nomorAntrean',
      'kodeLoket',
      'namaLoket',
      'namaPasien',
      'teks',
      'bahasa',
      'dipanggilPada',
    });
  }
  return safeSnapshot(data) as Json;
}
