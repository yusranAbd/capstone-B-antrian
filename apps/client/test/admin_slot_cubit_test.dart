import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:queueb_client/src/api.dart';
import 'package:queueb_client/src/config.dart';
import 'package:queueb_client/src/features/admin/application/slot_session_cubit.dart';
import 'package:queueb_client/src/features/admin/application/slot_session_state.dart';
import 'package:queueb_client/src/features/admin/data/admin_catalog_repository.dart';
import 'package:queueb_client/src/features/admin/data/admin_slot_repository.dart';
import 'package:timezone/data/latest.dart' as tz;

class SlotFixture {
  SlotFixture() {
    api = QueueApi(
      config: AppConfig(apiBaseUrl: 'http://localhost/api/v1', realtime: false),
      client: MockClient(handle),
    )..user = {'id': 'admin', 'peran': 'ADMIN'};
    catalog = AdminCatalogRepository(api);
    repository = AdminSlotRepository(catalog);
  }
  late final QueueApi api;
  late final AdminCatalogRepository catalog;
  late final AdminSlotRepository repository;
  final calls = <http.Request>[];
  final data = <String, List<Json>>{
    'a': [slot('a')],
    'b': [slot('b')],
  };
  final masters = <String, List<Json>>{
    '/layanan': [
      {'id': 'clinic', 'nama': 'Poli', 'aktif': true},
    ],
    '/dokter': [
      {'id': 'doctor', 'nama': 'Dokter', 'aktif': true},
    ],
    '/loket': [
      {'id': 'room', 'nama': 'Ruang', 'layananId': 'clinic', 'aktif': true},
    ],
    '/jadwal-praktik': [session('a'), session('b')],
    '/jadwal-layanan': [
      {'id': 'hours', 'layananId': 'clinic', 'kapasitasHarian': 24},
    ],
  };
  final reads = <String, int>{};
  final readGates = <(String, int), Completer<void>>{};
  final readWaiters = <(String, int), Completer<void>>{};
  Completer<void>? writeGate, writeStarted;
  int? readError, writeError;
  bool commitLost = false, malformedRead = false, malformedWrite = false;
  void Function()? afterWrite;
  Json identity = {'id': 'admin', 'peran': 'ADMIN'};
  static Json session(String id) => {
    'id': id,
    'tanggal': '2026-10-29',
    'mulaiPada': '2026-10-28T17:00:00Z',
    'selesaiPada': '2026-10-28T19:00:00Z',
    'aktif': true,
    'loketId': 'room',
    'dokterLayananId': 'link',
    'loket': {'id': 'room', 'nama': 'Ruang'},
    'dokterLayanan': {
      'layananId': 'clinic',
      'dokterId': 'doctor',
      'layanan': {'id': 'clinic', 'nama': 'Poli'},
      'dokter': {'id': 'doctor', 'nama': 'Dokter'},
    },
  };
  static Json slot(String id) => {
    'id': 'slot-$id',
    'jadwalPraktikId': id,
    'mulaiPada': '2026-10-28T17:00:00Z',
    'selesaiPada': '2026-10-28T17:15:00Z',
    'kapasitas': 2,
    'jumlahJanjiTemu': 1,
    'sisaKapasitas': 1,
    'tersedia': true,
    'aktif': true,
    'nested': {
      'values': [1],
    },
  };
  Future<void> initialize() => catalog.refresh(masters.keys);
  Future<void> waitRead(String id, int count) => (reads[id] ?? 0) >= count
      ? Future.value()
      : (readWaiters[(id, count)] ??= Completer<void>()).future;
  http.Response reply(Object value, [int status = 200]) =>
      http.Response(jsonEncode(value), status);
  Future<http.Response> handle(http.Request request) async {
    calls.add(request);
    final path = request.url.path.replaceFirst('/api/v1', '');
    if (path == '/auth/me') return reply(identity);
    if (request.method == 'GET' && path == '/slot-praktik') {
      final id = request.url.queryParameters['jadwalPraktikId']!;
      final count = reads.update(id, (v) => v + 1, ifAbsent: () => 1);
      final response = readError == null
          ? reply(malformedRead ? {'invalid': true} : data[id] ?? [])
          : reply({'message': 'Slot read unavailable'}, readError!);
      readWaiters.remove((id, count))?.complete();
      if (readGates[(id, count)] case final gate?) await gate.future;
      return response;
    }
    if (request.method == 'GET') return reply(masters[path] ?? []);
    if (!path.startsWith('/slot-praktik')) {
      final resource = '/${path.split('/')[1]}';
      final body = request.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(request.body) as Json;
      masters[resource] = [
        for (final row in masters[resource]!)
          path.endsWith('/${row['id']}') ? {...row, ...body} : row,
      ];
      return reply(body);
    }
    final body = request.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(request.body) as Json;
    final id =
        body['jadwalPraktikId'] as String? ??
        data.keys.firstWhere(
          (k) => data[k]!.any((r) => path.contains('/${r['id']}')),
        );
    writeStarted?.complete();
    writeStarted = null;
    if (writeGate case final gate?) await gate.future;
    final row = {'id': 'created-$id', ...body};
    if (writeError == null || commitLost) {
      if (request.method == 'POST') data[id]!.add(row);
      if (request.method == 'PATCH') {
        data[id] = [
          for (final r in data[id]!)
            path.endsWith('/${r['id']}') ? {...r, ...body} : r,
        ];
      }
      if (request.method == 'DELETE') {
        if (path.endsWith('/permanen')) {
          data[id]!.removeWhere((r) => path.contains('/${r['id']}/'));
        } else {
          data[id] = [
            for (final r in data[id]!)
              path.endsWith('/${r['id']}') ? {...r, 'aktif': false} : r,
          ];
        }
      }
    }
    afterWrite?.call();
    if (writeError == 0) {
      throw http.ClientException('Connection lost after send');
    }
    return writeError == null
        ? reply(malformedWrite ? [] : row)
        : reply({'message': 'Slot terisi atau konflik jadwal'}, writeError!);
  }

