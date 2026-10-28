import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:queueb_client/src/api.dart';
import 'package:queueb_client/src/config.dart';
import 'package:queueb_client/src/features/admin/application/admin_catalog_state.dart';
import 'package:queueb_client/src/features/admin/application/display_management_cubit.dart';
import 'package:queueb_client/src/features/admin/application/display_management_state.dart';
import 'package:queueb_client/src/features/admin/data/admin_catalog_repository.dart';
import 'package:queueb_client/src/features/admin/data/admin_display_repository.dart';
import 'package:queueb_client/src/features/admin/models/admin_display_models.dart';
import 'package:timezone/data/latest.dart' as tz;

const fixtureActivationCode = '001234567890';

class DisplayFixture {
  DisplayFixture() {
    api = QueueApi(
      config: AppConfig(apiBaseUrl: 'http://localhost/api/v1', realtime: false),
      client: MockClient(handle),
    )..user = {'id': 'admin', 'peran': 'ADMIN'};
    catalog = AdminCatalogRepository(api);
    repository = AdminDisplayRepository(catalog);
  }
  late final QueueApi api;
  late final AdminCatalogRepository catalog;
  late final AdminDisplayRepository repository;
  final calls = <http.Request>[];
  final data = <String, List<Json>>{
    '/layanan': [
      {'id': 'clinic', 'nama': 'Poli Awal', 'kode': 'PD', 'aktif': true},
    ],
    '/dokter': [],
    '/loket': [],
    '/jadwal-praktik': [],
    '/jadwal-layanan': [],
    '/penugasan-petugas': [],
    '/akun-petugas': [],
    '/perangkat-display': [device('a'), device('b')],
  };
  static Json device(String id) => {
    'id': id,
    'nama': 'TV $id',
    'layananId': 'clinic',
    'aktif': true,
    'terakhirAktifPada': null,
    'kode': fixtureActivationCode,
    'tokenHash': 'fixture-secret',
    'pasien': [
      {'nama': 'must-not-publish'},
    ],
  };
  final reads = <String, int>{};
  final gates = <(String, int), Completer<void>>{};
  final waiters = <(String, int), Completer<void>>{};
  final failures = <String, int>{};
  int? readError;
  bool commitUnknown = false, malformedRead = false, malformedWrite = false;
  Duration activationLifetime = const Duration(minutes: 5);
  String code = fixtureActivationCode;
  Json identity = {'id': 'admin', 'peran': 'ADMIN'};
  Completer<void>? writeGate, writeStarted;
  void Function()? afterWrite;
  http.Response reply(Object value, [int status = 200]) =>
      http.Response(jsonEncode(value), status);
  Future<void> waitRead(String path, int count) => (reads[path] ?? 0) >= count
      ? Future.value()
      : (waiters[(path, count)] ??= Completer<void>()).future;
  Future<http.Response> handle(http.Request request) async {
    calls.add(request);
    final path = request.url.path.replaceFirst('/api/v1', '');
    if (path == '/auth/me') return reply(identity);
    if (request.method != 'GET' && !path.startsWith(adminDisplayPath)) {
      final resource = '/${path.split('/')[1]}';
      final body = request.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(request.body) as Json;
      final id = request.method == 'POST'
          ? 'server-${resource.substring(1)}'
          : path.split('/')[2];
      if (request.method == 'POST') {
        data.putIfAbsent(resource, () => []).add({'id': id, ...body});
      }
      if (request.method == 'PATCH') {
        data[resource] = [
          for (final old in data[resource]!)
            old['id'] == id ? {...old, ...body} : old,
        ];
      }
      return reply({'id': id, ...body});
    }
    if (request.method == 'GET') {
      final count = reads.update(path, (n) => n + 1, ifAbsent: () => 1);
      final rows = path == '/penugasan-petugas'
          ? [
              for (final row in data[path]!)
                {
                  ...row,
                  'petugas':
                      data['/akun-petugas']!
                          .where((a) => a['id'] == row['petugasId'])
                          .firstOrNull ??
                      {},
                  'loket':
                      data['/loket']!
                          .where((a) => a['id'] == row['loketId'])
                          .firstOrNull ??
                      {},
                },
            ]
          : path == adminDisplayPath
          ? [
              for (final d in data[path]!)
                {
                  ...d,
                  'layanan':
                      data['/layanan']!
                          .where((c) => c['id'] == d['layananId'])
                          .firstOrNull ??
                      {},
                },
            ]
          : data[path] ?? [];
      final result = readError == null
          ? reply(
              malformedRead && path == adminDisplayPath
                  ? {'invalid': true}
                  : rows,
            )
          : reply({
              'message': 'raw secret=$fixtureActivationCode fixture-secret',
            }, readError!);
      waiters.remove((path, count))?.complete();
      if (gates[(path, count)] case final gate?) await gate.future;
      return result;
    }
    final action = path.endsWith('/aktivasi')
        ? 'activate'
        : path.endsWith('/nonaktifkan')
        ? 'revoke'
        : request.method == 'POST'
        ? 'create'
        : request.method == 'PATCH'
        ? 'update'
        : 'delete';
    final body = request.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(request.body) as Json;
    final id = action == 'create' ? 'server-created' : path.split('/')[2];
    writeStarted?.complete();
    writeStarted = null;
    if (writeGate case final gate?) await gate.future;
    final failure = failures[action];
    final record = <String, dynamic>{'id': id, ...body};
    if (failure == null || commitUnknown) {
      if (action == 'create') {
        data[adminDisplayPath]!.add({...record, 'aktif': false});
      }
      if (action == 'update' || action == 'activate' || action == 'revoke') {
        data[adminDisplayPath] = [
          for (final d in data[adminDisplayPath]!)
            d['id'] == id
                ? {
                    ...d,
                    ...body,
                    if (action == 'activate' || action == 'revoke')
                      'aktif': action == 'activate',
                  }
                : d,
        ];
      }
      if (action == 'delete') {
        data[adminDisplayPath]!.removeWhere((d) => d['id'] == id);
      }
    }
    afterWrite?.call();
    if (failure == 0) throw http.ClientException('Response lost');
    if (failure != null) {
      return reply({
        'message': 'raw code=$fixtureActivationCode token=fixture-secret',
      }, failure);
    }
    if (malformedWrite) return reply([]);
    return action == 'activate'
        ? reply({
            'kode': code,
            'berlakuHingga': DateTime.now()
                .toUtc()
                .add(activationLifetime)
                .toIso8601String(),
          })
        : reply({
            ...record,
            'token': 'fixture-secret',
            'kode': fixtureActivationCode,
          });
  }

