import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:queueb_client/src/api.dart';
import 'package:queueb_client/src/config.dart';
import 'package:queueb_client/src/features/admin/data/admin_catalog_repository.dart';
import 'package:queueb_client/src/features/admin/data/admin_schedule_repository.dart';
import 'package:queueb_client/src/features/admin/application/admin_catalog_cubit.dart';
import 'package:queueb_client/src/features/admin/application/admin_catalog_state.dart';
import 'package:queueb_client/src/features/admin/application/practice_schedule_cubit.dart';
import 'package:queueb_client/src/features/admin/application/schedule_batch_cubit.dart';
import 'package:queueb_client/src/features/admin/application/schedule_batch_state.dart';
import 'package:queueb_client/src/features/admin/models/admin_schedule_models.dart';

class SchedulingFixture {
  SchedulingFixture() {
    api = QueueApi(
      config: AppConfig(apiBaseUrl: 'http://localhost/api/v1', realtime: false),
      client: MockClient(handle),
    )..user = {'id': 'admin', 'peran': 'ADMIN'};
    catalog = AdminCatalogRepository(api);
    schedules = AdminScheduleRepository(catalog);
  }
  late final QueueApi api;
  late final AdminCatalogRepository catalog;
  late final AdminScheduleRepository schedules;
  final calls = <http.Request>[];
  final data = <String, List<Json>>{
    '/layanan': [
      {'id': 'clinic', 'nama': 'Clinic', 'aktif': true},
    ],
    '/dokter': [],
    '/loket': [],
    '/jadwal-layanan': [],
    '/jadwal-praktik': [],
  };
  final dayFailures = <String, int>{};
  final committedDays = <String>{};
  bool commitLostWrite = false;
  void Function()? afterWrite;
  int? readFailure, writeFailure;
  int serial = 0;
  Completer<void>? readGate, writeGate;
  Future<http.Response> handle(http.Request request) async {
    calls.add(request);
    final path = request.url.path.replaceFirst('/api/v1', '');
    if (request.method == 'GET') {
      final encoded = jsonEncode(data[path] ?? []);
      if (readGate case final gate?) await gate.future;
      return http.Response(
        readFailure == null ? encoded : '{"message":"Read unavailable"}',
        readFailure ?? 200,
      );
    }
    final body = request.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(request.body) as Json;
    if (writeGate case final gate?) await gate.future;
    final resource = '/${path.split('/')[1]}';
    final code = resource == '/jadwal-layanan'
        ? dayFailures[body['hari']] ?? writeFailure
        : writeFailure;
    final id = path.split('/').length > 2
        ? path.split('/')[2]
        : 'new-${++serial}';
    final row = {'id': id, ...body};
    if (code == null ||
        committedDays.contains(body['hari']) ||
        commitLostWrite) {
      if (request.method == 'POST') data[resource]!.add(row);
      if (request.method == 'PATCH') {
        data[resource] = [
          for (final old in data[resource]!)
            old['id'] == id ? {...old, ...body} : old,
        ];
      }
      if (request.method == 'DELETE') {
        if (path.endsWith('/permanen')) {
          data[resource]!.removeWhere((r) => r['id'] == id);
        } else {
          data[resource] = [
            for (final old in data[resource]!)
              old['id'] == id ? {...old, 'aktif': false} : old,
          ];
        }
      }
    }
    afterWrite?.call();
    if (code == 0) throw http.ClientException('Response lost');
    return http.Response(
      jsonEncode(
        code == null ? row : {'message': 'Schedule conflict or linked slots'},
      ),
      code ?? 200,
    );
  }

  List<http.Request> get posts =>
      calls.where((r) => r.method == 'POST').toList();
  Future<void> run(
    ScheduleBatchCubit cubit, {
    Set<String> days = const {'SENIN', 'SELASA', 'RABU'},
  }) => cubit.submit(
    clinicId: 'clinic',
    days: days,
    opens: '08:00',
    closes: '16:00',
    capacity: 24,
  );
  void dispose() {
    catalog.dispose();
    api.dispose();
  }
}

