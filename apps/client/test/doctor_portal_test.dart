import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:timezone/data/latest.dart' as tz;
import 'package:queueb_client/src/api.dart';
import 'package:queueb_client/src/app.dart';
import 'package:queueb_client/src/config.dart';
import 'package:queueb_client/src/doctor.dart';
import 'package:queueb_client/src/doctor_account.dart';
import 'package:queueb_client/src/patient_sync.dart';
import 'package:queueb_client/src/session_store.dart';

class DoctorSocket extends Fake implements io.Socket {
  final handlers = <String, Function>{};
  bool disposed = false;
  @override
  dynamic noSuchMethod(Invocation i) {
    if (i.memberName == #on) {
      handlers[i.positionalArguments[0] as String] =
          i.positionalArguments[1] as Function;
      return () {};
    }
    return super.noSuchMethod(i);
  }

  @override
  io.Socket connect() => this;
  @override
  void dispose() {
    disposed = true;
    handlers.clear();
  }

  void fire(String event, Object data) => handlers[event]?.call(data);
}

void main() {
  setUpAll(tz.initializeTimeZones);
  Json identity() => {
    'id': 'doctor-account',
    'nama': 'Dokter Satu',
    'email': 'satu@test.local',
    'peran': 'DOKTER',
  };
  http.Response reply(Object data, [int status = 200]) => http.Response(
    jsonEncode(data),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
  Json profile() => {
    'id': 'own',
    'kode': 'DR-01',
    'nama': 'Dokter Satu',
    'spesialisasi': 'Mata',
    'aktif': true,
    'poliklinik': [
      {'nama': 'Poli Mata'},
    ],
  };
  Json session(AppConfig c) => {
    'id': 'own-session',
    'tanggal': c.today,
    'mulaiPada': '${c.today}T00:00:00+07:00',
    'selesaiPada': '${c.today}T23:59:59+07:00',
    'aktif': true,
    'ruang': {'nama': 'Ruang Mata'},
    'poliklinik': {'nama': 'Poli Mata'},
  };
  for (final width in [320.0, 375.0, 768.0, 1280.0]) {
    testWidgets('DOKTER route renders read-only own data at width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final config = AppConfig(
        apiBaseUrl: 'http://localhost:3000/api/v1',
        realtime: false,
      );
      final requests = <String>[];
      final api =
          QueueApi(
              config: config,
              client: MockClient((r) async {
                requests.add(r.method);
                expect(r.url.queryParameters.containsKey('dokterId'), false);
                if (r.url.path.endsWith('/profil')) return reply(profile());
                if (r.url.path.endsWith('/jadwal')) {
                  return reply([session(config)]);
                }
                if (r.url.path.endsWith('/janji-temu')) {
                  return reply([
                    {
                      'nomorAntrean': 'M-001',
                      'status': 'DIPESAN',
                      'mulaiPada': '${config.today}T08:00:00+07:00',
                      'selesaiPada': '${config.today}T09:00:00+07:00',
                      'ruang': {'nama': 'Ruang Mata'},
                      'poliklinik': {'nama': 'Poli Mata'},
                    },
                  ]);
                }
                return reply({
                  'sesi': session(config),
                  'ruang': {'nama': 'Ruang Mata'},
                  'poliklinik': {'nama': 'Poli Mata'},
                  'totalMenunggu': 2,
                  'aktif': [
                    {'nomorAntrean': 'M-002', 'status': 'DIPANGGIL'},
                  ],
                  'menunggu': [],
                });
              }),
            )
            ..user = identity()
            ..accessToken = 'access';
      await tester.pumpWidget(QueueBApp(api: api));
      await tester.pumpAndSettle();
      expect(find.text('Dashboard Dokter'), findsOneWidget);
      expect(find.text('Dokter Satu'), findsWidgets);
      await tester.scrollUntilVisible(
        find.text('M-001'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('M-001'), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.text('M-002'), findsWidgets);
      expect(find.text('Dalam Antrean'), findsOneWidget);
      expect(find.text('Panggil berikutnya'), findsNothing);
      expect(find.text('Check-In QR'), findsNothing);
      expect(requests.every((m) => m == 'GET'), true);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      api.dispose();
      await tester.binding.setSurfaceSize(null);
    });
  }
  testWidgets('empty/error/loading states and date filter recover safely', (
    tester,
  ) async {
    final config = AppConfig(
      apiBaseUrl: 'http://localhost:3000/api/v1',
      realtime: false,
    );
    bool fail = true;
    final dates = <String?>[];
    final api = QueueApi(
      config: config,
      client: MockClient((r) async {
        dates.add(r.url.queryParameters['tanggal']);
        if (fail) return reply({'message': 'Koneksi gagal'}, 503);
        return reply(r.url.path.endsWith('/profil') ? profile() : []);
      }),
    )..user = identity();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DoctorPage(api: api)),
      ),
    );
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.textContaining('Koneksi gagal'), findsOneWidget);
    fail = false;
    await tester.tap(find.byTooltip('Muat ulang portal'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Tidak ada jadwal untuk tanggal pilihan.'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.text('Tidak ada jadwal untuk tanggal pilihan.'),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.textContaining('Monitoring tersedia selama sesi'),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.textContaining('Monitoring tersedia selama sesi'),
      findsOneWidget,
    );
    expect(dates.whereType<String>().every((d) => d == config.today), true);
    await tester.pumpWidget(const SizedBox());
    api.dispose();
  });
  test('DOKTER persistent restore validates server identity', () async {
    final store = MemorySessionStore();
    await store.write(const SessionCredentials('old', 'refresh'));
    final api = QueueApi(
      config: AppConfig(
        apiBaseUrl: 'http://localhost:3000/api/v1',
        realtime: false,
      ),
      sessionStore: store,
      client: MockClient((r) async => reply(identity())),
    );
    await api.restoreSession();
    expect(api.user?['peran'], 'DOKTER');
    expect(api.accessToken, 'old');
    api.dispose();
  });
  testWidgets(
    'doctor events refresh REST snapshot; duplicate ignored, pause/resume and dispose',
    (tester) async {
      final config = AppConfig(apiBaseUrl: 'http://localhost:3000/api/v1');
      int reads = 0;
      String number = 'M-001';
      final api =
          QueueApi(
              config: config,
              client: MockClient((r) async {
                if (r.url.path.endsWith('/profil')) return reply(profile());
                if (r.url.path.endsWith('/jadwal')) {
                  return reply([session(config)]);
                }
                if (r.url.path.endsWith('/janji-temu')) return reply([]);
                reads++;
                return reply({
                  'sesi': session(config),
                  'ruang': {'nama': 'Ruang Mata'},
                  'totalMenunggu': 1,
                  'aktif': [
                    {'nomorAntrean': number, 'status': 'DIPANGGIL'},
                  ],
                });
              }),
            )
            ..user = identity()
            ..accessToken = 'access';
      final socket = DoctorSocket();
      final feed = PatientUpdates(
        api: api,
        role: 'DOKTER',
        namespace: 'doctor',
        eventKinds: const ['ANTREAN'],
        socketFactory: (url, options) {
          expect(url, 'http://localhost:3000/doctor');
          expect(options['auth'], {'token': 'access'});
          return socket;
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DoctorPage(api: api, updates: feed),
          ),
        ),
      );
      await tester.pumpAndSettle();
      number = 'M-009';
      socket.fire('doctor:updated', {
        'versiSkema': 1,
        'jenis': 'ANTREAN',
        'eventId': 'new',
      });
      await tester.pump(const Duration(milliseconds: 260));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Daftar Antrean Poli'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.scrollUntilVisible(
        find.text('M-009').first,
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('M-009'), findsWidgets);
      final count = reads;
      socket.fire('doctor:updated', {
        'versiSkema': 1,
        'jenis': 'ANTREAN',
        'eventId': 'new',
      });
      await tester.pump(const Duration(milliseconds: 260));
      expect(reads, count);
      feed.didChangeAppLifecycleState(AppLifecycleState.paused);
      feed.invalidate();
      await tester.pump(const Duration(milliseconds: 260));
      expect(reads, count);
      feed.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump(const Duration(milliseconds: 260));
      await tester.pumpAndSettle();
      expect(reads, greaterThan(count));
      final beforeReconnect = reads;
      socket.fire('disconnect', 'transport close');
      expect(feed.status.value, contains('Realtime terputus'));
      socket.fire('doctor:ready', {'versiSkema': 1});
      await tester.pump(const Duration(milliseconds: 260));
      await tester.pumpAndSettle();
      expect(feed.status.value, 'Realtime terhubung');
      expect(reads, greaterThan(beforeReconnect));
      await tester.pumpWidget(const SizedBox());
      feed.dispose();
      expect(socket.disposed, true);
      api.dispose();
    },
  );
  testWidgets(
    'ADMIN provisions doctor account without changing role/password contract',
    (tester) async {
      Json? body;
      final api = QueueApi(
        config: AppConfig(
          apiBaseUrl: 'http://localhost:3000/api/v1',
          realtime: false,
        ),
        client: MockClient((r) async {
          expect(r.url.path, '/api/v1/dokter/own/akun');
          body = jsonDecode(r.body) as Json;
          return reply({
            'akun': {'peran': 'DOKTER'},
          }, 201);
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) =>
                    DoctorAccountDialog(api: api, doctor: profile()),
              ),
              child: const Text('Buka'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Buka'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email dokter'),
        'dokter@test.local',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Kata sandi awal'),
        'Rahasia123!',
      );
      await tester.tap(find.text('Buat akun DOKTER'));
      await tester.pumpAndSettle();
      expect(body, {'email': 'dokter@test.local', 'kataSandi': 'Rahasia123!'});
      api.dispose();
    },
  );
}