  void dispose() {
    catalog.dispose();
    api.dispose();
  }
}

void main() {
  setUpAll(tz.initializeTimeZones);
  late SlotFixture f;
  late SlotSessionCubit c;
  setUp(() async {
    f = SlotFixture();
    await f.initialize();
    c = SlotSessionCubit(f.repository, SlotFixture.session('a'));
  });
  tearDown(() async {
    await c.close();
    f.dispose();
  });

  test(
    'construction is lazy; initial load is scoped and recursively immutable',
    () async {
      expect(f.reads, isEmpty);
      expect(c.state.load, SlotLoadStatus.initial);
      await c.refresh();
      expect(c.state.load, SlotLoadStatus.loaded);
      expect(c.state.hasLoaded, isTrue);
      expect(c.state.slots.single['id'], 'slot-a');
      expect(f.calls.last.url.queryParameters, {'jadwalPraktikId': 'a'});
      expect(() => c.state.slots.clear(), throwsUnsupportedError);
      expect(
        () => c.state.slots.single['nested']['values'].add(2),
        throwsUnsupportedError,
      );
      f.data['a']!.single['nested']['values'].add(2);
      expect(c.state.slots.single['nested']['values'], [1]);
    },
  );
  test('loaded empty differs from initial read failure and recovery', () async {
    f.readError = 503;
    await c.refresh();
    expect(c.state.load, SlotLoadStatus.failure);
    expect(c.state.hasLoaded, isFalse);
    expect(c.state.loadError, isA<ApiException>());
    f.readError = null;
    f.data['a'] = [];
    await c.refresh();
    expect(c.state.load, SlotLoadStatus.empty);
    expect(c.state.hasLoaded, isTrue);
  });
  test('refresh failure retains last verified snapshot and explicit refresh recovers', () async {
    await c.refresh();
    f.readError = 503;
    await c.refresh();
    expect(c.state.slots, hasLength(1));
    expect(c.state.load, SlotLoadStatus.failure);
    f.readError = null;
    f.data['a']!.single['kapasitas'] = 3;
    await c.refresh();
    expect(c.state.slots.single['kapasitas'], 3);
    expect(c.state.loadError, isNull);
  });
  for (final malformed in [true, false]) {
    test(
      malformed
          ? 'malformed response is failure, never a false empty state'
          : 'wrong-session response is rejected',
      () async {
        f.malformedRead = malformed;
        if (!malformed) f.data['a'] = [SlotFixture.slot('b')];
        await c.refresh();
        expect(c.state.hasLoaded, isFalse);
        expect(c.state.load, SlotLoadStatus.failure);
      },
    );
  }
  test('single flight, burst invalidation, and every caller waits for trailing completion', () async {
    final firstGate = Completer<void>(), trailingGate = Completer<void>();
    f.readGates[('a', 1)] = firstGate;
    f.readGates[('a', 2)] = trailingGate;
    var completed = false;
    final first = c.refresh().then((_) => completed = true);
    await f.waitRead('a', 1);
    final pending = [for (var i = 0; i < 30; i++) c.refresh()];
    expect(f.reads['a'], 1);
    f.data['a']!.single['kapasitas'] = 7;
    firstGate.complete();
    await f.waitRead('a', 2);
    expect(completed, isFalse);
    expect(c.state.slots, isEmpty);
    trailingGate.complete();
    await Future.wait([first, ...pending]);
    expect(f.reads['a'], 2);
    expect(c.state.slots.single['kapasitas'], 7);
  });
  test(
    'invalidation during trailing request requires a further serialized read',
    () async {
      final firstGate = Completer<void>(), secondGate = Completer<void>();
      f.readGates[('a', 1)] = firstGate;
      f.readGates[('a', 2)] = secondGate;
      final pending = c.refresh();
      await f.waitRead('a', 1);
      c.refresh();
      firstGate.complete();
      await f.waitRead('a', 2);
      c.refresh();
      f.data['a']!.single['kapasitas'] = 9;
      secondGate.complete();
      await pending;
      expect(f.reads['a'], 3);
      expect(c.state.slots.single['kapasitas'], 9);
    },
  );
  test('collapsed invalidations defer fetch until expanded', () async {
    c.invalidate();
    c.invalidate();
    expect(f.reads, isEmpty);
    c.setExpanded(true);
    await c.refresh();
    final before = f.reads['a']!;
    c.setExpanded(false);
    c.invalidate();
    expect(f.reads['a'], before);
    c.setExpanded(true);
    await c.refresh();
    expect(f.reads['a'], greaterThan(before));
  });
  test('two sessions and out-of-order responses never mix snapshots', () async {
    final other = SlotSessionCubit(f.repository, SlotFixture.session('b'));
    final gate = Completer<void>();
    f.readGates[('a', 1)] = gate;
    final old = c.refresh();
    await f.waitRead('a', 1);
    await other.refresh();
    expect(other.state.slots.single['id'], 'slot-b');
    expect(c.state.slots, isEmpty);
    gate.complete();
    await old;
    expect(c.state.slots.single['id'], 'slot-a');
    await other.close();
  });
  for (final ending in ['close', 'logout', 'account', 'role', 'removed']) {
    test(
      '$ending during a pending read discards old response and cleans listener',
      () async {
        final gate = Completer<void>();
        f.readGates[('a', 1)] = gate;
        final pending = c.refresh();
        await f.waitRead('a', 1);
        if (ending == 'close') {
          await c.close();
        }
        if (ending == 'logout') {
          await f.api.clearSession();
        }
        if (ending == 'account' || ending == 'role') {
          f.identity = {
            'id': ending == 'account' ? 'other-admin' : 'admin',
            'peran': ending == 'role' ? 'USER' : 'ADMIN',
          };
          await f.api.reloadOwnProfile();
        }
        if (ending == 'removed') {
          f.masters['/jadwal-praktik'] = [SlotFixture.session('b')];
          await f.catalog.refresh(['/jadwal-praktik']);
        }
        gate.complete();
        await pending;
        expect(c.state.slots, isEmpty);
        expect(c.isClosed, isTrue);
        if (ending != 'close') {
          expect(
            c.state.load,
            ending == 'removed'
                ? SlotLoadStatus.sessionRemoved
                : SlotLoadStatus.sessionEnded,
          );
        }
      },
    );
  }
  for (final path in [
    '/jadwal-praktik',
    '/jadwal-layanan',
    '/layanan',
    '/dokter',
    '/loket',
  ]) {
    test(
      '$path dependency change refreshes only an open relevant session',
      () async {
        c.setExpanded(true);
        await c.refresh();
        final before = f.reads['a']!;
        f.masters[path] = [
          for (final r in f.masters[path]!) {...r, 'aktif': false},
        ];
        await f.catalog.refresh([path]);
        await c.refresh();
        expect(f.reads['a'], greaterThan(before));
        expect(f.reads['b'], isNull);
      },
    );
  }
  test(
    'unrelated sessions/catalog and identical snapshots do not refetch slots',
    () async {
      c.setExpanded(true);
      await c.refresh();
      final before = f.reads['a'];
      f.masters['/jadwal-praktik'] = [
        SlotFixture.session('a'),
        {...SlotFixture.session('b'), 'aktif': false},
      ];
      await f.catalog.refresh(f.masters.keys);
      expect(f.reads['a'], before);
    },
  );
  test('dependency invalidation while initial read runs keeps required trailing read', () async {
    final gate = Completer<void>();
    f.readGates[('a', 1)] = gate;
    c.setExpanded(true);
    await f.waitRead('a', 1);
    f.masters['/jadwal-layanan']!.single['kapasitasHarian'] = 30;
    await f.catalog.refresh(['/jadwal-layanan']);
    f.data['a']!.single['tersedia'] = false;
    final pending = c.refresh();
    gate.complete();
    await pending;
    expect(f.reads['a'], 2);
    expect(c.state.slots.single['tersedia'], isFalse);
  });
  for (final action in ['create', 'update', 'deactivate', 'delete']) {
    for (final reject in [false, true]) {
      test(
        '$action ${reject ? 'backend conflict retains authoritative slot' : 'uses existing endpoint/payload and reconciles'}',
        () async {
          await c.refresh();
          f.writeError = reject ? 409 : null;
          final Future<Json> operation = switch (action) {
            'create' => c.save({
              'jadwalPraktikId': 'a',
              'mulaiPada': '2026-10-28T17:15:00Z',
              'selesaiPada': '2026-10-28T17:30:00Z',
              'kapasitas': 2,
            }),
            'update' => c.save({'kapasitas': 3}, id: 'slot-a'),
            'deactivate' => c.deactivate('slot-a'),
            _ => c.delete('slot-a'),
          };
          if (reject) {
            await expectLater(
              operation,
              throwsA(
                isA<ApiException>().having((e) => e.status, 'status', 409),
              ),
            );
          } else {
            await operation;
          }
          final write = f.calls.lastWhere((r) => r.method != 'GET');
          expect(
            write.url.path,
            '/api/v1/slot-praktik${action == 'create' ? '' : '/slot-a'}${action == 'delete' ? '/permanen' : ''}',
          );
          expect(
            c.state.mutation,
            reject ? SlotMutationStatus.failure : SlotMutationStatus.success,
          );
          expect(
            c.state.slots.length,
            reject
                ? 1
                : action == 'create'
                ? 2
                : action == 'delete'
                ? 0
                : 1,
          );
          if (action == 'update') {
            expect(jsonDecode(write.body), {'kapasitas': 3});
          }
          if (action == 'create') {
            expect(jsonDecode(write.body)['mulaiPada'], '2026-10-28T17:15:00Z');
          }
        },
      );
    }
  }
  for (final committed in [false, true]) {
    test(
      'timeout committed=$committed reconciles without retry and keeps unknown outcome',
      () async {
        f.writeError = 0;
        f.commitLost = committed;
        await expectLater(
          c.save({'kapasitas': 4}, id: 'slot-a'),
          throwsA(isA<ApiException>()),
        );
        expect(c.state.slots.single['kapasitas'], committed ? 4 : 2);
        expect(c.state.mutation, SlotMutationStatus.unknown);
        expect(c.state.needsReconciliation, isFalse);
        expect(f.calls.where((r) => r.method == 'PATCH'), hasLength(1));
      },
    );
  }
  test(
    'failed reconciliation blocks further writes until successful REST read',
    () async {
      f.writeError = 0;
      f.commitLost = true;
      f.afterWrite = () => f.readError = 503;
      await expectLater(
        c.save({'kapasitas': 4}, id: 'slot-a'),
        throwsA(isA<ApiException>()),
      );
      expect(c.state.needsReconciliation, isTrue);
      await expectLater(c.delete('slot-a'), throwsA(isA<ApiException>()));
      expect(f.calls.where((r) => r.method == 'DELETE'), isEmpty);
      f.writeError = null;
      f.afterWrite = null;
      f.readError = null;
      await c.refresh();
      await c.deactivate('slot-a');
      expect(c.state.slots.single['aktif'], isFalse);
    },
  );
  test('double submit blocked while write is pending; close suppresses late mutation emission', () async {
    final gate = Completer<void>();
    f.writeGate = gate;
    final started = f.writeStarted = Completer<void>();
    final operation = expectLater(
      c.save({'kapasitas': 3}, id: 'slot-a'),
      throwsA(isA<ApiException>()),
    );
    await started.future;
    await expectLater(c.delete('slot-a'), throwsA(isA<ApiException>()));
    await c.close();
    gate.complete();
    await operation;
    expect(f.calls.where((r) => r.method != 'GET'), hasLength(1));
  });
  test(
    'late read started before mutation cannot overwrite reconciled slot',
    () async {
      final gate = Completer<void>();
      f.readGates[('a', 1)] = gate;
      final old = c.refresh();
      await f.waitRead('a', 1);
      final started = f.writeStarted = Completer<void>();
      final update = c.save({'kapasitas': 6}, id: 'slot-a');
      await started.future;
      // The transport has no barrier here; wait deterministically for the read
      // invalidation by the mutation's refresh instead of an arbitrary delay.
      f.afterWrite = null;
      final next = c.refresh();
      gate.complete();
      await Future.wait([old, update, next]);
      expect(c.state.slots.single['kapasitas'], 6);
    },
  );
  test(
    'repository rejects mismatched create session without sending a write',
    () async {
      await expectLater(
        c.save({'jadwalPraktikId': 'b'}),
        throwsA(isA<ApiException>()),
      );
      expect(f.calls.where((r) => r.method != 'GET'), isEmpty);
    },
  );
  test(
    'changed doctor or clinic context clears old slots before new read applies',
    () async {
      await c.refresh();
      c.setExpanded(true);
      final gate = Completer<void>();
      f.readGates[('a', 2)] = gate;
      f.masters['/jadwal-praktik'] = [
        {
          ...SlotFixture.session('a'),
          'dokterLayananId': 'different-link',
          'dokterLayanan': {
            'layananId': 'different-clinic',
            'dokterId': 'different-doctor',
          },
        },
        SlotFixture.session('b'),
      ];
      await f.catalog.refresh(['/jadwal-praktik']);
      await f.waitRead('a', 2);
      expect(c.state.slots, isEmpty);
      expect(c.state.hasLoaded, isFalse);
      gate.complete();
      await c.settled;
      expect(c.state.slots.single['id'], 'slot-a');
    },
  );
  test('successful server write is retained when reconciliation fails and later writes are blocked', () async {
    f.afterWrite = () => f.readError = 503;
    await c.save({'kapasitas': 8}, id: 'slot-a');
    expect(c.state.mutation, SlotMutationStatus.success);
    expect(c.state.needsReconciliation, isTrue);
    expect(f.data['a']!.single['kapasitas'], 8);
    await expectLater(c.delete('slot-a'), throwsA(isA<ApiException>()));
    f.afterWrite = null;
    f.readError = null;
    await c.refresh();
    expect(c.state.slots.single['kapasitas'], 8);
    expect(c.state.needsReconciliation, isFalse);
  });
  test('malformed success response reconciles actual write without automatic retry', () async {
    f.malformedWrite = true;
    await expectLater(
      c.save({'kapasitas': 5}, id: 'slot-a'),
      throwsA(isA<ApiException>()),
    );
    expect(c.state.slots.single['kapasitas'], 5);
    expect(c.state.mutation, SlotMutationStatus.unknown);
    expect(f.calls.where((r) => r.method == 'PATCH'), hasLength(1));
  });
  for (final logout in [true, false]) {
    test(
      logout
          ? 'logout during write clears old slot state'
          : 'account change during write ignores old result',
      () async {
        await c.refresh();
        final gate = Completer<void>();
        f.writeGate = gate;
        final started = f.writeStarted = Completer<void>();
        final checked = expectLater(
          c.save({'kapasitas': 3}, id: 'slot-a'),
          throwsA(isA<ApiException>()),
        );
        await started.future;
        if (logout) {
          await f.api.clearSession();
        } else {
          f.identity = {'id': 'next-admin', 'peran': 'ADMIN'};
          await f.api.reloadOwnProfile();
        }
        gate.complete();
        await checked;
        expect(c.state.slots, isEmpty);
        expect(c.state.load, SlotLoadStatus.sessionEnded);
      },
    );
  }
}
