import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:queueb_client/src/api.dart';
import 'package:queueb_client/src/config.dart';
import 'package:queueb_client/src/features/patient/models/patient_queue_models.dart';
import 'package:queueb_client/src/patient_design.dart';
import 'package:queueb_client/src/patient_home_v7.dart';
import 'package:queueb_client/src/patient_home_v8.dart';
import 'package:queueb_client/src/patient_navigation.dart';
import 'package:queueb_client/src/patient_ui.dart';
import 'package:queueb_client/src/queueb_motion.dart';

const _service = <String, dynamic>{
  'id': 'registration',
  'kode': 'PENDAFTARAN',
  'nama': 'Pendaftaran',
};

void main() {
  setUpAll(tz.initializeTimeZones);
  for (final width in [320.0, 360.0, 390.0, 430.0]) {
    for (final scale in [1.3, 1.5, 2.0]) {
      testWidgets(
        'header, compact visit and four menus fit width=$width text=$scale',
        (t) async {
          t.view.physicalSize = Size(width, 844);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.resetPhysicalSize);
          addTearDown(t.view.resetDevicePixelRatio);
          var calls = 0, requests = 0;
          final api =
              QueueApi(
                  config: AppConfig(
                    apiBaseUrl: 'http://localhost/api/v1',
                    realtime: false,
                  ),
                  client: MockClient((_) async {
                    requests++;
                    return http.Response('[]', 200);
                  }),
                )
                ..user = {
                  'id': 'self',
                  'nama': 'Nama Pasien Panjang dari Sesi yang Sedang Aktif',
                  'peran': 'USER',
                };
          final search = TextEditingController();
          addTearDown(api.dispose);
          addTearDown(search.dispose);
          await t.pumpWidget(
            MaterialApp(
              theme: PatientDesign.theme,
              home: Builder(
                builder: (root) => MediaQuery(
                  data: MediaQuery.of(root)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: Builder(
                    builder: (context) => Scaffold(
                      appBar: PatientHomeAppBarV8(
                        api: api,
                        height: PatientHomeAppBarV8.heightFor(context),
                        onProfile: () {},
                        onNotifications: () {},
                      ),
                      bottomNavigationBar: PatientBottomNavigation(
                        selectedIndex: 0,
                        onSelected: (_) {},
                      ),
                      body: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            PatientHomeWelcomeV8(
                              name: '${api.user!['nama']}',
                              now: DateTime(2026, 10, 31, 8),
                              controller: search,
                              onSearch: (_) {},
                            ),
                            const SizedBox(height: 12),
                            PatientHomeVisitV8(
                              config: api.config,
                              ticket: const {
                                'id': 'own-ticket',
                                'layanan': _service,
                                'nomorAntrean': 'PEN-012',
                                'tanggalPelayanan': '2026-10-31',
                                'status': 'DIPESAN',
                              },
                              appointment: const {
                                'slotPraktik': {
                                  'mulaiPada': '2026-10-31T02:00:00Z',
                                  'selesaiPada': '2026-10-31T02:30:00Z',
                                },
                              },
                              onOpen: () => calls++,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
          expect(find.textContaining('09:00 – 09:30'), findsOneWidget);
          await t.ensureVisible(find.text('Lihat Detail'));
          await t.pumpAndSettle();
          await t.tap(find.text('Lihat Detail'));
          await t.pumpAndSettle();
          expect(calls, 1);
          expect(requests, 0);
          await t.pumpWidget(const SizedBox());
        },
      );
    }
  }
  test('paper contour cuts both sides and the perforation endpoints without losing the body', () {
    final path = const PatientTicketClipper(82).getClip(const Size(358, 160));
    for (final hole in [
      const Offset(1, 80),
      const Offset(357, 80),
      const Offset(276, 1),
      const Offset(276, 159),
    ]) {
      expect(path.contains(hole), isFalse);
    }
    expect(path.contains(const Offset(100, 80)), isTrue);
    expect(path.contains(const Offset(310, 80)), isTrue);
    expect(path.contains(const Offset(276, 30)), isTrue);
  });

  test('four visible destinations explicitly preserve six internal branch identities', () {
    expect(patientBottomTabs, [0, 2, 6, 5]);
    expect(patientBottomBranches, [0, 1, 5, 4]);
    for (var i = 0; i < 4; i++) {
      expect(
        patientBottomIndex(patientBranchTabs[patientBottomBranches[i]]),
        i,
      );
    }
    expect(patientBottomIndex(1), 1); // old tickets
    expect(patientBottomIndex(3), 1); // old agenda
    expect(patientBottomIndex(4), 1); // old internal history
  });

  test('service hours keep weekday/service identity and DB wall clock, not an instant offset', () {
    final rows = <Json>[
      {
        'layananId': 'registration',
        'hari': 'SABTU',
        'jamBuka': '1970-01-01T08:00:00.000Z',
        'jamTutup': '1970-01-01T16:00:00.000Z',
        'aktif': true,
      },
      {
        'layananId': 'other',
        'hari': 'SABTU',
        'jamBuka': '09:00',
        'jamTutup': '21:00',
        'aktif': true,
      },
      {
        'layananId': 'registration',
        'hari': 'JUMAT',
        'jamBuka': '10:00',
        'jamTutup': '11:00',
        'aktif': true,
      },
      {
        'layananId': 'registration',
        'hari': 'SABTU',
        'jamBuka': '07:00',
        'jamTutup': '20:00',
        'aktif': false,
      },
    ];
    expect(
      patientServiceHours(rows, 'registration', '2026-10-31'),
      '08.00–16.00',
    );
    expect(
      patientServiceHours(rows, 'registration', '2026-10-31', available: false),
      'Jam belum tersedia',
    );
    expect(
      patientServiceHours(rows, 'registration', '2026-11-01'),
      'Tidak ada jadwal hari ini',
    );
    expect(
      patientServiceHours(
        [
          {
            'layananId': 'registration',
            'hari': 'SABTU',
            'jamBuka': '99:00',
            'jamTutup': 'garbage',
            'aktif': true,
          },
        ],
        'registration',
        '2026-10-31',
      ),
      'Jam belum tersedia',
    );
  });

  Widget scene(
    WidgetTester t, {
    double scale = 1,
    bool reduced = false,
    Json clinic = _service,
    Json? ticket,
    PatientQueueView? queue,
    VoidCallback? onTap,
  }) => MaterialApp(
    theme: PatientDesign.theme,
    home: MediaQuery(
      data: MediaQueryData.fromView(t.view).copyWith(
        textScaler: TextScaler.linear(scale),
        disableAnimations: reduced,
      ),
      child: Scaffold(
        body: Center(
          child: SizedBox(
            width: math.min(t.view.physicalSize.width - 32, 648),
            child: SingleChildScrollView(
              child: PatientServiceTicketV8(
                clinic: clinic,
                ticket: ticket,
                queue: queue,
                hours: '08.00–16.00',
                onTap: onTap ?? () {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
  PatientQueueView queue(
    int total,
    String serving, {
    bool live = true,
    String id = 'registration',
  }) => PatientQueueView(
    summary: PatientQueueSummary(
      id,
      '2026-10-31',
      DateTime.now().toUtc(),
      total,
      2,
      [PatientServingNumber('room', 'REG', serving)],
    ),
    live: live,
  );

  for (final width in [320.0, 360.0, 390.0, 430.0, 768.0, 1366.0]) {
    for (final scale in [1.0, 1.3, 1.5, 2.0]) {
      testWidgets(
        'paper ticket remains readable at width=$width scale=$scale',
        (t) async {
          t.view.physicalSize = Size(width, 1000);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.resetPhysicalSize);
          addTearDown(t.view.resetDevicePixelRatio);
          await t.pumpWidget(
            scene(
              t,
              scale: scale,
              clinic: {
                ..._service,
                'nama': 'Kasir / Pembayaran dan Administrasi Pelayanan',
              },
              ticket: const {'nomorAntrean': 'PENDAFTARAN-2026-000123'},
              queue: queue(42, 'PENDAFTARAN-2026-000121'),
            ),
          );
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
          expect(find.text('PENDAFTARAN-2026-000123'), findsOneWidget);
          expect(find.text('PENDAFTARAN-2026-000121'), findsOneWidget);
          expect(find.text('42'), findsOneWidget);
          expect(find.text('Ambil Nomor Antrean'), findsNothing);
          expect(find.byType(IconButton), findsNothing);
          expect(
            t.getRect(find.byType(PatientServiceTicketV8)).width,
            lessThanOrEqualTo(648),
          );
        },
      );
    }
  }

  for (final reduced in [false, true]) {
    testWidgets(
      'paper press/keyboard calls the existing action once, reduced=$reduced',
      (t) async {
        var calls = 0;
        await t.pumpWidget(scene(t, reduced: reduced, onTap: () => calls++));
        await t.pumpAndSettle();
        final card = find.byType(PatientServiceTicketV8);
        final down = await t.startGesture(t.getCenter(card));
        await t.pump(QueueBMotion.press);
        expect(
          t
              .widget<AnimatedScale>(
                find.descendant(of: card, matching: find.byType(AnimatedScale)),
              )
              .scale,
          reduced ? 1 : QueueBMotion.pressedScale,
        );
        await down.up();
        await t.pumpAndSettle();
        expect(calls, 1);
        final box = t.getRect(card);
        await t.tapAt(Offset(box.left + 1, box.center.dy));
        await t.pumpAndSettle();
        expect(calls, 1);
        await t.sendKeyEvent(LogicalKeyboardKey.tab);
        await t.pump();
        await t.sendKeyEvent(LogicalKeyboardKey.enter);
        await t.pumpAndSettle();
        expect(calls, 2);
      },
    );
  }

  testWidgets(
    'authoritative counter/serving stay distinct, duplicate values do not replay and foreign summary is hidden',
    (t) async {
      final handle = t.ensureSemantics();
      try {
        await t.pumpWidget(
          scene(
            t,
            ticket: const {'nomorAntrean': 'PEN-012'},
            queue: queue(42, 'PEN-010'),
          ),
        );
        await t.pumpAndSettle();
        expect(
          find.bySemanticsLabel(
            RegExp(
              'Nomor Antreanmu PEN-012.*Sedang dilayani: PEN-010.*Total check-in hari ini 42',
            ),
          ),
          findsOneWidget,
        );
        await t.pumpWidget(
          scene(
            t,
            ticket: const {'nomorAntrean': 'PEN-012'},
            queue: queue(43, 'PEN-011'),
          ),
        );
        await t.pumpAndSettle();
        await t.pumpWidget(
          scene(
            t,
            ticket: const {'nomorAntrean': 'PEN-012'},
            queue: queue(43, 'PEN-011'),
          ),
        );
        await t.pump();
        expect(t.binding.hasScheduledFrame, isFalse);
        expect(find.text('PEN-012'), findsOneWidget);
        expect(find.text('+1'), findsNothing);
        await t.pumpWidget(
          scene(t, queue: queue(99, 'SECRET-001', id: 'other')),
        );
        await t.pumpAndSettle();
        expect(find.text('SECRET-001'), findsNothing);
        expect(find.text('99'), findsNothing);
        expect(find.text('Belum tersedia'), findsWidgets);
      } finally {
        handle.dispose();
      }
    },
  );

  testWidgets(
    'navigation exposes exactly four destinations and their correct labels',
    (t) async {
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: PatientBottomNavigation(
              selectedIndex: 0,
              onSelected: (_) {},
            ),
          ),
        ),
      );
      expect(
        t
            .widgetList<NavigationDestination>(
              find.byType(NavigationDestination),
            )
            .map((w) => w.label),
        ['Beranda', 'Riwayat', 'Informasi', 'Profil'],
      );
    },
  );

  testWidgets(
    'greeting uses current identity and the authenticated selector rejects foreign tickets',
    (t) async {
      final search = TextEditingController();
      addTearDown(search.dispose);
      await t.pumpWidget(
        MaterialApp(
          theme: PatientDesign.theme,
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  PatientHomeWelcomeV8(
                    name: 'Pasien Sesi Baru',
                    now: DateTime(2026, 10, 31, 8),
                    controller: search,
                    onSearch: (_) {},
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Selamat pagi,'), findsOneWidget);
      expect(find.text('Pasien Sesi Baru'), findsOneWidget);
      expect(
        find.text('Cari layanan, poli, atau informasi...'),
        findsOneWidget,
      );
      expect(find.byType(Image), findsOneWidget);
      expect(
        homeServiceTicket(
          [
            {
              'id': 'foreign',
              'layananId': 'registration',
              'penggunaId': 'other',
              'nomorAntrean': 'FOREIGN-001',
              'tanggalPelayanan': '2026-10-31',
              'status': 'DIPESAN',
            },
          ],
          'registration',
          '2026-10-31',
          'self',
        ),
        isNull,
      );
    },
  );
}
