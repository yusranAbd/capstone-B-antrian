import 'dart:async';
import 'dart:convert';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:queueb_client/src/api.dart';
import 'package:queueb_client/src/config.dart';
import 'package:queueb_client/src/features/doctor/application/doctor_portal_cubit.dart';
import 'package:queueb_client/src/features/doctor/application/doctor_portal_state.dart';
import 'package:queueb_client/src/features/doctor/data/doctor_repository.dart';
import 'package:queueb_client/src/features/doctor/models/doctor_portal_data.dart';
import 'package:queueb_client/src/patient_sync.dart';

class FakeDoctorRepository extends DoctorRepository {
  bool get subscribed => hasListeners;
  bool active = true, disposed = false;
  int calls = 0, inFlight = 0, maxInFlight = 0;
  final dates = <String>[];
  final status = ValueNotifier('Realtime terhubung');
  Future<DoctorPortalData> Function(String)? read;
  @override
  bool get sessionActive => active;
  @override
  ValueListenable<String> get connectionStatus => status;
  @override
  Future<DoctorPortalData> load(String date) async {
    calls++;
    dates.add(date);
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    try {
      return await (read?.call(date) ?? Future.value(data(date)));
    } finally {
      inFlight--;
    }
  }

  void invalidate() => notifyListeners();
  void endSession() {
    active = false;
    notifyListeners();
  }

  @override
  void dispose() {
    disposed = true;
    status.dispose();
    super.dispose();
  }
}

class TrackingDoctorUpdates extends PatientUpdates {
  TrackingDoctorUpdates(QueueApi api)
    : super(api: api, role: 'DOKTER', namespace: 'doctor');
  bool get subscribed => hasListeners;
}