  void dispose() {
    catalog.dispose();
    api.dispose();
  }
}

String stateText(DisplayManagementState s) => jsonEncode({
  'snapshot': s.snapshot.collections,
  'error': '${s.error}',
  'action': s.action,
  'deviceId': s.deviceId,
  'unknown': s.uncertainActivations.toList(),
  'disclosure': s.awaitingDisclosure,
});

void main() {
  setUpAll(tz.initializeTimeZones);
  late DisplayFixture f;
  late DisplayManagementCubit c;
  setUp(() {
    f = DisplayFixture();
    c = DisplayManagementCubit(f.repository);
  });
  tearDown(() async {
    await c.close();
    f.dispose();
  });

  test('initial load is lazy, scoped, sanitized, immutable and allows same clinic on many devices', () async {
    expect(f.calls, isEmpty);
    expect(c.state.load, CatalogLoadStatus.initial);
    await c.refresh();
    expect(c.devices, hasLength(2));
    expect(c.state.load, CatalogLoadStatus.loaded);
    expect(c.devices.map((d) => d['layananId']), ['clinic', 'clinic']);
    expect(() => c.devices.clear(), throwsUnsupportedError);
    expect(
      () => c.devices.first['layanan']['nama'] = 'Changed',
      throwsUnsupportedError,
    );
    expect(stateText(c.state).contains(fixtureActivationCode), isFalse);
    expect(stateText(c.state).contains('fixture-secret'), isFalse);
    expect(stateText(c.state).contains('must-not-publish'), isFalse);
    expect(f.reads, {adminDisplayPath: 1, '/layanan': 1});
  });
  test('initial failure, verified empty, refresh failure with data and recovery are distinct', () async {
    f.readError = 503;
    await c.refresh();
    expect(c.state.load, CatalogLoadStatus.failure);
    expect(c.state.snapshot.collections.containsKey(adminDisplayPath), isFalse);
    f.readError = null;
    f.data[adminDisplayPath] = [];
    await c.refresh();
    expect(c.state.load, CatalogLoadStatus.loaded);
    expect(c.devices, isEmpty);
    f.data[adminDisplayPath] = [DisplayFixture.device('a')];
    await c.refresh();
    f.readError = 503;
    await c.refresh();
    expect(c.devices, hasLength(1));
    expect(c.state.load, CatalogLoadStatus.failure);
    f.readError = null;
    await c.refresh();
    expect(c.state.loadError, isNull);
  });
  test(
    'malformed array is an error rather than a false empty result',
    () async {
      f.malformedRead = true;
      await c.refresh();
      expect(c.state.load, CatalogLoadStatus.failure);
      expect(
        c.state.snapshot.collections.containsKey(adminDisplayPath),
        isFalse,
      );
    },
  );
  test(
    'single flight and burst refresh wait for the trailing request to finish',
    () async {
      final first = Completer<void>(), last = Completer<void>();
      f.gates[(adminDisplayPath, 1)] = first;
      f.gates[(adminDisplayPath, 2)] = last;
      var complete = false;
      final initial = c.refresh().then((_) => complete = true);
      await f.waitRead(adminDisplayPath, 1);
      final burst = [for (var i = 0; i < 30; i++) c.refresh()];
      f.data[adminDisplayPath]!.first['nama'] = 'Latest';
      first.complete();
      await f.waitRead(adminDisplayPath, 2);
      expect(complete, isFalse);
      expect(f.reads[adminDisplayPath], 2);
      last.complete();
      await Future.wait([initial, ...burst]);
      expect(c.devices.first['nama'], 'Latest');
      expect(f.reads[adminDisplayPath], 2);
    },
  );
  test(
    'invalidation during trailing read preserves another serialized refresh',
    () async {
      final first = Completer<void>(), second = Completer<void>();
      f.gates[(adminDisplayPath, 1)] = first;
      f.gates[(adminDisplayPath, 2)] = second;
      final initial = c.refresh();
      await f.waitRead(adminDisplayPath, 1);
      c.refresh();
      first.complete();
      await f.waitRead(adminDisplayPath, 2);
      c.refresh();
      f.data[adminDisplayPath]!.first['nama'] = 'Third';
      second.complete();
      await initial;
      expect(c.devices.first['nama'], 'Third');
      expect(f.reads[adminDisplayPath], 3);
    },
  );
  test('failed burst refresh consumes every adapter future and recovers explicitly', () async {
    final gate = Completer<void>();
    f.gates[(adminDisplayPath, 1)] = gate;
    f.readError = 503;
    final first = c.refresh();
    await f.waitRead(adminDisplayPath, 1);
    final pending = [for (var i = 0; i < 5; i++) c.refresh()];
    gate.complete();
    await Future.wait([first, ...pending]);
    expect(c.state.load, CatalogLoadStatus.failure);
    f.readError = null;
    await c.refresh();
    expect(c.state.load, CatalogLoadStatus.loaded);
  });
  for (final action in ['create', 'update', 'revoke', 'delete']) {
    Future<void> operation() => switch (action) {
      'create' => c.create({'nama': 'New TV', 'layananId': 'clinic'}),
      'update' => c.update('a', 'Renamed'),
      'revoke' => c.revoke('a'),
      _ => c.delete('a'),
    };
    for (final reject in [false, true]) {
      test(
        '$action ${reject ? 'backend rejection preserves data' : 'uses existing endpoint and reconciles'}',
        () async {
          await c.refresh();
          if (reject) f.failures[action] = 409;
          if (reject) {
            await expectLater(operation(), throwsA(isA<ApiException>()));
          } else {
            await operation();
          }
          final write = f.calls.singleWhere((r) => r.method != 'GET');
          final suffix = switch (action) {
            'create' => '',
            'revoke' => '/a/nonaktifkan',
            'delete' => '/a/permanen',
            _ => '/a',
          };
          expect(write.url.path, '/api/v1/perangkat-display$suffix');
          if (action == 'update') {
            expect(jsonDecode(write.body), {'nama': 'Renamed'});
          }
          if (action == 'create') {
            expect(jsonDecode(write.body), {
              'nama': 'New TV',
              'layananId': 'clinic',
            });
          }
          expect(
            c.state.mutation,
            reject
                ? CatalogMutationStatus.failure
                : CatalogMutationStatus.success,
          );
          expect(c.devices.any((d) => d['id'] == 'b'), isTrue);
          expect(c.devices.firstWhere((d) => d['id'] == 'b')['nama'], 'TV b');
          expect(
            c.devices.length,
            reject
                ? 2
                : action == 'create'
                ? 3
                : action == 'delete'
                ? 1
                : 2,
          );
        },
      );
    }
  }
  for (final status in [400, 401, 403, 429]) {
    test(
      'activation rejection $status is safe and never leaks server response',
      () async {
        f.failures['activate'] = status;
        await expectLater(
          c.activate('a'),
          throwsA(
            isA<ApiException>().having((e) => e.status, 'status', status),
          ),
        );
        expect(stateText(c.state).contains(fixtureActivationCode), isFalse);
        expect(stateText(c.state).contains('fixture-secret'), isFalse);
      },
    );
  }
  test('activation returns transient code outside emitted state and blocks writes until disclosure finishes', () async {
    final emitted = <String>[];
    final sub = c.stream.listen((s) => emitted.add(stateText(s)));
    final activation = await c.activate('a');
    expect(activation.deviceId, 'a');
    expect(activation.code, fixtureActivationCode);
    expect(c.state.awaitingDisclosure, isTrue);
    await expectLater(c.activate('a'), throwsA(isA<ApiException>()));
    expect(
      emitted.every(
        (s) =>
            !s.contains(fixtureActivationCode) && !s.contains('fixture-secret'),
      ),
      isTrue,
    );
    activation.clear();
    c.finishDisclosure();
    expect(activation.code, isNull);
    expect(c.state.busy, isFalse);
    expect(
      f.calls.where((r) => r.url.path.endsWith('/aktivasi')),
      hasLength(1),
    );
    await sub.cancel();
  });
  for (final committed in [false, true]) {
    test(
      'lost rotation committed=$committed cannot be recovered or replayed by metadata refresh',
      () async {
        f.failures['activate'] = 0;
        f.commitUnknown = committed;
        await expectLater(c.activate('a'), throwsA(isA<ApiException>()));
        expect(c.state.mutation, CatalogMutationStatus.unknown);
        expect(c.state.uncertainActivations, {'a'});
        await c.refresh();
        await c.update('a', 'New name');
        await expectLater(c.activate('a'), throwsA(isA<ApiException>()));
        expect(
          f.calls.where((r) => r.url.path.endsWith('/aktivasi')),
          hasLength(1),
        );
        expect(
          () => c.state.uncertainActivations.clear(),
          throwsUnsupportedError,
        );
        f.failures.clear();
        final result = await c.activate('a', confirmedReplacement: true);
        result.clear();
        c.finishDisclosure();
        expect(c.state.uncertainActivations, isEmpty);
      },
    );
  }
  test(
    'rotation uncertainty for A does not prevent deliberately activating B',
    () async {
      f.failures['activate'] = 503;
      await expectLater(c.activate('a'), throwsA(isA<ApiException>()));
      f.failures.clear();
      final result = await c.activate('b');
      result.clear();
      c.finishDisclosure();
      expect(c.state.uncertainActivations, {'a'});
      expect(
        f.calls
            .where((r) => r.url.path.endsWith('/aktivasi'))
            .map((r) => r.url.path),
        [
          '/api/v1/perangkat-display/a/aktivasi',
          '/api/v1/perangkat-display/b/aktivasi',
        ],
      );
      await c.revoke('a');
      expect(c.state.uncertainActivations, isEmpty);
    },
  );
  test(
    'failed reconciliation blocks risky actions until explicit REST recovery',
    () async {
      f.failures['create'] = 0;
      f.commitUnknown = true;
      f.afterWrite = () => f.readError = 503;
      await expectLater(
        c.create({'nama': 'New', 'layananId': 'clinic'}),
        throwsA(isA<ApiException>()),
      );
      expect(c.state.needsReconciliation, isTrue);
      await expectLater(c.delete('a'), throwsA(isA<ApiException>()));
      expect(f.calls.where((r) => r.method == 'DELETE'), isEmpty);
      f.afterWrite = null;
      f.readError = null;
      f.failures.clear();
      await c.refresh();
      expect(c.devices, hasLength(3));
      await c.delete('a');
      expect(c.devices, hasLength(2));
    },
  );
  for (final malformed in [false, true]) {
    test(
      malformed
          ? 'malformed activation response is unknown without exposing secret'
          : 'expired activation is unknown without retry',
      () async {
        if (malformed) {
          f.code = 'bad';
        } else {
          f.activationLifetime = const Duration(seconds: -1);
        }
        await expectLater(c.activate('a'), throwsA(isA<ApiException>()));
        expect(c.state.uncertainActivations, {'a'});
        expect(f.calls.where((r) => r.method == 'POST'), hasLength(1));
      },
    );
  }
  test(
    'double submit while request pending never sends a second command',
    () async {
      final gate = Completer<void>();
      f.writeGate = gate;
      final started = f.writeStarted = Completer<void>();
      final pending = c.update('a', 'Changed');
      await started.future;
      await expectLater(c.delete('a'), throwsA(isA<ApiException>()));
      gate.complete();
      await pending;
      expect(f.calls.where((r) => r.method != 'GET'), hasLength(1));
    },
  );
  for (final ending in ['close', 'logout', 'account', 'role']) {
    test('$ending during read ignores old response and old catalog', () async {
      final gate = Completer<void>();
      f.gates[(adminDisplayPath, 1)] = gate;
      final pending = c.refresh();
      await f.waitRead(adminDisplayPath, 1);
      if (ending == 'close') {
        await c.close();
      }
      if (ending == 'logout') {
        await f.api.clearSession();
      }
      if (ending == 'account' || ending == 'role') {
        f.identity = {
          'id': ending == 'account' ? 'next-admin' : 'admin',
          'peran': ending == 'role' ? 'USER' : 'ADMIN',
        };
        await f.api.reloadOwnProfile();
      }
      gate.complete();
      await pending;
      expect(c.devices, isEmpty);
      if (ending != 'close') {
        expect(c.state.load, CatalogLoadStatus.sessionEnded);
      }
    });
  }
  for (final close in [false, true]) {
    test(
      close
          ? 'close while rotation runs drops late disclosure'
          : 'logout while rotation runs clears metadata',
      () async {
        final gate = Completer<void>();
        f.writeGate = gate;
        final started = f.writeStarted = Completer<void>();
        final pending = expectLater(
          c.activate('a'),
          throwsA(isA<ApiException>()),
        );
        await started.future;
        if (close) {
          await c.close();
        } else {
          await f.api.clearSession();
        }
        gate.complete();
        await pending;
        expect(c.state.awaitingDisclosure, isFalse);
        expect(c.devices, isEmpty);
      },
    );
  }
  test('catalog-only refresh is shared and does not trigger another device request', () async {
    await f.catalog.refresh([adminDisplayPath, '/layanan']);
    expect(c.state.load, CatalogLoadStatus.loaded);
    expect(f.reads[adminDisplayPath], 1);
    await f.catalog.refresh(['/layanan']);
    expect(f.reads[adminDisplayPath], 1);
    f.readError = 503;
    await expectLater(
      f.catalog.refresh([adminDisplayPath]),
      throwsA(
        isA<ApiException>()
            .having((e) => e.status, 'status', 503)
            .having(
              (e) => '$e',
              'safe message',
              isNot(contains(fixtureActivationCode)),
            )
            .having(
              (e) => '$e',
              'safe message',
              isNot(contains('fixture-secret')),
            ),
      ),
    );
  });
}
