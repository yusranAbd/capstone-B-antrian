import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:queueb_client/src/admin_practice_agenda.dart';
import 'package:queueb_client/src/admin_ui.dart';
import 'package:queueb_client/src/config.dart';
import 'package:timezone/data/latest.dart' as tz;

void main() {
  setUpAll(tz.initializeTimeZones);
  AppConfig config() =>
      AppConfig(apiBaseUrl: 'https://fixture.invalid/api/v1', realtime: false);
  List<Json> data(AppConfig c) => [
    for (var i = 0; i < 30; i++)
      {
        'id': 'session-$i',
        'tanggal': i < 18
            ? c.today
            : calendarDate(
                DateTime.parse(c.today).add(const Duration(days: 1)),
              ),
        'mulaiPada': '${c.today}T${i.isEven ? '01' : '06'}:00:00Z',
        'selesaiPada': '${c.today}T${i.isEven ? '05' : '09'}:00:00Z',
        'aktif': i % 3 != 0,
        'dokterLayanan': {
          'dokter': {'nama': 'Dokter $i dengan nama cukup panjang'},
          'layanan': {'nama': 'Poliklinik Anak'},
        },
        'loket': {
          'id': 'room-${i % 2}',
          'kode': 'AN0${i % 2 + 1}',
          'nama': 'Ruang Anak ${i % 2 + 1}',
        },
      },
  ];
  Future<void> mount(
    WidgetTester t,
    List<Json> rows,
    AppConfig c, {
    ValueChanged<Json>? action,
  }) async {
    await t.pumpWidget(
      MaterialApp(
        theme: AdminStyle.theme,
        home: Scaffold(
          body: SingleChildScrollView(
            child: AdminPracticeAgenda(
              rows: rows,
              config: c,
              busy: false,
              clinicName: (_) => 'Poliklinik Anak',
              actions: (r) => AdminRowActions(
                tooltip: 'Aksi ${r['id']}',
                actions: [
                  AdminRowAction(
                    'Ubah',
                    Icons.edit_outlined,
                    () => action?.call(r),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(768, 1024),
    const Size(1280, 720),
    const Size(1366, 768),
  ]) {
    testWidgets(
      'Daily practice agenda fits $size and builds at most six sessions',
      (t) async {
        t.view.physicalSize = size;
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final c = config(), rows = data(config());
        await mount(t, rows, c);
        expect(find.byType(AdminRowActions), findsNWidgets(6));
        expect(find.text('18 sesi · Asia/Jakarta'), findsOneWidget);
        expect(find.textContaining('Dokter 18 '), findsNothing);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets(
    'Date controls, pagination and all dates keep every source row reachable',
    (t) async {
      t.view.physicalSize = const Size(1366, 768);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final c = config(), rows = data(config());
      final original = rows.map((r) => r['id']).toList();
      Json? edited;
      await mount(t, rows, c, action: (r) => edited = r);
      await t.tap(find.byTooltip('Halaman berikutnya'));
      await t.pumpAndSettle();
      expect(find.text('7–12 dari 18 sesi'), findsOneWidget);
      await t.tap(find.byTooltip('Tanggal berikutnya'));
      await t.pumpAndSettle();
      expect(find.text('12 sesi · Asia/Jakarta'), findsOneWidget);
      expect(find.byType(AdminRowActions), findsNWidgets(6));
      await t.tap(find.byType(AdminRowActions).first);
      await t.pumpAndSettle();
      await t.tap(find.text('Ubah'));
      await t.pumpAndSettle();
      expect(edited, isNotNull);
      expect(dateOnly(edited!['tanggal']), isNot(c.today));
      await t.tap(find.widgetWithText(FilterChip, 'Semua tanggal'));
      await t.pumpAndSettle();
      expect(find.text('30 sesi · Asia/Jakarta'), findsOneWidget);
      expect(find.byType(AdminRowActions), findsNWidgets(6));
      expect(rows.map((r) => r['id']).toList(), original);
      await t.tap(find.text('Hari ini'));
      await t.pumpAndSettle();
      expect(find.text('18 sesi · Asia/Jakarta'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets('Large text remains readable and empty day offers recovery', (
    t,
  ) async {
    t.view.physicalSize = const Size(320, 568);
    t.view.devicePixelRatio = 1;
    t.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    final c = config();
    await mount(t, data(c), c);
    expect(t.takeException(), isNull);
    await mount(t, [], c);
    expect(
      find.textContaining('Tidak ada jadwal pada tanggal'),
      findsOneWidget,
    );
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });
}
