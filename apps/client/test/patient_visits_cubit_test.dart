import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:queueb_client/src/api.dart';
import 'package:queueb_client/src/features/patient/application/patient_reservations_cubit.dart';
import 'package:queueb_client/src/features/patient/application/patient_ticket_cubit.dart';
import 'package:queueb_client/src/features/patient/models/patient_models.dart';
import 'package:timezone/data/latest.dart' as tz;

import 'patient_cubit_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(tz.initializeTimeZones);
  late PatientFixture f;
  late PatientReservationsCubit visits;
  late PatientTicketCubit ticket;
  setUp(() {
    f = PatientFixture();
    f.data['/tiket/saya'] = [f.ticket()];
    f.data['/janji-temu'] = [
      {
        'id': 'appointment',
        'tiket': f.ticket(),
        'slotPraktik': {...f.slot(), 'jadwalPraktik': f.session()},
      },
    ];
    visits = PatientReservationsCubit(f.repository);
    ticket = PatientTicketCubit(f.repository, 'ticket');
  });
  tearDown(() async {
    await visits.close();
    await ticket.close();
    f.dispose();
  });
  test(
    'owned lists and detail share canonical ticket metadata and real ticket ID',
    () async {
      await visits.refresh();
      await ticket.refresh();
      expect(ticket.ticket?['id'], 'ticket');
      expect(f.reads['/tiket/ticket'], 1);
      expect(f.reads['/tiket/appointment'], isNull);
      expect(visits.state.snapshot, same(ticket.state.snapshot));
      f.data['/tiket/saya'] = [
        {...f.ticket(), 'status': 'CHECK_IN'},
      ];
      await visits.refresh();
      expect(
        visits.state.snapshot.appointments.single['tiket']['status'],
        'CHECK_IN',
      );
      await ticket.refresh();
      expect(visits.state.snapshot.tickets.single['status'], 'CHECK_IN');
      expect(
        visits.state.snapshot.appointments.single['tiket']['status'],
        'CHECK_IN',
      );
      expect(ticket.canIssue, isFalse);
    },
  );
  test('list failure is distinct from verified empty and recovery', () async {
    f.failures['/janji-temu'] = 503;
    await visits.refresh();
    expect(visits.state.load, PatientLoad.failure);
    expect(visits.state.snapshot.tickets, hasLength(1));
    f.failures.clear();
    f.data['/janji-temu'] = [];
    await visits.refresh();
    expect(visits.state.load, PatientLoad.loaded);
    expect(visits.state.snapshot.appointments, isEmpty);
  });
  test('cancellation waits for server, then updates existing identities without optimistic removal', () async {
    await visits.refresh();
    final gate = Completer<void>();
    f.mutationGate = gate;
    final started = f.mutationStarted = Completer<void>();
    final pending = visits.cancel('appointment');
    await started.future;
    expect(visits.state.snapshot.tickets.single['status'], 'DIPESAN');
    await expectLater(
      visits.cancel('appointment'),
      throwsA(isA<ApiException>()),
    );
    gate.complete();
    await pending;
    expect(visits.state.snapshot.tickets.single['id'], 'ticket');
    expect(visits.state.snapshot.tickets.single['status'], 'DIBATALKAN');
    expect(f.writes, 1);
    expect(
      f.calls.singleWhere((r) => r.method == 'POST').url.path,
      '/api/v1/janji-temu/appointment/batalkan',
    );
  });
  for (final status in [
    'CHECK_IN',
    'MENUNGGU',
    'DIPANGGIL',
    'DILAYANI',
    'DILEWATI',
    'SELESAI',
    'DIBATALKAN',
  ]) {
    test('$status cannot be cancelled by the patient', () async {
      f.data['/tiket/saya'] = [
        {...f.ticket(), 'status': status},
      ];
      await visits.refresh();
      await expectLater(
        visits.cancel('appointment'),
        throwsA(isA<ApiException>()),
      );
      expect(f.writes, 0);
    });
  }
  test('cancellation conflict re-reads actual status rather than inventing cancellation', () async {
    await visits.refresh();
    f.postFailures['/janji-temu/appointment/batalkan'] = 409;
    f.afterMutation = (_) {
      f.data['/tiket/saya'] = [
        {...f.ticket(), 'status': 'CHECK_IN'},
      ];
    };
    await expectLater(
      visits.cancel('appointment'),
      throwsA(isA<ApiException>()),
    );
    expect(visits.state.snapshot.tickets.single['status'], 'CHECK_IN');
    expect(visits.state.mutation, PatientMutation.failure);
    expect(visits.state.error, contains('pembatalan ditolak'));
    expect(visits.state.error, isNot(contains('fixture-secret')));
  });
  for (final committed in [false, true]) {
    test(
      'cancel timeout committed=$committed never retries or treats GET as proof of failure',
      () async {
        await visits.refresh();
        f.postFailures['/janji-temu/appointment/batalkan'] = 0;
        f.commitUnknown = committed;
        if (committed) {
          await visits.cancel('appointment');
        } else {
          await expectLater(
            visits.cancel('appointment'),
            throwsA(isA<ApiException>()),
          );
          await visits.refresh();
          await expectLater(
            visits.cancel('appointment'),
            throwsA(isA<ApiException>()),
          );
          expect(visits.state.unknown, {'appointment'});
        }
        expect(f.writes, 1);
        expect(
          visits.state.snapshot.tickets.single['status'],
          committed ? 'DIBATALKAN' : 'DIPESAN',
        );
      },
    );
  }
  test('post-success cancellation with failed reconciliation blocks until REST recovery', () async {
    await visits.refresh();
    f.failures['/tiket/saya'] = 503;
    await visits.cancel('appointment');
    expect(visits.state.needsReconciliation, isTrue);
    f.failures.clear();
    await visits.refresh();
    expect(visits.state.needsReconciliation, isFalse);
    expect(visits.state.snapshot.tickets.single['status'], 'DIBATALKAN');
  });
  test(
    'QR is only a transient return value, never emitted, serialized or cached',
    () async {
      await visits.refresh();
      await ticket.refresh();
      final states = <PatientTicketState>[];
      final subscription = ticket.stream.listen(states.add);
      final qr = await ticket.issue();
      expect(qr?.payload, f.qrPayload);
      expect(qr?.ticketId, 'ticket');
      expect('$qr', isNot(contains(f.qrPayload)));
      for (final state in states) {
        expect(
          jsonEncode(state.snapshot.collections),
          isNot(contains(f.qrPayload)),
        );
        expect(state.error, isNot(contains(f.qrPayload)));
      }
      expect(
        jsonEncode(f.repository.snapshot.collections),
        isNot(contains('qrPayload')),
      );
      qr!.clear();
      expect(qr.payload, isNull);
      await subscription.cancel();
    },
  );
  for (final status in ['CHECK_IN', 'DIBATALKAN', 'SELESAI']) {
    test('$status ticket cannot issue patient QR', () async {
      f.data['/tiket/saya'] = [
        {...f.ticket(), 'status': status},
      ];
      await ticket.refresh();
      await expectLater(ticket.issue(), throwsA(isA<ApiException>()));
      expect(f.writes, 0);
    });
  }
  test('future ticket day cannot issue QR', () async {
    f.data['/tiket/saya'] = [
      {...f.ticket(), 'tanggalPelayanan': '2099-01-01'},
    ];
    await ticket.refresh();
    expect(ticket.canIssue, isFalse);
    expect(f.writes, 0);
  });
  for (final malformed in ['expired', 'wrong-ticket']) {
    test('$malformed QR never reaches presentation', () async {
      await ticket.refresh();
      if (malformed == 'expired') {
        f.qrLifetime = const Duration(seconds: -1);
      } else {
        f.qrTicketId = 'other-ticket';
      }
      expect(await ticket.issue(), isNull);
      expect(ticket.state.mutation, isNot(PatientMutation.success));
      expect(ticket.state.error, isNot(contains(f.qrPayload)));
      expect(f.writes, 1);
    });
  }
  test(
    'lost QR response is not recoverable from GET and has no automatic retry',
    () async {
      await ticket.refresh();
      f.postFailures['/tiket/ticket/qr'] = 0;
      expect(await ticket.issue(), isNull);
      expect(ticket.state.mutation, PatientMutation.unknown);
      await ticket.refresh();
      expect(f.writes, 1);
      f.postFailures.clear();
      final next = await ticket.issue();
      expect(next?.ticketId, 'ticket');
      expect(f.writes, 2);
      next?.clear();
    },
  );
  test(
    'double issuance is guarded across Cubits sharing one repository',
    () async {
      await ticket.refresh();
      final other = PatientTicketCubit(f.repository, 'ticket');
      final gate = Completer<void>();
      f.mutationGate = gate;
      final started = f.mutationStarted = Completer<void>();
      final first = ticket.issue();
      await started.future;
      await expectLater(ticket.issue(), throwsA(isA<ApiException>()));
      expect(await other.issue(), isNull);
      gate.complete();
      final qr = await first;
      qr?.clear();
      expect(f.writes, 1);
      await other.close();
    },
  );
  test(
    'detail errors remain scoped and do not poison overview collections',
    () async {
      await visits.refresh();
      f.failures['/tiket/ticket'] = 404;
      await ticket.refresh();
      expect(ticket.state.load, PatientLoad.failure);
      expect(ticket.canIssue, isFalse);
      expect(visits.state.load, PatientLoad.loaded);
      expect(ticket.state.error, isNot(contains('fixture-secret')));
      f.failures.clear();
      await ticket.refresh();
      expect(ticket.state.load, PatientLoad.loaded);
    },
  );
  test('serialized detail follows held list and publishes the newer status to both consumers', () async {
    final gate = Completer<void>();
    f.gates[('/tiket/saya', 1)] = gate;
    final first = visits.refresh();
    await f.waitRead('/tiket/saya', 1);
    f.data['/tiket/saya'] = [
      {...f.ticket(), 'status': 'MENUNGGU'},
    ];
    final detail = ticket.refresh();
    gate.complete();
    await Future.wait([first, detail]);
    expect(ticket.ticket?['status'], 'MENUNGGU');
    expect(visits.state.snapshot.tickets.single['status'], 'MENUNGGU');
  });
  test('burst detail refresh waits for the trailing request without duplicate tickets', () async {
    final a = Completer<void>(), b = Completer<void>();
    f.gates[('/tiket/ticket', 1)] = a;
    f.gates[('/tiket/ticket', 2)] = b;
    bool done = false;
    final first = ticket.refresh().then((_) => done = true);
    await f.waitRead('/tiket/ticket', 1);
    final burst = [for (var i = 0; i < 10; i++) ticket.refresh()];
    a.complete();
    await f.waitRead('/tiket/ticket', 2);
    expect(done, isFalse);
    b.complete();
    await Future.wait([first, ...burst]);
    expect(f.repository.snapshot.tickets, hasLength(1));
    expect(f.reads['/tiket/ticket'], 2);
  });
  for (final ending in ['close', 'logout', 'account', 'role']) {
    test('$ending during a QR request drops the late secret', () async {
      await ticket.refresh();
      final gate = Completer<void>();
      f.mutationGate = gate;
      final started = f.mutationStarted = Completer<void>();
      final pending = ticket.issue();
      await started.future;
      if (ending == 'close') {
        await ticket.close();
      } else if (ending == 'logout') {
        await f.api.clearSession();
      } else {
        f.identity = {
          ...f.identity,
          'id': ending == 'account' ? 'patient-b' : 'patient-a',
          'peran': ending == 'role' ? 'ADMIN' : 'USER',
        };
        await f.api.reloadOwnProfile();
      }
      gate.complete();
      expect(await pending, isNull);
      expect(
        ticket.state.snapshot.collections.toString(),
        isNot(contains(f.qrPayload)),
      );
      if (ending != 'close') {
        expect(ticket.state.load, PatientLoad.sessionEnded);
      }
    });
  }
  test(
    'ticket realtime refreshes the open detail and visits without another feed',
    () async {
      await visits.refresh();
      await ticket.refresh();
      final feed = f.repository.updates;
      f.data['/tiket/saya'] = [
        {...f.ticket(), 'status': 'CHECK_IN'},
      ];
      feed.invalidate(kinds: {'TIKET'});
      await f.waitRead('/tiket/ticket', 2);
      await f.repository.refresh(const []);
      expect(ticket.ticket?['status'], 'CHECK_IN');
      expect(visits.state.snapshot.tickets.single['status'], 'CHECK_IN');
      expect(f.repository.updates, same(feed));
      expect(f.writes, 0);
    },
  );
}
