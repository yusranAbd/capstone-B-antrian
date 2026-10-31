import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:queueb_client/src/api.dart';
import 'package:queueb_client/src/config.dart';
import 'package:queueb_client/src/features/patient/data/patient_repository.dart';
import 'package:queueb_client/src/features/patient/models/patient_queue_models.dart';
import 'package:queueb_client/src/patient_home_v7.dart';
import 'package:queueb_client/src/patient.dart';
import 'package:queueb_client/src/patient_home_v8.dart';
import 'package:queueb_client/src/patient_sync.dart';

import 'patient_sync_test.dart' show FakePatientSocket;
import 'patient_home_v3_test.dart' show HomeBackend;

const a = '11111111-1111-4111-8111-111111111111',
    b = '22222222-2222-4222-8222-222222222222',
    day = '2026-10-30';
Json batch(
  Iterable<String> ids, {
  int? total = 42,
  int? waiting = 31,
  String date = day,
  List<Json> serving = const [],
}) => {
  'versiSkema': 1,
  'tanggalPelayanan': date,
  'diperolehPada': DateTime.now().toUtc().toIso8601String(),
  'layanan': [
    for (final id in ids)
      {
        'layananId': id,
        'totalCheckIn': total,
        'jumlahMenunggu': waiting,
        'sedangDilayani': serving,
      },
  ],
};

class QueueSocket extends FakePatientSocket {
  final watches = <Json>[];
  @override
  void emitWithAck(
    String event,
    dynamic data, {
    Function? ack,
    bool binary = false,
  }) {
    watches.add(Map<String, dynamic>.from(data as Map));
    ack?.call({'ok': true, 'versiSkema': 1, ...watches.last});
  }
}

class IdentityApi extends QueueApi {
  IdentityApi(http.Client client, {bool realtime = false})
    : super(
        config: AppConfig(
          apiBaseUrl: 'http://localhost/api/v1',
          realtime: realtime,
        ),
        client: client,
      ) {
    accessToken = 'fixture';
    user = {'id': 'owner', 'peran': 'USER'};
  }
  void replace(Json? next) {
    user = next;
    notifyListeners();
  }
}

