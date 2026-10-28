import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:queueb_client/src/features/patient/application/patient_booking_cubit.dart';
import 'package:queueb_client/src/features/patient/application/patient_overview_cubit.dart';
import 'package:queueb_client/src/features/patient/application/patient_reservations_cubit.dart';
import 'package:queueb_client/src/features/patient/application/patient_ticket_cubit.dart';
import 'package:queueb_client/src/features/patient/models/patient_models.dart';
import 'package:queueb_client/src/patient.dart';
import 'package:queueb_client/src/patient_home.dart';
import 'package:timezone/data/latest.dart' as tz;

import 'patient_cubit_fixture.dart';
import 'patient_sync_test.dart' show FakePatientSocket;

void main() {
  setUpAll(tz.initializeTimeZones);
  Future<void> open(WidgetTester tester, PatientFixture f) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: PatientPage(api: f.api, repository: f.repository),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> qr(WidgetTester tester) async {
    final visit = tester.widget<PatientHomeVisit>(
      find.byType(PatientHomeVisit),
    );
    visit.onQr!();
    await tester.pumpAndSettle();
  }

  testWidgets(
    'all five destinations retain one feed and shared visit owners without rebuild fetches',
    (tester) async {
      final sockets = <FakePatientSocket>[];
      final f = PatientFixture(
        realtime: true,
        socketFactory: (_, _) {
          final socket = FakePatientSocket();
          sockets.add(socket);
          return socket;
        },
      );
      addTearDown(f.dispose);
      await open(tester, f);
      final context = tester.element(
        find.byType(BlocBuilder<PatientOverviewCubit, PatientOverviewState>),
      );
      final overview = context.read<PatientOverviewCubit>(),
          booking = context.read<PatientBookingCubit>(),
          visits = context.read<PatientReservationsCubit>();
      for (final label in [
        'Reservasi',
        'Tiket Saya',
        'Janji Temu',
        'Profil',
        'Beranda',
      ]) {
        final target = find.widgetWithText(NavigationDestination, label).last;
        await tester.ensureVisible(target);
        await tester.tap(target);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      expect(sockets, hasLength(1));
      expect(f.reads['/dokter'], 1);
      expect(f.reads['/tiket/saya'], 1);
      expect(overview.state.snapshot, same(visits.state.snapshot));
      expect(booking.patient, same(f.repository));
      expect(find.byType(PatientHomeVisit), findsNothing);
      expect(f.writes, 0);
      await tester.pumpWidget(const SizedBox());
      f.dispose();
      expect(overview.isClosed, isTrue);
      expect(booking.isClosed, isTrue);
      expect(visits.isClosed, isTrue);
    },
  );
  testWidgets(
    'reconnect and burst typed invalidations reuse the feed and do not replay commands',
    (tester) async {
      final sockets = <FakePatientSocket>[];
      final f = PatientFixture(
        realtime: true,
        socketFactory: (_, _) {
          final socket = FakePatientSocket();
          sockets.add(socket);
          return socket;
        },
      );
      addTearDown(f.dispose);
      await open(tester, f);
      for (var i = 0; i < 20; i++) {
        sockets.single.fire('patient:updated', {
          'versiSkema': 1,
          'eventId': 'ticket-$i',
          'jenis': 'TIKET',
        });
      }
      await tester.pumpAndSettle();
      expect(f.reads['/tiket/saya'], 2);
      expect(f.reads['/dokter'], 1);
      expect(f.writes, 0);
      f.api.accessToken = 'fixture-rotated';
      f.api.notifyListeners();
      expect(sockets, hasLength(2));
      expect(sockets.first.disposed, isTrue);
      sockets.last.fire('patient:ready', {'versiSkema': 1});
      await tester.pumpAndSettle();
      expect(f.reads['/dokter'], 2);
      expect(f.writes, 0);
      await f.api.clearSession();
      await tester.pumpAndSettle();
      expect(sockets.last.disposed, isTrue);
      expect(f.repository.snapshot.collections, isEmpty);
      expect(find.text('Pasien A'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      f.dispose();
    },
  );
  testWidgets('QR expiry clears presentation without automatic QR renewal', (
    tester,
  ) async {
    final f = PatientFixture();
    addTearDown(f.dispose);
    f.data['/tiket/saya'] = [f.ticket()];
    f.qrLifetime = const Duration(seconds: 3);
    await open(tester, f);
    await qr(tester);
    expect(find.byType(QrImageView), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.byType(QrImageView), findsNothing);
    expect(f.writes, 1);
    await tester.tap(find.text('Tutup'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    f.dispose();
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'logout removes QR and clears all portal Cubits and the dialog scope',
    (tester) async {
      final f = PatientFixture();
      addTearDown(f.dispose);
      f.data['/tiket/saya'] = [f.ticket()];
      await open(tester, f);
      await qr(tester);
      final owner = tester
          .element(
            find.byType(BlocConsumer<PatientTicketCubit, PatientTicketState>),
          )
          .read<PatientTicketCubit>();
      expect(find.byType(QrImageView), findsOneWidget);
      await tester.runAsync(f.api.clearSession);
      await tester.pumpAndSettle();
      expect(find.byType(QrImageView), findsNothing);
      expect(owner.isClosed, isTrue);
      expect(f.repository.snapshot.collections, isEmpty);
      await tester.pumpWidget(const SizedBox());
      f.dispose();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'disposing a ticket dialog during pending QR drops the late response and timer',
    (tester) async {
      final f = PatientFixture();
      addTearDown(f.dispose);
      f.data['/tiket/saya'] = [f.ticket()];
      await open(tester, f);
      final gate = Completer<void>();
      f.mutationGate = gate;
      tester.widget<PatientHomeVisit>(find.byType(PatientHomeVisit)).onQr!();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(f.writes, 1);
      await tester.pumpWidget(const SizedBox());
      f.dispose();
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byType(QrImageView), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'logout during pending overview clears every projection before the response arrives',
    (tester) async {
      final f = PatientFixture();
      addTearDown(f.dispose);
      await open(tester, f);
      final context = tester.element(
        find.byType(BlocBuilder<PatientOverviewCubit, PatientOverviewState>),
      );
      final overview = context.read<PatientOverviewCubit>(),
          visits = context.read<PatientReservationsCubit>();
      final gate = Completer<void>();
      f.gates[('/tiket/saya', 2)] = gate;
      final pending = overview.refresh();
      await tester.pump();
      await tester.runAsync(f.api.clearSession);
      expect(overview.state.snapshot.collections, isEmpty);
      expect(visits.state.snapshot.collections, isEmpty);
      gate.complete();
      await pending;
      await tester.pumpAndSettle();
      expect(overview.state.load, PatientLoad.sessionEnded);
      await tester.pumpWidget(const SizedBox());
      f.dispose();
    },
  );
}
