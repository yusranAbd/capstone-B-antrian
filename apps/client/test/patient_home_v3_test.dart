import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:queueb_client/src/api.dart';
import 'package:queueb_client/src/app.dart';
import 'package:queueb_client/src/config.dart';
import 'package:queueb_client/src/patient_home.dart';
import 'package:queueb_client/src/patient_home_v6.dart';
import 'package:queueb_client/src/doctor_professional.dart';

import 'patient_v2_test.dart' show PatientV2Backend;
import 'ui_test.dart' show uid;

class HomeBackend extends PatientV2Backend {
  bool manyHomeDoctors = false;
  String? homeScheduleDay;
  Completer<void>? homeGate;
  bool failHomeSchedule = false;
  bool expiredQr = false;
  bool failQr = false, failTicketRead = false;
  Completer<void>? qrGate;
  String? ticketDay;
  @override
  Json get ticket => {
    ...super.ticket,
    if (ticketDay != null) 'tanggalPelayanan': ticketDay,
  };
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
    if (request.url.path.endsWith('/layanan')) {
      final items = manyClinics
          ? [
              service,
              for (var i = 1; i < 11; i++)
                {...service, 'id': 'clinic-$i', 'nama': 'Poliklinik $i'},
            ]
          : [service];
      return reply([
        ...items,
        {
          ...service,
          'id': 'aux-registration',
          'kode': 'PENDAFTARAN',
          'nama': 'Pendaftaran',
          'modeReservasi': 'HIBRIDA',
        },
      ]);
    }
    if (request.url.path.endsWith('/dokter')) {
      return reply([
        for (var i = 0; i < (manyHomeDoctors ? 30 : 1); i++)
          {
            'id': i == 0 ? uid : 'doctor-$i',
            'nama': i == 0 ? 'dr. Sindi QA' : 'dr. Sindi QA $i',
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
    if (request.url.path.endsWith('/tiket/$uid') && failTicketRead) {
      requests.add((request.method, '/tiket/$uid', {}));
      return reply({'message': 'Status tiket belum dapat diperiksa.'}, 503);
    }
    if (request.url.path.endsWith('/qr')) {
      requests.add((request.method, '/tiket/$uid/qr', {}));
      await qrGate?.future;
      if (failQr) {
        return reply({'message': 'Penerbitan QR gagal. Coba lagi.'}, 503);
      }
      return reply({
        'tiketId': uid,
        'qrPayload': expiredQr ? 'expired' : 'SQ1.fixture',
        'berlakuHingga': DateTime.now()
            .add(
              expiredQr
                  ? const Duration(seconds: -1)
                  : const Duration(minutes: 10),
            )
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
      final day = homeScheduleDay ?? today;
      return reply([
        for (var i = 0; i < (manyHomeDoctors ? 30 : 1); i++)
          {
            'id': i == 0 ? 'session-home' : 'session-home-$i',
            'aktif': true,
            'tanggal': day,
            'mulaiPada': '${day}T02:00:00Z',
            'selesaiPada': '${day}T04:00:00Z',
            'dokterLayananId': uid,
            'dokterLayanan': {
              'aktif': true,
              'dokterId': i == 0 ? uid : 'doctor-$i',
              'layananId': uid,
            },
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

  for (final size in [
    Size(320, 568),
    Size(360, 800),
    Size(375, 812),
    Size(390, 844),
    Size(412, 915),
    Size(1366, 768),
  ]) {
    testWidgets('V6 modes, header and five destinations fit $size', (
      tester,
    ) async {
      await launch(
        tester,
        HomeBackend()..manyClinics = true,
        width: size.width,
        height: size.height,
      );
      expect(
        find.text('Rahmat Abdullah Pratama dengan Nama Panjang'),
        findsOneWidget,
      );
      expect(find.byTooltip('Aktivitas tiket'), findsNothing);
      expect(find.byTooltip('Profil akun'), findsNothing);
      expect(find.byType(PatientHomeHeaderV6), findsOneWidget);
      expect(find.byType(PatientHomeService), findsWidgets);
      expect(find.byType(PatientHomeDoctorV6), findsNothing);
      expect(find.text('Kunjungan Terdekat'), findsNothing);
      await press(tester, find.byKey(const ValueKey('home-mode-appointment')));
      expect(find.byType(ChoiceChip), findsNWidgets(12));
      await tester.scrollUntilVisible(
        find.byType(PatientHomeDoctorV6),
        120,
        scrollable: find
            .byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
            )
            .first,
      );
      expect(
        tester
            .widget<PatientHomeDoctorV6>(find.byType(PatientHomeDoctorV6))
            .preview
            .session?['id'],
        'session-home',
      );
      for (final destination in [
        'Reservasi',
        'Tiket Saya',
        'Janji Temu',
        'Profil',
        'Beranda',
      ]) {
        await press(
          tester,
          find.widgetWithText(NavigationDestination, destination),
        );
        expect(find.byType(NavigationDestination), findsNWidgets(5));
        expect(find.byTooltip('Keluar akun'), findsNothing);
        expect(tester.takeException(), isNull);
      }
    });
  }

  testWidgets(
    'bottom profile opens existing account and logout stays available there',
    (tester) async {
      final api = await launch(tester, HomeBackend());
      await press(tester, find.widgetWithText(NavigationDestination, 'Profil'));
      expect(find.text('Profil Saya'), findsOneWidget);
      expect(find.text('Keluar Akun'), findsOneWidget);
      await press(
        tester,
        find.widgetWithText(NavigationDestination, 'Beranda'),
      );
      expect(find.byType(PatientHomeIdentity), findsNothing);
      expect(find.byTooltip('Keluar akun'), findsNothing);
      await press(tester, find.widgetWithText(NavigationDestination, 'Profil'));
      await press(tester, find.text('Keluar Akun'));
      expect(api.user, isNull);
      expect(find.widgetWithText(TextFormField, 'Email'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'home search filters API clinic and doctor then doctor card opens existing detail',
    (tester) async {
      final b = HomeBackend()..manyClinics = true;
      await launch(tester, b);
      await press(tester, find.byKey(const ValueKey('home-mode-appointment')));
      await tester.drag(find.byType(NestedScrollView), const Offset(0, 1000));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'dr. Sindi QA');
      await tester.pumpAndSettle();
      expect(find.byType(ChoiceChip), findsNWidgets(12));
      expect(find.text('Anak \u00b7 Poli Umum'), findsOneWidget);
      await press(tester, find.byType(PatientHomeDoctorV6));
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
        expect(find.text('08:00 – 08:30'), findsOneWidget);
        expect(find.text('RU · Ruang Umum'), findsOneWidget);
        expect(
          tester.getTopLeft(card).dy,
          greaterThan(tester.getBottomLeft(find.byType(TextField).first).dy),
        );
        expect(
          tester.getBottomLeft(card).dy,
          lessThan(tester.getTopLeft(find.byType(PatientHomeModes)).dy),
        );
        expect(find.byType(PatientHomeBanner), findsNothing);
        await press(tester, find.text('QR Code'));
        expect(find.byType(QrImageView), findsOneWidget);
        expect(find.text('Perbarui QR'), findsOneWidget);
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
    'detail stays read-only while direct QR issues once and never renews on polling or check-in',
    (tester) async {
      final b = HomeBackend();
      b.tickets.add(b.ticket);
      await launch(tester, b);
      await press(tester, find.text('Lihat Detail'));
      expect(b.requests.where((r) => r.$1 == 'POST'), isEmpty);
      expect(find.byType(QrImageView), findsNothing);
      await press(tester, find.text('Tutup'));
      await press(tester, find.text('QR Code'));
      expect(
        tester.widget<QrImageView>(find.byType(QrImageView)).semanticsLabel,
        'QR check-in tiket UM-001',
      );
      await tester.pump(const Duration(seconds: 31));
      await tester.pumpAndSettle();
      expect(b.requests.where((r) => r.$1 == 'POST'), hasLength(1));
      b.status = 'CHECK_IN';
      b.tickets[0] = b.ticket;
      await tester.pump(const Duration(seconds: 31));
      await tester.pumpAndSettle();
      expect(find.byType(QrImageView), findsNothing);
      expect(b.requests.where((r) => r.$1 == 'POST'), hasLength(1));
    },
  );

  for (final condition in ['future', 'changedStatus', 'readFailed']) {
    testWidgets('direct QR does not issue when $condition', (tester) async {
      final b = HomeBackend();
      if (condition == 'future') b.ticketDay = b.tomorrow;
      b.tickets.add(b.ticket);
      await launch(tester, b);
      if (condition == 'changedStatus') b.status = 'CHECK_IN';
      if (condition == 'readFailed') b.failTicketRead = true;
      await press(tester, find.text('QR Code'));
      expect(find.byType(QrImageView), findsNothing);
      expect(b.requests.where((r) => r.$1 == 'POST'), isEmpty);
      if (condition == 'future') {
        expect(
          find.textContaining('tanggal pelayanan (${b.tomorrow})'),
          findsOneWidget,
        );
      }
      if (condition == 'readFailed') {
        expect(
          find.text(
            'Layanan sedang mengalami gangguan. Muat ulang data dan coba lagi nanti.',
          ),
          findsOneWidget,
        );
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'direct QR opening coalesces double taps and pending issuance; failed issuance remains visible without retry',
    (tester) async {
      final b = HomeBackend()..qrGate = Completer<void>();
      b.tickets.add(b.ticket);
      await launch(tester, b);
      final action = tester
          .widget<PatientHomeVisit>(find.byType(PatientHomeVisit))
          .onQr!;
      action();
      action();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(b.requests.where((r) => r.$1 == 'POST'), hasLength(1));
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .semanticsLabel,
        'Memuat QR check-in',
      );
      b.failQr = true;
      b.qrGate!.complete();
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Layanan sedang mengalami gangguan. Muat ulang data dan coba lagi nanti.',
        ),
        findsOneWidget,
      );
      expect(find.byType(QrImageView), findsNothing);
      expect(b.requests.where((r) => r.$1 == 'POST'), hasLength(1));
      b.failQr = false;
      await press(tester, find.text('Terbitkan QR'));
      expect(find.byType(QrImageView), findsOneWidget);
      expect(b.requests.where((r) => r.$1 == 'POST'), hasLength(2));
    },
  );

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
      expect(find.text('expired'), findsNothing);
      expect(find.textContaining('QR sudah kedaluwarsa'), findsOneWidget);
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
      await press(tester, find.byKey(const ValueKey('home-mode-appointment')));
      final target = find.widgetWithText(ChoiceChip, 'Poliklinik 1');
      await press(tester, target);
      expect(find.byType(PatientHomeDoctorV6), findsNothing);
      expect(
        find.text(
          'Tidak ada dokter praktik hari ini yang sesuai pencarian atau poliklinik.',
        ),
        findsOneWidget,
      );
      await press(tester, find.widgetWithText(ChoiceChip, 'Semua'));
      expect(find.byType(PatientHomeDoctorV6), findsOneWidget);
      await press(tester, find.byType(PatientHomeDoctorV6));
      expect(find.text('Detail Dokter'), findsOneWidget);
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
      await press(tester, find.byKey(const ValueKey('home-mode-appointment')));
      expect(find.text('Jadwal praktik belum dapat dimuat.'), findsOneWidget);
      expect(find.byType(PatientHomeDoctorV6), findsNothing);
      await press(tester, find.byKey(const ValueKey('home-mode-appointment')));
      await tester.pumpAndSettle();
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
