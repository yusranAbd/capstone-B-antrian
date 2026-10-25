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
import 'package:queueb_client/src/doctor_professional.dart';
import 'package:queueb_client/src/mobile_ui.dart';

import 'patient_v2_test.dart' show PatientV2Backend;
import 'ui_test.dart' show uid;

class HomeBackend extends PatientV2Backend {
  Completer<void>? homeGate;
  bool failHomeSchedule = false;
  bool expiredQr = false;
  Json get appointmentFixture => {
    'id': 'appointment-id-distinct-from-ticket',
    'tiket': ticket,
    'slotPraktik': {
      'mulaiPada': '${today}T01:00:00Z',
      'selesaiPada': '${today}T01:30:00Z',
      'jadwalPraktik': {
        'loket': room,
        'dokterLayanan': {
          'dokter': {'id': uid, 'nama': 'dr. Sindi QA', 'spesialisasi': 'Anak'},
        },
      },
    },
  };
  @override
  Json get user => {
    ...super.user,
    'nama': 'Rahmat Abdullah Pratama dengan Nama Panjang',
  };
  @override
  Future<http.Response> handle(http.Request request) async {
    if (request.url.path.endsWith('/dokter')) {
      return reply([
        {
          'id': uid,
          'nama': 'dr. Sindi QA',
          'spesialisasi': 'Anak',
          'aktif': true,
          'fotoProfil':
              '/media/dokter/11111111-1111-4111-8111-111111111111.webp',
          'dokterLayanan': [
            {'id': uid, 'aktif': true, 'layananId': uid, 'layanan': service},
          ],
        },
      ]);
    }
    if (request.url.path.endsWith('/qr') && expiredQr) {
      requests.add((request.method, '/tiket/$uid/qr', {}));
      return reply({
        'tiketId': uid,
        'qrPayload': 'expired',
        'berlakuHingga': DateTime.now()
            .subtract(const Duration(seconds: 1))
            .toUtc()
            .toIso8601String(),
      });
    }
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
          'Cari Dokter Spesialis',
          'Dokter Pilihan',
          'Akses cepat',
        ]) {
          await tester.ensureVisible(find.text(section));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
        expect(find.byType(ChoiceChip), findsNWidgets(12));
        expect(find.text('Kunjungan Terdekat'), findsNothing);
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
      await tester.enterText(find.byType(TextField).first, 'dr. Sindi QA');
      await tester.pumpAndSettle();
      expect(find.byType(ChoiceChip), findsNWidgets(2));
      expect(find.text('Anak \u00b7 Poli Umum'), findsOneWidget);
      await press(tester, find.byType(PatientHomeDoctor));
      expect(find.text('Detail Dokter'), findsOneWidget);
      expect(find.text('Buat Janji Temu'), findsOneWidget);
      expect(b.requests.where((r) => r.$1 != 'GET'), isEmpty);
    },
  );

  for (final width in [320.0, 360.0, 375.0, 390.0, 412.0, 414.0, 768.0]) {
    testWidgets(
      'V3.1 real appointment follows search and QR uses ticket ID at $width',
      (tester) async {
        final b = HomeBackend();
        b.tickets.add(b.ticket);
        b.appointments.add(b.appointmentFixture);
        await launch(tester, b, width: width);
        final card = find.byType(PatientHomeVisit);
        final view = tester.widget<PatientHomeVisit>(card);
        expect(view.ticket['id'], uid);
        expect(view.doctor['spesialisasi'], 'Anak');
        expect(view.doctor['fotoProfil'], contains('/media/dokter/'));
        expect(
          find.descendant(of: card, matching: find.text('dr. Sindi QA')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: card,
            matching: find.byType(ProfessionalDoctorAvatar),
          ),
          findsOneWidget,
        );
        expect(find.text('08:00 – 08:30 · Asia/Jakarta'), findsOneWidget);
        expect(find.text('RU · Ruang Umum'), findsOneWidget);
        expect(
          tester.getTopLeft(card).dy,
          greaterThan(tester.getBottomLeft(find.byType(TextField).first).dy),
        );
        expect(
          tester.getBottomLeft(card).dy,
          lessThan(tester.getTopLeft(find.text('Cari Dokter Spesialis')).dy),
        );
        expect(find.byType(PatientHomeBanner), findsNothing);
        await press(tester, find.text('QR Code'));
        await press(tester, find.text('Terbitkan QR'));
        expect(
          b.requests.where((r) => r.$1 == 'POST').single.$2,
          '/tiket/$uid/qr',
        );
        expect(find.text('Tiket UM-001'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'expired home QR stays hidden; completed and cancelled visits disappear on reconciliation',
    (tester) async {
      final b = HomeBackend()..expiredQr = true;
      b.tickets.add(b.ticket);
      await launch(tester, b);
      expect(
        tester.widget<PatientHomeVisit>(find.byType(PatientHomeVisit)).doctor,
        isEmpty,
      );
      expect(find.textContaining('08:00 –'), findsNothing);
      await press(tester, find.text('QR Code'));
      await press(tester, find.text('Terbitkan QR'));
      expect(find.text('expired'), findsNothing);
      await press(tester, find.text('Tutup'));
      for (final status in ['SELESAI', 'DIBATALKAN']) {
        b.tickets[0] = {...b.ticket, 'status': status};
        await tester.pump(const Duration(seconds: 31));
        await tester.pumpAndSettle();
        expect(find.text('Kunjungan Terdekat'), findsNothing);
        expect(find.byType(PatientHomeVisit), findsNothing);
      }
    },
  );

  testWidgets(
    'API clinic chips filter doctor cards and preserve clinic navigation',
    (tester) async {
      await launch(tester, HomeBackend()..manyClinics = true);
      final target = find.widgetWithText(ChoiceChip, 'Poliklinik 1');
      await press(tester, target);
      expect(find.byType(PatientHomeDoctor), findsNothing);
      expect(
        find.text('Belum ada dokter yang sesuai pencarian.'),
        findsOneWidget,
      );
      await press(tester, find.widgetWithText(ChoiceChip, 'Semua'));
      expect(find.byType(PatientHomeDoctor), findsOneWidget);
      await press(tester, find.text('Poliklinik dan Dokter'));
      expect(find.byType(ClinicCard), findsWidgets);
    },
  );

  test('nearest display prioritizes an active service over reserved slots on same date', () {
    final b = HomeBackend();
    expect(
      nearestHomeTicket(
        [
          b.ticket,
          {...b.ticket, 'id': 'live', 'status': 'DILAYANI'},
        ],
        [],
        b.today,
      )?['id'],
      'live',
    );
    expect(
      nearestHomeTicket(
        [
          {...b.ticket, 'status': 'DIBATALKAN'},
          {...b.ticket, 'status': 'SELESAI'},
        ],
        [],
        b.today,
      ),
      isNull,
    );
  });

  testWidgets(
    'hero, appointment, clinic, history and activity shortcuts keep existing routes',
    (tester) async {
      await launch(tester, HomeBackend());
      await press(tester, find.text('Janji Temu Dokter'));
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
      await press(tester, find.text('QR Code'));
      expect(find.textContaining('UM-001'), findsWidgets);
      expect(find.byType(AlertDialog), findsOneWidget);
    },
  );

  testWidgets(
    'home loading and schedule error remain explicit without fabricated availability',
    (tester) async {
      final b = HomeBackend()..homeGate = Completer<void>();
      await launch(tester, b, settle: false);
      expect(find.byType(PatientHomeLoading), findsWidgets);
      expect(find.text('Kunjungan Terdekat'), findsNothing);
      b.failHomeSchedule = true;
      b.homeGate!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(PatientHomeVisit), findsNothing);
      expect(find.text('Kunjungan Terdekat'), findsNothing);
      expect(find.text('Jadwal praktik belum dapat dimuat.'), findsOneWidget);
      expect(find.text('Jadwal belum dapat dimuat.'), findsOneWidget);
      await press(tester, find.text('Janji Temu Dokter'));
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