Future<void> idle(PatientRepository repo) async {
  if (repo.queueState.value.loading.isEmpty) return;
  final done = Completer<void>();
  void listener() {
    if (repo.queueState.value.loading.isEmpty && !done.isCompleted) {
      done.complete();
    }
  }

  repo.queueState.addListener(listener);
  try {
    await done.future.timeout(const Duration(seconds: 3));
  } finally {
    repo.queueState.removeListener(listener);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(tz.initializeTimeZones);
  test(
    'parses valid zeros, nullable counts, multiple rooms; stores no extra PII',
    () {
      final raw = batch(
        [a],
        total: 2,
        waiting: 0,
        serving: [
          {
            'loketId': 'room-a',
            'kodeLoket': 'A',
            'nomorAntrean': 'PEN-007',
            'namaPasien': 'PRIVATE',
          },
          {'loketId': 'room-b', 'kodeLoket': 'B', 'nomorAntrean': 'PEN-011'},
        ],
      );
      final parsed = PatientQueueSummary.parseBatch(raw, {a}, day)[a]!;
      expect(parsed.checkedInTotal, 2);
      expect(parsed.waitingCount, 0);
      expect(parsed.serving.map((s) => s.number), ['PEN-007', 'PEN-011']);
      expect(() => parsed.serving.clear(), throwsUnsupportedError);
      final nullable = PatientQueueSummary.parseBatch(
        batch([a], total: null, waiting: null),
        {a},
        day,
      )[a]!;
      expect(nullable.checkedInTotal, isNull);
      expect(nullable.waitingCount, isNull);
    },
  );
  test(
    'V7.1 keeps Pendaftaran then Apotek, with all remaining rows stable',
    () {
      final rows = <Json>[
        {'kode': 'ADMINISTRASI'},
        {'kode': 'APOTIK'},
        {'kode': 'PENDAFTARAN'},
        {'kode': 'APOTEK'},
        {'kode': 'REGISTRASI'},
      ];
      final before = [...rows];
      expect(registrationFirst(rows).map((r) => r['kode']), [
        'PENDAFTARAN',
        'APOTEK',
        'ADMINISTRASI',
        'APOTIK',
        'REGISTRASI',
      ]);
      expect(rows, orderedEquals(before));
    },
  );
  test(
    'rejects malformed, foreign, duplicate, wrong-date and impossible data',
    () {
      final invalid = <Object?>[
        [],
        {
          ...batch([a]),
          'versiSkema': 2,
        },
        batch([b]),
        batch([a, a]),
        batch([a], date: '2026-10-31'),
        batch([a], total: -1),
        batch([a], total: 1, waiting: 2),
        {
          ...batch([a]),
          'diperolehPada': 'bad',
        },
        {
          'versiSkema': 1,
          'tanggalPelayanan': day,
          'diperolehPada': DateTime.now().toUtc().toIso8601String(),
          'layanan': [
            {'layananId': a},
          ],
        },
        {
          ...batch([a]),
          'layanan': [
            {
              'layananId': a,
              'totalCheckIn': '42',
              'jumlahMenunggu': 0,
              'sedangDilayani': [],
            },
          ],
        },
        batch(
          [a],
          total: 0,
          waiting: 0,
          serving: [
            {'loketId': 'r', 'kodeLoket': 'R', 'nomorAntrean': 'PEN-001'},
          ],
        ),
      ];
      for (final raw in invalid) {
        expect(
          () => PatientQueueSummary.parseBatch(raw, {a}, day),
          throwsA(isA<ApiException>()),
        );
      }
      expect(validPatientQueueDate('2026-02-30'), isFalse);
    },
  );
  test('Live requires acknowledged connection, current date, fresh valid data and no pending/error', () {
    final parsed = PatientQueueSummary.parseBatch(batch([a]), {a}, day);
    final now = DateTime.now();
    expect(
      PatientQueueState(
        date: day,
        summaries: parsed,
        connected: true,
      ).forService(a, day, now: now).live,
      isTrue,
    );
    expect(
      PatientQueueState(
        date: day,
        summaries: parsed,
      ).forService(a, day).freshness,
      'Data terakhir',
    );
    expect(
      PatientQueueState(
        date: day,
        summaries: parsed,
        connected: true,
        loading: {a},
      ).forService(a, day).live,
      isFalse,
    );
    expect(
      PatientQueueState(
        date: day,
        summaries: parsed,
        connected: true,
        errors: {a},
      ).forService(a, day).live,
      isFalse,
    );
    expect(
      PatientQueueState(
        date: day,
        summaries: parsed,
        connected: true,
      ).forService(a, '2026-10-31').summary,
      isNull,
    );
    expect(
      PatientQueueState(
        date: day,
        summaries: parsed,
        connected: true,
      ).forService(a, day, now: now.add(const Duration(minutes: 5))).live,
      isFalse,
    );
  });
  test(
    'initial summary uses one GET; repeated same scope does not reload or post',
    () async {
      var reads = 0;
      final api = IdentityApi(
        MockClient((r) async {
          expect(r.method, 'GET');
          reads++;
          expect(r.url.queryParameters['tanggal'], day);
          return http.Response(
            jsonEncode(batch(r.url.queryParameters['layananId']!.split(','))),
            200,
          );
        }),
      );
      final repo = PatientRepository(api);
      addTearDown(() {
        repo.dispose();
        api.dispose();
      });
      repo.configureQueueScope([a, b], day);
      await idle(repo);
      repo.configureQueueScope([b, a], day);
      await Future<void>.delayed(Duration.zero);
      expect(reads, 1);
      expect(repo.queueState.value.summaries.keys.toSet(), {a, b});
    },
  );
  test('burst refresh is single-flight with one trailing read, rejects the older response', () async {
    var reads = 0, concurrent = 0, maxConcurrent = 0;
    final gate = Completer<void>();
    final api = IdentityApi(
      MockClient((r) async {
        final n = ++reads;
        concurrent++;
        if (concurrent > maxConcurrent) maxConcurrent = concurrent;
        if (n == 1) await gate.future;
        concurrent--;
        return http.Response(
          jsonEncode(batch([a], total: n == 1 ? 42 : 44)),
          200,
        );
      }),
    );
    final repo = PatientRepository(api);
    addTearDown(() {
      repo.dispose();
      api.dispose();
    });
    final seen = <int?>[];
    repo.queueState.addListener(
      () => seen.add(repo.queueState.value.summaries[a]?.checkedInTotal),
    );
    repo.configureQueueScope([a], day);
    final requests = [for (var i = 0; i < 20; i++) repo.refreshQueue()];
    gate.complete();
    await Future.wait(requests);
    await idle(repo);
    expect(reads, 2);
    expect(maxConcurrent, 1);
    expect(seen, isNot(contains(42)));
    expect(repo.queueState.value.summaries[a]!.checkedInTotal, 44);
  });
  test('network failure keeps last value stale and explicit retry reads server truth', () async {
    var fail = false, total = 42;
    final api = IdentityApi(
      MockClient(
        (r) async => http.Response(
          jsonEncode(
            fail ? {'message': 'private error'} : batch([a], total: total),
          ),
          fail ? 503 : 200,
        ),
      ),
    );
    final repo = PatientRepository(api);
    addTearDown(() {
      repo.dispose();
      api.dispose();
    });
    repo.configureQueueScope([a], day);
    await idle(repo);
    fail = true;
    await repo.refreshQueue();
    expect(repo.queueState.value.errors, {a});
    expect(repo.queueState.value.forService(a, day).freshness, 'Data terakhir');
    expect(repo.queueState.value.summaries[a]!.checkedInTotal, 42);
    fail = false;
    total = 43;
    await repo.refreshQueue();
    expect(repo.queueState.value.summaries[a]!.checkedInTotal, 43);
  });
  test(
    'service/date change discards late response and old scope values',
    () async {
      final gate = Completer<void>();
      var reads = 0;
      final api = IdentityApi(
        MockClient((r) async {
          final n = ++reads;
          if (n == 1) await gate.future;
          return http.Response(
            jsonEncode(
              batch(
                r.url.queryParameters['layananId']!.split(','),
                date: r.url.queryParameters['tanggal']!,
              ),
            ),
            200,
          );
        }),
      );
      final repo = PatientRepository(api);
      addTearDown(() {
        repo.dispose();
        api.dispose();
      });
      repo.configureQueueScope([a], day);
      repo.configureQueueScope([b], '2026-10-31');
      gate.complete();
      await idle(repo);
      expect(repo.queueState.value.date, '2026-10-31');
      expect(repo.queueState.value.summaries.keys, [b]);
      expect(reads, 2);
    },
  );
  test('logout/account change clears values and ignores late read', () async {
    final gate = Completer<void>();
    final api = IdentityApi(
      MockClient((r) async {
        await gate.future;
        return http.Response(jsonEncode(batch([a])), 200);
      }),
    );
    final repo = PatientRepository(api);
    addTearDown(() {
      repo.dispose();
      api.dispose();
    });
    repo.configureQueueScope([a], day);
    api.replace({'id': 'other', 'peran': 'USER'});
    expect(repo.active, isFalse);
    expect(repo.queueState.value.summaries, isEmpty);
    gate.complete();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(repo.queueState.value.summaries, isEmpty);
  });
  testWidgets(
    'one socket handles duplicate, foreign scope, reconnect and offline refresh',
    (t) async {
      var total = 42, reads = 0, factories = 0;
      final api = IdentityApi(
        MockClient((r) async {
          if (!r.url.path.endsWith('/layanan/antrean')) {
            return http.Response('[]', 200);
          }
          reads++;
          return http.Response(jsonEncode(batch([a], total: total)), 200);
        }),
        realtime: true,
      );
      final socket = QueueSocket();
      final feed = PatientUpdates(
        api: api,
        socketFactory: (_, _) {
          factories++;
          return socket;
        },
        debounce: const Duration(milliseconds: 10),
      );
      final repo = PatientRepository(api, updates: feed);
      repo.configureQueueScope([a], day);
      socket.fire('patient:ready', {'versiSkema': 1});
      await t.pump(const Duration(milliseconds: 20));
      await t.pump();
      expect(repo.queueState.value.summaries[a]?.checkedInTotal, 42);
      final before = reads;
      total = 43;
      Json event(String id, {String service = a, String date = day}) => {
        'versiSkema': 1,
        'jenis': 'ANTREAN',
        'eventId': id,
        'layananId': service,
        'tanggalPelayanan': date,
      };
      socket.fire('patient:updated', event('same'));
      socket.fire('patient:updated', event('same'));
      socket.fire('patient:updated', event('foreign', service: b));
      socket.fire('patient:updated', event('tomorrow', date: '2026-10-31'));
      await t.pump(const Duration(milliseconds: 20));
      await t.pump();
      expect(reads, before + 1);
      expect(repo.queueState.value.summaries[a]!.checkedInTotal, 43);
      socket.fire('disconnect', 'transport close');
      await t.pump();
      expect(repo.queueState.value.connected, isFalse);
      total = 44;
      socket.fire('patient:ready', {'versiSkema': 1});
      await t.pump(const Duration(milliseconds: 20));
      await t.pump();
      expect(repo.queueState.value.summaries[a]!.checkedInTotal, 44);
      expect(factories, 1);
      expect(socket.watches.length, 2);
      repo.dispose();
      api.dispose();
      await t.pump();
      expect(socket.disposed, isTrue);
    },
  );
  testWidgets(
    'queue invalidation changes cards without rebuilding Home or replacing its owner',
    (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final backend = HomeBackend();
      var total = 42, queueReads = 0;
      final api =
          QueueApi(
              config: AppConfig(
                apiBaseUrl: 'http://localhost/api/v1',
                realtime: true,
              ),
              client: MockClient((r) async {
                if (r.url.path.endsWith('/layanan/antrean')) {
                  queueReads++;
                  return http.Response(
                    jsonEncode(
                      batch(
                        r.url.queryParameters['layananId']!.split(','),
                        total: total,
                        date: r.url.queryParameters['tanggal']!,
                      ),
                    ),
                    200,
                  );
                }
                return backend.handle(r);
              }),
            )
            ..accessToken = 'fixture'
            ..user = backend.user;
      final socket = QueueSocket();
      final feed = PatientUpdates(
        api: api,
        socketFactory: (_, _) => socket,
        debounce: const Duration(milliseconds: 10),
      );
      final repo = PatientRepository(api, updates: feed);
      await t.pumpWidget(
        MaterialApp(
          home: PatientPage(api: api, repository: repo),
        ),
      );
      socket.fire('patient:ready', {'versiSkema': 1});
      await t.pumpAndSettle();
      await t.pump(const Duration(milliseconds: 20));
      await t.pumpAndSettle();
      final host = t.state(find.byType(PatientPage));
      final welcome = t.widget(find.byType(PatientHomeWelcomeV8));
      final before = queueReads;
      total = 43;
      socket.fire('patient:updated', {
        'versiSkema': 1,
        'jenis': 'ANTREAN',
        'eventId': 'queue-only',
        'layananId': b,
        'tanggalPelayanan': api.config.today,
      });
      await t.pump(const Duration(milliseconds: 20));
      await t.pumpAndSettle();
      expect(queueReads, before + 1);
      expect(find.text('43'), findsOneWidget);
      expect(t.widget(find.byType(PatientHomeWelcomeV8)), same(welcome));
      expect(t.state(find.byType(PatientPage)), same(host));
      expect(backend.requests.where((r) => r.$1 == 'POST'), isEmpty);
      await t.pumpWidget(const SizedBox());
      repo.dispose();
      api.dispose();
      await t.pump();
      expect(t.takeException(), isNull);
    },
  );

  for (final width in [320.0, 360.0, 390.0, 430.0, 768.0, 1366.0]) {
    for (final scale in [1.0, 1.3, 1.5, 2.0]) {
      testWidgets(
        'bound card fits width $width scale $scale, preserves personal vs multi-room serving',
        (t) async {
          t.view.physicalSize = Size(width, 1100);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.resetPhysicalSize);
          addTearDown(t.view.resetDevicePixelRatio);
          final summary = PatientQueueSummary(
            a,
            day,
            DateTime.now().toUtc(),
            100000,
            99999,
            [
              const PatientServingNumber('r1', 'A', 'PEN-0000000007'),
              const PatientServingNumber('r2', 'B', 'PEN-0000000011'),
            ],
          );
          await t.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: Scaffold(
                  body: SingleChildScrollView(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 760),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: PatientServiceCardV7(
                            clinic: const {
                              'id': a,
                              'kode': 'PENDAFTARAN',
                              'nama': 'Pendaftaran',
                            },
                            ticket: const {'nomorAntrean': 'PEN-008'},
                            queue: PatientQueueView(
                              summary: summary,
                              live: true,
                            ),
                            onTap: () {},
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
          expect(find.text('PEN-008'), findsOneWidget);
          expect(find.text('100000'), findsOneWidget);
          expect(find.text('99999 menunggu'), findsOneWidget);
          expect(find.textContaining('A: PEN-0000000007'), findsOneWidget);
          expect(find.text('Live'), findsOneWidget);
        },
      );
    }
  }
}
