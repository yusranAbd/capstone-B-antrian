import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:queueb_client/src/api.dart';
import 'package:queueb_client/src/app.dart';
import 'package:queueb_client/src/config.dart';
import 'package:queueb_client/src/mobile_ui.dart';
import 'package:queueb_client/src/patient_ui.dart';

import 'doctor_schedule_test.dart' show DoctorBackend;
import 'ui_test.dart' show uid;

class PatientV2Backend extends DoctorBackend {
  bool manyClinics = false, mixedDoctors = false, walkOnly = false;
  @override
  Json get service => {
    ...super.service,
    if (walkOnly) 'modeReservasi': 'ANTREAN_HARIAN',
  };
  @override
  Future<http.Response> handle(http.Request request) async {
    if (request.url.path.endsWith('/layanan') && manyClinics) {
      return reply([
        service,
        for (var i = 1; i < 11; i++)
          {...service, 'id': 'clinic-$i', 'nama': 'Poliklinik $i'},
        {
          ...service,
          'id': 'closed',
          'nama': 'Poliklinik Nonaktif',
          'aktif': false,
        },
      ]);
    }
    if (request.url.path.endsWith('/dokter') && mixedDoctors) {
      return reply([
        {
          'id': uid,
          'nama': 'dr. Indah',
          'spesialisasi': 'Penyakit Dalam',
          'aktif': true,
          'dokterLayanan': [
            {'id': uid, 'aktif': true, 'layananId': uid, 'layanan': service},
          ],
        },
        {
          'id': 'inactive',
          'nama': 'Dokter Nonaktif',
          'aktif': false,
          'dokterLayanan': [
            {'aktif': true, 'layananId': uid},
          ],
        },
        {
          'id': 'unlinked',
          'nama': 'Dokter Poli Lain',
          'aktif': true,
          'dokterLayanan': [
            {'aktif': true, 'layananId': 'other'},
          ],
        },
        {
          'id': 'link-inactive',
          'nama': 'Dokter Relasi Nonaktif',
          'aktif': true,
          'dokterLayanan': [
            {'aktif': false, 'layananId': uid},
          ],
        },
      ]);
    }
    return super.handle(request);
  }
}

