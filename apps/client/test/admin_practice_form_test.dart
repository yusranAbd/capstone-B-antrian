import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:queueb_client/src/admin.dart';
import 'package:queueb_client/src/admin_practice_form.dart';
import 'package:queueb_client/src/api.dart';
import 'package:queueb_client/src/config.dart';
import 'package:timezone/data/latest.dart' as tz;

const clinic = {'id': 'clinic-pd', 'nama': 'Penyakit Dalam', 'aktif': true};
const eye = {'id': 'clinic-eye', 'nama': 'Poli Mata', 'aktif': true};
const room = {
  'id': 'room-pd',
  'kode': 'PD01',
  'nama': 'Ruang Penyakit Dalam 1',
  'layananId': 'clinic-pd',
  'aktif': true,
};
const doctorLabel =
    'dr. Indah Suci Permatasari\nPenyakit Dalam · Penyakit Dalam';
const eyeLabel = 'dr. Andi Setiawan\nSpesialis Mata · Poli Mata';
final catalog = <String, List<Json>>{
  '/layanan': [clinic, eye],
  '/loket': [
    room,
    {
      'id': 'room-eye',
      'kode': 'MT01',
      'nama': 'Ruang Mata',
      'layananId': 'clinic-eye',
      'aktif': true,
    },
    {
      'id': 'room-inactive',
      'kode': 'PD02',
      'nama': 'Ruang Nonaktif',
      'layananId': 'clinic-pd',
      'aktif': false,
    },
  ],
  '/dokter': [
    {
      'id': 'doctor-pd',
      'nama': 'dr. Indah Suci Permatasari',
      'spesialisasi': 'Penyakit Dalam',
      'aktif': true,
      'dokterLayanan': [
        {
          'id': 'link-pd',
          'layananId': 'clinic-pd',
          'layanan': clinic,
          'aktif': true,
        },
      ],
    },
    {
      'id': 'doctor-eye',
      'nama': 'dr. Andi Setiawan',
      'spesialisasi': 'Spesialis Mata',
      'aktif': true,
      'dokterLayanan': [
        {
          'id': 'link-eye',
          'layananId': 'clinic-eye',
          'layanan': eye,
          'aktif': true,
        },
      ],
    },
    {
      'id': 'doctor-off',
      'nama': 'Dokter Nonaktif',
      'aktif': false,
      'dokterLayanan': [
        {
          'id': 'link-off',
          'layananId': 'clinic-pd',
          'layanan': clinic,
          'aktif': true,
        },
      ],
    },
  ],
};
Json session() => {
  'id': 'practice-1',
  'dokterLayananId': 'link-pd',
  'loketId': 'room-pd',
  'tanggal': '2026-10-19T00:00:00.000Z',
  'mulaiPada': '2026-10-19T01:00:00.000Z',
  'selesaiPada': '2026-10-19T05:00:00.000Z',
  'aktif': true,
  'dokterLayanan': {
    'id': 'link-pd',
    'layananId': 'clinic-pd',
    'layanan': clinic,
    'dokter': catalog['/dokter']!.first,
  },
  'loket': room,
};

