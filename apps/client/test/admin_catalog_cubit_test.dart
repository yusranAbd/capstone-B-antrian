import 'dart:async';
import 'dart:convert';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:queueb_client/src/api.dart';
import 'package:queueb_client/src/config.dart';
import 'package:queueb_client/src/features/admin/application/admin_catalog_cubit.dart';
import 'package:queueb_client/src/features/admin/application/admin_catalog_state.dart';
import 'package:queueb_client/src/features/admin/data/admin_catalog_repository.dart';
import 'package:queueb_client/src/features/admin/models/admin_catalog_models.dart';

class CatalogFixture {
  CatalogFixture() {
    api = QueueApi(
      config: AppConfig(apiBaseUrl: 'http://localhost/api/v1', realtime: false),
      client: MockClient(handle),
    )..user = {'id': 'admin-one', 'peran': 'ADMIN'};
    repository = AdminCatalogRepository(api);
  }
  late final QueueApi api;
  late final AdminCatalogRepository repository;
  final requests = <http.Request>[];
  final data = <String, List<Json>>{
    for (final path in adminMasterPaths)
      path: [
        {'id': 'one', 'kode': 'ONE', 'nama': 'Before', 'aktif': true},
      ],
    '/jadwal-praktik': [
      {
        'id': 'schedule',
        'layanan': {'nama': 'Before'},
      },
    ],
  };
  int? failRead, failWrite;
  Completer<void>? readBarrier, writeBarrier;
  bool commitBeforeTimeout = false;
  Object? malformed;
  Json? nextIdentity;
  Future<http.Response> handle(http.Request request) async {
    requests.add(request);
    final path = request.url.path.replaceFirst('/api/v1', '');
    final collection = '/${path.split('/')[1]}';
    if (request.method == 'GET') {
      // Capture before waiting, so the race tests really return stale data.
      final body = jsonEncode(
        path == '/auth/me' ? nextIdentity ?? api.user : data[path] ?? [],
      );
      if (readBarrier case final barrier?) await barrier.future;
      return http.Response(
        failRead == null ? body : '{"message":"Read failed"}',
        failRead ?? 200,
      );
    }
    if (writeBarrier case final barrier?) await barrier.future;
    final body = request.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(request.body) as Json;
    final id = path.split('/').length > 2 ? path.split('/')[2] : 'created';
    final result = {'id': id, ...body};
    if (failWrite == null || commitBeforeTimeout) {
      if (request.method == 'POST') data[collection]!.add(result);
      if (request.method == 'PATCH') {
        data[collection] = [
          for (final row in data[collection]!)
            row['id'] == id ? {...row, ...body} : row,
        ];
        // Mimic the server's embedded relation projection on the next read.
        data['/jadwal-praktik'] = [
          {
            'id': 'schedule',
            'layanan': {'nama': body['nama']},
          },
        ];
      }
      if (request.method == 'DELETE') {
        if (path.endsWith('/permanen')) {
          data[collection]!.removeWhere((row) => row['id'] == id);
        } else {
          data[collection] = [
            for (final row in data[collection]!)
              row['id'] == id ? {...row, 'aktif': false} : row,
          ];
        }
      }
    }
    if (failWrite == 0) throw http.ClientException('Connection lost');
    return http.Response(
      jsonEncode(
        failWrite == null
            ? malformed ?? result
            : {'message': 'Relation conflict'},
      ),
      failWrite ?? 200,
    );
  }

  void dispose() {
    repository.dispose();
    api.dispose();
  }
}