void main() {
  setUpAll(tz.initializeTimeZones);

  Future<QueueApi> launch(
    WidgetTester tester,
    PatientV2Backend backend, {
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
    return api;
  }

  Future<void> press(WidgetTester tester, Finder target) async {
    if (target.evaluate().isEmpty) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 8000));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        target,
        160,
        scrollable: find.byType(Scrollable).first,
      );
    }
    await tester.ensureVisible(target.last);
    await tester.pumpAndSettle();
    await tester.tap(target.last);
    await tester.pumpAndSettle();
  }

  Future<void> clinic(WidgetTester tester) async {
    await press(tester, find.text('Janji Temu Dokter'));
    await press(tester, find.byType(ClinicCard).first);
  }

  Future<void> review(WidgetTester tester) async {
    await clinic(tester);
    await press(tester, find.text('Lihat Detail Dokter'));
    await press(tester, find.text('Buat Janji Temu'));
    await press(tester, find.text('Lihat slot'));
    await press(tester, find.text('Sisa slot 2'));
    await press(tester, find.widgetWithText(FilledButton, 'Lanjutkan'));
  }

  Iterable<(String, String, Json)> bookings(PatientV2Backend backend) =>
      backend.requests.where((r) => r.$1 == 'POST' && r.$2 == '/janji-temu');

  testWidgets(
    'home clinic grid contains all eleven API clinics and omits inactive entries',
    (tester) async {
      await launch(tester, PatientV2Backend()..manyClinics = true);
      await tester.ensureVisible(find.byType(ChoiceChip).first);
      expect(find.byType(ChoiceChip), findsNWidgets(12));
      expect(find.text('Poliklinik Nonaktif'), findsNothing);
    },
  );

  testWidgets(
    'specialty search filters API clinics without adding fixture clinics',
    (tester) async {
      await launch(
        tester,
        PatientV2Backend()
          ..manyClinics = true
          ..mixedDoctors = true,
      );
      await tester.enterText(find.byType(TextField).first, 'Penyakit Dalam');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(ChoiceChip).first);
      expect(find.byType(ChoiceChip), findsNWidgets(2));
      expect(find.widgetWithText(ChoiceChip, 'Poli Umum'), findsOneWidget);
    },
  );

  testWidgets(
    'clinic page filters inactive doctor, inactive link and unrelated clinic',
    (tester) async {
      await launch(tester, PatientV2Backend()..mixedDoctors = true);
      await clinic(tester);
      expect(find.byType(PatientDoctorCard), findsOneWidget);
      expect(find.text('dr. Indah'), findsOneWidget);
      expect(find.textContaining('Dokter Nonaktif'), findsNothing);
      expect(find.textContaining('Dokter Poli Lain'), findsNothing);
      expect(find.textContaining('Dokter Relasi Nonaktif'), findsNothing);
      expect(
        find.textContaining('slot tersedia pada sesi terdekat'),
        findsOneWidget,
      );
      await press(tester, find.text('Lihat Detail Dokter'));
      expect(find.text('Detail Dokter'), findsOneWidget);
      expect(find.text('Penyakit Dalam'), findsOneWidget);
      expect(find.text('4.9'), findsNothing);
      expect(find.textContaining('tahun pengalaman'), findsNothing);
    },
  );

  for (final width in [320.0, 375.0, 414.0, 768.0]) {
    testWidgets(
      'review at $width shows factual context and waits for explicit confirmation',
      (tester) async {
        final backend = PatientV2Backend();
        await launch(tester, backend, width: width);
        await review(tester);
        expect(find.byType(AppointmentReview), findsOneWidget);
        expect(bookings(backend), isEmpty);
        final dialog = find.byType(AppointmentReview);
        expect(
          find.descendant(of: dialog, matching: find.text('Dokter Umum')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: dialog, matching: find.text('Poli Umum')),
          findsOneWidget,
        );
        expect(find.text('RU · Ruang Umum'), findsOneWidget);
        expect(find.textContaining('Asia/Jakarta'), findsWidgets);
        expect(find.text('UM-001'), findsNothing);
        await press(
          tester,
          find.widgetWithText(FilledButton, 'Konfirmasi Janji Temu'),
        );
        expect(bookings(backend).single.$3, {'slotPraktikId': uid});
        expect(find.text('UM-001'), findsOneWidget);
        expect(
          backend.appointments.single['id'],
          isNot(backend.tickets.single['id']),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'walk-in only clinic keeps doctor information read-only and reservation available',
    (tester) async {
      final backend = PatientV2Backend()..walkOnly = true;
      await launch(tester, backend);
      await press(tester, find.text('Daftar Walk-in'));
      await press(tester, find.byType(ClinicCard).first);
      await press(tester, find.text('Lihat Detail Dokter'));
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Buat Janji Temu'),
            )
            .onPressed,
        isNull,
      );
      await press(tester, find.byTooltip('Kembali'));
      await press(tester, find.text('Reservasi walk-in'));
      await press(tester, find.text('Lanjutkan'));
      expect(
        backend.requests
            .where((r) => r.$1 == 'POST' && r.$2 == '/reservasi')
            .single
            .$3,
        {'layananId': uid, 'tanggalAntrean': backend.today},
      );
      expect(bookings(backend), isEmpty);
    },
  );

  testWidgets('back from review preserves selection and performs no POST', (
    tester,
  ) async {
    final backend = PatientV2Backend();
    await launch(tester, backend);
    await review(tester);
    await press(tester, find.widgetWithText(TextButton, 'Kembali'));
    expect(bookings(backend), isEmpty);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Lanjutkan'))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets(
    'reconciliation during review rejects a slot that became unavailable',
    (tester) async {
      final backend = PatientV2Backend();
      await launch(tester, backend);
      await review(tester);
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
      await press(
        tester,
        find.widgetWithText(FilledButton, 'Konfirmasi Janji Temu'),
      );
      expect(bookings(backend), isEmpty);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 8000));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Pilihan berubah selama konfirmasi'),
        findsOneWidget,
      );
    },
  );

  testWidgets('history and active card use only owned actual tickets', (
    tester,
  ) async {
    final backend = PatientV2Backend();
    backend.tickets.add({
      ...backend.ticket,
      'id': 'done',
      'status': 'SELESAI',
      'nomorAntrean': 'UM-004',
    });
    backend.tickets.add(backend.ticket);
    await launch(tester, backend);
    await tester.ensureVisible(find.text('Kunjungan Terdekat'));
    expect(find.text('Kunjungan Terdekat'), findsOneWidget);
    expect(find.text('UM-001'), findsOneWidget);
    await press(tester, find.text('Riwayat Kunjungan'));
    expect(find.text('Riwayat kunjungan'), findsOneWidget);
    expect(find.text('UM-004 · Poli Umum'), findsOneWidget);
    expect(find.text('UM-001 · Poli Umum'), findsNothing);
  });

  test('calendar DATE and slot labels follow configured service timezone', () {
    final config = AppConfig(
      apiBaseUrl: 'http://localhost/api/v1',
      serviceTimeZone: 'Asia/Jayapura',
    );
    expect(patientDate('2026-10-21T00:00:00Z'), 'Rabu, 21 Oktober 2026');
    expect(
      patientTime({
        'mulaiPada': '2026-10-21T23:30:00Z',
        'selesaiPada': '2026-10-22T00:00:00Z',
      }, config),
      '08:30 – 09:00',
    );
  });
}