void main() {
  setUpAll(tz.initializeTimeZones);

  Future<QueueApi> open(
    WidgetTester tester, {
    Json? row,
    double width = 1280,
    double height = 900,
    Future<http.Response> Function(http.Request)? handler,
    Map<String, List<Json>>? data,
  }) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = QueueApi(
      config: AppConfig(apiBaseUrl: 'http://localhost/api/v1', realtime: false),
      client: MockClient(handler ?? (_) async => http.Response('{}', 201)),
    );
    addTearDown(api.dispose);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('id'),
        supportedLocales: const [Locale('id'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<bool>(
                context: context,
                barrierDismissible: false,
                builder: (_) => PracticeScheduleEditor(
                  api: api,
                  catalog: data ?? catalog,
                  row: row,
                ),
              ),
              child: const Text('Buka form'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Buka form'));
    await tester.pumpAndSettle();
    return api;
  }

  Finder keyed(String value) => find.byKey(ValueKey(value));
  Future<void> chooseDoctor(
    WidgetTester tester,
    String query,
    String title,
  ) async {
    final field = find.descendant(
      of: keyed('practice-doctor'),
      matching: find.byType(TextField),
    );
    await tester.tap(field);
    await tester.enterText(field, query);
    await tester.pumpAndSettle();
    await tester.tap(find.text(title).last);
    await tester.pumpAndSettle();
  }

  Future<void> chooseRoom(WidgetTester tester, String title) async {
    await tester.tap(
      find.descendant(
        of: find.byType(PracticeScheduleEditor),
        matching: find.byType(DropdownButtonFormField<String>),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(title).last);
    await tester.pumpAndSettle();
  }

  Future<void> chooseTime(
    WidgetTester tester,
    String field,
    String hour,
    String minute,
  ) async {
    await tester.ensureVisible(keyed(field));
    await tester.tap(keyed(field));
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsOneWidget);
    await tester.tap(find.byIcon(Icons.keyboard_outlined));
    await tester.pumpAndSettle();
    final fields = find.descendant(
      of: find.byType(TimePickerDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(fields.at(0), hour);
    await tester.enterText(fields.at(1), minute);
    await tester.tap(find.text('Pilih Jam'));
    await tester.pumpAndSettle();
  }

  Future<void> fillCreate(WidgetTester tester) async {
    await chooseDoctor(tester, 'Indah', doctorLabel);
    await chooseRoom(tester, 'PD01 · Ruang Penyakit Dalam 1');
    await chooseTime(tester, 'practice-start', '08', '00');
    await chooseTime(tester, 'practice-end', '12', '00');
  }

  for (final width in [320.0, 375.0, 414.0, 768.0, 1280.0, 1920.0]) {
    for (final edit in [false, true]) {
      testWidgets('${edit ? 'edit' : 'create'} responsive modal at $width', (
        tester,
      ) async {
        await open(
          tester,
          row: edit ? session() : null,
          width: width,
          height: 720,
        );
        expect(
          find.text('${edit ? 'Ubah' : 'Tambah'} Jadwal Praktik'),
          findsOneWidget,
        );
        expect(find.text('Simpan Jadwal'), findsOneWidget);
        expect(
          tester.getRect(find.text('Simpan Jadwal')).bottom,
          lessThan(720),
        );
        expect(find.textContaining('YYYY-MM-DD'), findsNothing);
        expect(find.textContaining('Catatan'), findsNothing);
        if (width >= 1280) {
          expect(
            tester.getTopLeft(keyed('practice-start')).dx,
            greaterThan(tester.getTopLeft(keyed('practice-date')).dx),
          );
        }
        await tester.ensureVisible(keyed('practice-end'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Batal'));
        await tester.pumpAndSettle();
        expect(find.byType(PracticeScheduleEditor), findsNothing);
      });
    }
  }

  for (final query in ['Indah', 'Penyakit Dalam', 'Permatasari']) {
    testWidgets('doctor search matches $query and room choices follow clinic', (
      tester,
    ) async {
      await open(tester);
      await chooseDoctor(tester, query, doctorLabel);
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      expect(find.text('PD01 · Ruang Penyakit Dalam 1'), findsOneWidget);
      expect(find.text('MT01 · Ruang Mata'), findsNothing);
      expect(find.textContaining('PD02'), findsNothing);
      await tester.tap(find.text('PD01 · Ruang Penyakit Dalam 1'));
      await tester.pumpAndSettle();
      await chooseDoctor(tester, 'Mata', eyeLabel);
      final dropdown = tester.widget<DropdownButtonFormField<String>>(
        find.byType(DropdownButtonFormField<String>),
      );
      expect(dropdown.initialValue, isNull);
      await chooseRoom(tester, 'MT01 · Ruang Mata');
    });
  }

  testWidgets(
    'calendar selection and 24h time pickers create correct Jakarta API payload',
    (tester) async {
      final writes = <http.Request>[];
      final api = await open(
        tester,
        handler: (r) async {
          writes.add(r);
          return http.Response('{}', 201);
        },
      );
      final today = DateTime.parse(api.config.today);
      await tester.tap(keyed('practice-date'));
      await tester.pumpAndSettle();
      expect(find.byType(CalendarDatePicker), findsOneWidget);
      final picker = tester.widget<CalendarDatePicker>(
        find.byType(CalendarDatePicker),
      );
      expect(calendarDate(picker.initialDate!), api.config.today);
      await tester.tap(find.text('${today.day}').last);
      await tester.tap(find.text('Pilih Tanggal'));
      await tester.pumpAndSettle();
      await fillCreate(tester);
      expect(find.text('Durasi praktik: 4 jam'), findsOneWidget);
      await tester.tap(find.text('Simpan Jadwal'));
      await tester.pumpAndSettle();
      expect(writes.length, 1);
      expect(writes.single.method, 'POST');
      expect(writes.single.url.path, '/api/v1/jadwal-praktik');
      expect(jsonDecode(writes.single.body), {
        'dokterLayananId': 'link-pd',
        'loketId': 'room-pd',
        'tanggal': api.config.today,
        'mulaiPada': '${api.config.today}T01:00:00.000Z',
        'selesaiPada': '${api.config.today}T05:00:00.000Z',
      });
      expect(find.byType(PracticeScheduleEditor), findsNothing);
    },
  );

  testWidgets('edit prefills service time and patches only changed values', (
    tester,
  ) async {
    http.Request? sent;
    await open(
      tester,
      row: session(),
      handler: (r) async {
        sent = r;
        return http.Response('{}', 200);
      },
    );
    expect(
      tester.widget<TextFormField>(keyed('practice-start')).controller!.text,
      '08:00',
    );
    expect(
      tester.widget<TextFormField>(keyed('practice-end')).controller!.text,
      '12:00',
    );
    expect(
      tester.widget<TextFormField>(keyed('practice-date')).controller!.text,
      '19 Oktober 2026',
    );
    await chooseTime(tester, 'practice-end', '13', '30');
    expect(find.text('Durasi praktik: 5 jam 30 menit'), findsOneWidget);
    await tester.tap(find.text('Simpan Jadwal'));
    await tester.pumpAndSettle();
    expect(sent!.method, 'PATCH');
    expect(sent!.url.path, '/api/v1/jadwal-praktik/practice-1');
    expect(jsonDecode(sent!.body), {'selesaiPada': '2026-10-19T06:30:00.000Z'});
  });

  testWidgets(
    'status-only edit preserves exact existing timestamps without resending schedule fields',
    (tester) async {
      http.Request? sent;
      await open(
        tester,
        row: {
          ...session(),
          'mulaiPada': '2026-10-19T01:00:17.000Z',
          'selesaiPada': '2026-10-19T05:00:17.000Z',
        },
        handler: (r) async {
          sent = r;
          return http.Response('{}', 200);
        },
      );
      await tester.tap(find.byType(SwitchListTile));
      await tester.tap(find.text('Simpan Jadwal'));
      await tester.pumpAndSettle();
      expect(jsonDecode(sent!.body), {'aktif': false});
    },
  );

  testWidgets('opening and cancelling existing schedule makes no mutation', (
    tester,
  ) async {
    int calls = 0;
    await open(
      tester,
      row: session(),
      handler: (_) async {
        calls++;
        return http.Response('{}', 200);
      },
    );
    await tester.tap(find.text('Simpan Jadwal'));
    await tester.pumpAndSettle();
    expect(
      find.text('Belum ada perubahan. Ubah isian atau pilih Batal.'),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Tutup formulir'));
    await tester.pumpAndSettle();
    expect(calls, 0);
  });

  testWidgets('required fields and end <= start prevent submission', (
    tester,
  ) async {
    int calls = 0;
    await open(
      tester,
      handler: (_) async {
        calls++;
        return http.Response('{}', 201);
      },
    );
    await tester.tap(find.text('Simpan Jadwal'));
    await tester.pumpAndSettle();
    expect(
      find.text('Pilih dokter dan poliklinik dari hasil pencarian.'),
      findsOneWidget,
    );
    expect(find.text('Pilih ruang sesuai poliklinik.'), findsOneWidget);
    await fillCreate(tester);
    await chooseTime(tester, 'practice-end', '08', '00');
    await tester.tap(find.text('Simpan Jadwal'));
    await tester.pumpAndSettle();
    expect(find.text('Jam selesai harus setelah jam mulai.'), findsOneWidget);
    expect(calls, 0);
  });

  testWidgets('unselected search text cannot submit the previous doctor', (
    tester,
  ) async {
    int calls = 0;
    await open(
      tester,
      row: session(),
      handler: (_) async {
        calls++;
        return http.Response('{}', 201);
      },
    );
    await tester.enterText(
      find.descendant(
        of: keyed('practice-doctor'),
        matching: find.byType(TextField),
      ),
      'Tidak ada dokter',
    );
    await tester.tap(find.text('Simpan Jadwal'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(
      find.text('Pilih dokter dan poliklinik dari hasil pencarian.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'API conflict stays visible with input preserved; loading prevents duplicate writes and closing',
    (tester) async {
      final gate = Completer<http.Response>();
      int calls = 0;
      await open(
        tester,
        row: session(),
        handler: (_) {
          calls++;
          return gate.future;
        },
      );
      await chooseTime(tester, 'practice-end', '13', '00');
      await tester.tap(find.text('Simpan Jadwal'));
      await tester.pump();
      expect(find.text('Menyimpan…'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.close))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Batal'),
            )
            .onPressed,
        isNull,
      );
      gate.complete(
        http.Response(
          jsonEncode({'message': 'Jadwal dokter atau ruang bertabrakan.'}),
          409,
        ),
      );
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(
        find.text('Jadwal dokter atau ruang bertabrakan.'),
        findsOneWidget,
      );
      expect(
        tester.widget<TextFormField>(keyed('practice-end')).controller!.text,
        '13:00',
      );
      expect(find.byType(PracticeScheduleEditor), findsOneWidget);
    },
  );

  testWidgets(
    'changing service date moves both instants to that Jakarta date',
    (tester) async {
      http.Request? sent;
      await open(
        tester,
        row: session(),
        handler: (r) async {
          sent = r;
          return http.Response('{}', 200);
        },
      );
      await tester.tap(keyed('practice-date'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('20').last);
      await tester.tap(find.text('Pilih Tanggal'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Simpan Jadwal'));
      await tester.pumpAndSettle();
      expect(jsonDecode(sent!.body), {
        'tanggal': '2026-10-20',
        'mulaiPada': '2026-10-20T01:00:00.000Z',
        'selesaiPada': '2026-10-20T05:00:00.000Z',
      });
    },
  );

  testWidgets(
    'backend slot lock remains authoritative and does not close the form',
    (tester) async {
      await open(
        tester,
        row: session(),
        handler: (_) async => http.Response(
          jsonEncode({
            'message': 'Jadwal yang memiliki slot tidak boleh diubah atau dinonaktifkan',
          }),
          409,
        ),
      );
      await chooseTime(tester, 'practice-end', '13', '00');
      await tester.tap(find.text('Simpan Jadwal'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Jadwal yang memiliki slot tidak boleh diubah atau dinonaktifkan',
        ),
        findsOneWidget,
      );
      expect(find.byType(PracticeScheduleEditor), findsOneWidget);
      expect(
        tester.widget<TextFormField>(keyed('practice-end')).controller!.text,
        '13:00',
      );
    },
  );

  testWidgets('cancelling pickers preserves existing data without a request', (
    tester,
  ) async {
    int calls = 0;
    await open(
      tester,
      row: session(),
      handler: (_) async {
        calls++;
        return http.Response('{}', 200);
      },
    );
    await tester.tap(keyed('practice-date'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Batal').last);
    await tester.pumpAndSettle();
    await tester.tap(keyed('practice-start'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Batal').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Simpan Jadwal'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(
      tester.widget<TextFormField>(keyed('practice-start')).controller!.text,
      '08:00',
    );
  });

  testWidgets(
    'successful create closes modal and refreshes ADMIN schedule list',
    (tester) async {
      int listReads = 0, writes = 0;
      final api = QueueApi(
        config: AppConfig(
          apiBaseUrl: 'http://localhost/api/v1',
          realtime: false,
        ),
        client: MockClient((r) async {
          if (r.method == 'POST') {
            writes++;
            return http.Response('{}', 201);
          }
          final path = r.url.path.replaceFirst('/api/v1', '');
          if (path == '/jadwal-praktik') listReads++;
          return http.Response(jsonEncode(catalog[path] ?? []), 200);
        }),
      );
      addTearDown(api.dispose);
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          supportedLocales: const [Locale('id')],
          locale: const Locale('id'),
          home: Scaffold(body: AdminPage(api: api)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Manajemen jadwal'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Jadwal praktik'));
      await tester.pumpAndSettle();
      final before = listReads;
      await tester.tap(find.text('Tambah'));
      await tester.pumpAndSettle();
      await fillCreate(tester);
      await tester.tap(find.text('Simpan Jadwal'));
      await tester.pumpAndSettle();
      expect(writes, 1);
      expect(listReads, greaterThan(before));
      expect(find.byType(PracticeScheduleEditor), findsNothing);
      expect(find.text('Data disimpan.'), findsOneWidget);
    },
  );
}
