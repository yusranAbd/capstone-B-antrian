import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:queueb_client/src/api.dart';
import 'package:queueb_client/src/app.dart';
import 'package:queueb_client/src/config.dart';
import 'package:queueb_client/src/doctor_schedule_ui.dart';
import 'package:queueb_client/src/mobile_ui.dart';

import 'ui_test.dart' show FakeBackend, uid;

class DoctorBackend extends FakeBackend {
  DoctorBackend() : super('USER');
  bool emptySchedule = false, conflict = false, failSchedule = false;
  bool emptyDoctors = false, emptySlots = false;
  Completer<void>? scheduleGate;
  final queries = <Map<String, String>>[];
  String get tomorrow =>
      calendarDate(DateTime.parse(today).add(const Duration(days: 1)));

  @override
  Future<http.Response> handle(http.Request request) async {
    final path = request.url.path;
    if (path.endsWith('/dokter') && emptyDoctors) return reply([]);
    if (path.endsWith('/slot-praktik') && emptySlots) return reply([]);
    if (path.endsWith('/jadwal-praktik')) {
      queries.add(request.url.queryParameters);
      if (failSchedule) return reply({'message': 'Jadwal gagal dimuat'}, 503);
      if (emptySchedule) return reply([]);
      final selected = request.url.queryParameters['tanggal'];
      if (selected != null) await scheduleGate?.future;
      return reply([
        for (final day in [today, tomorrow])
          if (selected == null || selected == day)
            {
              'id': day,
              'tanggal': '${day}T00:00:00.000Z',
              'mulaiPada': '${day}T02:00:00Z',
              'selesaiPada': '${day}T04:00:00Z',
              'loket': room,
              'dokterLayanan': {
                'dokterId': uid,
                'dokter': {'id': uid},
              },
            },
      ]);
    }
    if (path.endsWith('/janji-temu') && request.method == 'POST' && conflict) {
      requests.add(('POST', '/janji-temu', object(jsonDecode(request.body))));
      slotsAvailable = false;
      return reply({'message': 'Slot sudah penuh'}, 409);
    }
    return super.handle(request);
  }
}

