import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:queueb_client/src/api.dart';
import 'package:queueb_client/src/app.dart';
import 'package:queueb_client/src/config.dart';

import 'ui_test.dart' show FakeBackend, uid;

const roomB = '22222222-2222-4222-8222-222222222222';

class StaffV4Backend extends FakeBackend {
  StaffV4Backend() : super('PETUGAS');
  bool empty = false, schedulesEmpty = false, denied = false;
  Completer<http.Response>? scheduleGate;
  bool paged = false;
  String remoteStatus = 'CHECK_IN';
  Json get remote => {
    'tiketId': 'remote',
    'nomorAntrean': 'UM-101',
    'namaPasien': 'Pasien halaman dua',
    'status': remoteStatus,
    'bisaMasukAntrean': remoteStatus == 'CHECK_IN',
  };
  final patients = <Json>[
    {
      'tiketId': uid,
      'nomorAntrean': 'UM-001',
      'namaPasien': 'Andi Pratama',
      'status': 'MENUNGGU',
      'layakDipanggil': true,
    },
    {
      'tiketId': 'skip',
      'nomorAntrean': 'UM-002',
      'namaPasien': 'Budi Saputra',
      'status': 'DILEWATI',
      'loketId': uid,
      'bisaAntreUlang': true,
    },
    {
      'tiketId': 'check',
      'nomorAntrean': 'UM-003',
      'namaPasien': 'Citra Lestari',
      'status': 'CHECK_IN',
      'bisaMasukAntrean': true,
    },
  ];
  List<Json> get current => empty
      ? []
      : patients
            .map((p) => {...p, 'checkInPada': '${today}T02:10:00Z'})
            .toList();
  @override
  Future<http.Response> handle(http.Request r) async {
    final p = r.url.path.replaceFirst('/api/v1', '');
    if (p == '/penugasan-petugas') {
      return reply([
        for (final id in [uid, roomB])
          {
            'id': id,
            'loketId': id,
            'aktif': true,
            'tanggalMulai': today,
            'loket': {
              ...room,
              'id': id,
              'kode': id == uid ? 'RU' : 'RU2',
              'nama': id == uid ? 'Ruang Umum' : 'Ruang Dua',
            },
          },
      ]);
    }
    if (p == '/jadwal-praktik') {
      if (scheduleGate != null) {
        final gate = scheduleGate!;
        scheduleGate = null;
        return gate.future;
      }
      if (schedulesEmpty) return reply([]);
      return reply([
        for (final id in [uid, roomB])
          {
            'id': id,
            'aktif': true,
            'tanggal': today,
            'mulaiPada': '${today}T01:00:00Z',
            'selesaiPada': '${today}T09:00:00Z',
            'loketId': id,
            'loket': {...room, 'id': id},
            'dokterLayanan': {
              'layanan': service,
              'dokter': {
                'id': id,
                'nama': id == uid
                    ? 'dr. Sindi Fixture'
                    : 'dr. Dokter Ruang Dua',
                'spesialisasi': 'Anak',
                'fotoProfil': null,
              },
            },
          },
      ]);
    }
    if (p == '/queue/snapshot') {
      if (denied) return reply({'message': 'Penugasan tidak berlaku.'}, 403);
      final page =
          int.tryParse(r.url.queryParameters['halamanTindakLanjut'] ?? '1') ??
          1;
      requests.add((r.method, p, {'halamanTindakLanjut': page}));
      final list = paged
          ? (page == 2
                ? [remote]
                : [...current, if (remoteStatus == 'MENUNGGU') remote])
          : current;
      return reply({
        'tanggalPelayanan': today,
        'diperolehPada': '${today}T03:00:00Z',
        'menunggu': {
          'total': current.where((t) => t['status'] == 'MENUNGGU').length,
          'tiket': current.where((t) => t['status'] == 'MENUNGGU').toList(),
        },
        'daftarPasien': {
          'total': paged ? 104 : current.length,
          'ditampilkan': list.length,
          'tiket': list,
          'halamanTindakLanjut': page,
          'jumlahHalamanTindakLanjut': paged && remoteStatus == 'CHECK_IN'
              ? 2
              : 1,
        },
        'loket': [
          {...room, 'tiketAktif': <Json>[]},
        ],
      });
    }
    if (p.endsWith('/antre-ulang') || p.endsWith('/masuk')) {
      requests.add((
        r.method,
        p,
        object(r.body.isEmpty ? null : jsonDecode(r.body)),
      ));
      final id = p.split('/')[2];
      if (id == 'remote') {
        remoteStatus = 'MENUNGGU';
        return reply(remote);
      }
      final item = patients.firstWhere((t) => t['tiketId'] == id);
      item['status'] = 'MENUNGGU';
      return reply(item);
    }
    return super.handle(r);
  }
}

