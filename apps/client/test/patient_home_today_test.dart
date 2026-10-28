import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:queueb_client/src/api.dart';
import 'package:queueb_client/src/app.dart';
import 'package:queueb_client/src/config.dart';
import 'package:queueb_client/src/patient_home.dart';
import 'package:queueb_client/src/patient_home_v6.dart';

import 'patient_home_v3_test.dart' show HomeBackend;

class TodayConfig extends AppConfig {
  TodayConfig() : super(apiBaseUrl: 'http://localhost/api/v1');
  // UTC is still October 27; the service day in Jakarta is October 28.
  @override
  tz.TZDateTime get now =>
      tz.TZDateTime.from(DateTime.utc(2026, 10, 27, 18, 30), location);
}

void main() {
  setUpAll(tzdata.initializeTimeZones);
  test('home uses Jakarta service date, excludes future/past/missing/inactive schedules, retains all sessions today', () {
    final config = TodayConfig();
    expect(config.today, '2026-10-28');
    final clinics = <Json>[
      {'id': 'a', 'nama': 'Poli Anak', 'aktif': true},
      {'id': 'b', 'nama': 'Poli Mata', 'aktif': true},
    ];
    Json doctor(String id) => {
      'id': id,
      'nama': 'dr. $id',
      'aktif': true,
      'dokterLayanan': [
        {'id': 'link-$id', 'layananId': 'a', 'aktif': true},
      ],
    };
    Json session(String id, String day, {bool active = true}) => {
      'id': 'session-$id', 'aktif': active, 'tanggal': day,
      'dokterLayananId': 'link-$id',
      'dokterLayanan': {'dokterId': id, 'layananId': 'a', 'aktif': true},
      'loket': {'aktif': true},
      // An earlier session today remains a schedule for today, not live presence.
      'mulaiPada': '2026-10-27T17:00:00Z',
      'selesaiPada': '2026-10-27T18:00:00Z',
    };
    final doctors = [
      'today',
      'tomorrow',
      'past',
      'missing',
      'inactive',
      'closedRoom',
      'disabledLink',
      'disabledDoctor',
    ].map(doctor).toList();
    doctors.last['aktif'] = false;
    final schedules = <Json>[
      session('today', config.today),
      {
        ...session('today', config.today),
        'id': 'second-session',
        'mulaiPada': '2026-10-28T02:00:00Z',
      },
      session('tomorrow', '2026-10-29'),
      session('past', '2026-10-27'),
      session('inactive', config.today, active: false),
      {
        ...session('closedRoom', config.today),
        'loket': {'aktif': false},
      },
      {
        ...session('disabledLink', config.today),
        'dokterLayanan': {
          'dokterId': 'disabledLink',
          'layananId': 'a',
          'aktif': false,
        },
      },
      session('disabledDoctor', config.today),
    ];
    final results = homeDoctorPreviews(doctors, clinics, schedules, config, '');
    expect(results.map((p) => p.doctor['id']), ['today']);
    expect(results.single.session?['id'], 'session-today');
    expect(
      homeDoctorPreviews(doctors, clinics, schedules, config, 'tomorrow'),
      isEmpty,
    );
    expect(
      homeDoctorPreviews(
        doctors,
        clinics,
        schedules,
        config,
        '',
        clinicId: 'b',
      ),
      isEmpty,
    );
    expect(
      homeDoctorPreviews(
        doctors,
        clinics,
        schedules,
        config,
        'poli anak',
      ).length,
      1,
    );
  });

  testWidgets(
    'home excludes tomorrow-only doctor, reacts to refreshed day and hides unverified schedules on failure',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final backend = HomeBackend();
      backend.homeScheduleDay = backend.tomorrow;
      final api =
          QueueApi(
              config: AppConfig(
                apiBaseUrl: 'http://localhost/api/v1',
                realtime: false,
              ),
              client: MockClient(backend.handle),
            )
            ..accessToken = 'fixture'
            ..user = backend.user;
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        api.dispose();
      });
      await tester.pumpWidget(QueueBApp(api: api));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('home-mode-appointment')));
      await tester.pumpAndSettle();
      expect(find.byType(PatientHomeDoctorV6), findsNothing);
      expect(
        find.text('Belum ada dokter dengan jadwal praktik hari ini.'),
        findsOneWidget,
      );
      backend.homeScheduleDay = backend.today;
      await tester.pump(const Duration(seconds: 31));
      await tester.pumpAndSettle();
      expect(find.byType(PatientHomeDoctorV6), findsOneWidget);
      backend.failHomeSchedule = true;
      await tester.pump(const Duration(seconds: 31));
      await tester.pumpAndSettle();
      expect(find.text('Jadwal praktik belum dapat dimuat.'), findsOneWidget);
      expect(find.byType(PatientHomeDoctorV6), findsNothing);
      backend.failHomeSchedule = false;
      await tester.tap(find.text('Muat ulang jadwal'));
      await tester.pumpAndSettle();
      expect(find.byType(PatientHomeDoctorV6), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
