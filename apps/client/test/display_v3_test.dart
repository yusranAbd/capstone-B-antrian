import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:queueb_client/src/config.dart';
import 'package:queueb_client/src/display_board.dart';
import 'package:queueb_client/src/mobile_ui.dart';

// Synthetic, clearly isolated QA data. Production always reads the REST snapshot.
Json monitorSnapshot({
  int waiting = 1,
  String status = 'DIPANGGIL',
  bool full = false,
}) => {
  'versiSkema': 1,
  'tanggalPelayanan': '2026-10-26',
  'totalMenunggu': waiting,
  'layanan': {'kode': 'AN', 'nama': 'Poliklinik Anak'},
  'modeNama': full ? 'LENGKAP' : 'SAMAR',
  'menunggu': [
    for (var i = 0; i < waiting; i++)
      {
        'nomorAntrean': 'AN-${(i + 2).toString().padLeft(3, '0')}',
        'namaPasien': full ? 'Pasien Demonstrasi $i' : 'Pasien D.',
      },
  ],
  'loket': [
    for (var i = 0; i < 3; i++)
      {
        'kode': 'AN0${i + 1}',
        'nama': 'Ruang Anak ${i + 1}',
        'tiketAktif': [
          if (i == 0 && ['DIPANGGIL', 'DILAYANI'].contains(status))
            {
              'nomorAntrean': 'AN-001',
              'status': status,
              'namaPasien': full
                  ? 'Pasien Demonstrasi Dengan Nama Yang Sangat Panjang Sekali'
                  : 'Pasien D.',
              'dipanggilPada': '2026-10-26T02:00:00Z',
            },
        ],
      },
  ],
  'pengumumanTerakhir': status == 'DIPANGGIL'
      ? {
          'peristiwaId': 'fixture-call',
          'aksi': 'CALL',
          'nomorAntrean': 'AN-001',
          'kodeLoket': 'AN01',
          'teks':
              'Panggilan nomor antrean A N, nol nol satu atas nama ${full ? 'Pasien Demonstrasi Dengan Nama Yang Sangat Panjang Sekali' : 'Pasien D.'}, silakan menuju ke Poliklinik Anak, terima kasih.',
        }
      : null,
};

