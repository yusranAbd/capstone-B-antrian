import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:queueb_client/src/api.dart';
import 'package:queueb_client/src/config.dart';
import 'package:queueb_client/src/features/patient/data/patient_repository.dart';
import 'package:queueb_client/src/patient_sync.dart';

class PatientFixture {
  PatientFixture({bool realtime = false, PatientSocketFactory? socketFactory}) {
    api = QueueApi(
      config: AppConfig(
        apiBaseUrl: 'http://localhost/api/v1',
        realtime: realtime,
      ),
      client: MockClient(handle),
    )..user = identity;
    if (realtime) api.accessToken = 'fixture-access';
    repository = PatientRepository(
      api,
      updates: PatientUpdates(
        api: api,
        debounce: Duration.zero,
        socketFactory: socketFactory,
      ),
    );
    data['/layanan'] = [clinic()];
    data['/dokter'] = [
      {
        'id': 'doctor',
        'nama': 'Dokter Awal',
        'aktif': true,
        'dokterLayanan': [
          {
            'id': 'link',
            'layananId': 'clinic',
            'aktif': true,
            'layanan': clinic(),
          },
        ],
      },
    ];
    data['/jadwal-praktik'] = [session()];
    slots['session'] = [slot()];
  }
  late final QueueApi api;
  late final PatientRepository repository;
  Json identity = {
    'id': 'patient-a',
    'peran': 'USER',
    'nama': 'Pasien A',
    'email': 'a@example.test',
  };
  final data = <String, List<Json>>{
    '/layanan': [],
    '/dokter': [],
    '/jadwal-praktik': [],
    '/jadwal-layanan': [],
    '/tiket/saya': [],
    '/janji-temu': [],
  };
  final calls = <http.Request>[];
  final reads = <String, int>{};
  final gates = <(String, int), Completer<void>>{},
      waiters = <(String, int), Completer<void>>{};
  final slots = <String, List<Json>>{};
  Completer<void>? mutationGate, mutationStarted;
  bool commitUnknown = false;
  int writes = 0;
  String qrPayload = 'SQ1.fixture';
  String? qrTicketId;
  Duration qrLifetime = const Duration(minutes: 10);
  void Function(String)? afterMutation;
  final failures = <String, int>{};
  final postFailures = <String, int>{};
  bool malformed = false;
  Json clinic([String mode = 'HIBRIDA']) => {
    'id': 'clinic',
    'nama': 'Poli Awal',
    'kode': 'PD',
    'aktif': true,
    'modeReservasi': mode,
  };
  Json session([String id = 'session']) => {
    'id': id,
    'tanggal': api.config.today,
    'aktif': true,
    'mulaiPada': DateTime.now()
        .add(const Duration(days: 1))
        .toUtc()
        .toIso8601String(),
    'selesaiPada': DateTime.now()
        .add(const Duration(days: 1, hours: 2))
        .toUtc()
        .toIso8601String(),
    'dokterLayanan': {
      'id': 'link',
      'aktif': true,
      'dokterId': 'doctor',
      'layananId': 'clinic',
      'dokter': {'id': 'doctor', 'nama': 'Dokter Awal'},
      'layanan': clinic(),
    },
    'loket': {'id': 'room', 'nama': 'Ruang Satu', 'aktif': true},
  };
  Json ticket([String id = 'ticket']) => {
    'id': id,
    'status': 'DIPESAN',
    'nomorAntrean': 'PD-001',
    'tanggalPelayanan': api.config.today,
    'tanggalAntrean': api.config.today,
    'layananId': 'clinic',
    'layanan': clinic(),
  };
  Json slot([String id = 'slot', String sessionId = 'session']) => {
    'id': id,
    'jadwalPraktikId': sessionId,
    'aktif': true,
    'tersedia': true,
    'sisaKapasitas': 2,
    'mulaiPada': DateTime.now()
        .add(const Duration(days: 1))
        .toUtc()
        .toIso8601String(),
    'selesaiPada': DateTime.now()
        .add(const Duration(days: 1, minutes: 30))
        .toUtc()
        .toIso8601String(),
  };
  http.Response reply(Object? value, [int status = 200]) =>
      http.Response(jsonEncode(value), status);
  Future<void> waitRead(String path, int n) => (reads[path] ?? 0) >= n
      ? Future.value()
      : (waiters[(path, n)] ??= Completer<void>()).future;
  Future<http.Response> handle(http.Request request) async {
    calls.add(request);
    final path = request.url.path.replaceFirst('/api/v1', '');
    if (path == '/auth/me') return reply(identity);
    if (request.method == 'POST' &&
        (path.endsWith('/batalkan') || path.endsWith('/qr'))) {
      writes++;
      mutationStarted?.complete();
      mutationStarted = null;
      if (mutationGate case final gate?) await gate.future;
      final failure = postFailures[path];
      if (path.endsWith('/batalkan') && (failure == null || commitUnknown)) {
        final id = path.split('/')[2];
        final appointment = data['/janji-temu']!.firstWhere(
          (a) => a['id'] == id,
        );
        final ticketId = (appointment['tiket'] as Json)['id'];
        data['/tiket/saya'] = data['/tiket/saya']!
            .map(
              (t) => t['id'] == ticketId ? {...t, 'status': 'DIBATALKAN'} : t,
            )
            .toList();
        appointment['tiket'] = {
          ...(appointment['tiket'] as Json),
          'status': 'DIBATALKAN',
        };
      }
      afterMutation?.call(path);
      if (failure == 0) throw http.ClientException('fixture response lost');
      if (failure != null) {
        return reply({'message': 'fixture-secret $qrPayload'}, failure);
      }
      return reply(
        path.endsWith('/qr')
            ? {
                'tiketId': qrTicketId ?? path.split('/')[2],
                'qrPayload': qrPayload,
                'berlakuHingga': DateTime.now()
                    .toUtc()
                    .add(qrLifetime)
                    .toIso8601String(),
              }
            : data['/janji-temu']!.first,
        201,
      );
    }
    if (request.method == 'POST' &&
        ['/reservasi', '/janji-temu'].contains(path)) {
      writes++;
      mutationStarted?.complete();
      mutationStarted = null;
      if (mutationGate case final gate?) await gate.future;
      final body = jsonDecode(request.body) as Json;
      final failure = postFailures[path];
      final created = {
        ...ticket('server-ticket-$writes'),
        if (path == '/reservasi') 'tanggalPelayanan': body['tanggalAntrean'],
      };
      final appointment = {
        'id': 'server-appointment-$writes',
        'tiket': created,
        'slotPraktikId': body['slotPraktikId'],
        'slotPraktik': {...slot(), 'jadwalPraktik': session()},
      };
      if (failure == null || commitUnknown) {
        data['/tiket/saya']!.add(created);
        if (path == '/janji-temu') data['/janji-temu']!.add(appointment);
      }
      if (failure == 0) throw http.ClientException('fixture response lost');
      if (failure != null) return reply({'message': 'fixture-secret'}, failure);
      return reply(path == '/janji-temu' ? appointment : created, 201);
    }
    final n = reads.update(path, (v) => v + 1, ifAbsent: () => 1);
    final response = failures.containsKey(path)
        ? reply({
            'message': 'fixture-secret SQ1.fixture-token',
          }, failures[path]!)
        : reply(
            malformed
                ? {'invalid': true}
                : path == '/slot-praktik'
                ? slots[request.url.queryParameters['jadwalPraktikId']] ?? []
                : path.startsWith('/tiket/') && path != '/tiket/saya'
                ? data['/tiket/saya']!
                          .where((t) => t['id'] == path.split('/')[2])
                          .firstOrNull ??
                      {}
                : data[path] ?? [],
          );
    waiters.remove((path, n))?.complete();
    if (gates[(path, n)] case final gate?) await gate.future;
    return response;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    repository.dispose();
    api.dispose();
  }

  bool _disposed = false;
}
