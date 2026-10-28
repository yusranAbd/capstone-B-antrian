import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:queueb_client/src/api.dart';
import 'package:queueb_client/src/features/patient/application/patient_booking_cubit.dart';
import 'package:queueb_client/src/features/patient/data/patient_booking_repository.dart';
import 'package:queueb_client/src/features/patient/models/patient_models.dart';
import 'package:timezone/data/latest.dart' as tz;

import 'patient_cubit_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(tz.initializeTimeZones);
  late PatientFixture f;
  late PatientBookingCubit c;
  setUp(() {
    f = PatientFixture();
    c = PatientBookingCubit(PatientBookingRepository(f.repository));
  });
  tearDown(() async {
    await c.close();
    f.dispose();
  });
  Future<PatientBookingRequest> choose({
    bool appointment = true,
    String mode = 'HIBRIDA',
  }) async {
    f.data['/layanan'] = [f.clinic(mode)];
    await f.repository.refresh();
    c.change({
      'serviceId': 'clinic',
      'doctorId': 'doctor',
      'appointment': appointment,
    });
    if (appointment) {
      await c.loadSchedules();
      await c.loadSlots('session');
      c.change({'slotId': 'slot'});
    }
    return c.prepare(f.api.config.today);
  }

  for (final appointment in [true, false]) {
    final path = appointment ? '/janji-temu' : '/reservasi';
    test(
      '${appointment ? 'appointment' : 'walk-in'} uses the existing payload and server ticket ID',
      () async {
        final request = await choose(appointment: appointment);
        final result = await c.submit(request);
        expect(result['id'], 'server-ticket-1');
        expect(c.state.mutation, PatientMutation.success);
        final post = f.calls.singleWhere((r) => r.method == 'POST');
        expect(post.url.path, '/api/v1$path');
        expect(
          jsonDecode(post.body),
          appointment
              ? {'slotPraktikId': 'slot'}
              : {'layananId': 'clinic', 'tanggalAntrean': f.api.config.today},
        );
        expect(f.repository.snapshot.tickets.single['id'], 'server-ticket-1');
      },
    );
    for (final status in [400, 403, 409]) {
      test('$path rejection $status preserves authoritative visits', () async {
        final request = await choose(appointment: appointment);
        f.postFailures[path] = status;
        await expectLater(
          c.submit(request),
          throwsA(
            isA<ApiException>().having((e) => e.status, 'status', status),
          ),
        );
        expect(c.state.mutation, PatientMutation.failure);
        expect(f.repository.snapshot.tickets, isEmpty);
        expect(c.state.error, isNot(contains('fixture-secret')));
        expect(f.writes, 1);
      });
    }
    test(
      '$path response lost after commit recovers exactly the server ticket without retry',
      () async {
        final request = await choose(appointment: appointment);
        f.postFailures[path] = 0;
        f.commitUnknown = true;
        final result = await c.submit(request);
        expect(result['id'], 'server-ticket-1');
        expect(c.state.mutation, PatientMutation.success);
        expect(f.writes, 1);
      },
    );
    test(
      '$path unresolved timeout blocks another POST across selection changes and GET',
      () async {
        final request = await choose(appointment: appointment);
        f.postFailures[path] = 0;
        await expectLater(c.submit(request), throwsA(isA<ApiException>()));
        expect(c.state.mutation, PatientMutation.unknown);
        c.change({'serviceId': null});
        c.change({'serviceId': 'clinic'});
        await f.repository.refresh();
        await expectLater(c.submit(request), throwsA(isA<ApiException>()));
        expect(
          () => c.prepare(f.api.config.today),
          throwsA(isA<ApiException>()),
        );
        expect(f.writes, 1);
      },
    );
  }
  for (final mode in ['ANTREAN_HARIAN', 'JANJI_TEMU_DOKTER', 'HIBRIDA']) {
    test(
      '$mode permits only backend channels, including Bedah Umum daily-only',
      () async {
        f.data['/layanan'] = [
          {...f.clinic(mode), 'nama': 'Bedah Umum'},
        ];
        await f.repository.refresh();
        c.change({'serviceId': 'clinic', 'appointment': false});
        if (mode == 'JANJI_TEMU_DOKTER') {
          expect(
            () => c.prepare(f.api.config.today),
            throwsA(isA<ApiException>()),
          );
        } else {
          expect(c.prepare(f.api.config.today).appointment, isFalse);
        }
        c.change({'appointment': true, 'doctorId': 'doctor'});
        await c.loadSchedules();
        await c.loadSlots('session');
        c.change({'slotId': 'slot'});
        if (mode == 'ANTREAN_HARIAN') {
          expect(
            () => c.prepare(f.api.config.today),
            throwsA(isA<ApiException>()),
          );
        } else {
          expect(c.prepare(f.api.config.today).appointment, isTrue);
        }
        expect(f.writes, 0);
      },
    );
  }
  test(
    'changed selection during review rejects the captured request before POST',
    () async {
      final request = await choose();
      c.change({'date': '2099-01-02'});
      await expectLater(c.submit(request), throwsA(isA<ApiException>()));
      expect(f.writes, 0);
    },
  );
  test('double submit and selection changes while POST is pending cannot duplicate booking', () async {
    final request = await choose();
    final gate = Completer<void>();
    f.mutationGate = gate;
    final started = f.mutationStarted = Completer<void>();
    final first = c.submit(request);
    await started.future;
    c.change({'slotId': 'other'});
    expect(c.slotId, 'slot');
    await expectLater(c.submit(request), throwsA(isA<ApiException>()));
    gate.complete();
    await first;
    expect(f.writes, 1);
  });
  test('old doctor/date results cannot overwrite a newer selection', () async {
    await f.repository.refresh();
    c.change({'serviceId': 'clinic', 'doctorId': 'doctor'});
    final gate = Completer<void>();
    f.gates[('/jadwal-praktik', 2)] = gate;
    final first = c.loadSchedules();
    await f.waitRead('/jadwal-praktik', 2);
    f.data['/jadwal-praktik'] = [f.session('new-session')];
    c.change({'doctorId': 'other', 'date': '2099-02-03'});
    await c.loadSchedules();
    gate.complete();
    await first;
    expect(c.state.rows('schedules').single['id'], 'new-session');
    expect(c.state.values['date'], '2099-02-03');
  });
  test('old slot response cannot overwrite the current session', () async {
    await choose();
    final count = f.reads['/slot-praktik']! + 1, gate = Completer<void>();
    f.gates[('/slot-praktik', count)] = gate;
    final first = c.loadSlots('session');
    await f.waitRead('/slot-praktik', count);
    f.slots['new'] = [f.slot('new-slot', 'new')];
    await c.loadSlots('new');
    gate.complete();
    await first;
    expect(c.sessionId, 'new');
    expect(c.state.rows('slots').single['id'], 'new-slot');
  });
  test('slot unavailable after refresh cannot be submitted', () async {
    await choose();
    f.slots['session'] = [
      {...f.slot(), 'tersedia': false},
    ];
    await c.loadSchedules(preserve: true);
    expect(c.slotId, isNull);
    expect(() => c.prepare(f.api.config.today), throwsA(isA<ApiException>()));
    expect(f.writes, 0);
  });
  test('selection arrays are immutable and nearest preview is bounded and advisory', () async {
    await f.repository.refresh();
    await c.loadNearest();
    expect(c.state.rows('nearestChoices'), hasLength(1));
    expect(
      () => c.state.rows('nearestChoices').first['slot']['tersedia'] = false,
      throwsUnsupportedError,
    );
    f.slots['session'] = [];
    f.repository.updates.invalidate(kinds: {'KATALOG'});
    await f.waitRead('/slot-praktik', 2);
    await c.referencesSettled;
    expect(c.state.rows('nearestChoices'), isEmpty);
    expect(f.writes, 0);
  });
  test('unverified visit baseline cannot mistake an old ticket for a recovered booking', () async {
    f.failures['/tiket/saya'] = 503;
    await f.repository.refresh();
    c.change({'serviceId': 'clinic', 'appointment': false});
    expect(() => c.prepare(f.api.config.today), throwsA(isA<ApiException>()));
    expect(f.writes, 0);
    f.failures.clear();
    await f.repository.refresh();
    expect(c.prepare(f.api.config.today).appointment, isFalse);
  });
  for (final ending in ['close', 'logout', 'account', 'role']) {
    test('$ending ignores a pending booking result', () async {
      final request = await choose();
      final gate = Completer<void>();
      f.mutationGate = gate;
      final started = f.mutationStarted = Completer<void>();
      final pending = expectLater(
        c.submit(request),
        throwsA(isA<ApiException>()),
      );
      await started.future;
      if (ending == 'close') {
        await c.close();
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
      await pending;
      expect(c.state.values['resultId'], isNull);
    });
  }
  test('failed post-success reconciliation blocks new bookings until explicit REST recovery', () async {
    final request = await choose(appointment: false);
    f.failures['/tiket/saya'] = 503;
    final result = await c.submit(request);
    expect(result['id'], 'server-ticket-1');
    expect(c.state.values['needsReconciliation'], isTrue);
    expect(() => c.prepare(f.api.config.today), throwsA(isA<ApiException>()));
    f.failures.clear();
    await f.repository.refresh();
    expect(c.state.values['needsReconciliation'], isFalse);
  });
}
