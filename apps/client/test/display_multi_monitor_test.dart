import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:queueb_client/src/api.dart';
import 'package:queueb_client/src/config.dart';
import 'package:queueb_client/src/display.dart';
import 'package:queueb_client/src/display_selection.dart';
import 'package:queueb_client/src/mobile_ui.dart';

void main() {
  final capture = Platform.environment['QUEUEB_MULTI_CAPTURE_DIR'];
  setUpAll(() async {
    tz.initializeTimeZones();
    final fontRoot = Platform.environment['QUEUEB_FONT_DIR'];
    if (capture != null && fontRoot != null) {
      final fonts = FontLoader('Roboto');
      for (final name in ['regular', 'medium', 'bold', 'black']) {
        fonts.addFont(
          File('$fontRoot/roboto-$name.ttf')
              .readAsBytes()
              .then((v) => ByteData.sublistView(v)),
        );
      }
      await fonts.load();
      final icons = FontLoader('MaterialIcons');
      icons.addFont(
        File('$fontRoot/materialicons-regular.otf')
            .readAsBytes()
            .then((v) => ByteData.sublistView(v)),
      );
      await icons.load();
    }
  });
  const a = '00000000-0000-4000-8000-000000000001';
  const b = '00000000-0000-4000-8000-000000000002';
  http.Response reply(Object v) => http.Response(jsonEncode(v), 200);
  testWidgets(
    'new tab never adopts ambient cookie; pairing persists only its selector',
    (tester) async {
      final requests = <http.Request>[];
      final selection = MemoryDisplaySelection();
      final api = QueueApi(
        config: AppConfig(
          apiBaseUrl: 'http://localhost/api/v1',
          realtime: false,
        ),
        client: MockClient((r) async {
          requests.add(r);
          if (r.url.path.endsWith('/pairing') || r.url.path.endsWith('/sesi')) {
            return reply({'id': a, 'layananId': a});
          }
          return reply({
            'versiSkema': 1,
            'layanan': {'nama': 'Anak QA'},
            'totalMenunggu': 0,
            'loket': [],
          });
        }),
      );
      Future<void> render(Key key) => tester.pumpWidget(
        MaterialApp(
          home: DisplayPage(
            key: key,
            api: api,
            selection: selection,
            onExit: () {},
          ),
        ),
      );
      await render(const ValueKey('first'));
      await tester.pumpAndSettle();
      expect(requests, isEmpty);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Kode Aktivasi'),
        '123456789012',
      );
      await tester.ensureVisible(find.text('Hubungkan Perangkat'));
      await tester.tap(find.text('Hubungkan Perangkat'));
      await tester.pumpAndSettle();
      expect(jsonDecode(requests.first.body), {
        'kode': '123456789012',
        'isolasiSesi': true,
      });
      expect(selection.value, a);
      for (final r in requests.skip(1)) {
        expect(r.headers['x-display-device-id'], a);
        expect(r.headers.containsKey('x-display-token'), false);
        expect(r.headers.containsKey('Authorization'), false);
      }
      await render(const ValueKey('reload'));
      await tester.pumpAndSettle();
      expect(find.text('Anak QA'), findsOneWidget);
      expect(requests.last.headers['x-display-device-id'], a);
      await tester.pumpWidget(const SizedBox());
      api.dispose();
    },
  );

  testWidgets(
    'two page instances isolate selectors, logout, audio, polling and disposal',
    (tester) async {
      tester.view.physicalSize = const Size(2560, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('flutter_tts'),
        (call) async => call.method == 'isLanguageAvailable' ? true : 1,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('flutter_tts'),
          null,
        ),
      );
      final selectionA = MemoryDisplaySelection(value: a),
          selectionB = MemoryDisplaySelection(value: b);
      final requests = <http.Request>[];
      final api = QueueApi(
        config: AppConfig(
          apiBaseUrl: 'http://localhost/api/v1',
          realtime: false,
        ),
        client: MockClient((r) async {
          requests.add(r);
          final id = r.headers['x-display-device-id'];
          expect([a, b], contains(id));
          if (r.url.path.endsWith('/sesi')) {
            return reply({'id': id, 'layananId': id});
          }
          if (r.url.path.endsWith('/putuskan')) return reply({'ok': true});
          return reply({
            'versiSkema': 1,
            'layanan': {'nama': id == a ? 'Anak QA' : 'Bedah QA'},
            'totalMenunggu': 0,
            'loket': [],
          });
        }),
      );
      final captureKey = GlobalKey();
      final left = find.byKey(const ValueKey('tab-a')),
          right = find.byKey(const ValueKey('tab-b'));
      await tester.pumpWidget(
        MaterialApp(
          theme: QueueBStyle.theme,
          home: RepaintBoundary(
            key: captureKey,
            child: Row(
              children: [
                Expanded(
                  child: DisplayPage(
                    key: const ValueKey('tab-a'),
                    api: api,
                    selection: selectionA,
                    onExit: () {},
                  ),
                ),
                Expanded(
                  child: DisplayPage(
                    key: const ValueKey('tab-b'),
                    api: api,
                    selection: selectionB,
                    onExit: () {},
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Anak QA'), findsOneWidget);
      expect(find.text('Bedah QA'), findsOneWidget);
      await tester.tap(
        find.descendant(of: left, matching: find.text('Aktifkan suara')),
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: left, matching: find.text('Matikan suara')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: right, matching: find.text('Aktifkan suara')),
        findsOneWidget,
      );
      if (capture != null) {
        await tester.runAsync(() async {
          final image =
              await (captureKey.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('$capture/after-widget-two-monitors.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.tap(
        find.descendant(of: left, matching: find.text('Ganti perangkat')),
      );
      await tester.pumpAndSettle();
      expect(selectionA.value, isNull);
      expect(selectionB.value, b);
      expect(
        requests
            .lastWhere((r) => r.method == 'POST')
            .headers['x-display-device-id'],
        a,
      );
      expect(find.text('Bedah QA'), findsOneWidget);
      final count = requests.length;
      await tester.pump(const Duration(seconds: 16));
      await tester.pumpAndSettle();
      expect(
        requests
            .skip(count)
            .every((r) => r.headers['x-display-device-id'] == b),
        true,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 20));
      expect(tester.takeException(), isNull);
      api.dispose();
    },
  );
}
