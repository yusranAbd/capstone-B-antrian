import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:queueb_client/src/api.dart';
import 'package:queueb_client/src/app.dart';
import 'package:queueb_client/src/config.dart';
import 'package:queueb_client/src/patient_design.dart';
import 'package:queueb_client/src/patient_home.dart';
import 'package:queueb_client/src/patient_home_v6.dart';

import 'patient_home_v3_test.dart' show HomeBackend;

void main() {
  setUpAll(tz.initializeTimeZones);
  test(
    'home channels are derived from known active API modes, never guessed',
    () {
      final clinics = [
        for (final mode in [
          'ANTREAN_HARIAN',
          'HIBRIDA',
          'JANJI_TEMU_DOKTER',
          'UNKNOWN',
        ])
          <String, dynamic>{
            'id': mode,
            'nama': mode,
            'kode': 'POLI$mode',
            'modeReservasi': mode,
            'aktif': true,
          },
        {'id': 'closed', 'modeReservasi': 'HIBRIDA', 'aktif': false},
        {'id': 'missing'},
      ];
      expect(homeWalkInClinics(clinics, [], ''), isEmpty);
      final auxiliary = <Json>[
        {
          'id': 'registration',
          'kode': 'PENDAFTARAN',
          'nama': 'Pendaftaran',
          'modeReservasi': 'ANTREAN_HARIAN',
        },
        {
          'id': 'pharmacy',
          'kode': 'APOTEK',
          'nama': 'Apotek',
          'modeReservasi': 'ANTREAN_HARIAN',
        },
      ];
      expect(
        homeWalkInClinics(
          [...clinics, ...auxiliary],
          [],
          '',
        ).map((c) => c['id']),
        ['registration', 'pharmacy'],
      );
      expect(auxiliary.where(supportsHomeAppointment), isEmpty);
      expect(clinics.where(supportsHomeAppointment).map((c) => c['id']), [
        'ANTREAN_HARIAN',
        'HIBRIDA',
        'JANJI_TEMU_DOKTER',
      ]);
      expect(homeWalkInClinics(clinics, [], 'unknown'), isEmpty);
      final service = {
        'id': 'a',
        'nama': 'Pendaftaran',
        'kode': 'PENDAFTARAN',
        'modeReservasi': 'HIBRIDA',
      };
      final doctor = {
        'nama': 'Sindi',
        'spesialisasi': 'Anak',
        'dokterLayanan': [
          {'aktif': true, 'layananId': 'a'},
        ],
      };
      expect(homeWalkInClinics([service], [doctor], 'sindi'), [service]);
      expect(
        homeWalkInClinics(
          [service],
          [
            {...doctor, 'aktif': false},
          ],
          'sindi',
        ),
        isEmpty,
      );
    },
  );

  test('home-specific solid colors have readable white text', () {
    for (final color in [
      PatientHomeV6Style.walkIn,
      PatientHomeV6Style.visit,
      PatientDesign.primary,
    ]) {
      expect(
        1.05 / (color.computeLuminance() + .05),
        greaterThanOrEqualTo(4.5),
      );
    }
  });

  test('doctor search matches a second clinic relation without fabricating schedules', () {
    final config = AppConfig(apiBaseUrl: 'http://localhost/api/v1');
    final clinics = <Json>[
      {'id': 'a', 'nama': 'Poli Satu', 'modeReservasi': 'HIBRIDA'},
      {'id': 'b', 'nama': 'Poli Dua', 'modeReservasi': 'HIBRIDA'},
    ];
    final doctors = <Json>[
      {
        'id': 'd',
        'nama': 'Dokter Dua Poli',
        'dokterLayanan': [
          {'aktif': true, 'layananId': 'a'},
          {'aktif': true, 'layananId': 'b'},
        ],
      },
    ];
    final results = homeDoctorPreviews(
      doctors,
      clinics,
      [],
      config,
      'poli dua',
    );
    expect(results.single.clinic['id'], 'b');
    expect(results.single.session, isNull);
  });

  testWidgets(
    'home doctor list builds lazily and reaches every backend doctor',
    (t) async {
      final b = HomeBackend()..manyHomeDoctors = true;
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final api =
          QueueApi(
              config: AppConfig(
                apiBaseUrl: 'http://localhost/api/v1',
                realtime: false,
              ),
              client: MockClient(b.handle),
            )
            ..accessToken = 'test'
            ..user = b.user;
      addTearDown(api.dispose);
      await t.pumpWidget(QueueBApp(api: api));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('home-mode-appointment')));
      await t.pumpAndSettle();
      expect(find.byType(PatientHomeDoctorV6).evaluate().length, lessThan(30));
      await t.scrollUntilVisible(
        find.text('dr. Sindi QA 29'),
        160,
        scrollable: find
            .byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
            )
            .first,
      );
      expect(find.text('dr. Sindi QA 29'), findsOneWidget);
      expect(find.text('Poliklinik Nonaktif'), findsNothing);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'hybrid home entry uses walk-in selection, no POST before confirmation; mode/search survive tabs',
    (t) async {
      final b = HomeBackend();
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final api =
          QueueApi(
              config: AppConfig(
                apiBaseUrl: 'http://localhost/api/v1',
                realtime: false,
              ),
              client: MockClient(b.handle),
            )
            ..accessToken = 'test'
            ..user = b.user;
      addTearDown(api.dispose);
      await t.pumpWidget(QueueBApp(api: api));
      await t.pumpAndSettle();
      await t.tap(find.byType(PatientHomeService));
      await t.pumpAndSettle();
      expect(find.text('Reservasi walk-in'), findsOneWidget);
      expect(b.requests.where((r) => r.$1 == 'POST'), isEmpty);
      await t.ensureVisible(find.text('Reservasi walk-in'));
      await t.tap(find.text('Reservasi walk-in'));
      await t.pumpAndSettle();
      expect(find.textContaining('Daftarkan walk-in'), findsOneWidget);
      expect(b.requests.where((r) => r.$1 == 'POST'), isEmpty);
      await t.tap(find.text('Kembali'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(NavigationDestination, 'Beranda'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('home-mode-appointment')));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField).first, 'Sindi');
      await t.pumpAndSettle();
      expect(find.byType(PatientHomeDoctorV6), findsOneWidget);
      await t.tap(find.widgetWithText(NavigationDestination, 'Tiket Saya'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(NavigationDestination, 'Beranda'));
      await t.pumpAndSettle();
      expect(
        t.widget<TextField>(find.byType(TextField).first).controller!.text,
        'Sindi',
      );
      expect(find.byType(PatientHomeDoctorV6), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'daily-only clinical service is discoverable under Janji Temu but keeps its walk-in flow',
    (t) async {
      final b = HomeBackend()..walkOnly = true;
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final api =
          QueueApi(
              config: AppConfig(
                apiBaseUrl: 'http://localhost/api/v1',
                realtime: false,
              ),
              client: MockClient(b.handle),
            )
            ..accessToken = 'test'
            ..user = b.user;
      addTearDown(api.dispose);
      await t.pumpWidget(QueueBApp(api: api));
      await t.pumpAndSettle();
      expect(
        find.widgetWithText(PatientHomeService, 'Poli Umum'),
        findsNothing,
      );
      await t.tap(find.byKey(const ValueKey('home-mode-appointment')));
      await t.pumpAndSettle();
      await t.tap(find.byType(PatientHomeDoctorV6));
      await t.pumpAndSettle();
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Buat Janji Temu'),
            )
            .onPressed,
        isNull,
      );
      final action = find.text('Daftar antrean poliklinik');
      await t.ensureVisible(action);
      await t.pumpAndSettle();
      await t.ensureVisible(action);
      await t.pumpAndSettle();
      await t.tap(action);
      await t.pumpAndSettle();
      expect(find.text('Reservasi walk-in'), findsOneWidget);
      expect(b.requests.where((r) => r.$1 == 'POST'), isEmpty);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'two-mode controls and long content adapt to text scale 2 at 320px',
    (t) async {
      t.view.physicalSize = const Size(320, 568);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      var mode = PatientHomeMode.walkIn;
      await t.pumpWidget(
        MaterialApp(
          theme: PatientDesign.theme,
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: StatefulBuilder(
                  builder: (context, setState) => Column(
                    children: [
                      const PatientHomeHeaderV6(
                        name: 'Nama Pengguna Sangat Panjang Sekali',
                      ),
                      PatientHomeModes(
                        value: mode,
                        onChanged: (v) => setState(() => mode = v),
                      ),
                      const PatientHomeService(
                        clinic: {
                          'nama': 'Poliklinik dengan nama layanan yang sangat panjang',
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await t.tap(find.byKey(const ValueKey('home-mode-appointment')));
      await t.pumpAndSettle();
      expect(mode, PatientHomeMode.appointment);
      expect(t.takeException(), isNull);
    },
  );
}
