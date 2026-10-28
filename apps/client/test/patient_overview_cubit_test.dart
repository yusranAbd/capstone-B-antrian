import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:queueb_client/src/features/patient/application/patient_overview_cubit.dart';
import 'package:queueb_client/src/features/patient/data/patient_repository.dart';
import 'package:queueb_client/src/features/patient/models/patient_models.dart';
import 'package:queueb_client/src/patient.dart';
import 'package:timezone/data/latest.dart' as tz;

import 'patient_cubit_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(tz.initializeTimeZones);
  late PatientFixture f;
  late PatientOverviewCubit c;
  setUp(() {
    f = PatientFixture();
    c = PatientOverviewCubit(f.repository);
  });
  tearDown(() async {
    await c.close();
    f.dispose();
  });
  test(
    'initial overview is lazy and loads the existing five endpoints once',
    () async {
      expect(f.calls, isEmpty);
      await c.refresh();
      expect(c.state.load, PatientLoad.loaded);
      expect(f.reads.keys.toSet(), patientOverviewPaths);
      expect(f.reads.values, everyElement(1));
      expect(c.state.snapshot, same(f.repository.snapshot));
    },
  );
  test(
    'verified empty differs from partial failure and explicit recovery',
    () async {
      f.failures['/tiket/saya'] = 503;
      await c.refresh();
      expect(c.state.load, PatientLoad.failure);
      expect(c.state.snapshot.collections.containsKey('/tiket/saya'), isFalse);
      expect(c.state.snapshot.services, hasLength(1));
      expect(c.state.error, isNot(contains('fixture-secret')));
      f.failures.clear();
      await c.refresh();
      expect(c.state.load, PatientLoad.loaded);
      expect(c.state.snapshot.tickets, isEmpty);
      expect(c.state.snapshot.collections.containsKey('/tiket/saya'), isTrue);
    },
  );
  test('malformed arrays are failures, not verified empty data', () async {
    f.malformed = true;
    await c.refresh();
    expect(c.state.load, PatientLoad.failure);
    expect(c.state.snapshot.collections, isEmpty);
  });
  test(
    'snapshot is recursively frozen and excludes QR and credential fields',
    () async {
      f.data['/tiket/saya'] = [
        {
          ...f.ticket(),
          'qrPayload': 'SQ1.fixture-token',
          'tokenQrHash': 'fixture-secret',
          'nested': {'password': 'fixture-secret'},
        },
      ];
      await c.refresh();
      expect(() => c.state.snapshot.tickets.add({}), throwsUnsupportedError);
      expect(
        () => c.state.snapshot.tickets.first['layanan']['nama'] = 'bad',
        throwsUnsupportedError,
      );
      expect(
        jsonEncode(c.state.snapshot.collections),
        isNot(contains('fixture-secret')),
      );
      expect(jsonEncode(c.state.snapshot.collections), isNot(contains('SQ1.')));
    },
  );
  test(
    'burst refresh waits for held trailing read and later invalidation',
    () async {
      final a = Completer<void>(), b = Completer<void>(), d = Completer<void>();
      f.gates[('/tiket/saya', 1)] = a;
      f.gates[('/tiket/saya', 2)] = b;
      f.gates[('/tiket/saya', 3)] = d;
      bool completed = false;
      final first = c
          .refresh(paths: patientVisitPaths)
          .then((_) => completed = true);
      await f.waitRead('/tiket/saya', 1);
      final burst = [
        for (var i = 0; i < 20; i++) c.refresh(paths: patientVisitPaths),
      ];
      a.complete();
      await f.waitRead('/tiket/saya', 2);
      expect(completed, isFalse);
      final last = c.refresh(paths: patientVisitPaths);
      b.complete();
      await f.waitRead('/tiket/saya', 3);
      expect(completed, isFalse);
      d.complete();
      await Future.wait([first, ...burst, last]);
      expect(f.reads['/tiket/saya'], 3);
      expect(completed, isTrue);
    },
  );
  test(
    'ticket events refresh visits while catalog events refresh references',
    () async {
      await c.refresh();
      f.repository.updates.invalidate(kinds: {'TIKET'});
      await f.waitRead('/tiket/saya', 2);
      await f.repository.refresh(const []);
      expect(f.reads['/tiket/saya'], 2);
      expect(f.reads['/dokter'], 1);
      f.repository.updates.invalidate(kinds: {'KATALOG'});
      await f.waitRead('/dokter', 2);
      await f.repository.refresh(const []);
      expect(f.reads['/dokter'], 2);
      expect(f.reads['/tiket/saya'], 2);
    },
  );
  for (final ending in ['close', 'logout', 'account', 'role']) {
    test('$ending discards an old in-flight snapshot', () async {
      final gate = Completer<void>();
      f.gates[('/tiket/saya', 1)] = gate;
      final pending = c.refresh();
      await f.waitRead('/tiket/saya', 1);
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
      expect(c.state.snapshot.collections, isEmpty);
      if (ending != 'close') expect(c.state.load, PatientLoad.sessionEnded);
    });
  }
  testWidgets(
    'Home V6 consumes the scoped Cubit without reads caused by rebuilds',
    (tester) async {
      await tester.pumpWidget(MaterialApp(home: PatientPage(api: f.api)));
      await tester.pumpAndSettle();
      final element = tester.element(find.byType(PatientPage));
      final owner = tester
          .element(
            find.byType(
              BlocBuilder<PatientOverviewCubit, PatientOverviewState>,
            ),
          )
          .read<PatientOverviewCubit>();
      expect(owner.state.load, PatientLoad.loaded);
      expect(find.text('Ambil Antrean'), findsWidgets);
      expect(find.text('Janji Temu'), findsWidgets);
      expect(find.text('Kunjungan Terdekat'), findsNothing);
      final count = f.calls.length;
      (element as StatefulElement).markNeedsBuild();
      await tester.pumpAndSettle();
      expect(f.calls.length, count);
      await tester.pumpWidget(const SizedBox());
      expect(owner.isClosed, isTrue);
    },
  );
}