void main() {
  setUpAll(() async {
    tz.initializeTimeZones();
    if (Platform.environment['QUEUEB_STAFF_CAPTURE_DIR'] != null) {
      final fonts = Platform.environment['QUEUEB_FONT_DIR']!;
      for (final family in ['Roboto', 'Ahem']) {
        final loader = FontLoader(family);
        loader.addFont(
          File('$fonts/roboto-regular.ttf')
              .readAsBytes()
              .then((b) => ByteData.sublistView(b)),
        );
        await loader.load();
      }
      final icons = FontLoader('MaterialIcons');
      icons.addFont(
        File('$fonts/materialicons-regular.otf')
            .readAsBytes()
            .then((b) => ByteData.sublistView(b)),
      );
      await icons.load();
    }
  });
  Future<QueueApi> launch(WidgetTester t, StaffV4Backend b, Size size) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    final api = QueueApi(
      config: AppConfig(apiBaseUrl: 'http://localhost/api/v1', realtime: false),
      client: MockClient(b.handle),
    );
    await api.login('fixture@test.local', 'fixture-only');
    await t.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('staff-capture'),
        child: QueueBApp(api: api),
      ),
    );
    await t.pumpAndSettle();
    addTearDown(() async {
      await t.pumpWidget(const SizedBox());
      api.dispose();
      t.view.resetPhysicalSize();
      t.view.resetDevicePixelRatio();
    });
    return api;
  }

  final output = Platform.environment['QUEUEB_STAFF_CAPTURE_DIR'];
  if (output != null) {
    testWidgets('Capture staff fixtures for before/after review', (t) async {
      await launch(t, StaffV4Backend(), const Size(1366, 768));
      for (final size in [const Size(1366, 768), const Size(390, 844)]) {
        t.view.physicalSize = size;
        await t.pumpAndSettle();
        final boundary = t.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('staff-capture')),
        );
        await t.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(output).create(recursive: true);
          await File(
            '$output/staff-${size.width.toInt()}x${size.height.toInt()}.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    });
  }
  for (final size in [
    const Size(1366, 768),
    const Size(1440, 900),
    const Size(1920, 1080),
    const Size(768, 1024),
    const Size(375, 812),
    const Size(390, 844),
  ]) {
    testWidgets(
      'V4 responsive integrated patients and scheduled doctor $size',
      (t) async {
        await launch(t, StaffV4Backend(), size);
        expect(find.text('dr. Sindi Fixture'), findsOneWidget);
        expect(find.text('dr. Dokter Ruang Dua'), findsNothing);
        expect(find.text('Sedang praktik'), findsNothing);
        expect(find.text('Pasien menunggu'), findsNothing);
        expect(find.text('Tiket diterima / dilewati'), findsNothing);
        if (size.width >= 1000) {
          for (final name in [
            'UM-001',
            'UM-002',
            'UM-003',
            'Mulai Pindai QR',
            'Input Manual',
          ]) {
            expect(find.text(name), findsOneWidget);
            expect(t.getBottomLeft(find.text(name)).dy, lessThan(size.height));
          }
          final scroll = t.state<ScrollableState>(
            find
                .descendant(
                  of: find.byKey(const ValueKey('staff-page-scroll')),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          expect(scroll.position.maxScrollExtent, 0);
        }
        expect(t.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'Full patient search persists through REQUEUE; CHECK_IN uses row action; no duplicate',
    (t) async {
      final backend = StaffV4Backend();
      await launch(t, backend, const Size(1366, 768));
      final search = find.widgetWithText(
        TextField,
        'Cari nomor antrean atau nama pasien',
      );
      await t.enterText(search, 'Budi');
      await t.pumpAndSettle();
      expect(find.text('UM-001'), findsNothing);
      expect(find.text('UM-002'), findsOneWidget);
      await t.tap(find.byTooltip('Aksi UM-002'));
      await t.pumpAndSettle();
      expect(find.text('Kembalikan ke Antrean'), findsOneWidget);
      await t.tap(find.text('Kembalikan ke Antrean'));
      await t.pumpAndSettle();
      expect(backend.patients[1]['status'], 'MENUNGGU');
      expect(find.text('UM-002'), findsOneWidget);
      expect(find.text('Dilewati'), findsNothing);
      expect(t.widget<TextField>(search).controller!.text, 'Budi');
      expect(
        backend.requests
            .where((r) => r.$2.endsWith('/antre-ulang'))
            .single
            .$3['loketId'],
        uid,
      );
      await t.enterText(search, '');
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Aksi UM-003'));
      await t.pumpAndSettle();
      await t.tap(find.text('Masuk Antrean'));
      await t.pumpAndSettle();
      expect(backend.patients[2]['status'], 'MENUNGGU');
      expect(find.text('UM-003'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'Only the originating room can requeue and room change replaces schedule',
    (t) async {
      final backend = StaffV4Backend();
      backend.patients[1]['bisaAntreUlang'] = false;
      await launch(t, backend, const Size(1366, 768));
      await t.tap(find.byTooltip('Aksi UM-002'));
      await t.pumpAndSettle();
      expect(find.text('Kembalikan ke Antrean'), findsNothing);
      await t.tap(find.text('Detail tiket'));
      await t.pumpAndSettle();
      await t.tap(find.text('Tutup'));
      await t.pumpAndSettle();
      await t.tap(find.text('Ruang Umum · Poli Umum'));
      await t.pumpAndSettle();
      await t.tap(find.text('Ruang Dua · Poli Umum').last);
      await t.pumpAndSettle();
      expect(find.text('dr. Dokter Ruang Dua'), findsOneWidget);
      expect(find.text('dr. Sindi Fixture'), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('Long names, empty data and bounded pagination remain usable', (
    t,
  ) async {
    final backend = StaffV4Backend();
    backend.patients[0]['namaPasien'] = 'Nama pasien panjang '.padRight(
      150,
      'a',
    );
    for (var i = 4; i < 24; i++) {
      backend.patients.add({
        'tiketId': 'id$i',
        'nomorAntrean': 'UM-$i',
        'namaPasien': 'Pasien $i',
        'status': 'MENUNGGU',
      });
    }
    await launch(t, backend, const Size(1366, 768));
    expect(find.text('UM-23'), findsNothing);
    await t.tap(find.byTooltip('Halaman antrean berikutnya'));
    await t.pumpAndSettle();
    expect(find.textContaining('halaman 2/'), findsOneWidget);
    backend.empty = true;
    await t.tap(find.byTooltip('Muat ulang antrean'));
    await t.pumpAndSettle();
    expect(find.text('Belum ada antrean yang sesuai.'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('Late schedule response cannot replace the newly selected room', (
    t,
  ) async {
    final backend = StaffV4Backend();
    final gate = Completer<http.Response>();
    backend.scheduleGate = gate;
    addTearDown(() {
      if (!gate.isCompleted) gate.complete(backend.reply([]));
    });
    await launch(t, backend, const Size(1366, 768));
    await t.tap(find.text('Ruang Umum · Poli Umum'));
    await t.pumpAndSettle();
    await t.tap(find.text('Ruang Dua · Poli Umum').last);
    await t.pumpAndSettle();
    expect(find.text('dr. Dokter Ruang Dua'), findsOneWidget);
    gate.complete(
      backend.reply([
        {
          'tanggal': backend.today,
          'loketId': uid,
          'dokterLayanan': {
            'dokter': {'nama': 'Dokter Respons Lama'},
          },
        },
      ]),
    );
    await t.pumpAndSettle();
    expect(find.text('Dokter Respons Lama'), findsNothing);
    expect(find.text('dr. Dokter Ruang Dua'), findsOneWidget);
  });
  testWidgets(
    'Polling and resume reload authoritative statuses; disposal cancels polling',
    (t) async {
      final backend = StaffV4Backend();
      await launch(t, backend, const Size(1366, 768));
      final count = backend.requests
          .where((r) => r.$2 == '/queue/snapshot')
          .length;
      backend.patients[0].addAll({
        'status': 'DILEWATI',
        'bisaAntreUlang': true,
      });
      await t.pump(const Duration(seconds: 16));
      await t.pumpAndSettle();
      expect(
        backend.requests.where((r) => r.$2 == '/queue/snapshot').length,
        greaterThan(count),
      );
      expect(find.text('Dilewati'), findsNWidgets(2));
      expect(find.text('UM-001'), findsOneWidget);
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        t.binding.handleAppLifecycleStateChanged(state);
      }
      backend.patients[0]['status'] = 'MENUNGGU';
      for (final state in [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        t.binding.handleAppLifecycleStateChanged(state);
      }
      await t.pumpAndSettle();
      expect(find.text('Dilewati'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      final disposedCount = backend.requests.length;
      await t.pump(const Duration(seconds: 30));
      expect(backend.requests.length, disposedCount);
    },
  );
  testWidgets('Missing schedule is honest and never blocks queue operations', (
    t,
  ) async {
    final backend = StaffV4Backend()..schedulesEmpty = true;
    await launch(t, backend, const Size(1366, 768));
    expect(
      find.text('Tidak ada jadwal dokter untuk ruang dan tanggal ini.'),
      findsOneWidget,
    );
    expect(find.text('UM-001'), findsOneWidget);
    expect(
      t
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Panggil berikutnya'),
          )
          .onPressed,
      isNotNull,
    );
  });
  testWidgets(
    'Revoked assignment clears cached patient identity and active controls',
    (t) async {
      final backend = StaffV4Backend();
      await launch(t, backend, const Size(1366, 768));
      expect(find.text('Andi Pratama'), findsOneWidget);
      backend.denied = true;
      await t.tap(find.byTooltip('Muat ulang antrean'));
      await t.pumpAndSettle();
      expect(find.text('Andi Pratama'), findsNothing);
      expect(find.text('dr. Sindi Fixture'), findsNothing);
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Panggil berikutnya'),
            )
            .onPressed,
        isNull,
      );
    },
  );
  testWidgets(
    'Follow-up beyond first 100 remains recoverable and page clamps after enqueue',
    (t) async {
      final backend = StaffV4Backend()..paged = true;
      await launch(t, backend, const Size(1366, 768));
      await t.tap(find.byTooltip('Tindak lanjut berikutnya'));
      await t.pumpAndSettle();
      expect(find.text('UM-101'), findsOneWidget);
      expect(
        backend.requests
            .lastWhere((r) => r.$2 == '/queue/snapshot')
            .$3['halamanTindakLanjut'],
        2,
      );
      await t.tap(find.byTooltip('Aksi UM-101'));
      await t.pumpAndSettle();
      await t.tap(find.text('Masuk Antrean'));
      await t.pumpAndSettle();
      expect(backend.remoteStatus, 'MENUNGGU');
      expect(
        backend.requests
            .lastWhere((r) => r.$2 == '/queue/snapshot')
            .$3['halamanTindakLanjut'],
        1,
      );
      // The refreshed waiting list is virtualized; locate the recovered row
      // through the same number search used by staff, including after reorder.
      await t.enterText(
        find.widgetWithText(TextField, 'Cari nomor antrean atau nama pasien'),
        'UM-101',
      );
      await t.pumpAndSettle();
      expect(
        find.byWidgetPredicate((w) => w is Text && w.data == 'UM-101'),
        findsOneWidget,
      );
      expect(find.text('Menunggu'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
}
