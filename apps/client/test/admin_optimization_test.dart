import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:queueb_client/src/admin.dart';
import 'package:queueb_client/src/admin_data.dart';
import 'package:queueb_client/src/admin_navigation.dart';
import 'package:queueb_client/src/admin_schema.dart';
import 'package:queueb_client/src/api.dart';
import 'package:queueb_client/src/config.dart';

void main() {
  setUpAll(tz.initializeTimeZones);
  final clinics = [
    for (int i = 0; i < 11; i++)
      {
        'id': 'clinic-$i',
        'nama': 'Poliklinik $i',
        'kode': 'P$i',
        'aktif': i != 10,
      },
  ];
  final doctors = [
    for (int i = 0; i < 22; i++)
      {
        'id': 'doctor-$i',
        'nama': 'Dokter $i',
        'spesialisasi': 'Spesialis $i',
        'aktif': true,
        'dokterLayanan': [
          {
            'id': 'link-$i',
            'layananId': 'clinic-${i % 11}',
            'layanan': clinics[i % 11],
            'aktif': true,
          },
        ],
      },
  ];
  final sessions = <Json>[
    for (int i = 0; i < 440; i++)
      {
        'id': 'session-$i',
        'tanggal': '2026-10-${(17 + i % 3).toString().padLeft(2, '0')}',
        'mulaiPada': '2026-10-17T01:00:00Z',
        'selesaiPada': '2026-10-17T09:00:00Z',
        'aktif': i % 2 == 0,
        'dokterLayanan': {
          'dokter': doctors[i % 22],
          'layanan': clinics[i % 11],
          'layananId': 'clinic-${i % 11}',
        },
        'loket': {'id': 'room-$i', 'nama': 'Ruang $i'},
      },
  ];
  testWidgets(
    'category navigation exposes only backed modules and collapses groups',
    (tester) async {
      int selected = -1;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdminNavigation(selected: 0, onSelect: (v) => selected = v),
          ),
        ),
      );
      expect(find.text('Master data'), findsOneWidget);
      expect(find.text('Dokter'), findsOneWidget);
      expect(find.text('Slot konsultasi'), findsNothing);
      await tester.tap(find.text('Manajemen jadwal'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Slot konsultasi'));
      expect(selected, 5);
      await tester.tap(find.text('Master data'));
      await tester.pumpAndSettle();
      expect(find.text('Dokter'), findsNothing);
    },
  );
  for (final width in [320.0, 375.0, 414.0, 768.0, 1440.0]) {
    testWidgets('ADMIN responsive at $width with real dataset shapes', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = QueueApi(
        config: AppConfig(
          apiBaseUrl: 'http://localhost/api/v1',
          realtime: false,
        ),
        client: MockClient(
          (r) async => http.Response(
            jsonEncode(switch (r.url.path.split('/').last) {
              'layanan' => clinics,
              'dokter' => doctors,
              'jadwal-praktik' => sessions,
              _ => <Json>[],
            }),
            200,
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AdminPage(api: api)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Poliklinik 0'), findsOneWidget);
      if (width < 960) {
        await tester.tap(find.byTooltip('Menu administrasi'));
        await tester.pumpAndSettle();
        expect(find.byType(AdminNavigation), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      api.dispose();
    });
  }
  testWidgets(
    'hundreds of practice rows stay lazy with clinic doctor date grouping and filters',
    (tester) async {
      final api = QueueApi(
        config: AppConfig(
          apiBaseUrl: 'http://localhost/api/v1',
          realtime: false,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AdminDataView(
                resource: resources[4],
                data: sessions,
                catalog: {'/layanan': clinics, '/dokter': doctors},
                api: api,
                busy: false,
                revision: 1,
                onEdit: (_) {},
                onDeactivate: (_) {},
                onDoctorLinks: (_) {},
                detail: (_) => 'Jam praktik',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AdminDataGroup), findsNWidgets(11));
      expect(find.text('Ubah'), findsNothing);
      await tester.enterText(
        find.widgetWithText(TextField, 'Cari nama atau kode'),
        'Dokter 21',
      );
      await tester.pumpAndSettle();
      expect(find.byType(AdminDataGroup), findsOneWidget);
      await tester.tap(find.text('Poliklinik 10'));
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate((w) => w is Text && w.data == 'Dokter 21'),
        findsOneWidget,
      );
      await tester.tap(find.text('Dokter 21').last);
      await tester.pumpAndSettle();
      expect(find.text('2026-10-17'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Dari tanggal (YYYY-MM-DD)'),
        '2026-02-30',
      );
      await tester.pumpAndSettle();
      expect(find.text('Gunakan tanggal kalender YYYY-MM-DD.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      api.dispose();
    },
  );
  testWidgets(
    'slots are fetched only on session expansion and inactive filter works',
    (tester) async {
      int requests = 0;
      final api = QueueApi(
        config: AppConfig(
          apiBaseUrl: 'http://localhost/api/v1',
          realtime: false,
        ),
        client: MockClient((r) async {
          requests++;
          expect(r.url.queryParameters['jadwalPraktikId'], 'session-0');
          return http.Response(
            jsonEncode([
              {
                'id': 'slot',
                'mulaiPada': '2026-10-17T01:00:00Z',
                'selesaiPada': '2026-10-17T01:15:00Z',
                'kapasitas': 2,
                'jumlahJanjiTemu': 0,
                'tersedia': false,
                'aktif': false,
              },
            ]),
            200,
          );
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AdminSlotSession(
                session: sessions.first,
                api: api,
                status: 'false',
                search: '',
                busy: false,
                revision: 1,
                onEdit: (_) {},
                onDeactivate: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(requests, 0);
      await tester.tap(find.byType(ExpansionTile));
      await tester.pumpAndSettle();
      expect(requests, 1);
      expect(find.text('NONAKTIF'), findsOneWidget);
      expect(find.text('Ubah'), findsOneWidget);
      expect(find.text('Nonaktifkan'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      api.dispose();
    },
  );
}
