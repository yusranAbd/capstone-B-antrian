import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:queueb_client/src/admin.dart';
import 'package:queueb_client/src/admin_dashboard.dart';
import 'package:queueb_client/src/admin_navigation.dart';
import 'package:queueb_client/src/admin_ui.dart';
import 'package:queueb_client/src/api.dart';
import 'package:queueb_client/src/config.dart';

void main() {
  setUpAll(tz.initializeTimeZones);
  const staffId = '11111111-1111-4111-8111-111111111111';
  final catalog = <String, List<Json>>{
    '/layanan': [
      {
        'id': 'clinic',
        'kode': 'PD',
        'nama': 'Penyakit Dalam',
        'aktif': true,
        'modeReservasi': 'HIBRIDA',
      },
    ],
    '/dokter': [
      {
        'id': 'doctor',
        'nama': 'dr. Indah',
        'kode': 'DR01',
        'spesialisasi': 'Penyakit Dalam',
        'aktif': true,
        'dokterLayanan': [
          {
            'layananId': 'clinic',
            'aktif': true,
            'layanan': {'id': 'clinic', 'nama': 'Penyakit Dalam'},
          },
        ],
      },
    ],
    '/loket': [
      {
        'id': 'room',
        'kode': 'PD01',
        'nama': 'Ruang 1',
        'aktif': true,
        'layananId': 'clinic',
        'layanan': {'id': 'clinic', 'nama': 'Penyakit Dalam'},
      },
    ],
    '/jadwal-praktik': [],
    '/jadwal-layanan': [],
    '/penugasan-petugas': [
      {
        'id': 'assignment',
        'petugasId': staffId,
        'petugas': {'id': staffId, 'nama': 'Petugas Satu'},
        'aktif': true,
        'tanggalMulai': '2026-10-19',
        'loket': {'id': 'room', 'nama': 'Ruang 1', 'layananId': 'clinic'},
      },
    ],
    '/perangkat-display': [],
  };

  Future<void> press(WidgetTester tester, Finder target) async {
    await tester.ensureVisible(target.last);
    await tester.pumpAndSettle();
    await tester.tap(target.last);
    await tester.pumpAndSettle();
  }

  Future<QueueApi> open(
    WidgetTester tester, {
    int initial = -1,
    bool fail = false,
  }) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final api = QueueApi(
      config: AppConfig(apiBaseUrl: 'http://localhost/api/v1', realtime: false),
      client: MockClient((r) async {
        expect(r.url.path, isNot(contains('/queue/')));
        return http.Response(
          jsonEncode(
            fail
                ? {'message': 'Katalog gagal dimuat'}
                : catalog[r.url.path.replaceFirst('/api/v1', '')] ?? [],
          ),
          fail ? 503 : 200,
        );
      }),
    );
    addTearDown(api.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AdminStyle.theme,
        home: Scaffold(
          body: AdminPage(api: api, initialSection: initial),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return api;
  }

  testWidgets(
    'dashboard derives master totals from actual catalog without patient analytics',
    (tester) async {
      await open(tester);
      expect(find.byType(AdminDashboard), findsOneWidget);
      expect(find.text('Penyakit Dalam'), findsOneWidget);
      expect(find.text('1 aktif'), findsNWidgets(3));
      expect(find.text('0 aktif'), findsOneWidget);
      expect(find.text('128'), findsNothing);
      expect(find.textContaining('14 menit'), findsNothing);
      expect(find.textContaining('Statistik pasien'), findsNothing);
      await press(tester, find.byTooltip('Ciutkan sidebar'));
      expect(
        tester.widget<AdminNavigation>(find.byType(AdminNavigation)).collapsed,
        isTrue,
      );
      await press(tester, find.byTooltip('Perluas sidebar'));
      expect(
        tester.widget<AdminNavigation>(find.byType(AdminNavigation)).collapsed,
        isFalse,
      );
    },
  );

  testWidgets(
    'failed catalog shows unavailable metrics rather than fabricated zero totals',
    (tester) async {
      await open(tester, fail: true);
      expect(find.text('—'), findsNWidgets(4));
      expect(find.text('Data belum tersedia'), findsNWidgets(4));
      expect(
        find.text(
          'Layanan sedang mengalami gangguan. Muat ulang data dan coba lagi nanti.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'two thousand rows render one page and numeric sorting remains numeric',
    (tester) async {
      var built = 0;
      final data = <Json>[
        for (var i = 0; i < 2000; i++)
          {
            'id': '$i',
            'nama': 'Data ${i.toString().padLeft(4, '0')}',
            'nilai': i,
          },
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AdminTable(
                rows: data,
                columns: [
                  AdminColumn(
                    'Nama',
                    (r) => r['nama'],
                    cell: (r) {
                      built++;
                      return Text('${r['nama']}');
                    },
                  ),
                  AdminColumn('Nilai', (r) => r['nilai'], numeric: true),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(built, 10);
      expect(find.text('Data 0000'), findsOneWidget);
      expect(find.text('Data 0010'), findsNothing);
      final table = tester.widget<PaginatedDataTable>(
        find.byType(PaginatedDataTable),
      );
      expect(table.source.rowCount, 2000);
      table.columns[1].onSort!(1, false);
      await tester.pumpAndSettle();
      expect(find.text('Data 1999'), findsOneWidget);
      expect(find.text('Data 0000'), findsNothing);
      final sorted = tester.widget<PaginatedDataTable>(
        find.byType(PaginatedDataTable),
      );
      sorted.onPageChanged!(10);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AdminTable(
                rows: data.take(2).toList(),
                columns: [
                  AdminColumn('Nama', (r) => r['nama']),
                  AdminColumn('Nilai', (r) => r['nilai']),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<PaginatedDataTable>(find.byType(PaginatedDataTable))
            .source
            .rowCount,
        2,
      );
      expect(find.text('Data 0000'), findsOneWidget);
      expect(
        tester.getSize(find.byType(PaginatedDataTable)).height,
        lessThan(600),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('searchable choices reject unselected typed text and stale IDs', (
    tester,
  ) async {
    final form = GlobalKey<FormState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Form(
            key: form,
            child: AdminSearchChoice(
              label: 'Poliklinik',
              choices: const [('poli', 'Penyakit Dalam')],
              value: 'poli',
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '');
    expect(form.currentState!.validate(), isFalse);
    await tester.enterText(find.byType(TextField), 'Dokter yang tidak dipilih');
    expect(form.currentState!.validate(), isFalse);
    await tester.pumpAndSettle();
    expect(find.textContaining('Pilih poliklinik dari daftar'), findsOneWidget);
  });

  for (final initial in [0, 1, 2, 4, 6, 7]) {
    testWidgets(
      'backed ADMIN module $initial retains reachable actions and empty states',
      (tester) async {
        await open(tester, initial: initial);
        expect(
          find.text(
            initial == 7
                ? 'Tambah perangkat'
                : initial == 6
                ? 'Tambah akun PETUGAS'
                : 'Tambah',
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'staff assignment uses the account directory and never exposes manual UUID input',
    (tester) async {
      await open(tester, initial: 6);
      await press(tester, find.text('Penugasan Loket'));
      await press(tester, find.text('Tambah'));
      expect(find.byType(AdminSearchChoice), findsOneWidget);
      expect(find.text('Petugas (nama / email)'), findsOneWidget);
      expect(find.text('ID akun PETUGAS'), findsNothing);
      expect(find.textContaining('Tempel ID'), findsNothing);
      expect(find.textContaining('tab Akun Petugas'), findsOneWidget);
      await press(tester, find.text('Kembali'));
    },
  );
}
