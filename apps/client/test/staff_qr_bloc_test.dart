import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:queueb_client/src/api.dart';
import 'package:queueb_client/src/config.dart';
import 'package:queueb_client/src/features/staff/application/staff_queue_event.dart';
import 'package:queueb_client/src/features/staff/application/staff_queue_state.dart';
import 'package:queueb_client/src/features/staff/models/staff_queue_models.dart';
import 'package:queueb_client/src/staff_qr_scanner.dart';

import 'staff_bloc_fixture.dart';

void main() {
  setUpAll(tz.initializeTimeZones);
  late StaffFixture f;
  setUp(() => f = StaffFixture());
  tearDown(() => f.dispose());
  Future<Json> scan([String? qr]) =>
      f.bloc.execute(StaffOperation.scan, qr: qr ?? staffQr);
  test(
    '4C valid One-Scan uses atomic route and real ticket identity',
    () async {
      await f.load();
      final result = await scan();
      expect(result['tiketId'], staffTicket);
      expect(result['status'], 'MENUNGGU');
      expect(f.bloc.state.patients.single['tiketId'], staffTicket);
      expect(f.bloc.state.command, StaffCommandStatus.confirmed);
      expect(f.api.calls.lastWhere((c) => c.method == 'POST').body, {
        'qrPayload': staffQr,
        'loketId': staffRoomA,
      });
      expect(f.api.count('/check-in/auto-antrean', 'POST'), 1);
      expect(f.api.calls.any((c) => c.path.endsWith('/masuk')), isFalse);
    },
  );
  for (final code in [400, 403, 409, 410]) {
    test(
      '4C invalid/unauthorized/used/expired QR $code is safe backend rejection',
      () async {
        await f.load();
        f.api.failures['POST /check-in/auto-antrean'] = ApiException(
          code,
          'secret $staffQr',
        );
        await expectLater(
          scan(),
          throwsA(isA<ApiException>().having((e) => e.status, 'status', code)),
        );
        expect(f.bloc.state.message, isNull);
        expect(f.bloc.state.command, StaffCommandStatus.failed);
        expect(f.bloc.state.error, isNot(contains(staffQr)));
      },
    );
  }
  test('4C invalid format never reaches transport', () async {
    await f.load();
    await expectLater(scan('SQ1.partial'), throwsA(isA<ApiException>()));
    expect(f.api.count('/check-in/auto-antrean', 'POST'), 0);
  });
  test(
    '4C adjacent duplicate scan cannot bypass global command lock',
    () async {
      await f.load();
      final gate = f.api.block('/check-in/auto-antrean', 'POST');
      final first = scan();
      final second = scan();
      final rejected = expectLater(second, throwsA(isA<ApiException>()));
      await gate.entered.future;
      await rejected;
      expect(f.api.count('/check-in/auto-antrean', 'POST'), 1);
      gate.release.complete();
      await first;
    },
  );
  test('4C scanner cannot submit during CALL', () async {
    await f.load();
    final gate = f.api.block('/queue/panggil', 'POST');
    final command = f.bloc.execute(StaffOperation.call);
    await gate.entered.future;
    await expectLater(scan(), throwsA(isA<ApiException>()));
    expect(f.api.count('/check-in/auto-antrean', 'POST'), 0);
    gate.release.complete();
    await command;
  });
  test('4C CALL cannot submit during scanner command', () async {
    await f.load();
    final gate = f.api.block('/check-in/auto-antrean', 'POST');
    final command = scan();
    await gate.entered.future;
    await expectLater(
      f.bloc.execute(StaffOperation.call),
      throwsA(isA<ApiException>()),
    );
    expect(f.api.count('/queue/panggil', 'POST'), 0);
    gate.release.complete();
    await command;
  });
  test('4C scan result waits REST; no premature scanner success', () async {
    await f.load();
    final gate = f.api.block('/queue/snapshot');
    final command = scan();
    var finished = false;
    unawaited(
      command.then((_) {
        finished = true;
      }),
    );
    await gate.entered.future;
    expect(finished, isFalse);
    expect(f.bloc.state.busy, isTrue);
    expect(f.bloc.state.mutationConfirmed, isTrue);
    gate.release.complete();
    await command;
    expect(f.bloc.state.patients.single['status'], 'MENUNGGU');
  });
  test('4C timeout reconciles queue but opaque QR outcome stays guarded without identity', () async {
    await f.load();
    f.api.loseMutation = true;
    await expectLater(scan(), throwsA(isA<ApiException>()));
    expect(f.bloc.state.patients.single['status'], 'MENUNGGU');
    expect(f.bloc.state.command, StaffCommandStatus.uncertain);
    await f.bloc.refresh();
    await expectLater(scan('SQ1.${'B' * 43}'), throwsA(isA<ApiException>()));
    expect(f.api.count('/check-in/auto-antrean', 'POST'), 1);
    expect(f.bloc.state.message, isNull);
  });
  test('4C emitted states and event diagnostics never expose QR', () async {
    await f.load();
    final states = <StaffQueueState>[];
    final sub = f.bloc.stream.listen(states.add);
    await scan();
    await sub.cancel();
    for (final state in states) {
      final text = jsonEncode({
        'snapshot': state.snapshot,
        'assignments': state.assignments,
        'schedules': state.schedules,
        'error': state.error,
        'message': state.message,
      });
      expect(text, isNot(contains(staffQr)));
      expect(text, isNot(contains('qrPayload')));
    }
    final event = StaffCommand(StaffOperation.scan, qr: staffQr);
    expect('$event', 'StaffCommand');
    expect(event.takeQr(), staffQr);
    expect(event.takeQr(), isNull);
  });
  testWidgets(
    '4C scanner closes during pending request; late result does not revive preview',
    (tester) async {
      await tester.runAsync(() => f.load());
      ValueChanged<String>? detect;
      final gate = f.api.block('/check-in/auto-antrean', 'POST');
      await tester.pumpWidget(
        MaterialApp(
          home: StaffQrScanner(
            onScan: (qr) => scan(qr),
            previewBuilder: (callback) {
              detect = callback;
              return const Text('Fixture camera');
            },
          ),
        ),
      );
      detect!(staffQr);
      await tester.pump();
      expect(gate.entered.isCompleted, isTrue);
      await tester.pumpWidget(const SizedBox());
      gate.release.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('staff-qr-result')), findsNothing);
      detect!(staffQr);
      await tester.pump();
      expect(f.api.count('/check-in/auto-antrean', 'POST'), 1);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('4C unexpected scanner exception never renders its raw text', (
    tester,
  ) async {
    ValueChanged<String>? detect;
    await tester.pumpWidget(
      MaterialApp(
        home: StaffQrScanner(
          onScan: (_) => Future.error(StateError('sensitive $staffQr')),
          previewBuilder: (callback) {
            detect = callback;
            return const SizedBox();
          },
        ),
      ),
    );
    detect!(staffQr);
    await tester.pumpAndSettle();
    expect(find.textContaining(staffQr), findsNothing);
    expect(find.byKey(const ValueKey('staff-qr-result')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
}
