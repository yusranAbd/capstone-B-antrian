import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:queueb_client/src/admin.dart';
import 'package:queueb_client/src/admin_delete.dart';
import 'package:queueb_client/src/admin_display.dart';
import 'package:queueb_client/src/admin_ui.dart';
import 'package:queueb_client/src/api.dart';
import 'package:queueb_client/src/config.dart';

void main() {
  setUpAll(tz.initializeTimeZones);
  QueueApi apiFor(Future<http.Response> Function(http.Request) handler) =>
      QueueApi(
        config: AppConfig(
          apiBaseUrl: 'http://localhost/api/v1',
          realtime: false,
        ),
        client: MockClient(handler),
      );
  http.Response reply(Object data, [int status = 200]) => http.Response(
    jsonEncode(data),
    status,
    headers: {'content-type': 'application/json'},
  );
  Future<void> openDialog(
    WidgetTester tester,
    QueueApi api,
    String path,
    Json row,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AdminStyle.theme,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showAdminDelete(context, api, path, row),
              child: const Text('Buka'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Buka'));
    await tester.pumpAndSettle();
  }

  for (final path in ['/layanan', '/dokter']) {
    testWidgets(
      '$path requires exact code and permits cancel without a request',
      (tester) async {
        var requests = 0;
        final api = apiFor((r) async {
          requests++;
          return reply({});
        });
        addTearDown(api.dispose);
        await openDialog(tester, api, path, {
          'id': 'unused',
          'kode': 'QA01',
          'nama': 'Data QA',
          'aktif': true,
        });
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Hapus Permanen'),
              )
              .onPressed,
          isNull,
        );
        await tester.enterText(find.byType(TextField), 'wrong');
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Hapus Permanen'),
              )
              .onPressed,
          isNull,
        );
        await tester.enterText(find.byType(TextField), 'QA01');
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Hapus Permanen'),
              )
              .onPressed,
          isNotNull,
        );
        await tester.tap(find.text('Batal'));
        await tester.pumpAndSettle();
        expect(requests, 0);
      },
    );
  }
  testWidgets(
    'backend relation conflict stays visible and offers Nonaktifkan',
    (tester) async {
      final api = apiFor((r) async {
        expect(r.method, 'DELETE');
        expect(r.url.path, '/api/v1/loket/room/permanen');
        return reply({
          'message': 'Ruang masih memiliki jadwal. Gunakan Nonaktifkan.',
        }, 409);
      });
      addTearDown(api.dispose);
      await openDialog(tester, api, '/loket', {
        'id': 'room',
        'nama': 'Ruang QA',
        'aktif': true,
      });
      await tester.tap(find.text('Hapus Permanen'));
      await tester.pumpAndSettle();
      expect(
        find.text('Ruang masih memiliki jadwal. Gunakan Nonaktifkan.'),
        findsOneWidget,
      );
      expect(find.text('Gunakan Nonaktifkan'), findsOneWidget);
      expect(find.text('Hapus Data?'), findsOneWidget);
    },
  );
  testWidgets('successful delete reloads rows while retaining active search', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final data = <Json>[
      {'id': 'bad', 'nama': 'Salah input', 'kode': 'BAD', 'aktif': true},
      {'id': 'good', 'nama': 'Benar', 'kode': 'OK', 'aktif': true},
    ];
    var deletions = 0;
    final api = apiFor((r) async {
      if (r.method == 'DELETE') {
        expect(r.url.path, '/api/v1/layanan/bad/permanen');
        data.removeWhere((x) => x['id'] == 'bad');
        deletions++;
        return reply({'dihapus': true});
      }
      return reply(r.url.path.endsWith('/layanan') ? data : []);
    });
    addTearDown(api.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AdminStyle.theme,
        home: Scaffold(body: AdminPage(api: api, initialSection: 0)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Cari nama atau kode'),
      'Salah',
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Hapus'));
    await tester.tap(find.byTooltip('Hapus'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Konfirmasi kode/nama'),
      'BAD',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hapus Permanen'));
    await tester.pumpAndSettle();
    expect(deletions, 1);
    expect(find.text('Data berhasil dihapus permanen.'), findsOneWidget);
    expect(
      tester
          .widget<EditableText>(
            find.descendant(
              of: find.widgetWithText(TextField, 'Cari nama atau kode'),
              matching: find.byType(EditableText),
            ),
          )
          .controller
          .text,
      'Salah',
    );
    expect(find.text('Benar'), findsNothing);
    expect(find.text('0 dari 1 data'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'display deletion refreshes filtered table without exposing credentials',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final devices = <Json>[
        {
          'id': 'tv',
          'nama': 'TV QA',
          'aktif': false,
          'layananId': 'clinic',
          'layanan': {'id': 'clinic', 'nama': 'Poli QA', 'aktif': true},
        },
      ];
      final api = apiFor((r) async {
        if (r.method == 'DELETE') {
          expect(r.url.path, '/api/v1/perangkat-display/tv/permanen');
          devices.clear();
          return reply({'dihapus': true});
        }
        return reply(
          r.url.path.endsWith('/layanan')
              ? [
                  {'id': 'clinic', 'nama': 'Poli QA', 'aktif': true},
                ]
              : devices,
        );
      });
      addTearDown(api.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AdminStyle.theme,
          home: Scaffold(body: AdminDisplayPage(api: api)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Cari perangkat atau poliklinik'),
        'TV QA',
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byTooltip('Hapus'));
      await tester.tap(find.byTooltip('Hapus'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hapus Permanen'));
      await tester.pumpAndSettle();
      expect(find.text('Perangkat berhasil dihapus permanen.'), findsOneWidget);
      expect(devices, isEmpty);
      expect(find.text('TV QA'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
