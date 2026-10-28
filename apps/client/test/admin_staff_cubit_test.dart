import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:queueb_client/src/api.dart';
import 'package:queueb_client/src/config.dart';
import 'package:queueb_client/src/features/admin/application/admin_catalog_cubit.dart';
import 'package:queueb_client/src/features/admin/application/admin_catalog_state.dart';
import 'package:queueb_client/src/features/admin/application/staff_management_cubit.dart';
import 'package:queueb_client/src/features/admin/data/admin_catalog_repository.dart';
import 'package:queueb_client/src/features/admin/data/admin_staff_repository.dart';
import 'package:timezone/data/latest.dart' as tz;

const existingStaffId = '11111111-1111-4111-8111-111111111111';
const createdStaffId = '22222222-2222-4222-8222-222222222222';
const fakePassword = 'Fixture-only-password-27';

class StaffFixture {
  StaffFixture() {
    api = QueueApi(
      config: AppConfig(apiBaseUrl: 'http://localhost/api/v1', realtime: false),
      client: MockClient(handle),
    )..user = {'id': 'admin', 'peran': 'ADMIN'};
    catalog = AdminCatalogRepository(api);
    repository = AdminStaffRepository(catalog);
  }
  late final QueueApi api;
  late final AdminCatalogRepository catalog;
  late final AdminStaffRepository repository;
  final calls = <http.Request>[];
  final data = <String, List<Json>>{
    '/akun-petugas': [
      {
        'id': existingStaffId,
        'nama': 'Petugas Lama',
        'email': 'lama@example.test',
        'peran': 'PETUGAS',
        'aktif': true,
      },
    ],
    '/penugasan-petugas': [
      {
        'id': 'assignment-one',
        'petugasId': existingStaffId,
        'loketId': 'room',
        'tanggalMulai': '2026-10-01',
        'tanggalSelesai': null,
        'aktif': true,
      },
    ],
    '/layanan': [
      {'id': 'clinic', 'nama': 'Poli', 'aktif': true},
    ],
    '/loket': [
      {
        'id': 'room',
        'kode': 'R01',
        'nama': 'Ruang Awal',
        'layananId': 'clinic',
        'aktif': true,
        'layanan': {'id': 'clinic', 'nama': 'Poli', 'aktif': true},
      },
    ],
    '/dokter': [],
    '/jadwal-praktik': [],
    '/jadwal-layanan': [],
  };
  final reads = <String, int>{};
  final gates = <(String, int), Completer<void>>{};
  final waiters = <(String, int), Completer<void>>{};
  final failures = <String, int>{};
  Completer<void>? writeGate, writeStarted;
  int? readError;
  bool commitUnknown = false,
      echoSecrets = false,
      malformedRead = false,
      malformedWrite = false;
  String errorMessage = 'Role petugas, ruang atau periode ditolak backend';
  Json identity = {'id': 'admin', 'peran': 'ADMIN'};
  void Function()? afterWrite;
  Future<void> waitRead(String path, int count) => (reads[path] ?? 0) >= count
      ? Future.value()
      : (waiters[(path, count)] ??= Completer<void>()).future;
  List<Json> rowsFor(String path) => path == '/penugasan-petugas'
      ? [
          for (final r in data[path]!)
            {
              ...r,
              'petugas':
                  data['/akun-petugas']!
                      .where((a) => a['id'] == r['petugasId'])
                      .firstOrNull ??
                  {},
              'loket':
                  data['/loket']!
                      .where((a) => a['id'] == r['loketId'])
                      .firstOrNull ??
                  {},
            },
        ]
      : data[path] ?? [];
  http.Response reply(Object value, [int status = 200]) =>
      http.Response(jsonEncode(value), status);
  Future<http.Response> handle(http.Request request) async {
    calls.add(request);
    final path = request.url.path.replaceFirst('/api/v1', '');
    if (path == '/auth/me') return reply(identity);
    if (request.method == 'GET') {
      final count = reads.update(path, (v) => v + 1, ifAbsent: () => 1);
      final response = readError == null
          ? reply(malformedRead ? {'invalid': true} : rowsFor(path))
          : reply({'message': 'Read unavailable'}, readError!);
      waiters.remove((path, count))?.complete();
      if (gates[(path, count)] case final gate?) await gate.future;
      return response;
    }
    final resource = '/${path.split('/')[1]}';
    final body = request.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(request.body) as Json;
    writeStarted?.complete();
    writeStarted = null;
    if (writeGate case final gate?) await gate.future;
    final status = failures[resource];
    final account = resource == '/akun-petugas';
    final id = request.method == 'POST'
        ? account
              ? createdStaffId
              : 'assignment-new'
        : path.split('/')[2];
    final row = <String, dynamic>{
      'id': id,
      ...body,
      if (request.method == 'POST') 'aktif': true,
      if (account) 'peran': 'PETUGAS',
    };
    if (account) {
      row['email'] =
          '${body['email'] ?? data[resource]!.firstWhere((r) => r['id'] == id, orElse: () => {})['email']}'
              .toLowerCase();
      row.remove('kataSandi');
      if (echoSecrets) {
        row.addAll({
          'kataSandi': fakePassword,
          'accessToken': 'fixture-token',
          'passwordHash': 'fixture-hash',
        });
      }
    }
    if (status == null || commitUnknown) {
      if (request.method == 'POST') data[resource]!.add(row);
      if (request.method == 'PATCH') {
        data[resource] = [
          for (final old in data[resource]!)
            old['id'] == id ? {...old, ...row} : old,
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
    if (status == 0) throw http.ClientException('Connection lost after send');
    return status == null
        ? reply(malformedWrite ? [] : row)
        : reply({'message': errorMessage}, status);
  }

  void dispose() {
    catalog.dispose();
    api.dispose();
  }
}

void main() {
  setUpAll(tz.initializeTimeZones);
  late StaffFixture f;
  setUp(() => f = StaffFixture());
  tearDown(() => f.dispose());
  Future<Json> createAccount(StaffAccountCubit c) => c.createAccount(
    name: 'Petugas Baru',
    email: 'baru@example.test',
    password: fakePassword,
  );
  Json assignment() => {
    'petugasId': createdStaffId,
    'loketId': 'room',
    'tanggalMulai': '2026-10-29',
    'tanggalSelesai': null,
  };

  for (final account in [true, false]) {
    group(account ? 'Staff accounts' : 'Assignments', () {
      final path = account ? '/akun-petugas' : '/penugasan-petugas';
      AdminStaffCubit create() => account
          ? StaffAccountCubit(f.repository)
          : AssignmentCubit(f.repository);
      Future<Json> write(AdminStaffCubit c) => account
          ? createAccount(c as StaffAccountCubit)
          : c.save(assignment());
      test(
        'initial load, loaded empty, failure and recovery are distinct',
        () async {
          final c = create();
          expect(c.state.load, CatalogLoadStatus.initial);
          f.readError = 503;
          await c.refresh();
          expect(c.state.load, CatalogLoadStatus.failure);
          expect(c.state.snapshot.collections.containsKey(path), isFalse);
          f.readError = null;
          await c.refresh();
          expect(c.rows, hasLength(1));
          f.data[path] = [];
          await c.refresh();
          expect(c.state.load, CatalogLoadStatus.loaded);
          expect(c.rows, isEmpty);
          expect(c.state.snapshot.collections.containsKey(path), isTrue);
          await c.close();
        },
      );
      test('refresh failure preserves verified immutable data', () async {
        final c = create();
        await c.refresh();
        f.readError = 503;
        await c.refresh();
        expect(c.rows, hasLength(1));
        expect(c.state.loadError, isA<ApiException>());
        expect(() => c.rows.clear(), throwsUnsupportedError);
        expect(() => c.rows.single['aktif'] = false, throwsUnsupportedError);
        if (!account) {
          expect(
            () => c.rows.single['loket']['nama'] = 'Changed',
            throwsUnsupportedError,
          );
        }
        f.readError = null;
        await c.refresh();
        expect(c.state.loadError, isNull);
        await c.close();
      });
      test(
        'burst invalidations coalesce and all callers wait for trailing read',
        () async {
          final c = create(),
              first = Completer<void>(),
              last = Completer<void>();
          f.gates[(path, 1)] = first;
          f.gates[(path, 2)] = last;
          var completed = false;
          final initial = c
              .refresh(paths: [path])
              .then((_) => completed = true);
          await f.waitRead(path, 1);
          final pending = [
            for (var i = 0; i < 25; i++) c.refresh(paths: [path]),
          ];
          f.data[path]!.single['aktif'] = false;
          first.complete();
          await f.waitRead(path, 2);
          expect(completed, isFalse);
          expect(f.reads[path], 2);
          last.complete();
          await Future.wait([initial, ...pending]);
          expect(c.rows.single['aktif'], isFalse);
          expect(f.reads[path], 2);
          await c.close();
        },
      );
      test('failed burst observes every adapter future and recovers without unhandled errors', () async {
        final c = create(), gate = Completer<void>();
        f.gates[(path, 1)] = gate;
        f.readError = 503;
        final first = c.refresh(paths: [path]);
        await f.waitRead(path, 1);
        final burst = [
          for (var i = 0; i < 10; i++) c.refresh(paths: [path]),
        ];
        gate.complete();
        await Future.wait([first, ...burst]);
        expect(c.state.load, CatalogLoadStatus.failure);
        f.readError = null;
        await c.refresh();
        expect(c.state.load, CatalogLoadStatus.loaded);
        await c.close();
      });
      for (final ending in ['close', 'logout', 'account', 'role']) {
        test('$ending discards pending old response', () async {
          final c = create(), gate = Completer<void>();
          f.gates[(path, 1)] = gate;
          final pending = c.refresh(paths: [path]);
          await f.waitRead(path, 1);
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
          expect(c.rows, isEmpty);
          if (ending != 'close') {
            expect(c.state.load, CatalogLoadStatus.sessionEnded);
            expect(c.state.snapshot.collections, isEmpty);
            await c.close();
          }
        });
      }
      test('create sends existing payload and reconciles only after server success', () async {
        final c = create();
        final result = await write(c);
        expect(c.state.mutation, CatalogMutationStatus.success);
        expect(c.rows, hasLength(2));
        expect(result['id'], account ? createdStaffId : 'assignment-new');
        final request = f.calls.singleWhere((r) => r.method == 'POST');
        expect(request.url.path, '/api/v1$path');
        final body = jsonDecode(request.body);
        if (account) {
          expect(body.keys.toSet(), {'nama', 'email', 'kataSandi'});
          expect(body.containsKey('peran'), isFalse);
        } else {
          expect(body, assignment());
        }
        expect(
          f.calls.any((r) => r.url.path.contains('slot-praktik')),
          isFalse,
        );
        await c.close();
      });
      for (final status in [400, 403, 409]) {
        test(
          'create backend rejection $status never creates optimistic rows',
          () async {
            final c = create();
            await c.refresh();
            f.failures[path] = status;
            await expectLater(
              write(c),
              throwsA(
                isA<ApiException>().having((e) => e.status, 'status', status),
              ),
            );
            expect(c.rows, hasLength(1));
            expect(c.state.mutation, CatalogMutationStatus.failure);
            await c.close();
          },
        );
      }
      for (final reject in [false, true]) {
        test(
          'update ${reject ? 'backend rejection' : 'preserves identity and reconciles'}',
          () async {
            final c = create();
            await c.refresh();
            f.failures[path] = reject ? 404 : 200;
            if (!reject) f.failures.remove(path);
            final id = account ? existingStaffId : 'assignment-one';
            final body = account
                ? <String, dynamic>{'aktif': false}
                : <String, dynamic>{'tanggalSelesai': '2026-10-29'};
            final operation = c.save(body, id: id);
            if (reject) {
              await expectLater(operation, throwsA(isA<ApiException>()));
            } else {
              await operation;
            }
            final request = f.calls.singleWhere((r) => r.method == 'PATCH');
            expect(request.url.path, '/api/v1$path/$id');
            expect(jsonDecode(request.body), body);
            expect(c.rows.single['id'], id);
            expect(
              c.state.mutation,
              reject
                  ? CatalogMutationStatus.failure
                  : CatalogMutationStatus.success,
            );
            await c.close();
          },
        );
      }
      for (final committed in [false, true]) {
        test(
          'create timeout committed=$committed reconciles without replay',
          () async {
            final c = create();
            f.failures[path] = 0;
            f.commitUnknown = committed;
            if (account && committed) {
              final result = await write(c);
              expect(result['id'], createdStaffId);
              expect(c.state.recoveredMutation, isTrue);
            } else {
              await expectLater(write(c), throwsA(isA<ApiException>()));
              expect(c.state.mutation, CatalogMutationStatus.unknown);
            }
            expect(c.rows, hasLength(committed ? 2 : 1));
            expect(f.calls.where((r) => r.method == 'POST'), hasLength(1));
            expect(c.state.needsReconciliation, isFalse);
            await c.close();
          },
        );
      }
      test('failed reconciliation blocks writes across staff scopes until verified refresh', () async {
        final c = create(),
            other = account
                ? AssignmentCubit(f.repository)
                : StaffAccountCubit(f.repository);
        f.failures[path] = 0;
        f.commitUnknown = true;
        f.afterWrite = () => f.readError = 503;
        await expectLater(write(c), throwsA(isA<ApiException>()));
        expect(c.state.needsReconciliation, isTrue);
        await expectLater(
          other.save(
            account ? assignment() : {'aktif': false},
            id: account ? null : existingStaffId,
          ),
          throwsA(isA<ApiException>()),
        );
        expect(f.calls.where((r) => r.method != 'GET'), hasLength(1));
        f.readError = null;
        f.afterWrite = null;
        f.failures.clear();
        await c.refresh(paths: ['/loket']);
        await expectLater(
          other.save(
            account ? assignment() : {'aktif': false},
            id: account ? null : existingStaffId,
          ),
          throwsA(isA<ApiException>()),
        );
        await c.refresh();
        expect(c.state.needsReconciliation, isFalse);
        await other.save(
          account ? assignment() : {'aktif': false},
          id: account ? null : existingStaffId,
        );
        await c.close();
        await other.close();
      });
      test('double-submit and cross-resource write conflict are rejected while request runs', () async {
        final c = create(),
            other = account
                ? AssignmentCubit(f.repository)
                : StaffAccountCubit(f.repository);
        final gate = Completer<void>();
        f.writeGate = gate;
        final started = f.writeStarted = Completer<void>();
        final pending = write(c);
        await started.future;
        await expectLater(write(c), throwsA(isA<ApiException>()));
        await expectLater(
          other.save(
            account ? assignment() : {'aktif': false},
            id: account ? null : existingStaffId,
          ),
          throwsA(isA<ApiException>()),
        );
        expect(f.calls.where((r) => r.method != 'GET'), hasLength(1));
        gate.complete();
        await pending;
        await c.close();
        await other.close();
      });
      for (final logout in [false, true]) {
        test(
          logout
              ? 'logout during write clears state'
              : 'close during write does not emit late result',
          () async {
            final c = create(), gate = Completer<void>();
            f.writeGate = gate;
            final started = f.writeStarted = Completer<void>();
            final pending = expectLater(write(c), throwsA(isA<ApiException>()));
            await started.future;
            if (logout) {
              await f.api.clearSession();
            } else {
              await c.close();
            }
            gate.complete();
            await pending;
            if (logout) {
              expect(c.state.snapshot.collections, isEmpty);
              await c.close();
            }
          },
        );
      }
    });
  }
  for (final permanent in [false, true]) {
    for (final reject in [false, true]) {
      test(
        'assignment ${permanent ? 'permanent delete' : 'revoke'} ${reject ? 'conflict' : 'success'}',
        () async {
          final c = AssignmentCubit(f.repository);
          await c.refresh();
          if (reject) f.failures['/penugasan-petugas'] = 409;
          final action = permanent
              ? c.delete('assignment-one')
              : c.deactivate('assignment-one');
          if (reject) {
            await expectLater(action, throwsA(isA<ApiException>()));
          } else {
            await action;
          }
          final request = f.calls.singleWhere((r) => r.method == 'DELETE');
          expect(
            request.url.path,
            '/api/v1/penugasan-petugas/assignment-one${permanent ? '/permanen' : ''}',
          );
          expect(c.rows, hasLength(permanent && !reject ? 0 : 1));
          if (!permanent) expect(c.rows.single['aktif'], reject);
          await c.close();
        },
      );
    }
  }
  test('account delete is unsupported and never sends HTTP', () async {
    final c = StaffAccountCubit(f.repository);
    await expectLater(c.delete(existingStaffId), throwsA(isA<ApiException>()));
    expect(f.calls, isEmpty);
    await c.close();
  });
  test(
    'credentials never enter any emitted snapshot or returned account metadata',
    () async {
      f.echoSecrets = true;
      final c = StaffAccountCubit(f.repository), states = <String>[];
      final sub = c.stream.listen(
        (s) => states.add(jsonEncode(s.snapshot.collections)),
      );
      final result = await createAccount(c);
      expect(result.keys.toSet(), {'id', 'nama', 'email', 'peran', 'aktif'});
      for (final text in [
        ...states,
        jsonEncode(c.state.snapshot.collections),
        jsonEncode(result),
      ]) {
        expect(text.contains(fakePassword), isFalse);
        expect(text.contains('fixture-token'), isFalse);
        expect(text.contains('passwordHash'), isFalse);
      }
      await sub.cancel();
      await c.close();
    },
  );
  test('credential-bearing backend exception is replaced before emission or rethrow', () async {
    final c = StaffAccountCubit(f.repository);
    f.failures['/akun-petugas'] = 400;
    f.errorMessage = 'kataSandi=$fakePassword accessToken=fixture-token';
    await expectLater(
      createAccount(c),
      throwsA(
        isA<ApiException>().having(
          (e) => e.toString().contains(fakePassword),
          'no credential',
          isFalse,
        ),
      ),
    );
    expect('${c.state.error}'.contains(fakePassword), isFalse);
    expect('${c.state.error}'.contains('fixture-token'), isFalse);
    await c.close();
  });
  test(
    'invalid roles are not offered as PETUGAS and malformed reads are failures',
    () async {
      final c = StaffAccountCubit(f.repository);
      f.data['/akun-petugas']!.add({
        'id': 'user',
        'nama': 'User',
        'peran': 'USER',
        'aktif': true,
      });
      await c.refresh();
      expect(c.rows, hasLength(1));
      f.malformedRead = true;
      await c.refresh();
      expect(c.state.load, CatalogLoadStatus.failure);
      expect(c.rows, hasLength(1));
      await c.close();
    },
  );
  test(
    'room catalog changes update assignment projection without a second owner',
    () async {
      final c = AssignmentCubit(f.repository);
      await c.refresh();
      final room = RoomCubit(f.catalog);
      await room.save({'nama': 'Nama Ruang Baru'}, id: 'room');
      expect(c.rows.single['loket']['nama'], 'Nama Ruang Baru');
      expect(room.repository, same(c.repository));
      await room.close();
      await c.close();
    },
  );
  test(
    'partial provisioning keeps account and retries assignment only',
    () async {
      final accounts = StaffAccountCubit(f.repository),
          assignments = AssignmentCubit(f.repository);
      final account = await createAccount(accounts);
      expect(account['id'], createdStaffId);
      f.failures['/penugasan-petugas'] = 409;
      await expectLater(
        assignments.save(assignment()),
        throwsA(isA<ApiException>()),
      );
      expect(accounts.rows.any((a) => a['id'] == createdStaffId), isTrue);
      f.failures.clear();
      await assignments.save(assignment());
      expect(
        f.calls.where(
          (r) => r.method == 'POST' && r.url.path.endsWith('/akun-petugas'),
        ),
        hasLength(1),
      );
      expect(assignments.rows.last['petugasId'], createdStaffId);
      await accounts.close();
      await assignments.close();
    },
  );
}