void main() {
  final capture = Platform.environment['QUEUEB_CAPTURE_DIR'];
  testWidgets('patient names, SKIP, REQUEUE and paging come from snapshot', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final data = monitorSnapshot(waiting: 1, full: true);
    final captureKey = GlobalKey();
    data['antrianPasien'] = [
      {
        'nomorAntrean': 'AN-002',
        'namaPasien': 'Pasien Demonstrasi Lengkap',
        'status': 'MENUNGGU',
      },
      {
        'nomorAntrean': 'AN-003',
        'namaPasien': 'Pasien Terlewat Lengkap',
        'status': 'DILEWATI',
      },
    ];
    data['totalAntrianPasien'] = 2;
    Future<void> render() => tester.pumpWidget(
      MaterialApp(
        theme: QueueBStyle.theme,
        home: Scaffold(
          body: RepaintBoundary(
            key: captureKey,
            child: DisplayBoard(
              snapshot: data,
              now: DateTime(2026, 10, 26),
              status: 'Realtime terhubung',
              onRefresh: () {},
              onAudio: () {},
              onConfigure: () {},
              onFullscreen: () {},
            ),
          ),
        ),
      ),
    );
    await render();
    expect(find.text('Antrian pasien'), findsOneWidget);
    expect(find.text('STATUS'), findsOneWidget);
    expect(find.text('Pasien Demonstrasi Lengkap'), findsOneWidget);
    expect(find.text('Pasien Terlewat Lengkap'), findsOneWidget);
    expect(find.text('Menunggu'), findsOneWidget);
    expect(find.text('Dilewati'), findsOneWidget);
    expect(tester.takeException(), isNull);
    if (capture != null) {
      await tester.runAsync(() async {
        final image =
            await (captureKey.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('$capture/display-patients-1280.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    data['antrianPasien'] = [
      {
        'nomorAntrean': 'AN-002',
        'namaPasien': 'Pasien Demonstrasi Lengkap',
        'status': 'MENUNGGU',
      },
      {
        'nomorAntrean': 'AN-003',
        'namaPasien': 'Pasien Terlewat Lengkap',
        'status': 'MENUNGGU',
      },
    ];
    await render();
    expect(find.text('Dilewati'), findsNothing);
    expect(find.text('Menunggu'), findsNWidgets(2));
    expect(find.text('AN-003'), findsOneWidget);
    data['antrianPasien'] = [
      for (var i = 0; i < 9; i++)
        {
          'nomorAntrean': 'QA-$i',
          'namaPasien': 'Pasien $i',
          'status': 'MENUNGGU',
        },
      {
        'nomorAntrean': 'QA-999',
        'namaPasien': 'Pasien Dilewati Terakhir',
        'status': 'DILEWATI',
      },
    ];
    data['totalAntrianPasien'] = 10;
    await render();
    for (var i = 0; i < 10 && find.text('QA-999').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(seconds: 12));
    }
    expect(find.text('QA-999'), findsOneWidget);
    expect(find.text('Dilewati'), findsOneWidget);
    expect(find.byType(Scrollable), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 20));
  });
  setUpAll(() async {
    final fontRoot = Platform.environment['QUEUEB_FONT_DIR'];
    if (capture != null && fontRoot != null) {
      final loader = FontLoader('Roboto');
      for (final font in ['regular', 'medium', 'bold', 'black']) {
        loader.addFont(
          File('$fontRoot/roboto-$font.ttf')
              .readAsBytes()
              .then((b) => ByteData.sublistView(b)),
        );
      }
      await loader.load();
      final icons = FontLoader('MaterialIcons');
      icons.addFont(
        File('$fontRoot/materialicons-regular.otf')
            .readAsBytes()
            .then((b) => ByteData.sublistView(b)),
      );
      await icons.load();
    }
  });
  for (final size in [
    const Size(1280, 720),
    const Size(1366, 768),
    const Size(1920, 1080),
  ]) {
    for (final count in [0, 1, 30]) {
      for (final full in [false, true]) {
        testWidgets(
          'V3 no scrolling or overflow at $size with $count waiting, full=$full',
          (tester) async {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final key = GlobalKey();
            final data = monitorSnapshot(waiting: count, full: full);
            await tester.pumpWidget(
              MaterialApp(
                theme: QueueBStyle.theme,
                home: Scaffold(
                  body: RepaintBoundary(
                    key: key,
                    child: DisplayBoard(
                      snapshot: data,
                      now: DateTime(2026, 10, 26, 9, 30),
                      status: 'Realtime terhubung',
                      fullscreenSupported: true,
                      onRefresh: () {},
                      onAudio: () {},
                      onConfigure: () {},
                      onFullscreen: () {},
                    ),
                  ),
                ),
              ),
            );
            await tester.pump();
            expect(tester.takeException(), isNull);
            expect(find.byType(Scrollable), findsNothing);
            expect(
              find.byKey(const ValueKey('display-call-name')),
              findsOneWidget,
            );

            if (count == 0) {
              expect(find.text('Belum ada antrian pasien.'), findsOneWidget);
            }
            if (count == 30) {
              expect(
                find.byKey(const ValueKey('display-more-waiting')),
                findsOneWidget,
              );
              final list = find.byKey(const ValueKey('display-waiting-panel'));
              expect(tester.getBottomRight(list).dy, lessThan(size.height));
            }
            if (capture != null && count == 30) {
              await tester.runAsync(() async {
                final image =
                    await (key.currentContext!.findRenderObject()!
                            as RenderRepaintBoundary)
                        .toImage();
                final bytes = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                final file = File(
                  '$capture/monitor-${size.width.toInt()}x${size.height.toInt()}${full ? '-full' : ''}.png',
                );
                await file.parent.create(recursive: true);
                await file.writeAsBytes(bytes!.buffer.asUint8List());
                image.dispose();
              });
            }
            await tester.pumpWidget(const SizedBox());
          },
        );
      }
    }
  }
  testWidgets(
    'snapshot updates replace waiting and called names after START/COMPLETE',
    (tester) async {
      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Future<void> render(Json data) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DisplayBoard(
              snapshot: data,
              now: DateTime(2026, 10, 26),
              status: 'Realtime terhubung',
              onRefresh: () {},
              onAudio: () {},
              onConfigure: () {},
              onFullscreen: () {},
            ),
          ),
        ),
      );
      await render(monitorSnapshot(waiting: 1));
      expect(find.text('AN-002'), findsOneWidget);
      await render(monitorSnapshot(waiting: 0, status: 'DILAYANI'));
      expect(find.byKey(const ValueKey('display-call-name')), findsNothing);
      expect(find.text('AN-002'), findsNothing);
      expect(find.textContaining('Sedang dilayani'), findsOneWidget);
      await render(monitorSnapshot(waiting: 0, status: 'SELESAI'));
      expect(find.text('AN-001'), findsNothing);
      expect(find.text('Belum ada nomor dipanggil.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
