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
import 'package:queueb_client/src/doctor.dart';
import 'package:queueb_client/src/doctor_dashboard.dart';
import 'package:queueb_client/src/mobile_ui.dart';

void main() {
  setUpAll(tz.initializeTimeZones);
  const poli = {'id': 'p', 'nama': 'Poli Mata'},
      room = {'id': 'r', 'kode': 'M1', 'nama': 'Ruang Mata'};
  Json appointment(String n, String status) => {
    'nomorAntrean': n,
    'status': status,
    'poliklinik': poli,
    'ruang': room,
  };
  Json snapshot(List<Json> waiting, List<Json> active) => {
    'sesi': {'id': 's'},
    'poliklinik': poli,
    'ruang': room,
    'totalMenunggu': waiting.length,
    'menunggu': waiting,
    'aktif': active,
  };

  test('REST snapshot overrides appointment status, preserves selector order and room scope', () {
    final data = DoctorDashboardData(
      [
        appointment('M-001', 'DIPESAN'),
        appointment('M-009', 'SELESAI'),
        {
          ...appointment('M-001', 'CHECK_IN'),
          'ruang': {'id': 'other', 'nama': 'Ruang Lain'},
        },
      ],
      [
        snapshot(
          [
            {
              'nomorAntrean': 'M-010',
              'status': 'MENUNGGU',
              'layakDipanggil': false,
              'jenisAntrean': 'WALK_IN',
            },
            {
              'nomorAntrean': 'M-003',
              'status': 'MENUNGGU',
              'layakDipanggil': true,
              'jenisAntrean': 'JANJI_TEMU',
            },
          ],
          [
            {'nomorAntrean': 'M-001', 'status': 'DILAYANI'},
          ],
        ),
      ],
    );
    expect(data.entries.map((e) => e['nomorAntrean']), [
      'M-001',
      'M-010',
      'M-003',
      'M-009',
      'M-001',
    ]);
    expect(data.entries.first['status'], 'DILAYANI');
    expect(data.waiting.map((e) => e['nomorAntrean']), ['M-010', 'M-003']);
    expect(data.nextEligible?['nomorAntrean'], 'M-003');
    expect(data.completed, 1);
    expect(data.queueTotal, 3);
  });

  test('full server waiting total does not imply all rows were downloaded', () {
    final data = DoctorDashboardData([], [
      {...snapshot([], []), 'totalMenunggu': 137},
    ]);
    expect(data.queueTotal, 137);
    expect(data.entries, isEmpty);
    expect(data.nextEligible, isNull);
  });

  testWidgets(
    'thousands of queue records render one page and search/status reset page',
    (tester) async {
      final config = AppConfig(
        apiBaseUrl: 'http://localhost:3000/api/v1',
        realtime: false,
      );
      final entries = List<Json>.generate(
        2000,
        (i) => appointment(
          'M-${i.toString().padLeft(4, '0')}',
          i == 1999 ? 'SELESAI' : 'MENUNGGU',
        ),
      );
      await tester.binding.setSurfaceSize(const Size(1440, 1000));
      await tester.pumpWidget(
        MaterialApp(
          theme: QueueBStyle.theme,
          home: Scaffold(
            body: SingleChildScrollView(
              child: DoctorQueuePanel(
                entries: entries,
                config: config,
                date: config.today,
                available: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('M-0000'), findsOneWidget);
      expect(find.text('M-0010'), findsNothing);
      await tester.ensureVisible(find.byTooltip('Antrean berikutnya'));
      await tester.tap(find.byTooltip('Antrean berikutnya'));
      await tester.pumpAndSettle();
      expect(find.text('M-0010'), findsOneWidget);
      await tester.ensureVisible(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'M-1999');
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate((w) => w is Text && w.data == 'M-1999'),
        findsOneWidget,
      );
      expect(find.text('M-0010'), findsNothing);
      await tester.tap(find.text('Semua status'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Menunggu').last);
      await tester.pumpAndSettle();
      expect(find.text('Belum ada antrean yang sesuai.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.binding.setSurfaceSize(null);
    },
  );

  for (final width in [1024.0, 1366.0, 1920.0]) {
    testWidgets(
      'single web dashboard exposes all panels at $width without mutation actions',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 1200));
        final config = AppConfig(
          apiBaseUrl: 'http://localhost:3000/api/v1',
          realtime: false,
        );
        final status = ValueNotifier('Realtime terhubung');
        final session = <String, dynamic>{
          'id': 's',
          'aktif': true,
          'tanggal': config.today,
          'mulaiPada': '${config.today}T00:00:00+07:00',
          'selesaiPada': '${config.today}T23:59:59+07:00',
          'poliklinik': poli,
          'ruang': room,
        };
        final snap = {
          ...snapshot([], [
            {'nomorAntrean': 'M-007', 'status': 'DIPANGGIL'},
          ]),
          'diperolehPada': DateTime.now().toUtc().toIso8601String(),
        };
        await tester.pumpWidget(
          MaterialApp(
            theme: QueueBStyle.theme,
            home: Scaffold(
              body: DoctorDashboard(
                config: config,
                date: config.today,
                profile: const {
                  'nama': 'Dokter Uji',
                  'spesialisasi': 'Mata',
                  'poliklinik': [poli],
                },
                schedules: [session],
                appointments: [
                  appointment('M-007', 'DIPESAN'),
                  appointment('M-001', 'SELESAI'),
                ],
                snapshots: [snap],
                loading: false,
                available: true,
                status: status,
                onRefresh: () async {},
                onPickDate: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Dashboard Dokter'), findsOneWidget);
        expect(find.text('Janji Hari Ini'), findsOneWidget);
        expect(find.text('Dalam Antrean'), findsOneWidget);
        expect(find.text('Konsultasi Selesai'), findsOneWidget);
        expect(find.text('Praktik Aktif'), findsOneWidget);
        expect(find.byType(NavigationBar), findsNothing);
        expect(find.text('M-007'), findsWidgets);
        await tester.scrollUntilVisible(
          find.text('Catatan Klinis Dokter'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('Jadwal Praktik Hari Ini'), findsOneWidget);
        expect(
          find.text('Pencatatan klinis belum tersedia di QueueB.'),
          findsOneWidget,
        );
        for (final action in [
          'Mulai Konsultasi',
          'Selesai Konsultasi',
          'Recall',
          'Catat Baru',
          'Lihat Rekam Medis (SOAP)',
        ]) {
          expect(find.text(action), findsNothing);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        status.dispose();
        await tester.binding.setSurfaceSize(null);
      },
    );
  }

  testWidgets(
    'live panel shows multiple active rooms and detail only, without patient identity',
    (tester) async {
      final config = AppConfig(
            apiBaseUrl: 'http://localhost:3000/api/v1',
            realtime: false,
          ),
          status = ValueNotifier('Realtime terhubung');
      final data = DoctorDashboardData([], [
        snapshot([], [
          {
            'nomorAntrean': 'M-001',
            'status': 'DIPANGGIL',
            'namaPasien': 'RAHASIA',
          },
        ]),
        {
          ...snapshot([], [
            {'nomorAntrean': 'M-002', 'status': 'DILAYANI'},
          ]),
          'ruang': {'id': 'r2', 'kode': 'M2', 'nama': 'Ruang Dua'},
        },
      ]);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DoctorLivePanel(
                data: data,
                config: config,
                available: true,
                loading: false,
                status: status,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ActionChip, 'M-002'));
      await tester.pumpAndSettle();
      expect(find.text('Dilayani'), findsOneWidget);
      expect(find.text('M2 · Ruang Dua'), findsOneWidget);
      expect(find.text('RAHASIA'), findsNothing);
      await tester.tap(find.text('Lihat detail antrean'));
      await tester.pumpAndSettle();
      expect(find.text('Detail antrean M-002'), findsOneWidget);
      expect(
        find.text(
          'Nama pasien, keluhan dan catatan klinis tidak disediakan pada portal ini.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Tutup'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      status.dispose();
    },
  );

  testWidgets(
    'denied/ended session drops live data while own appointments remain visible',
    (tester) async {
      final config = AppConfig(
        apiBaseUrl: 'http://localhost:3000/api/v1',
        realtime: false,
      );
      bool denied = false;
      int snapshotReads = 0;
      final api = QueueApi(
        config: config,
        client: MockClient((r) async {
          Object body;
          if (r.url.path.endsWith('/profil')) {
            body = {'nama': 'Dokter Uji', 'aktif': true};
          } else if (r.url.path.endsWith('/jadwal')) {
            body = [
              {
                'id': 's',
                'aktif': true,
                'mulaiPada': '${config.today}T00:00:00+07:00',
                'selesaiPada': '${config.today}T23:59:59+07:00',
              },
            ];
          } else if (r.url.path.endsWith('/janji-temu')) {
            body = [appointment('M-004', 'DIPESAN')];
          } else {
            snapshotReads++;
            if (denied) {
              return http.Response('{"message":"Sesi berakhir"}', 403);
            }
            body = snapshot([], [
              {'nomorAntrean': 'M-008', 'status': 'DIPANGGIL'},
            ]);
          }
          return http.Response(
            jsonEncode(body),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      )..user = {'id': 'doc', 'peran': 'DOKTER'};
      await tester.binding.setSurfaceSize(const Size(1440, 1000));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: DoctorPage(api: api)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('M-008'), findsWidgets);
      denied = true;
      await tester.tap(find.byTooltip('Muat ulang portal'));
      await tester.pumpAndSettle();
      expect(snapshotReads, 2);
      expect(find.text('M-008'), findsNothing);
      expect(find.text('M-004'), findsOneWidget);
      expect(
        find.textContaining('Monitoring tersedia selama sesi'),
        findsOneWidget,
      );
      expect(find.text('Praktik Aktif'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      api.dispose();
      await tester.binding.setSurfaceSize(null);
    },
  );

  testWidgets(
    'retry after a failed refresh keeps KPI unavailable until REST completes',
    (tester) async {
      int phase = 0;
      var resumed = Completer<void>();
      final config = AppConfig(
        apiBaseUrl: 'http://localhost:3000/api/v1',
        realtime: false,
      );
      final api = QueueApi(
        config: config,
        client: MockClient((r) async {
          if (phase == 1) {
            return http.Response('{"message":"Koneksi gagal"}', 503);
          }
          if (phase == 2) await resumed.future;
          final Object body = r.url.path.endsWith('/profil')
              ? {'nama': 'Dokter Uji', 'aktif': true}
              : r.url.path.endsWith('/janji-temu')
              ? [appointment('M-001', 'DIPESAN')]
              : [];
          return http.Response(
            jsonEncode(body),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      )..user = {'id': 'doc', 'peran': 'DOKTER'};
      await tester.binding.setSurfaceSize(const Size(1440, 1000));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: DoctorPage(api: api)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('1'), findsOneWidget);
      phase = 1;
      await tester.tap(find.byTooltip('Muat ulang portal'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          'Layanan sedang mengalami gangguan. Muat ulang data dan coba lagi nanti.',
        ),
        findsOneWidget,
      );
      phase = 2;
      await tester.tap(find.byTooltip('Muat ulang portal'));
      await tester.pump();
      expect(find.text('0'), findsNothing);
      expect(find.text('1'), findsNothing);
      expect(find.text('Data belum tersedia'), findsNWidgets(4));
      resumed.complete();
      await tester.pumpAndSettle();
      expect(find.text('1'), findsOneWidget);
      resumed = Completer<void>();
      await tester.tap(find.text('Tanggal: ${config.today}'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('0'), findsNothing);
      expect(find.text('1'), findsNothing);
      resumed.complete();
      await tester.pumpAndSettle();
      expect(find.text('1'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      api.dispose();
      await tester.binding.setSurfaceSize(null);
    },
  );

  testWidgets(
    'DOKTER login routes to dashboard and logout removes the portal',
    (tester) async {
      final identity = {
        'id': 'doctor',
        'peran': 'DOKTER',
        'nama': 'Dokter Uji',
        'email': 'doctor@test.local',
      };
      final api = QueueApi(
        config: AppConfig(
          apiBaseUrl: 'http://localhost:3000/api/v1',
          realtime: false,
        ),
        client: MockClient((r) async {
          final Object body = r.url.path.endsWith('/login')
              ? {'accessToken': 'access', 'refreshToken': 'refresh'}
              : r.url.path.endsWith('/me')
              ? identity
              : r.url.path.endsWith('/profil')
              ? {'nama': 'Dokter Uji', 'aktif': true}
              : r.url.path.endsWith('/logout')
              ? {}
              : [];
          return http.Response(
            jsonEncode(body),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      await api.login('doctor@test.local', 'Synthetic-Test-123!');
      await tester.pumpWidget(QueueBApp(api: api));
      await tester.pumpAndSettle();
      expect(find.text('Dashboard Dokter'), findsOneWidget);
      await tester.tap(find.byTooltip('Keluar akun'));
      await tester.pumpAndSettle();
      expect(find.byType(DoctorPage), findsNothing);
      expect(api.user, isNull);
      expect(api.accessToken, isNull);
      await tester.pumpWidget(const SizedBox());
      api.dispose();
    },
  );

  testWidgets(
    'loading during realtime reconciliation preserves queue search and status filter',
    (tester) async {
      int phase = 0;
      final resumed = Completer<void>();
      final config = AppConfig(
        apiBaseUrl: 'http://localhost:3000/api/v1',
        realtime: false,
      );
      final api = QueueApi(
        config: config,
        client: MockClient((r) async {
          if (phase == 1) await resumed.future;
          final Object body = r.url.path.endsWith('/profil')
              ? {'nama': 'Dokter Uji', 'aktif': true}
              : r.url.path.endsWith('/janji-temu')
              ? [
                  appointment('M-001', phase == 0 ? 'DIPESAN' : 'CHECK_IN'),
                  appointment('M-002', 'SELESAI'),
                ]
              : [];
          return http.Response(
            jsonEncode(body),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      )..user = {'id': 'doc', 'peran': 'DOKTER'};
      await tester.binding.setSurfaceSize(const Size(1440, 1100));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: DoctorPage(api: api)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'M-001');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Semua status'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dipesan').last);
      await tester.pumpAndSettle();
      phase = 1;
      await tester.tap(find.byTooltip('Muat ulang portal'));
      await tester.pump();
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        'M-001',
      );
      resumed.complete();
      await tester.pumpAndSettle();
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        'M-001',
      );
      expect(find.text('Dipesan'), findsOneWidget);
      expect(find.text('Belum ada antrean yang sesuai.'), findsOneWidget);
      expect(find.text('M-002'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      api.dispose();
      await tester.binding.setSurfaceSize(null);
    },
  );
}
