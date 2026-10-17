import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:queueb_client/src/admin_schedules.dart';
import 'package:queueb_client/src/admin.dart';
import 'package:queueb_client/src/api.dart';
import 'package:queueb_client/src/config.dart';

const clinic = {
  'id': 'clinic-a',
  'nama': 'Poliklinik Saraf',
  'kode': 'NEURO',
  'aktif': true,
};
Json schedule(String day, {bool active = true}) => {
  'id': 'schedule-$day',
  'layananId': clinic['id'],
  'layanan': clinic,
  'hari': day,
  'aktif': active,
  'jamBuka': '1970-01-01T08:00:00Z',
  'jamTutup': '1970-01-01T16:00:00Z',
  'kapasitasHarian': 24,
};
http.Response reply(Object data, [int status = 200]) =>
    http.Response(jsonEncode(data), status);
QueueApi apiFor(Future<http.Response> Function(http.Request) handle) =>
    QueueApi(
      config: AppConfig(apiBaseUrl: 'http://localhost/api/v1', realtime: false),
      client: MockClient(handle),
    );

Future<void> editor(WidgetTester tester, QueueApi api) async {
  tester.view.physicalSize = const Size(1000, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showDialog<bool>(
              context: context,
              builder: (_) =>
                  BulkScheduleEditor(api: api, clinics: const [clinic]),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  await tester.tap(find.byType(DropdownButtonFormField<String>));
  await tester.pumpAndSettle();
  await tester.tap(find.text('NEURO · Poliklinik Saraf').last);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(tz.initializeTimeZones);
  testWidgets(
    'poliklinik save sends valid numeric payload once and explains server errors safely',
    (tester) async {
      final gate = Completer<void>();
      final sent = <Json>[];
      final api = apiFor((r) async {
        if (r.method == 'GET') return reply([]);
        sent.add(object(jsonDecode(r.body)));
        await gate.future;
        return reply({'message': 'Internal server error'}, 500);
      });
      addTearDown(api.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AdminPage(api: api)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tambah'));
      await tester.pumpAndSettle();
      final inputs = find.byType(TextFormField);
      await tester.enterText(inputs.at(0), 'NEURO');
      await tester.enterText(inputs.at(1), 'Saraf (Neurologi)');
      await tester.enterText(inputs.at(3), 'SF');
      await tester.enterText(inputs.at(4), '25');
      await tester.tap(find.text('Simpan'));
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Menyimpan…'),
            )
            .onPressed,
        isNull,
      );
      expect(sent.single, {
        'kode': 'NEURO',
        'nama': 'Saraf (Neurologi)',
        'deskripsi': null,
        'prefixAntrean': 'SF',
        'durasiDasarMenit': 25,
        'modeReservasi': 'HIBRIDA',
      });
      gate.complete();
      await tester.pumpAndSettle();
      expect(
        find.textContaining('memeriksa log API dan migration database'),
        findsOneWidget,
      );
      expect(find.text('Internal server error'), findsNothing);
      expect(sent.length, 1);
    },
  );
  test(
    'grouping preserves all records, inactive days and clinics without hours',
    () {
      final groups = groupClinicSchedules(
        [
          clinic,
          {'id': 'b', 'nama': 'Poliklinik Anak', 'aktif': false},
        ],
        [schedule('JUMAT'), schedule('SENIN', active: false)],
        '',
      );
      expect(groups.map((g) => g.name), [
        'Poliklinik Anak',
        'Poliklinik Saraf',
      ]);
      expect(groups.first.status, 'Poliklinik nonaktif');
      expect(groups.last.schedules.map((s) => s['hari']), ['SENIN', 'JUMAT']);
      expect(groups.last.activeDays, 1);
      expect(
        groupClinicSchedules([clinic], [schedule('SENIN')], ' nEuRo ').length,
        1,
      );
      expect(groupClinicSchedules([clinic], [], 'tidak ada'), isEmpty);
      expect(
        groupClinicSchedules([], [schedule('SENIN')], '').single.name,
        'Poliklinik Saraf',
      );
    },
  );
  test('closing time must be strictly later within the same day', () {
    expect(scheduleClosesAfter('08:00', '16:00'), isTrue);
    for (final closes in ['08:00', '07:59', '24:00', '9:00']) {
      expect(scheduleClosesAfter('08:00', closes), isFalse);
    }
  });
  test('five weekdays sent sequentially, successful days never automatically retried', () async {
    final stored = <Json>[];
    int concurrent = 0, peak = 0;
    final api = apiFor((r) async {
      if (r.method == 'GET') return reply(stored);
      concurrent++;
      if (concurrent > peak) peak = concurrent;
      await Future<void>.delayed(const Duration(milliseconds: 1));
      stored.add(object(jsonDecode(r.body)));
      concurrent--;
      return reply(stored.last, 201);
    });
    addTearDown(api.dispose);
    Future<List<ScheduleResult>> save() => createScheduleDays(
      api,
      clinicId: 'clinic-a',
      days: scheduleDays.take(5).toSet(),
      opens: '08:00',
      closes: '16:00',
      capacity: 24,
    );
    expect(
      (await save()).every((r) => r.outcome == ScheduleOutcome.created),
      isTrue,
    );
    expect(peak, 1);
    expect(stored.map((s) => s['hari']), scheduleDays.take(5));
    expect(
      (await save()).every((r) => r.outcome == ScheduleOutcome.existing),
      isTrue,
    );
    expect(stored.length, 5);
  });
  test(
    'preflight skips inactive/existing days and continues after partial 400',
    () async {
      final sent = <String>[];
      final api = apiFor((r) async {
        if (r.method == 'GET') return reply([schedule('SENIN', active: false)]);
        final day = '${object(jsonDecode(r.body))['hari']}';
        sent.add(day);
        return day == 'RABU'
            ? reply({'message': 'Simulasi validasi'}, 400)
            : reply({}, 201);
      });
      addTearDown(api.dispose);
      final result = await createScheduleDays(
        api,
        clinicId: 'clinic-a',
        days: scheduleDays.take(5).toSet(),
        opens: '08:00',
        closes: '16:00',
        capacity: 24,
      );
      expect(sent, ['SELASA', 'RABU', 'KAMIS', 'JUMAT']);
      expect(result.map((r) => r.outcome), [
        ScheduleOutcome.existing,
        ScheduleOutcome.created,
        ScheduleOutcome.failed,
        ScheduleOutcome.created,
        ScheduleOutcome.created,
      ]);
    },
  );
  test('lost response after commit and concurrent conflict are reread without POST retry', () async {
    for (final status in [0, 409, 503]) {
      int reads = 0, writes = 0;
      final api = apiFor((r) async {
        if (r.method == 'GET') {
          return reply(++reads == 1 ? [] : [schedule('SENIN')]);
        }
        writes++;
        if (status == 0) throw http.ClientException('Lost response');
        return reply({'message': 'Simulasi gangguan'}, status);
      });
      final result = await createScheduleDays(
        api,
        clinicId: 'clinic-a',
        days: {'SENIN'},
        opens: '08:00',
        closes: '16:00',
        capacity: 24,
      );
      expect(result.single.outcome, ScheduleOutcome.existing);
      expect(writes, 1);
      expect(reads, 2);
      api.dispose();
    }
  });
  test(
    'unverified result is explicit when mutation and reconciliation fail',
    () async {
      int reads = 0, writes = 0;
      final api = apiFor((r) async {
        if (r.method == 'GET' && ++reads == 1) return reply([]);
        if (r.method == 'POST') writes++;
        throw http.ClientException('Offline');
      });
      addTearDown(api.dispose);
      final result = await createScheduleDays(
        api,
        clinicId: 'clinic-a',
        days: {'SENIN'},
        opens: '08:00',
        closes: '16:00',
        capacity: 24,
      );
      expect(result.single.outcome, ScheduleOutcome.uncertain);
      expect(result.single.message, contains('belum terverifikasi'));
      expect(writes, 1);
    },
  );
  test('failed preflight sends zero mutations', () async {
    final methods = <String>[];
    final api = apiFor((r) async {
      methods.add(r.method);
      return reply({'message': 'Offline'}, 503);
    });
    addTearDown(api.dispose);
    await expectLater(
      createScheduleDays(
        api,
        clinicId: 'clinic-a',
        days: {'SENIN'},
        opens: '08:00',
        closes: '16:00',
        capacity: 24,
      ),
      throwsA(isA<ApiException>()),
    );
    expect(methods, ['GET']);
  });
  testWidgets(
    'grouped card uses clinic name, day order, missing days and row actions',
    (tester) async {
      final actions = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: GroupedClinicSchedules(
                clinics: const [clinic],
                schedules: [
                  schedule('SELASA', active: false),
                  schedule('SENIN'),
                ],
                search: '',
                onSearch: (_) {},
                onEdit: (s) => actions.add('edit-${s['hari']}'),
                onDeactivate: (s) => actions.add('off-${s['hari']}'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Poliklinik Saraf'), findsOneWidget);
      expect(find.text('1 hari aktif · Jadwal aktif'), findsOneWidget);
      expect(find.text('Belum dikonfigurasi'), findsNWidgets(5));
      expect(
        tester.getTopLeft(find.text('Senin')).dy,
        lessThan(tester.getTopLeft(find.text('Selasa')).dy),
      );
      expect(find.text('schedule-SENIN'), findsNothing);
      await tester.tap(find.text('Ubah').first);
      await tester.tap(find.text('Nonaktifkan').first);
      expect(actions, ['edit-SENIN', 'off-SENIN']);
    },
  );
  testWidgets('search keeps its own semantic bounds and filters clinic cards', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      String search = '';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: StatefulBuilder(
                builder: (context, setState) => GroupedClinicSchedules(
                  clinics: const [
                    clinic,
                    {
                      'id': 'b',
                      'nama': 'Poliklinik Anak',
                      'kode': 'ANAK',
                      'aktif': true,
                    },
                  ],
                  schedules: [schedule('SENIN')],
                  search: search,
                  onSearch: (value) => setState(() => search = value),
                  onEdit: (_) {},
                  onDeactivate: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(find.byType(TextFormField)).rect.height,
        lessThan(100),
      );
      await tester.enterText(find.byType(TextFormField), 'NEURO');
      await tester.pumpAndSettle();
      expect(find.text('Poliklinik Saraf'), findsOneWidget);
      expect(find.text('Poliklinik Anak'), findsNothing);
    } finally {
      semantics.dispose();
    }
  });
  testWidgets('bulk validates days, HH:mm, closing time and positive integer', (
    tester,
  ) async {
    int requests = 0;
    final api = apiFor((_) async {
      requests++;
      return reply([]);
    });
    addTearDown(api.dispose);
    await editor(tester, api);
    await tester.tap(find.text('Hapus Pilihan'));
    await tester.tap(find.text('Simpan Jadwal Terpilih'));
    await tester.pumpAndSettle();
    expect(find.text('Pilih minimal satu hari.'), findsOneWidget);
    await tester.tap(find.text('Pilih Senin–Jumat'));
    final inputs = find.byType(TextFormField);
    await tester.enterText(inputs.at(0), '8:00');
    await tester.enterText(inputs.at(2), '0');
    await tester.tap(find.text('Simpan Jadwal Terpilih'));
    await tester.pumpAndSettle();
    expect(find.text('Gunakan HH:mm.'), findsOneWidget);
    expect(find.text('Bilangan bulat 1 atau lebih.'), findsOneWidget);
    await tester.enterText(inputs.at(0), '16:00');
    await tester.enterText(inputs.at(2), '2.5');
    await tester.tap(find.text('Simpan Jadwal Terpilih'));
    await tester.pumpAndSettle();
    expect(find.text('Jam tutup harus sesudah jam buka.'), findsOneWidget);
    expect(requests, 0);
    await tester.tap(find.text('Pilih Semua'));
    await tester.pump();
    expect(
      tester
          .widgetList<FilterChip>(find.byType(FilterChip))
          .every((c) => c.selected),
      isTrue,
    );
  });
  testWidgets(
    'busy save cannot be double submitted and result cannot be resubmitted',
    (tester) async {
      final gate = Completer<void>();
      int posts = 0;
      final api = apiFor((r) async {
        if (r.method == 'GET') {
          await gate.future;
          return reply([]);
        }
        posts++;
        return reply({}, 201);
      });
      addTearDown(api.dispose);
      await editor(tester, api);
      await tester.tap(find.text('Simpan Jadwal Terpilih'));
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Menyimpan…'),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Kembali'))
            .onPressed,
        isNull,
      );
      gate.complete();
      await tester.pumpAndSettle();
      expect(posts, 5);
      expect(find.text('Simpan Jadwal Terpilih'), findsNothing);
      expect(
        find.text('5 berhasil · 0 dilewati · 0 gagal/belum terverifikasi'),
        findsOneWidget,
      );
    },
  );
}