void main() {
  setUpAll(tz.initializeTimeZones);
  Future<void> press(WidgetTester tester, Finder finder) async {
    if (finder.evaluate().isEmpty) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 6000));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        finder,
        180,
        scrollable: find.byType(Scrollable).first,
      );
    }
    await tester.ensureVisible(finder.last);
    await tester.pumpAndSettle();
    await tester.tap(finder.last);
    await tester.pumpAndSettle();
  }

  Future<QueueApi> open(
    WidgetTester tester,
    DoctorBackend backend, {
    double width = 375,
  }) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final api =
        QueueApi(
            config: AppConfig(
              apiBaseUrl: 'http://localhost/api/v1',
              realtime: false,
            ),
            client: MockClient(backend.handle),
          )
          ..accessToken = 'test'
          ..user = backend.user;
    addTearDown(api.dispose);
    await tester.pumpWidget(QueueBApp(api: api));
    await tester.pumpAndSettle();
    await press(tester, find.text('Janji Temu Dokter'));
    await press(tester, find.byType(ClinicCard).first);
    return api;
  }

  Future<void> detail(WidgetTester tester) =>
      press(tester, find.text('Lihat Jadwal'));
  Future<void> slot(WidgetTester tester) async {
    await detail(tester);
    await press(tester, find.text('Lihat slot'));
  }

  test(
    'slot states distinguish full, inactive and other server unavailability',
    () {
      expect(
        consultationSlotStatus({'aktif': false, 'sisaKapasitas': 0}),
        'Tidak aktif',
      );
      expect(
        consultationSlotStatus({'tersedia': false, 'sisaKapasitas': 0}),
        'Penuh',
      );
      expect(
        consultationSlotStatus({'tersedia': false, 'sisaKapasitas': 2}),
        'Tidak tersedia',
      );
      expect(
        consultationSlotStatus({'tersedia': true, 'sisaKapasitas': 2}),
        'Tersedia',
      );
    },
  );

  for (final width in [320.0, 375.0, 414.0, 768.0]) {
    testWidgets('doctor, real calendar, slot grid fit width $width', (
      tester,
    ) async {
      final backend = DoctorBackend();
      await open(tester, backend, width: width);
      expect(find.text('Tersedia Hari Ini'), findsNothing);
      await slot(tester);
      expect(find.byType(PracticeDateStrip), findsOneWidget);
      expect(find.text('09:00 – 09:15'), findsOneWidget);
      expect(find.text('Sisa slot 2'), findsOneWidget);
      await press(tester, find.text('Sisa slot 2'));
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Booking janji temu'),
            )
            .onPressed,
        isNotNull,
      );
      expect(
        backend.queries.any(
          (q) =>
              q['dokterId'] == uid &&
              q['layananId'] == uid &&
              q['tanggal'] == backend.today,
        ),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('clinic-name search keeps its doctors visible', (tester) async {
    await open(tester, DoctorBackend());
    await tester.enterText(find.byType(TextField).first, 'Poli Umum');
    await tester.pumpAndSettle();
    await press(tester, find.text('Lihat Jadwal'));
    expect(find.byType(DoctorProfileCard), findsOneWidget);
  });

  testWidgets(
    'calendar dates come only from API and date change clears selected slot',
    (tester) async {
      final backend = DoctorBackend();
      await open(tester, backend);
      await slot(tester);
      await press(tester, find.text('Sisa slot 2'));
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 4000));
      await tester.pumpAndSettle();
      final strip = tester.widget<PracticeDateStrip>(
        find.byType(PracticeDateStrip),
      );
      expect(strip.dates, [backend.today, backend.tomorrow]);
      strip.onChanged(backend.tomorrow);
      await tester.pumpAndSettle();
      expect(backend.queries.last['tanggal'], backend.tomorrow);
      expect(find.byType(ConsultationSlotGrid), findsNothing);
      await press(tester, find.text('Booking janji temu'));
      expect(
        backend.requests.where((r) => r.$1 == 'POST' && r.$2 == '/janji-temu'),
        isEmpty,
      );
    },
  );

  testWidgets(
    'calendar picker restricts selectable dates to backend practice DATE',
    (tester) async {
      final backend = DoctorBackend();
      await open(tester, backend);
      await detail(tester);
      await press(tester, find.text('Kalender · ${backend.today}'));
      final dialog = tester.widget<DatePickerDialog>(
        find.byType(DatePickerDialog),
      );
      expect(
        dialog.selectableDayPredicate!(DateTime.parse(backend.today)),
        isTrue,
      );
      expect(
        dialog.selectableDayPredicate!(
          DateTime.parse(backend.tomorrow).add(const Duration(days: 1)),
        ),
        isFalse,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'empty practice and server failure provide recovery without fake dates',
    (tester) async {
      final backend = DoctorBackend()..emptySchedule = true;
      await open(tester, backend);
      await detail(tester);
      expect(find.byType(PracticeDateStrip), findsNothing);
      await press(tester, find.text('Muat ulang jadwal'));
      expect(
        find.textContaining('Dokter belum memiliki jadwal'),
        findsOneWidget,
      );
      backend.failSchedule = true;
      await press(tester, find.text('Muat ulang jadwal'));
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 4000));
      await tester.pumpAndSettle();
      expect(find.textContaining('Jadwal gagal dimuat'), findsOneWidget);
      backend.failSchedule = false;
      await press(tester, find.text('Coba lagi'));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'empty doctor list and empty consultation slots have distinct empty states',
    (tester) async {
      final backend = DoctorBackend()..emptyDoctors = true;
      await open(tester, backend);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -800));
      await tester.pumpAndSettle();
      expect(
        find.text('Belum ada dokter pada poliklinik ini.'),
        findsOneWidget,
      );
      backend.emptyDoctors = false;
      await press(tester, find.text('Beranda'));
      await press(tester, find.text('Janji Temu Dokter'));
      await press(tester, find.byType(ClinicCard).first);
      // Reconcile through existing foreground lifecycle, not a second socket.
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      backend.emptySlots = true;
      await slot(tester);
      expect(
        find.text('Belum ada slot konsultasi pada sesi ini.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'foreground reconciliation invalidates a selected slot when server availability changes',
    (tester) async {
      final backend = DoctorBackend();
      await open(tester, backend);
      await slot(tester);
      await press(tester, find.text('Sisa slot 2'));
      backend.slotsAvailable = false;
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Booking janji temu'),
            )
            .onPressed,
        isNull,
      );
      expect(find.text('Sisa slot 0'), findsOneWidget);
    },
  );

  testWidgets(
    'doctor removal during an in-flight schedule read releases loading and rejects the late response',
    (tester) async {
      final backend = DoctorBackend();
      await open(tester, backend);
      backend.scheduleGate = Completer<void>();
      await tester.ensureVisible(find.text('Lihat Jadwal'));
      await tester.tap(find.text('Lihat Jadwal'));
      await tester.pump();
      backend.emptyDoctors = true;
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(LinearProgressIndicator), findsNothing);
      backend.scheduleGate!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(DoctorProfileCard), findsNothing);
      expect(find.byType(PracticeDateStrip), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '409 after confirmation clears selection, reloads slots and never retries booking',
    (tester) async {
      final backend = DoctorBackend()..conflict = true;
      await open(tester, backend);
      await slot(tester);
      await press(tester, find.text('Sisa slot 2'));
      await press(tester, find.text('Booking janji temu'));
      await press(tester, find.text('Lanjutkan'));
      expect(
        backend.requests
            .where((r) => r.$1 == 'POST' && r.$2 == '/janji-temu')
            .single
            .$3,
        {'slotPraktikId': uid},
      );
      await press(tester, find.text('Sisa slot 0'));
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Sisa slot 0'),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Booking janji temu'),
            )
            .onPressed,
        isNull,
      );
      expect(
        find.text('Seluruh slot penuh. Pilih sesi atau tanggal lain.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