void main() {
  setUpAll(tz.initializeTimeZones);
  late CatalogFixture f;
  setUp(() => f = CatalogFixture());
  tearDown(() => f.dispose());
  final factories =
      <String, AdminCatalogCubit Function(AdminCatalogRepository)>{
        '/layanan': PolyclinicCubit.new,
        '/dokter': DoctorCatalogCubit.new,
        '/loket': RoomCubit.new,
      };
  for (final entry in factories.entries) {
    group(entry.key, () {
      blocTest<AdminCatalogCubit, AdminCatalogState>(
        'initial load and immutable empty state',
        build: () {
          f.data[entry.key] = [];
          return entry.value(f.repository);
        },
        act: (c) => c.refresh(),
        expect: () => [
          isA<AdminCatalogState>().having(
            (s) => s.load,
            'load',
            CatalogLoadStatus.loading,
          ),
          isA<AdminCatalogState>(),
          isA<AdminCatalogState>().having(
            (s) => s.load,
            'load',
            CatalogLoadStatus.loaded,
          ),
        ],
        verify: (c) {
          expect(c.rows, isEmpty);
          expect(c.state.snapshot, same(f.repository.snapshot));
        },
      );

      test(
        'initial error, recovery, and refresh error retain known data',
        () async {
          final c = entry.value(f.repository);
          f.failRead = 503;
          await c.refresh();
          expect(c.state.load, CatalogLoadStatus.failure);
          expect(c.state.loadError, isA<ApiException>());
          expect(c.rows, isEmpty);
          f.failRead = null;
          await c.refresh();
          expect(c.rows.single['nama'], 'Before');
          f.failRead = 503;
          await c.refresh();
          expect(c.rows.single['nama'], 'Before');
          expect(c.state.load, CatalogLoadStatus.failure);
          await c.close();
        },
      );

      for (final action in ['create', 'update', 'delete']) {
        Future<Json> run(AdminCatalogCubit c) => switch (action) {
          'create' => c.save({
            'nama': 'New',
            'aktif': true,
            'kapasitas': 2,
            'deskripsi': null,
          }),
          'update' => c.save({'nama': 'Updated', 'aktif': false}, id: 'one'),
          _ => c.delete('one'),
        };
        test('$action succeeds and reconciles server catalog', () async {
          final c = entry.value(f.repository);
          await c.refresh();
          final before = f.requests.length;
          await run(c);
          expect(c.state.mutation, CatalogMutationStatus.success);
          final write = f.requests[before];
          expect(
            write.url.path,
            '/api/v1${entry.key}${action == 'create' ? '' : '/one'}${action == 'delete' ? '/permanen' : ''}',
          );
          expect(
            write.method,
            action == 'create'
                ? 'POST'
                : action == 'update'
                ? 'PATCH'
                : 'DELETE',
          );
          if (action == 'create') {
            expect(c.rows.length, 2);
            expect(jsonDecode(write.body), {
              'nama': 'New',
              'aktif': true,
              'kapasitas': 2,
              'deskripsi': null,
            });
          } else if (action == 'update') {
            expect(c.rows.single['nama'], 'Updated');
          } else {
            expect(c.rows, isEmpty);
          }
          expect(
            f.requests.skip(before + 1).every((r) => r.method == 'GET'),
            isTrue,
          );
          await c.close();
        });
        test(
          '$action backend rejection preserves data and typed error',
          () async {
            final c = entry.value(f.repository);
            await c.refresh();
            final snapshot = f.repository.snapshot;
            f.failWrite = 409;
            await expectLater(
              run(c),
              throwsA(
                isA<ApiException>().having((e) => e.status, 'status', 409),
              ),
            );
            expect(c.state.mutation, CatalogMutationStatus.failure);
            expect(c.state.snapshot, same(snapshot));
            expect(c.rows.single['nama'], 'Before');
            await c.close();
          },
        );
      }
      test('double-submit is blocked while mutation awaits server', () async {
        final c = entry.value(f.repository);
        final barrier = Completer<void>();
        f.writeBarrier = barrier;
        final first = c.save({'nama': 'New'});
        await expectLater(
          c.save({'nama': 'New'}),
          throwsA(isA<ApiException>()),
        );
        await Future<void>.delayed(Duration.zero);
        expect(f.requests.where((r) => r.method == 'POST').length, 1);
        barrier.complete();
        await first;
        await c.close();
      });
    });
  }

  test('burst refresh retains one trailing read, without parallel requests for a path', () async {
    final c = PolyclinicCubit(f.repository);
    final barrier = Completer<void>();
    f.readBarrier = barrier;
    final pending = c.refresh(paths: ['/layanan']);
    final waiting = <Future<void>>[];
    for (var i = 0; i < 20; i++) {
      waiting.add(c.refresh(paths: ['/layanan']));
    }
    await Future<void>.delayed(Duration.zero);
    expect(f.requests.length, 1);
    f.data['/layanan'] = [
      {'id': 'new', 'nama': 'Latest'},
    ];
    f.readBarrier = null;
    barrier.complete();
    await Future.wait([pending, ...waiting]);
    expect(f.requests.length, 2);
    expect(c.rows.single['nama'], 'Latest');
    await c.close();
  });

  test(
    'all Cubits and legacy reader share a single reconciled snapshot',
    () async {
      final cubits = [
        PolyclinicCubit(f.repository),
        DoctorCatalogCubit(f.repository),
        RoomCubit(f.repository),
      ];
      await f.repository.refresh([...adminMasterPaths, '/jadwal-praktik']);
      await cubits.first.save({'nama': 'Renamed'}, id: 'one');
      for (final c in cubits) {
        expect(c.state.snapshot, same(f.repository.snapshot));
      }
      expect(
        f.repository.snapshot
            .rowsFor('/jadwal-praktik')
            .single['layanan']['nama'],
        'Renamed',
      );
      expect(f.requests.where((r) => r.method == 'PATCH').length, 1);
      for (final c in cubits) {
        await c.close();
      }
    },
  );

  test(
    'timeout can commit: reconcile before unlocking, never auto POST again',
    () async {
      final c = PolyclinicCubit(f.repository);
      f.failWrite = 0;
      f.commitBeforeTimeout = true;
      final barrier = Completer<void>();
      f.readBarrier = barrier;
      final pending = c.save({'nama': 'Committed'});
      final assertion = expectLater(
        pending,
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 0)),
      );
      await Future<void>.delayed(Duration.zero);
      expect(c.state.mutation, CatalogMutationStatus.submitting);
      await expectLater(
        c.save({'nama': 'Duplicate'}),
        throwsA(isA<ApiException>()),
      );
      f.readBarrier = null;
      barrier.complete();
      await assertion;
      expect(c.rows.any((r) => r['nama'] == 'Committed'), isTrue);
      expect(f.requests.where((r) => r.method == 'POST').length, 1);
      await c.close();
    },
  );

  test(
    'failed reconciliation blocks further writes until a successful reload',
    () async {
      final c = RoomCubit(f.repository);
      await c.refresh();
      f.failWrite = 0;
      f.failRead = 503;
      await expectLater(
        c.save({'nama': 'Unknown'}),
        throwsA(isA<ApiException>()),
      );
      expect(c.state.needsReconciliation, isTrue);
      await expectLater(c.delete('one'), throwsA(isA<ApiException>()));
      expect(f.requests.where((r) => r.method == 'DELETE'), isEmpty);
      f.failWrite = null;
      f.failRead = null;
      await c.refresh();
      expect(c.state.needsReconciliation, isFalse);
      await c.deactivate('one');
      expect(c.rows.single['aktif'], isFalse);
      expect(
        f.requests.lastWhere((r) => r.method == 'DELETE').url.path,
        '/api/v1/loket/one',
      );
      await c.close();
    },
  );

  test(
    'server success with reload failure remains success plus refresh error',
    () async {
      final c = DoctorCatalogCubit(f.repository);
      await c.refresh();
      f.failRead = 503;
      final result = await c.save({'nama': 'Saved'});
      expect(result['id'], 'created');
      expect(c.state.mutation, CatalogMutationStatus.success);
      expect(c.state.loadError, isA<ApiException>());
      expect(c.rows.length, 1);
      expect(c.state.needsReconciliation, isTrue);
      await c.close();
    },
  );

  for (final close in [true, false]) {
    test(
      close
          ? 'close during request suppresses late emission'
          : 'logout clears all consumers during request',
      () async {
        final c = PolyclinicCubit(f.repository);
        final barrier = Completer<void>();
        f.readBarrier = barrier;
        final pending = c.refresh();
        if (close) {
          await c.close();
        } else {
          await f.api.clearSession();
          expect(c.state.load, CatalogLoadStatus.sessionEnded);
        }
        f.readBarrier = null;
        barrier.complete();
        await pending;
        expect(c.rows, isEmpty);
        if (!close) {
          expect(f.repository.snapshot.collections, isEmpty);
          await c.close();
        }
      },
    );
  }

  test('account change rejects old response and new repository reads new context', () async {
    final c = PolyclinicCubit(f.repository);
    final barrier = Completer<void>();
    f.readBarrier = barrier;
    final pending = c.refresh();
    f.api.user = {'id': 'admin-two', 'peran': 'ADMIN'};
    // QueueApi publishes identity through its existing profile API in widgets;
    // the repository also checks identity at every response boundary.
    f.readBarrier = null;
    barrier.complete();
    await pending;
    expect(c.rows, isEmpty);
    expect(f.repository.active, isFalse);
    await c.close();
    final fresh = AdminCatalogRepository(f.api);
    await fresh.refresh(['/layanan']);
    expect(fresh.snapshot.rowsFor('/layanan'), isNotEmpty);
    fresh.dispose();
  });

  test('mutation reconciles after an older GET completes without overwriting new data', () async {
    final c = PolyclinicCubit(f.repository);
    await c.refresh();
    final barrier = Completer<void>();
    f.readBarrier = barrier;
    final oldRead = c.refresh(paths: ['/layanan']);
    await Future<void>.delayed(Duration.zero);
    final mutation = c.save({'nama': 'After mutation'}, id: 'one');
    await Future<void>.delayed(Duration.zero);
    f.readBarrier = null;
    barrier.complete();
    await Future.wait([oldRead, mutation]);
    expect(c.rows.single['nama'], 'After mutation');
    expect(c.state.mutation, CatalogMutationStatus.success);
    await c.close();
  });

  test(
    'closing while mutation runs keeps catalog consistent without late emit',
    () async {
      final c = RoomCubit(f.repository);
      final barrier = Completer<void>();
      f.writeBarrier = barrier;
      final pending = c.save({'nama': 'Room'});
      final checked = expectLater(pending, throwsA(isA<ApiException>()));
      await Future<void>.delayed(Duration.zero);
      await c.close();
      barrier.complete();
      await checked;
      expect(c.isClosed, isTrue);
      expect(f.repository.snapshot.rowsFor('/loket').length, 2);
    },
  );

  for (final identity in [
    {'id': 'admin-two', 'peran': 'ADMIN'},
    {'id': 'admin-one', 'peran': 'USER'},
  ]) {
    test('published identity change clears catalog: $identity', () async {
      final c = PolyclinicCubit(f.repository);
      await c.refresh();
      f.nextIdentity = identity;
      await f.api.reloadOwnProfile();
      expect(c.state.load, CatalogLoadStatus.sessionEnded);
      expect(c.state.snapshot.collections, isEmpty);
      await c.close();
    });
  }

  test(
    'malformed success response is uncertain and is reconciled without retry',
    () async {
      final c = DoctorCatalogCubit(f.repository);
      f.malformed = [];
      await expectLater(
        c.save({'nama': 'Saved'}),
        throwsA(isA<ApiException>()),
      );
      expect(c.rows.any((r) => r['nama'] == 'Saved'), isTrue);
      expect(c.state.mutation, CatalogMutationStatus.failure);
      expect(f.requests.where((r) => r.method == 'POST').length, 1);
      await c.close();
    },
  );

  test('recursive immutability and detached input snapshot', () {
    final row = <String, dynamic>{
      'id': 'one',
      'links': [
        {'nama': 'Original'},
      ],
    };
    final source = <String, List<Json>>{
      '/layanan': [row],
    };
    final snapshot = AdminCatalogSnapshot(source);
    row['links'].clear();
    source.clear();
    expect(snapshot.rowsFor('/layanan').single['links'].length, 1);
    expect(() => snapshot.collections.clear(), throwsUnsupportedError);
    expect(() => snapshot.rowsFor('/layanan').clear(), throwsUnsupportedError);
    expect(
      () => snapshot.rowsFor('/layanan').single['links'][0]['nama'] = 'Changed',
      throwsUnsupportedError,
    );
  });
}
