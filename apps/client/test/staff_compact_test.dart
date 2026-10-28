import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:queueb_client/src/api.dart';
import 'package:queueb_client/src/app.dart';
import 'package:queueb_client/src/config.dart';
import 'package:queueb_client/src/staff_v4.dart';
import 'package:queueb_client/src/staff_ui.dart';

import 'staff_v4_test.dart' show StaffV4Backend;
import 'ui_test.dart' show uid;

class CompactStaffBackend extends StaffV4Backend {
  String? activeStatus;
  @override
  Future<http.Response> handle(http.Request request) async {
    final response = await super.handle(request);
    if (request.url.path.endsWith('/jadwal-praktik')) {
      final list = rows(jsonDecode(response.body));
      final first = list.firstWhere((s) => s['loketId'] == uid);
      return reply([
        ...list,
        {
          ...first,
          'id': 'afternoon',
          'mulaiPada': '${today}T06:00:00Z',
          'selesaiPada': '${today}T09:00:00Z',
          'dokterLayanan': {
            'dokter': {
              'nama': 'dr. Sekar Larasati, Sp.PD',
              'spesialisasi': 'Penyakit Dalam',
            },
          },
        },
      ]);
    }
    if (request.url.path.endsWith('/queue/snapshot') && activeStatus != null) {
      final data = object(jsonDecode(response.body));
      data['loket'] = [
        {
          ...room,
          'tiketAktif': [
            {
              'tiketId': 'active',
              'nomorAntrean': 'UM-010',
              'namaPasien': 'Nadia Permatasari',
              'status': activeStatus,
            },
          ],
        },
      ];
      return reply(data);
    }
    return response;
  }
}

void main() {
  setUpAll(tz.initializeTimeZones);
  Future<void> launch(
    WidgetTester tester,
    CompactStaffBackend backend,
    Size size,
  ) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    final api = QueueApi(
      config: AppConfig(apiBaseUrl: 'http://localhost/api/v1', realtime: false),
      client: MockClient(backend.handle),
    );
    await api.login('fixture@test.local', 'fixture-only');
    await tester.pumpWidget(QueueBApp(api: api));
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      api.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  for (final size in [
    const Size(1280, 640), // 720px laptop with browser chrome consuming height.
    const Size(1280, 720),
    const Size(1366, 768),
    const Size(1440, 900),
    const Size(1920, 1080),
    const Size(768, 1024),
    const Size(320, 740),
    const Size(375, 812),
    const Size(414, 896),
  ]) {
    testWidgets(
      'Two doctors and both pagination controls fit without overflow $size',
      (tester) async {
        final backend = CompactStaffBackend()..paged = true;
        await launch(tester, backend, size);
        expect(find.text('dr. Sekar Larasati, Sp.PD'), findsOneWidget);
        expect(tester.takeException(), isNull);
        expect(find.byType(FloatingActionButton), findsOneWidget);
        expect(find.text('Input Manual'), findsNothing);
        expect(find.byKey(const ValueKey('staff-qr-panel')), findsNothing);
        if (size.width >= 1000) {
          final left = tester.getSize(find.byType(StaffPatientList)).width;
          final service = find.byWidgetPredicate(
            (w) => w is StaffPanel && w.title == 'Pelayanan ruang ini',
          );
          final right = tester.getSize(service).width;
          expect(right / (left + right), greaterThan(.43));
          expect(
            tester.getBottomLeft(find.text('Pindai QR')).dy,
            lessThan(size.height),
          );
          expect(find.text('Tindak lanjut: 1/2'), findsOneWidget);
        }
      },
    );
  }
  for (final status in ['DIPANGGIL', 'DILAYANI']) {
    testWidgets('Compact service actions stay visible for $status', (
      tester,
    ) async {
      await launch(
        tester,
        CompactStaffBackend()..activeStatus = status,
        const Size(1280, 720),
      );
      for (final title
          in status == 'DIPANGGIL'
              ? ['Panggil Ulang', 'Lewati', 'Mulai Pelayanan']
              : ['Selesaikan Pelayanan']) {
        final button = find.text(title);
        expect(button, findsOneWidget);
        expect(tester.getBottomLeft(button).dy, lessThan(720));
      }
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'Profile header opens account directly; logout stays in account page',
    (tester) async {
      await launch(tester, CompactStaffBackend(), const Size(1280, 720));
      expect(
        find.descendant(
          of: find.byType(StaffToolbar),
          matching: find.byType(PopupMenuButton<String>),
        ),
        findsNothing,
      );
      expect(find.byTooltip('Keluar akun'), findsNothing);
      await tester.tap(find.byTooltip('Profil petugas'));
      await tester.pumpAndSettle();
      expect(find.text('Profil Saya'), findsOneWidget);
      final logout = find.text('Keluar Akun');
      await tester.ensureVisible(logout);
      await tester.tap(logout);
      await tester.pumpAndSettle();
      expect(find.text('Masuk'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
}
