import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:queueb_client/src/api.dart';
import 'package:queueb_client/src/config.dart';
import 'package:queueb_client/src/app.dart';
import 'package:queueb_client/src/staff_qr_scanner.dart';

import 'ui_test.dart' show FakeBackend;

void main() {
  setUpAll(() async {
    tz.initializeTimeZones();
    final fonts = Platform.environment['QUEUEB_FONT_DIR'];
    if (Platform.environment['QUEUEB_QR_CAPTURE_DIR'] != null &&
        fonts != null) {
      final text = FontLoader('Roboto');
      for (final style in ['regular', 'medium', 'bold', 'black']) {
        text.addFont(
          File('$fonts/roboto-$style.ttf')
              .readAsBytes()
              .then((b) => ByteData.sublistView(b)),
        );
      }
      await text.load();
      // Replace the test binding's Ahem fallback for screenshot-only captures.
      final fallback = FontLoader('Ahem');
      fallback.addFont(
        File('$fonts/roboto-regular.ttf')
            .readAsBytes()
            .then((b) => ByteData.sublistView(b)),
      );
      await fallback.load();
      final icons = FontLoader('MaterialIcons');
      icons.addFont(
        File('$fonts/materialicons-regular.otf')
            .readAsBytes()
            .then((b) => ByteData.sublistView(b)),
      );
      await icons.load();
    }
  });
  final qrA = 'SQ1.${'A' * 43}', qrB = 'SQ1.${'B' * 43}';
  Json result() => {
    'nomorAntrean': 'AN-001',
    'namaPasien': 'Pasien Uji',
    'namaPoliklinik': 'Poli Anak',
    'status': 'MENUNGGU',
  };
  testWidgets(
    'partial scan ignored; same/parallel frames suppressed; next QR accepted; reopen releases lock',
    (tester) async {
      ValueChanged<String>? detect;
      var calls = 0;
      var gate = Completer<Json>();
      Widget scanner() => MaterialApp(
        home: Scaffold(
          body: StaffQrScanner(
            onScan: (raw) {
              calls++;
              return gate.future;
            },
            previewBuilder: (onDetect) {
              detect = onDetect;
              return const Text('Camera fixture');
            },
          ),
        ),
      );
      await tester.pumpWidget(scanner());
      detect!('SQ1.partial');
      await tester.pump();
      expect(calls, 0);
      detect!(qrA);
      detect!(qrA);
      detect!(qrB);
      await tester.pump();
      expect(calls, 1);
      gate.complete(result());
      await tester.pumpAndSettle();
      expect(find.text('AN-001 · MENUNGGU'), findsOneWidget);
      detect!(qrA);
      await tester.pump();
      expect(calls, 1);
      gate = Completer<Json>();
      detect!(qrB);
      await tester.pump();
      expect(calls, 2);
      gate.complete(result());
      await tester.pumpAndSettle();
      final stale = detect!;
      await tester.pumpWidget(const SizedBox());
      stale(qrA);
      await tester.pump();
      expect(calls, 2);
      await tester.pumpWidget(scanner());
      gate = Completer<Json>();
      detect!(qrA);
      await tester.pump();
      expect(calls, 3);
      gate.complete(result());
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'offline scan stays failed, requires explicit retry and never shows successful status',
    (tester) async {
      ValueChanged<String>? detect;
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StaffQrScanner(
              onScan: (_) {
                calls++;
                return Future.error(
                  const ApiException(503, 'Backend tidak tersedia.'),
                );
              },
              previewBuilder: (onDetect) {
                detect = onDetect;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      detect!(qrA);
      await tester.pumpAndSettle();
      expect(find.textContaining('Backend tidak tersedia'), findsOneWidget);
      expect(find.byKey(const ValueKey('staff-qr-result')), findsNothing);
      detect!(qrA);
      await tester.pump();
      expect(calls, 1);
      await tester.tap(find.text('Coba pindai lagi'));
      await tester.pump();
      detect!(qrA);
      await tester.pumpAndSettle();
      expect(calls, 2);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
  for (final size in [const Size(1366, 768), const Size(375, 900)]) {
    testWidgets(
      'manual input explicit, snapshot updates only after server, result fits $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final backend = FakeBackend('PETUGAS');
        final api = QueueApi(
          config: AppConfig(
            apiBaseUrl: 'http://localhost/api/v1',
            realtime: false,
          ),
          client: MockClient(backend.handle),
        );
        await api.login('test@test.local', 'password');
        final key = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: QueueBApp(api: api),
          ),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Input Manual'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Input Manual'));
        await tester.tap(find.text('Input Manual'));
        await tester.pumpAndSettle();
        final field = find.widgetWithText(TextField, 'Payload QR (SQ1…)');
        await tester.enterText(field, 'SQ1.partial');
        await tester.pumpAndSettle();
        expect(
          backend.requests.where((r) => r.$2 == '/check-in/auto-antrean'),
          isEmpty,
        );
        final button = find.text('Proses QR & Masuk Antrean');
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(
          backend.requests.where((r) => r.$2 == '/check-in/auto-antrean'),
          isEmpty,
        );
        await tester.enterText(field, qrA);
        await tester.pumpAndSettle();
        expect(backend.status, 'DIPESAN');
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(backend.status, 'MENUNGGU');
        expect(
          backend.requests.where((r) => r.$2 == '/check-in/auto-antrean'),
          hasLength(1),
        );
        expect(backend.requests.where((r) => r.$2.endsWith('/masuk')), isEmpty);
        expect(
          find.text('Pasien Uji'),
          findsNWidgets(2),
        ); // Snapshot row + transient scan receipt.
        expect(find.text('UM-001 · MENUNGGU'), findsOneWidget);
        expect(tester.takeException(), isNull);
        final capture = Platform.environment['QUEUEB_QR_CAPTURE_DIR'];
        if (capture != null) {
          await tester.ensureVisible(find.text('QR Check-in Otomatis'));
          await tester.pumpAndSettle();
          await tester.runAsync(() async {
            final image = await tester
                .renderObject<RenderRepaintBoundary>(
                  find.byKey(const ValueKey('staff-qr-panel')),
                )
                .toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final f = File('$capture/qr-${size.width.toInt()}.png');
            await f.parent.create(recursive: true);
            await f.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.pumpWidget(const SizedBox());
        api.dispose();
      },
    );
  }
}
