import 'admin_action_helpers.dart';

import 'package:queueb_client/src/admin_ui.dart';

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:queueb_client/src/admin_display.dart';
import 'package:queueb_client/src/display.dart';
import 'package:queueb_client/src/api.dart';
import 'package:queueb_client/src/config.dart';

void main() {
  setUpAll(tz.initializeTimeZones);
  const clinicId = '00000000-0000-4000-8000-000000000001';
  final clinic = {'id': clinicId, 'nama': 'Poliklinik Mata', 'aktif': true};
  final device = {
    'id': 'device',
    'nama': 'TV Mata',
    'aktif': true,
    'layananId': clinicId,
    'layanan': clinic,
  };
  http.Response reply(Object body, [int code = 200]) =>
      http.Response(jsonEncode(body), code);
  QueueApi apiFor(Future<http.Response> Function(http.Request) handler) =>
      QueueApi(
        config: AppConfig(
          apiBaseUrl: 'http://localhost/api/v1',
          realtime: false,
        ),
        client: MockClient(handler),
      );
  Future<void> cleanup(WidgetTester tester, QueueApi api) async {
    await tester.pumpWidget(const SizedBox());
    api.dispose();
  }

  testWidgets(
    'activation form is primary, no UUID or bearer input, validates 12 digits',
    (tester) async {
      var pairing = 0;
      final api = apiFor((r) async {
        if (r.method == 'POST') pairing++;
        return reply({}, 401);
      });
      await tester.pumpWidget(
        MaterialApp(
          home: DisplayPage(api: api, onExit: () {}),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Aktivasi Public Display'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'ID layanan'), findsNothing);
      await tester.ensureVisible(find.text('Hubungkan Perangkat'));
      await tester.tap(find.text('Hubungkan Perangkat'));
      await tester.pumpAndSettle();
      expect(find.text('Masukkan 12 digit kode aktivasi.'), findsOneWidget);
      expect(pairing, 0);
      await cleanup(tester, api);
    },
  );
  testWidgets(
    'pairing uses code body only then opens snapshot with no token in Dart',
    (tester) async {
      final calls = <http.Request>[];
      var paired = false;
      final api = apiFor((r) async {
        calls.add(r);
        if (r.url.path.endsWith('/sesi')) {
          return paired ? reply(device) : reply({}, 401);
        }
        if (r.url.path.endsWith('/pairing')) {
          paired = true;
          return reply(device);
        }
        if (r.url.path.endsWith('/snapshot')) {
          return reply({
            'versiSkema': 1,
            'layanan': clinic,
            'totalMenunggu': 0,
            'loket': [],
          });
        }
        return reply({'ok': true});
      });
      await tester.pumpWidget(
        MaterialApp(
          home: DisplayPage(api: api, onExit: () {}),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Kode Aktivasi'),
        '123456789012',
      );
      await tester.ensureVisible(find.text('Hubungkan Perangkat'));
      await tester.tap(find.text('Hubungkan Perangkat'));
      await tester.pumpAndSettle();
      expect(find.text('Poliklinik Mata'), findsOneWidget);
      expect(jsonDecode(calls.firstWhere((r) => r.method == 'POST').body), {
        'kode': '123456789012',
      });
      expect(
        calls.every(
          (r) =>
              !r.url.hasQuery &&
              !r.headers.containsKey('x-display-token') &&
              !r.headers.containsKey('Authorization'),
        ),
        isTrue,
      );
      await cleanup(tester, api);
    },
  );
  testWidgets('stored device restores silently without entering code', (
    tester,
  ) async {
    final api = apiFor(
      (r) async => reply(
        r.url.path.endsWith('/sesi')
            ? device
            : {
                'versiSkema': 1,
                'layanan': clinic,
                'totalMenunggu': 0,
                'loket': [],
              },
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: DisplayPage(api: api, onExit: () {}),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Poliklinik Mata'), findsOneWidget);
    expect(find.text('Aktivasi Public Display'), findsNothing);
    await cleanup(tester, api);
  });
  testWidgets('expired/used pairing error stays visible and is not retried', (
    tester,
  ) async {
    var posts = 0;
    final api = apiFor((r) async {
      if (r.method == 'POST') {
        posts++;
        return reply({'message': 'Kode aktivasi sudah digunakan'}, 410);
      }
      return reply({}, 401);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: DisplayPage(api: api, onExit: () {}),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Kode Aktivasi'),
      '123456789012',
    );
    await tester.ensureVisible(find.text('Hubungkan Perangkat'));
    await tester.tap(find.text('Hubungkan Perangkat'));
    await tester.pumpAndSettle();
    expect(find.text('Kode aktivasi sudah digunakan'), findsOneWidget);
    expect(posts, 1);
    await cleanup(tester, api);
  });
  testWidgets(
    'forget revokes server credential before returning to activation',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      var forgotten = false;
      final api = apiFor((r) async {
        if (r.url.path.endsWith('/sesi')) return reply(device);
        if (r.url.path.endsWith('/putuskan')) {
          forgotten = true;
          return reply({'ok': true});
        }
        return reply({
          'versiSkema': 1,
          'layanan': clinic,
          'totalMenunggu': 0,
          'loket': [],
        });
      });
      await tester.pumpWidget(
        MaterialApp(
          home: DisplayPage(api: api, onExit: () {}),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Ganti perangkat'));
      await tester.tap(find.text('Ganti perangkat'));
      await tester.pumpAndSettle();
      expect(forgotten, isTrue);
      expect(find.text('Aktivasi Public Display'), findsOneWidget);
      await cleanup(tester, api);
    },
  );
  testWidgets(
    'admin compact device table preserves activation rotation and revocation',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final posts = <String>[];
      var active = true;
      final api = apiFor((r) async {
        if (r.method == 'POST') {
          posts.add(r.url.path);
          if (r.url.path.endsWith('/aktivasi')) {
            return reply({
              'kode': '123456',
              'berlakuHingga': '2026-10-23T08:05:00Z',
            });
          }
          active = false;
          return reply({'ok': true});
        }
        return reply(
          r.url.path.endsWith('/layanan')
              ? [clinic]
              : [
                  {...device, 'aktif': active},
                ],
        );
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: AdminStyle.theme,
          home: Scaffold(body: AdminDisplayPage(api: api)),
        ),
      );
      await tester.pumpAndSettle();
      await adminAction(tester, 'Kode aktivasi / rotasi');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lanjutkan'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Kode aktivasi sekali pakai'), findsOneWidget);
      await tester.tap(find.text('Selesai'));
      await tester.pumpAndSettle();
      await adminAction(tester, 'Nonaktifkan');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lanjutkan'));
      await tester.pumpAndSettle();
      expect(posts.length, 2);
      expect(posts[0], endsWith('/aktivasi'));
      expect(posts[1], endsWith('/nonaktifkan'));
      await tester.tap(find.byType(AdminRowActions));
      await tester.pumpAndSettle();
      expect(find.text('Reaktivasi'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await cleanup(tester, api);
    },
  );
  for (final width in [375.0, 1440.0]) {
    testWidgets(
      'admin searches compact device table without credentials at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        final api = apiFor(
          (r) async =>
              reply(r.url.path.endsWith('/layanan') ? [clinic] : [device]),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: AdminDisplayPage(api: api)),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('TV Mata'), findsOneWidget);
        expect(find.text(clinicId), findsNothing);
        await tester.enterText(
          find.widgetWithText(TextField, 'Cari perangkat atau poliklinik'),
          'Tidak ada',
        );
        await tester.pumpAndSettle();
        expect(find.text('TV Mata'), findsNothing);
        expect(tester.takeException(), isNull);
        await cleanup(tester, api);
      },
    );
  }
}