DoctorPortalData data(String value) => DoctorPortalData(
  profile: {
    'nama': value,
    'poliklinik': [
      {'nama': 'Mata'},
    ],
  },
  schedules: [
    {'id': value},
  ],
  appointments: [
    {'nomorAntrean': value},
  ],
  snapshots: [
    {
      'menunggu': [
        {'nomorAntrean': value},
      ],
    },
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(tz.initializeTimeZones);
  const date = '2026-10-28';
  late FakeDoctorRepository repo;
  setUp(() => repo = FakeDoctorRepository());
  DoctorPortalCubit create() => DoctorPortalCubit(repository: repo, date: date);
  Matcher status(DoctorPortalStatus value) =>
      isA<DoctorPortalState>().having((s) => s.status, 'status', value);

  blocTest<DoctorPortalCubit, DoctorPortalState>(
    'initial read succeeds',
    build: create,
    act: (c) => c.refresh(),
    expect: () => [
      status(DoctorPortalStatus.initialLoading),
      status(DoctorPortalStatus.loaded),
    ],
    verify: (c) {
      expect(c.state.available, isTrue);
      expect(repo.calls, 1);
    },
  );

  blocTest<DoctorPortalCubit, DoctorPortalState>(
    'initial error retains typed API failure',
    build: () {
      repo.read = (_) async => throw const ApiException(503, 'Unavailable');
      return create();
    },
    act: (c) => c.refresh(),
    expect: () => [
      status(DoctorPortalStatus.initialLoading),
      status(DoctorPortalStatus.error),
    ],
    verify: (c) {
      expect((c.state.error as ApiException).status, 503);
      expect(c.state.available, isFalse);
      expect(repo.calls, 1);
    },
  );

  test(
    'refresh keeps valid data while pending then publishes new data',
    () async {
      final c = create();
      await c.refresh();
      final next = Completer<DoctorPortalData>();
      repo.read = (_) => next.future;
      final pending = c.refresh();
      expect(c.state.status, DoctorPortalStatus.refreshing);
      expect(c.state.available, isTrue);
      expect(c.state.data.profile['nama'], date);
      next.complete(data('new'));
      await pending;
      expect(c.state.data.profile['nama'], 'new');
      await c.close();
    },
  );

  for (final error in [
    const ApiException(403, 'Denied'),
    const ApiException(0, 'Timeout'),
  ]) {
    test('refresh failure hides stale queue, does not retry: $error', () async {
      final c = create();
      await c.refresh();
      repo.read = (_) async => throw error;
      await c.refresh();
      expect(c.state.status, DoctorPortalStatus.error);
      expect(c.state.error, same(error));
      expect(c.state.available, isFalse);
      expect(c.state.data.snapshots, isEmpty);
      expect(repo.calls, 2);
      repo.read = null;
      await c.refresh();
      expect(c.state.available, isTrue);
      await c.close();
    });
  }

  test('realtime invalidation reads once; burst mid-fetch retains one trailing read', () async {
    final c = create();
    await c.refresh();
    repo.invalidate();
    await c.refresh();
    // Both notifications during the active request coalesce into a trailing read.
    final before = repo.calls;
    final first = Completer<DoctorPortalData>();
    repo.read = (_) =>
        repo.calls == before + 1 ? first.future : Future.value(data('latest'));
    final pending = c.refresh();
    for (var i = 0; i < 30; i++) {
      repo.invalidate();
    }
    var completed = false;
    final secondCaller = c.refresh().then((_) => completed = true);
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);
    expect(repo.calls, before + 1);
    first.complete(data('old'));
    await Future.wait([pending, secondCaller]);
    expect(repo.calls, before + 2);
    expect(repo.maxInFlight, 1);
    expect(c.state.data.profile['nama'], 'latest');
    await c.close();
  });

  test(
    'date changes discard old response and read only the latest date',
    () async {
      final first = Completer<DoctorPortalData>();
      repo.read = (d) => d == date ? first.future : Future.value(data(d));
      final c = create(), seen = <DoctorPortalState>[];
      final sub = c.stream.listen(seen.add);
      final pending = c.refresh();
      final changed = c.selectDate('2026-10-29');
      final latest = c.selectDate('2026-10-30');
      first.complete(data('old'));
      await Future.wait([pending, changed, latest]);
      expect(repo.dates, [date, '2026-10-30']);
      expect(c.state.selectedDate, '2026-10-30');
      expect(c.state.data.profile['nama'], '2026-10-30');
      expect(seen.any((s) => s.data.profile['nama'] == 'old'), isFalse);
      await sub.cancel();
      await c.close();
    },
  );

  test(
    'close during request disposes subscription and suppresses late result',
    () async {
      final first = Completer<DoctorPortalData>();
      repo.read = (_) => first.future;
      final c = create();
      final pending = c.refresh();
      await c.close();
      expect(repo.disposed, isTrue);
      expect(repo.subscribed, isFalse);
      first.complete(data('late'));
      await pending;
      expect(c.state.data.profile, isEmpty);
    },
  );

  test(
    'session change clears all data and discards in-flight and dirty work',
    () async {
      final c = create();
      await c.refresh();
      final first = Completer<DoctorPortalData>();
      repo.read = (_) => first.future;
      final pending = c.refresh();
      repo.invalidate();
      repo.endSession();
      expect(c.state.status, DoctorPortalStatus.sessionEnded);
      expect(c.state.data.profile, isEmpty);
      first.complete(data('foreign'));
      await pending;
      await c.refresh();
      expect(repo.calls, 2);
      expect(c.state.data.snapshots, isEmpty);
      await c.close();
    },
  );

  test('data snapshot copies and freezes every nested map/list', () {
    final nested = <String, dynamic>{
      'rooms': [
        {'name': 'old'},
      ],
    };
    final source = <Json>[nested];
    final snapshot = DoctorPortalData(
      profile: nested,
      schedules: source,
      appointments: source,
      snapshots: source,
    );
    (nested['rooms'] as List).clear();
    source.clear();
    expect((snapshot.profile['rooms'] as List).length, 1);
    expect(() => snapshot.profile['x'] = 1, throwsUnsupportedError);
    expect(
      () => (snapshot.profile['rooms'] as List).add({}),
      throwsUnsupportedError,
    );
    expect(
      () => snapshot.profile['rooms'][0]['name'] = 'new',
      throwsUnsupportedError,
    );
    for (final list in [
      snapshot.schedules,
      snapshot.appointments,
      snapshot.snapshots,
    ]) {
      expect(() => list.clear(), throwsUnsupportedError);
      expect(() => list[0]['rooms'][0]['name'] = 'new', throwsUnsupportedError);
    }
  });

  group('API repository', () {
    late QueueApi api;
    late TrackingDoctorUpdates updates;
    late ApiDoctorRepository repository;
    final calls = <Uri>[];
    int snapshotStatus = 200;
    setUp(() {
      calls.clear();
      snapshotStatus = 200;
      final config = AppConfig(
        apiBaseUrl: 'http://localhost:3000/api/v1',
        realtime: false,
      );
      api = QueueApi(
        config: config,
        client: MockClient((r) async {
          calls.add(r.url);
          expect(r.method, 'GET');
          Object body = [];
          var code = 200;
          if (r.url.path.endsWith('/profil')) body = {'nama': 'Own doctor'};
          if (r.url.path.endsWith('/jadwal')) {
            body = [
              {
                'id': 'active',
                'aktif': true,
                'mulaiPada': '${config.today}T00:00:00+07:00',
                'selesaiPada': '${config.today}T23:59:59+07:00',
              },
              {'id': 'inactive', 'aktif': false},
            ];
          }
          if (r.url.path.endsWith('/janji-temu')) {
            body = [
              {'nomorAntrean': 'A-001'},
            ];
          }
          if (r.url.path.endsWith('/snapshot')) {
            code = snapshotStatus;
            body = code == 200 ? {'totalMenunggu': 2} : {'message': 'Denied'};
          }
          return http.Response(
            jsonEncode(body),
            code,
            headers: {'content-type': 'application/json'},
          );
        }),
      )..user = {'id': 'own', 'peran': 'DOKTER'};
      updates = TrackingDoctorUpdates(api);
      repository = ApiDoctorRepository(api: api, updates: updates);
    });
    tearDown(() {
      repository.dispose();
      updates.dispose();
      api.dispose();
    });
    test(
      'injected API, exact GET paths/queries and immutable mapping',
      () async {
        final result = await repository.load(api.config.today);
        expect(calls.map((u) => u.path), [
          '/api/v1/portal-dokter/profil',
          '/api/v1/portal-dokter/jadwal',
          '/api/v1/portal-dokter/janji-temu',
          '/api/v1/portal-dokter/antrean/snapshot',
        ]);
        expect(calls[0].queryParameters, isEmpty);
        expect(calls[1].queryParameters, {'tanggal': api.config.today});
        expect(calls[2].queryParameters, {'tanggal': api.config.today});
        expect(calls[3].queryParameters, {'jadwalPraktikId': 'active'});
        expect(result.snapshots.single['totalMenunggu'], 2);
        expect(result.appointments.single['nomorAntrean'], 'A-001');
        expect(
          () => result.schedules.first['aktif'] = false,
          throwsUnsupportedError,
        );
      },
    );
    test('historical date never requests live snapshots', () async {
      final result = await repository.load('2020-01-01');
      expect(calls.length, 3);
      expect(result.snapshots, isEmpty);
    });
    test(
      '403 snapshot removes ended session, 503 retains typed error',
      () async {
        snapshotStatus = 403;
        expect((await repository.load(api.config.today)).snapshots, isEmpty);
        snapshotStatus = 503;
        await expectLater(
          repository.load(api.config.today),
          throwsA(isA<ApiException>().having((e) => e.status, 'status', 503)),
        );
      },
    );
    test(
      'one listener forwards invalidation; dispose releases borrowed feed',
      () {
        var notifications = 0;
        repository.addListener(() => notifications++);
        // notifyListeners is invoked by adapter debounce; no second socket is made.
        expect(updates.subscribed, isTrue);
        repository.dispose();
        expect(updates.subscribed, isFalse);
        expect(notifications, 0);
      },
    );
    test('logout terminally invalidates repository and clears cubit', () async {
      final c = DoctorPortalCubit(
        repository: repository,
        date: api.config.today,
      );
      await c.refresh();
      await api.clearSession();
      expect(c.state.status, DoctorPortalStatus.sessionEnded);
      expect(c.state.data.profile, isEmpty);
      expect(updates.subscribed, isFalse);
      await expectLater(
        repository.load(api.config.today),
        throwsA(isA<ApiException>()),
      );
      await c.close();
    });
  });
}
