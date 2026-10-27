import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:queueb_client/src/api.dart';
import 'package:queueb_client/src/app.dart';
import 'package:queueb_client/src/config.dart';
import 'package:queueb_client/src/display_board.dart';
import 'package:queueb_client/src/mobile_ui.dart';
import 'package:queueb_client/src/widgets.dart';
import 'package:timezone/data/latest.dart' as tz;

import 'ui_test.dart' show FakeBackend;
import 'display_v3_test.dart' show monitorSnapshot;

class DesignBackend extends FakeBackend {
  DesignBackend(super.role);
  @override
  Future<http.Response> handle(http.Request r) async {
    if (r.url.path.endsWith('/portal-dokter/profil')) {
      return reply({
        'nama': 'Dokter QA',
        'spesialisasi': 'Anak',
        'poliklinik': <Object>[],
      });
    }
    if (r.url.path.contains('/portal-dokter/')) return reply(<Object>[]);
    return super.handle(r);
  }
}

void main() {
  setUpAll(tz.initializeTimeZones);
  const viewports = [
    Size(1280, 720),
    Size(1366, 768),
    Size(1440, 900),
    Size(1920, 1080),
    Size(320, 568),
    Size(360, 800),
    Size(390, 844),
    Size(412, 915),
  ];
  for (final size in viewports) {
    for (final role in ['ADMIN', 'PETUGAS', 'DOKTER', 'USER', 'DISPLAY']) {
      testWidgets('QueueB design foundation $role fits $size', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        QueueApi? api;
        if (role == 'DISPLAY') {
          await tester.pumpWidget(
            MaterialApp(
              theme: QueueBStyle.theme,
              home: Scaffold(
                body: DisplayBoard(
                  snapshot: monitorSnapshot(waiting: 30),
                  now: DateTime(2026, 10, 27),
                  status: 'Realtime terhubung',
                  onRefresh: () {},
                  onAudio: () {},
                  onConfigure: () {},
                  onFullscreen: () {},
                ),
              ),
            ),
          );
          await tester.pump();
          expect(find.byType(Scrollable), findsNothing);
          expect(
            find.byKey(const ValueKey('display-call-number')),
            findsOneWidget,
          );
        } else {
          final backend = DesignBackend(role);
          if (role == 'USER') backend.tickets.add(backend.ticket);
          api = QueueApi(
            config: AppConfig(
              apiBaseUrl: 'http://localhost/api/v1',
              realtime: false,
            ),
            client: MockClient(backend.handle),
          );
          await api.login('fixture@test.local', 'fixture-only');
          await tester.pumpWidget(QueueBApp(api: api));
          await tester.pumpAndSettle();
          expect(api.user?['peran'], role);
          expect(find.text('Masuk'), findsNothing);
          if (role == 'DOKTER') {
            expect(find.text('Dashboard Dokter'), findsOneWidget);
          }
          if (role == 'PETUGAS') {
            expect(find.text('Pelayanan ruang ini'), findsOneWidget);
          }
          if (role == 'USER') {
            await tester.tap(find.text('Tiket Saya').last);
            await tester.pumpAndSettle();
            expect(find.text('UM-001'), findsOneWidget);
          }
        }
        expect(tester.takeException(), isNull);
        expect(
          tester.getSize(find.byType(Scaffold).first).width,
          lessThanOrEqualTo(size.width),
        );
        await tester.pumpWidget(const SizedBox());
        api?.dispose();
        await tester.pump(const Duration(seconds: 30));
        expect(tester.takeException(), isNull);
      });
    }
  }
  for (final scale in [1.0, 1.5, 2.0]) {
    testWidgets(
      'Shared section wraps actions and supports text scale $scale at 320px',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var pressed = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: QueueBStyle.theme,
            home: MediaQuery(
              data: MediaQueryData(
                size: const Size(320, 568),
                textScaler: TextScaler.linear(scale),
              ),
              child: Scaffold(
                body: SingleChildScrollView(
                  child: Section(
                    title: 'Tiket saya dan layanan',
                    subtitle: 'Informasi tiket untuk kunjungan berikutnya.',
                    action: OutlinedButton(
                      onPressed: () => pressed++,
                      child: const Text('Muat ulang'),
                    ),
                    child: const EmptyState(
                      text: 'Belum ada kunjungan yang sesuai.',
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('Muat ulang'));
        await tester.tap(find.text('Muat ulang'));
        await tester.pumpAndSettle();
        expect(pressed, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
