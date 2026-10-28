import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:queueb_client/src/api.dart';
import 'package:queueb_client/src/features/staff/application/staff_queue_state.dart';
import 'package:queueb_client/src/features/staff/models/staff_queue_models.dart';

import 'staff_bloc_fixture.dart';

const initialStatuses = {
  StaffOperation.call: 'MENUNGGU',
  StaffOperation.recall: 'DIPANGGIL',
  StaffOperation.skip: 'DIPANGGIL',
  StaffOperation.requeue: 'DILEWATI',
  StaffOperation.start: 'DIPANGGIL',
  StaffOperation.complete: 'DILAYANI',
  StaffOperation.enqueue: 'CHECK_IN',
};
String commandPath(StaffOperation op) => op == StaffOperation.call
    ? '/queue/panggil'
    : '/queue/$staffTicket/${op.route}';
void main() {
  setUpAll(tz.initializeTimeZones);
  late StaffFixture f;
  setUp(() => f = StaffFixture());
  tearDown(() => f.dispose());
  Future<void> prepare(StaffOperation op) async {
    f.api.status = initialStatuses[op]!;
    await f.load();
  }

  Future<dynamic> execute(StaffOperation op) => f.bloc.execute(
    op,
    ticketId: op == StaffOperation.call ? null : staffTicket,
  );
  for (final op in initialStatuses.keys) {
    test('4B ${op.name} confirmed only after REST reconciliation', () async {
      await prepare(op);
      final result = await execute(op);
      expect(result['tiketId'], staffTicket);
      expect(f.api.status, op.expectedStatus);
      expect(f.bloc.state.command, StaffCommandStatus.confirmed);
      expect(f.bloc.state.synchronized, isTrue);
      expect(f.api.count(commandPath(op), 'POST'), 1);
      expect(f.api.calls.lastWhere((c) => c.method == 'POST').body, {
        'loketId': staffRoomA,
      });
    });
    test('4B ${op.name} backend conflict keeps authoritative status', () async {
      await prepare(op);
      f.api.failures['POST ${commandPath(op)}'] = const ApiException(
        409,
        'private details',
      );
      await expectLater(execute(op), throwsA(isA<ApiException>()));
      expect(f.api.status, initialStatuses[op]);
      expect(f.bloc.state.command, StaffCommandStatus.failed);
      expect(f.bloc.state.errorStatus, 409);
      expect(f.bloc.state.message, isNull);
      expect(f.bloc.state.error, isNot(contains('private details')));
    });
  }
  for (final code in [400, 401, 403, 404, 409, 429]) {
    test(
      '4B fake response $code retains category without credentials',
      () async {
        await prepare(StaffOperation.call);
        f.api.failures['POST /queue/panggil'] = ApiException(
          code,
          'token SECRET',
        );
        await expectLater(
          execute(StaffOperation.call),
          throwsA(isA<ApiException>()),
        );
        expect(f.bloc.state.errorStatus, code);
        expect(f.bloc.state.error, isNot(contains('SECRET')));
        expect(f.api.count('/queue/panggil', 'POST'), 1);
      },
    );
  }
  for (final second in [
    StaffOperation.recall,
    StaffOperation.skip,
    StaffOperation.start,
  ]) {
    test(
      '4B one global guard rejects second ${second.name} while RECALL held',
      () async {
        await prepare(StaffOperation.recall);
        final gate = f.api.block(commandPath(StaffOperation.recall), 'POST');
        final first = execute(StaffOperation.recall);
        await gate.entered.future;
        await expectLater(execute(second), throwsA(isA<ApiException>()));
        expect(f.api.calls.where((c) => c.method == 'POST'), hasLength(1));
        gate.release.complete();
        await first;
      },
    );
  }
  test(
    '4B adjacent CALL events cannot both pass synchronous admission',
    () async {
      await prepare(StaffOperation.call);
      final gate = f.api.block('/queue/panggil', 'POST');
      final first = execute(StaffOperation.call);
      final second = execute(StaffOperation.call);
      final rejected = expectLater(second, throwsA(isA<ApiException>()));
      await gate.entered.future;
      await rejected;
      expect(f.api.count('/queue/panggil', 'POST'), 1);
      gate.release.complete();
      await first;
    },
  );
  test(
    '4B S02 POST completion waits active fetch AND trailing reconciliation',
    () async {
      await prepare(StaffOperation.call);
      final post = f.api.block('/queue/panggil', 'POST');
      final command = execute(StaffOperation.call);
      var done = false;
      unawaited(
        command.then((_) {
          done = true;
        }),
      );
      await post.entered.future;
      final oldRead = f.api.block('/queue/snapshot');
      final trailing = f.api.block('/queue/snapshot');
      final refresh = f.bloc.refresh();
      await oldRead.entered.future;
      post.release.complete();
      await f.until((s) => s.command == StaffCommandStatus.reconciling);
      expect(done, isFalse);
      expect(f.bloc.state.busy, isTrue);
      oldRead.release.complete();
      await trailing.entered.future;
      expect(done, isFalse);
      expect(f.bloc.state.busy, isTrue);
      expect(f.bloc.state.synchronized, isFalse);
      trailing.release.complete();
      await command;
      await refresh;
      expect(done, isTrue);
      expect(f.bloc.state.active.single['status'], 'DIPANGGIL');
      expect(f.api.maxReads['/queue/snapshot:$staffRoomA'], 1);
    },
  );
  test('4B POST confirmed but read failed remains unsynced and blocks next mutation', () async {
    await prepare(StaffOperation.call);
    f.api.failures['GET /queue/snapshot'] = const ApiException(503, 'down');
    await expectLater(
      execute(StaffOperation.call),
      throwsA(isA<ApiException>()),
    );
    expect(f.bloc.state.command, StaffCommandStatus.unsynced);
    expect(f.bloc.state.message, isNull);
    await expectLater(
      execute(StaffOperation.call),
      throwsA(isA<ApiException>()),
    );
    expect(f.api.count('/queue/panggil', 'POST'), 1);
    f.api.failures.clear();
    await f.bloc.refresh();
    expect(f.bloc.state.command, StaffCommandStatus.confirmed);
    expect(f.bloc.state.synchronized, isTrue);
  });
  test(
    '4B lost START response reconciles real ticket status without POST retry',
    () async {
      await prepare(StaffOperation.start);
      f.api.loseMutation = true;
      await expectLater(
        execute(StaffOperation.start),
        throwsA(isA<ApiException>()),
      );
      expect(f.bloc.state.active.single['status'], 'DILAYANI');
      expect(f.bloc.state.command, StaffCommandStatus.idle);
      expect(f.bloc.state.message, contains('diverifikasi'));
      expect(f.api.count(commandPath(StaffOperation.start), 'POST'), 1);
    },
  );
  test('4B uncertain CALL cannot infer its outcome or retry from a bounded snapshot', () async {
    await prepare(StaffOperation.call);
    f.api.loseWithoutCommit = true;
    await expectLater(
      execute(StaffOperation.call),
      throwsA(isA<ApiException>()),
    );
    await f.bloc.refresh();
    await expectLater(
      execute(StaffOperation.call),
      throwsA(isA<ApiException>()),
    );
    expect(f.bloc.state.command, StaffCommandStatus.uncertain);
    expect(f.api.count('/queue/panggil', 'POST'), 1);
    expect(f.bloc.state.message, isNull);
  });
  test(
    '4B lost COMPLETE response does not equate absence to success',
    () async {
      await prepare(StaffOperation.complete);
      f.api.loseMutation = true;
      await expectLater(
        execute(StaffOperation.complete),
        throwsA(isA<ApiException>()),
      );
      expect(f.bloc.state.active, isEmpty);
      expect(f.bloc.state.command, StaffCommandStatus.uncertain);
      expect(f.bloc.state.message, isNull);
    },
  );
  test('4B RECALL recovery requires backend version advancement', () async {
    await prepare(StaffOperation.recall);
    f.api.loseWithoutCommit = true;
    await expectLater(
      execute(StaffOperation.recall),
      throwsA(isA<ApiException>()),
    );
    expect(f.bloc.state.command, StaffCommandStatus.uncertain);
    f.api.version++;
    await f.bloc.refresh();
    expect(f.bloc.state.command, StaffCommandStatus.idle);
    expect(f.api.count(commandPath(StaffOperation.recall), 'POST'), 1);
  });
  test(
    '4B no transition is emitted optimistically while backend held',
    () async {
      await prepare(StaffOperation.skip);
      final gate = f.api.block(commandPath(StaffOperation.skip), 'POST');
      final command = execute(StaffOperation.skip);
      await gate.entered.future;
      expect(f.bloc.state.active.single['status'], 'DIPANGGIL');
      expect(f.bloc.state.message, isNull);
      gate.release.complete();
      await command;
      expect(f.bloc.state.patients.single['status'], 'DILEWATI');
    },
  );
}