void main() {
  setUpAll(tz.initializeTimeZones);
  late SchedulingFixture f;
  setUp(() => f = SchedulingFixture());
  tearDown(() => f.dispose());

  for (final practice in [false, true]) {
    group(practice ? 'Practice' : 'Service hours', () {
      AdminCatalogCubit create() => practice
          ? PracticeScheduleCubit(f.schedules)
          : ServiceScheduleCubit(f.schedules);
      final path = practice ? '/jadwal-praktik' : '/jadwal-layanan';
      test('initial load, refresh failure with data, recovery and immutable records', () async {
        final c = create();
        f.readFailure = 503;
        await c.refresh();
        expect(c.state.load, CatalogLoadStatus.failure);
        f.readFailure = null;
        f.data[path] = [
          {
            'id': 'one',
            'ruang': {'nama': 'Room'},
          },
        ];
        await c.refresh();
        expect(c.state.load, CatalogLoadStatus.loaded);
        expect(c.rows.length, 1);
        expect(
          () => c.rows.single['ruang']['nama'] = 'Changed',
          throwsUnsupportedError,
        );
        f.readFailure = 503;
        await c.refresh();
        expect(c.rows.length, 1);
        expect(c.state.loadError, isA<ApiException>());
        await c.close();
      });
      for (final action in ['create', 'update', 'delete']) {
        Future<Json> run(AdminCatalogCubit c) => switch (action) {
          'create' => c.save(
            practice
                ? {
                    'dokterLayananId': 'link',
                    'loketId': 'room',
                    'tanggal': '2026-10-29',
                    'mulaiPada': '2026-10-28T17:00:00.000Z',
                    'selesaiPada': '2026-10-28T18:00:00.000Z',
                  }
                : {
                    'layananId': 'clinic',
                    'hari': 'SENIN',
                    'jamBuka': '08:00',
                    'jamTutup': '16:00',
                    'kapasitasHarian': 24,
                  },
          ),
          'update' => c.save({'aktif': false}, id: 'one'),
          _ => c.delete('one'),
        };
        for (final reject in [false, true]) {
          test(
            '$action ${reject ? 'rejects conflict' : 'succeeds and reconciles'}',
            () async {
              final c = create();
              f.data[path] = [
                {'id': 'one', 'aktif': true},
              ];
              await c.refresh();
              final before = f.catalog.snapshot;
              f.writeFailure = reject ? 409 : null;
              if (reject) {
                await expectLater(
                  run(c),
                  throwsA(
                    isA<ApiException>().having((e) => e.status, 'status', 409),
                  ),
                );
                expect(c.state.mutation, CatalogMutationStatus.failure);
                expect(c.state.snapshot, same(before));
                expect(c.rows.single['id'], 'one');
              } else {
                await run(c);
                expect(c.state.mutation, CatalogMutationStatus.success);
                expect(
                  c.rows.length,
                  action == 'create'
                      ? 2
                      : action == 'delete'
                      ? 0
                      : 1,
                );
              }
              final write = f.calls.firstWhere((r) => r.method != 'GET');
              expect(
                write.url.path,
                '/api/v1$path${action == 'create' ? '' : '/one'}${action == 'delete' ? '/permanen' : ''}',
              );
              if (action == 'update') {
                expect(jsonDecode(write.body), {'aktif': false});
              }
              if (practice && action == 'create') {
                final body = jsonDecode(write.body);
                expect(body['tanggal'], '2026-10-29');
                expect(body['mulaiPada'], '2026-10-28T17:00:00.000Z');
              }
              expect(
                f.calls.any((r) => r.url.path.contains('slot-praktik')),
                isFalse,
              );
              await c.close();
            },
          );
        }
      }
      test(
        'invalidations during pending fetch retain a trailing read',
        () async {
          final c = create();
          final gate = Completer<void>();
          f.readGate = gate;
          final first = c.refresh(paths: [path]);
          await Future<void>.delayed(Duration.zero);
          final pending = [
            for (var i = 0; i < 20; i++) c.refresh(paths: [path]),
          ];
          f.data[path] = [
            {'id': 'latest'},
          ];
          f.readGate = null;
          gate.complete();
          await Future.wait([first, ...pending]);
          expect(f.calls.length, 2);
          expect(c.rows.single['id'], 'latest');
          await c.close();
        },
      );
      test('write before initial read still reconciles the resource', () async {
        final c = create();
        if (practice) {
          // An uncertain write to another not-yet-cached scheduling resource
          // must also be verified before reconciliation clears its guard.
          f.writeFailure = 0;
          f.commitLostWrite = true;
          await expectLater(
            f.schedules.write(
              '/jadwal-layanan',
              'POST',
              body: {'hari': 'SENIN'},
            ),
            throwsA(isA<ApiException>()),
          );
          f.writeFailure = null;
          f.commitLostWrite = false;
        }
        await c.save({'hari': 'SENIN'});
        expect(c.rows, hasLength(1));
        if (practice) {
          expect(f.catalog.snapshot.rowsFor('/jadwal-layanan'), hasLength(1));
        }
        await c.close();
      });
      test(
        'lost committed response reconciles without retrying the write',
        () async {
          final c = create();
          f.writeFailure = 0;
          f.commitLostWrite = true;
          await expectLater(
            c.save({'hari': 'SENIN'}),
            throwsA(isA<ApiException>()),
          );
          expect(c.rows, hasLength(1));
          expect(c.state.mutation, CatalogMutationStatus.failure);
          expect(c.state.needsReconciliation, isFalse);
          expect(f.posts, hasLength(1));
          await c.close();
        },
      );
      test('double submit is rejected and failed reconciliation blocks until refresh', () async {
        final c = create(), gate = Completer<void>();
        f.writeGate = gate;
        final pending = c.save({'hari': 'SENIN'});
        await expectLater(
          c.save({'hari': 'SELASA'}),
          throwsA(isA<ApiException>()),
        );
        await Future<void>.delayed(Duration.zero);
        expect(f.posts, hasLength(1));
        f.afterWrite = () => f.readFailure = 503;
        gate.complete();
        await pending;
        expect(c.state.needsReconciliation, isTrue);
        await expectLater(c.delete('one'), throwsA(isA<ApiException>()));
        expect(f.calls.where((r) => r.method == 'DELETE'), isEmpty);
        f.readFailure = null;
        f.afterWrite = null;
        await c.refresh();
        expect(c.rows, hasLength(1));
        expect(c.state.needsReconciliation, isFalse);
        await c.close();
      });
      test('older read cannot overwrite successful mutation', () async {
        final c = create();
        await c.refresh();
        final gate = Completer<void>();
        f.readGate = gate;
        final old = c.refresh(paths: [path]);
        final write = c.save({'hari': 'SENIN'});
        await Future<void>.delayed(Duration.zero);
        f.readGate = null;
        gate.complete();
        await Future.wait([old, write]);
        expect(c.rows, hasLength(1));
        await c.close();
      });
      test(
        'account changes invalidate old read and fresh scope loads separately',
        () async {
          final c = create(), gate = Completer<void>();
          f.readGate = gate;
          final pending = c.refresh();
          f.api.user = {'id': 'another-admin', 'peran': 'ADMIN'};
          gate.complete();
          await pending;
          expect(c.rows, isEmpty);
          expect(f.catalog.active, isFalse);
          final fresh = AdminCatalogRepository(f.api);
          await fresh.refresh([path]);
          expect(fresh.snapshot.collections.containsKey(path), isTrue);
          fresh.dispose();
          await c.close();
        },
      );
      test('closing during write suppresses emission but reconciles shared catalog', () async {
        final c = create(), gate = Completer<void>();
        f.writeGate = gate;
        final checked = expectLater(
          c.save({'hari': 'SENIN'}),
          throwsA(isA<ApiException>()),
        );
        await c.close();
        gate.complete();
        await checked;
        expect(f.catalog.snapshot.rowsFor(path), hasLength(1));
        expect(c.rows, isEmpty);
      });
      for (final logout in [true, false]) {
        test(
          logout
              ? 'logout discards old context response'
              : 'close discards response',
          () async {
            final c = create();
            final gate = Completer<void>();
            f.readGate = gate;
            final pending = c.refresh();
            if (logout) {
              await f.api.clearSession();
            } else {
              await c.close();
            }
            f.readGate = null;
            gate.complete();
            await pending;
            expect(c.rows, isEmpty);
            if (logout) {
              expect(c.state.load, CatalogLoadStatus.sessionEnded);
              await c.close();
            }
          },
        );
      }
    });
  }

  group('Multi-day batch', () {
    test('final reconciliation failure keeps per-day success and guards shared CRUD', () async {
      final c = ScheduleBatchCubit(f.schedules);
      f.afterWrite = () => f.readFailure = 503;
      await f.run(c, days: {'SENIN'});
      expect(c.state.results.single.outcome, ScheduleOutcome.created);
      expect(c.state.status, ScheduleBatchStatus.partial);
      expect(c.state.error, contains('Hasil per hari dipertahankan'));
      await expectLater(
        f.schedules.write('/jadwal-layanan', 'DELETE', id: 'one'),
        throwsA(isA<ApiException>()),
      );
      f.readFailure = null;
      f.afterWrite = null;
      final list = ServiceScheduleCubit(f.schedules);
      await list.refresh(paths: ['/layanan']);
      await expectLater(
        f.schedules.write('/jadwal-layanan', 'DELETE', id: 'one'),
        throwsA(isA<ApiException>()),
      );
      await list.refresh();
      await list.deactivate('new-1');
      expect(list.rows.single['aktif'], isFalse);
      await list.close();
      await c.close();
    });
    test('all success, ordered days, accurate progress, and completed dialog cannot replay', () async {
      final c = ScheduleBatchCubit(f.schedules), counts = <int>[];
      final sub = c.stream.listen((s) {
        if (s.results.isNotEmpty) counts.add(s.results.length);
      });
      await f.run(c, days: {'RABU', 'SELASA', 'SENIN'});
      expect(c.state.status, ScheduleBatchStatus.success);
      expect(c.state.finished, isTrue);
      expect(f.posts.map((r) => jsonDecode(r.body)['hari']), [
        'SENIN',
        'SELASA',
        'RABU',
      ]);
      expect(counts, containsAllInOrder([1, 2, 3]));
      expect(jsonDecode(f.posts.first.body)['kapasitasHarian'], 24);
      await f.run(c);
      expect(f.posts.length, 3);
      expect(() => c.state.results.clear(), throwsUnsupportedError);
      await sub.cancel();
      await c.close();
    });
    test('partial success and explicit new dialog retry skip successful/inactive days', () async {
      f.dayFailures['SELASA'] = 400;
      final c = ScheduleBatchCubit(f.schedules);
      await f.run(c);
      expect(c.state.status, ScheduleBatchStatus.partial);
      expect(c.state.results.map((r) => r.outcome), [
        ScheduleOutcome.created,
        ScheduleOutcome.failed,
        ScheduleOutcome.created,
      ]);
      await c.close();
      f.dayFailures.clear();
      f.data['/jadwal-layanan']!.first['aktif'] = false;
      final retry = ScheduleBatchCubit(f.schedules);
      await f.run(retry);
      expect(f.posts.map((r) => jsonDecode(r.body)['hari']), [
        'SENIN',
        'SELASA',
        'RABU',
        'SELASA',
      ]);
      expect(retry.state.results.map((r) => r.outcome), [
        ScheduleOutcome.existing,
        ScheduleOutcome.created,
        ScheduleOutcome.existing,
      ]);
      await retry.close();
    });
    test('all backend failures are not reported as success', () async {
      f.dayFailures.addAll({for (final d in scheduleDays) d: 400});
      final c = ScheduleBatchCubit(f.schedules);
      await f.run(c);
      expect(c.state.status, ScheduleBatchStatus.failure);
      expect(
        c.state.results.every((r) => r.outcome == ScheduleOutcome.failed),
        isTrue,
      );
      await c.close();
    });
    for (final committed in [false, true]) {
      test(
        'response lost after partial processing; committed=$committed; never retries POST',
        () async {
          f.dayFailures['SELASA'] = 0;
          if (committed) f.committedDays.add('SELASA');
          final c = ScheduleBatchCubit(f.schedules);
          await f.run(c);
          expect(c.state.results[0].outcome, ScheduleOutcome.created);
          expect(
            c.state.results[1].outcome,
            committed ? ScheduleOutcome.existing : ScheduleOutcome.uncertain,
          );
          expect(c.state.results[2].outcome, ScheduleOutcome.created);
          expect(f.posts.length, 3);
          expect(
            f.calls
                .where(
                  (r) =>
                      r.method == 'GET' &&
                      r.url.path.endsWith('/jadwal-layanan'),
                )
                .length,
            3,
          );
          await c.close();
        },
      );
    }
    test(
      'preflight failure sends no writes and permits explicit retry',
      () async {
        final c = ScheduleBatchCubit(f.schedules);
        f.readFailure = 503;
        await f.run(c);
        expect(c.state.status, ScheduleBatchStatus.failure);
        expect(c.state.finished, isFalse);
        expect(f.posts, isEmpty);
        f.readFailure = null;
        await f.run(c);
        expect(c.state.status, ScheduleBatchStatus.success);
        await c.close();
      },
    );
    test(
      'double-submit and conflicting CRUD are locked while batch writes',
      () async {
        final c = ScheduleBatchCubit(f.schedules);
        final gate = Completer<void>();
        f.writeGate = gate;
        final pending = f.run(c);
        await Future<void>.delayed(Duration.zero);
        await f.run(c);
        await expectLater(
          f.schedules.write('/jadwal-layanan', 'DELETE', id: 'one'),
          throwsA(isA<ApiException>()),
        );
        expect(f.posts.length, 1);
        gate.complete();
        await pending;
        expect(f.posts.length, 3);
        await c.close();
      },
    );
    for (final logout in [false, true]) {
      test(
        logout
            ? 'session ends during batch'
            : 'close during batch stops remaining POSTs',
        () async {
          final c = ScheduleBatchCubit(f.schedules);
          final gate = Completer<void>();
          f.writeGate = gate;
          final pending = f.run(c);
          await Future<void>.delayed(Duration.zero);
          if (logout) {
            await f.api.clearSession();
          } else {
            await c.close();
          }
          gate.complete();
          await pending;
          expect(f.posts.length, 1);
          if (logout) {
            expect(c.state.results, isEmpty);
            expect(c.state.status, ScheduleBatchStatus.sessionEnded);
            await c.close();
          }
        },
      );
    }
  });
}
