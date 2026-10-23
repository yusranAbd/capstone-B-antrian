import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:queueb_client/src/api.dart';
import 'package:queueb_client/src/app.dart';
import 'package:queueb_client/src/config.dart';
import 'package:queueb_client/src/patient_home.dart';
import 'package:queueb_client/src/patient_ui.dart';

import 'patient_v2_test.dart' show PatientV2Backend;
import 'ui_test.dart' show uid;

class HomeBackend extends PatientV2Backend {
  Completer<void>? homeGate;
  bool failHomeSchedule = false;
  @override
  Json get user => {
    ...super.user,
    'nama': 'Rahmat Abdullah Pratama dengan Nama Panjang',
  };
  @override
  Future<http.Response> handle(http.Request request) async {
    if (request.url.path.endsWith('/jadwal-praktik') &&
        request.url.queryParameters.isEmpty) {
      await homeGate?.future;
      if (failHomeSchedule) {
        return reply({'message': 'Jadwal tidak tersedia'}, 503);
      }
      return reply([
        {
          'id': 'session-home',
          'aktif': true,
          'tanggal': tomorrow,
          'mulaiPada': '${tomorrow}T02:00:00Z',
          'selesaiPada': '${tomorrow}T04:00:00Z',
          'dokterLayananId': uid,
          'dokterLayanan': {'aktif': true, 'dokterId': uid, 'layananId': uid},
          'loket': room,
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
    HomeBackend backend, {
    double width = 390,
    double height = 844,
    bool settle = true,
  }) async {
    tester.view.physicalSize = Size(width, height);
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
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump(const Duration(milliseconds: 100));
    }
    return api;
  }

  Future<void> press(WidgetTester tester, Finder target) async {
    await tester.ensureVisible(target.last);
    await tester.pumpAndSettle();
    await tester.tap(target.last);
    await tester.pumpAndSettle();
  }

  for (final width in [320.0, 360.0, 375.0, 390.0, 412.0, 414.0, 768.0]) {
    testWidgets(
      'home V3 fits $width with long name, all sections and existing destinations',
      (tester) async {
        await launch(tester, HomeBackend()..manyClinics = true, width: width);
        expect(
          find.text('Rahmat Abdullah Pratama dengan Nama Panjang'),
          findsOneWidget,
        );
        expect(find.byTooltip('Aktivitas tiket'), findsOneWidget);
        expect(find.byTooltip('Profil akun'), findsOneWidget);
        expect(find.byTooltip('Keluar akun'), findsOneWidget);
        for (final section in [
          'Kunjungan terdekat',
          'Poliklinik tersedia',
          'Dokter & Jadwal',
          'Tips Cepat',
        ]) {
          await tester.ensureVisible(find.text(section));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
        expect(
          tester
              .widget<PatientClinicGrid>(find.byType(PatientClinicGrid))
              .clinics,
          hasLength(11),
        );
        expect(
          tester
              .widget<PatientHomeDoctor>(find.byType(PatientHomeDoctor))
              .preview
              .session?['id'],
          'session-home',
        );
        expect(find.textContaining('tahun pengalaman'), findsNothing);
        expect(
          find.textContaining('Penyakit Dalam \u00b7 Poli Umum'),
          findsNothing,
        );
        expect(find.textContaining('\u00c2\u00b7'), findsNothing);
        expect(find.byType(NavigationDestination), findsNWidgets(4));
        await press(
          tester,
          find.widgetWithText(NavigationDestination, 'Pendaftaran'),
        );
        expect(find.text('Poliklinik & Dokter'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'home search filters API clinic and doctor then doctor card opens existing detail',
    (tester) async {
      final b = HomeBackend()..manyClinics = true;
      await launch(tester, b);
      await tester.enterText(find.byType(TextField).first, 'Dokter Umum');
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<PatientClinicGrid>(find.byType(PatientClinicGrid))
            .clinics
            .single['id'],
        uid,
      );
      expect(
        find.text('Spesialisasi belum dicantumkan \u00b7 Poli Umum'),
        findsOneWidget,
      );
      await press(tester, find.byType(PatientHomeDoctor));
      expect(find.text('Detail Dokter'), findsOneWidget);
      expect(find.text('Buat Janji Temu'), findsOneWidget);
      expect(b.requests.where((r) => r.$1 != 'GET'), isEmpty);
    },
  );

  testWidgets(
    'hero, appointment, clinic, history and activity shortcuts keep existing routes',
    (tester) async {
      await launch(tester, HomeBackend());
      await press(tester, find.text('Ambil Antrean'));
      expect(find.text('Poliklinik & Dokter'), findsOneWidget);
      await press(
        tester,
        find.widgetWithText(NavigationDestination, 'Beranda'),
      );
      await press(tester, find.text('Janji Temu Dokter'));
      expect(find.text('Poliklinik & Dokter'), findsOneWidget);
      await press(
        tester,
        find.widgetWithText(NavigationDestination, 'Beranda'),
      );
      await press(tester, find.text('Poliklinik dan Dokter'));
      expect(find.text('Poliklinik & Dokter'), findsOneWidget);
      await press(
        tester,
        find.widgetWithText(NavigationDestination, 'Beranda'),
      );
      await press(tester, find.text('Riwayat Kunjungan'));
      expect(find.text('Riwayat kunjungan'), findsOneWidget);
      await press(
        tester,
        find.widgetWithText(NavigationDestination, 'Beranda'),
      );
      await tester.tap(find.byTooltip('Aktivitas tiket'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Belum ada tiket. Daftar janji temu atau walk-in terlebih dahulu.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'owned nearest ticket replaces status after existing periodic REST reconciliation',
    (tester) async {
      final b = HomeBackend();
      b.tickets.addAll([
        {...b.ticket, 'id': 'later', 'tanggalPelayanan': b.tomorrow},
        b.ticket,
      ]);
      await launch(tester, b);
      expect(
        tester
            .widget<PatientHomeVisit>(find.byType(PatientHomeVisit))
            .ticket['id'],
        uid,
      );
      b.tickets[1] = {...b.ticket, 'status': 'DIPANGGIL'};
      await tester.pump(const Duration(seconds: 31));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<PatientHomeVisit>(find.byType(PatientHomeVisit))
            .ticket['status'],
        'DIPANGGIL',
      );
      await press(tester, find.text('Lihat Tiket'));
      expect(find.textContaining('UM-001'), findsWidgets);
      expect(find.byType(AlertDialog), findsOneWidget);
    },
  );

  testWidgets(
    'home loading and schedule error remain explicit without fabricated availability',
    (tester) async {
      final b = HomeBackend()..homeGate = Completer<void>();
      await launch(tester, b, settle: false);
      await tester.ensureVisible(find.text('Kunjungan terdekat'));
      expect(find.byType(PatientHomeLoading), findsWidgets);
      b.failHomeSchedule = true;
      b.homeGate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Belum ada kunjungan mendatang.'), findsOneWidget);
      expect(find.text('Buat Janji Temu'), findsOneWidget);
      expect(find.text('Jadwal praktik belum dapat dimuat.'), findsOneWidget);
      expect(find.text('Jadwal belum dapat dimuat.'), findsOneWidget);
      await press(tester, find.text('Buat Janji Temu'));
      expect(find.text('Poliklinik & Dokter'), findsOneWidget);
    },
  );

  test('nearest visit excludes terminal and past tickets, merges real appointment tickets without overriding latest ticket snapshot', () {
    final b = HomeBackend();
    final original = [
      {...b.ticket, 'status': 'SELESAI'},
      {...b.ticket, 'id': 'tomorrow', 'tanggalPelayanan': b.tomorrow},
    ];
    expect(
      nearestHomeTicket(original, [
        {'tiket': b.ticket},
      ], b.today)?['id'],
      'tomorrow',
    );
    expect(original.first['status'], 'SELESAI');
    expect(
      nearestHomeTicket(
        [
          {...b.ticket, 'tanggalPelayanan': '2000-01-01'},
        ],
        [],
        b.today,
      ),
      isNull,
    );
    expect(
      nearestHomeTicket([], [
        {'tiket': b.ticket},
      ], b.today)?['id'],
      uid,
    );
  });
}
