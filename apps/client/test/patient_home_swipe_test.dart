import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:queueb_client/src/api.dart';
import 'package:queueb_client/src/app.dart';
import 'package:queueb_client/src/config.dart';
import 'package:queueb_client/src/patient_home.dart';

import 'patient_home_v3_test.dart' show HomeBackend;

void main() {
  setUpAll(tz.initializeTimeZones);
  Future<QueueApi> launch(
    WidgetTester t,
    Size size, {
    bool many = false,
  }) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final b = HomeBackend()
      ..manyHomeDoctors = many
      ..manyClinics = true;
    final api =
        QueueApi(
            config: AppConfig(
              apiBaseUrl: 'http://localhost/api/v1',
              realtime: false,
            ),
            client: MockClient(b.handle),
          )
          ..accessToken = 'test'
          ..user = b.user;
    addTearDown(api.dispose);
    await t.pumpWidget(QueueBApp(api: api));
    await t.pumpAndSettle();
    return api;
  }

  for (final size in [
    const Size(320, 568),
    const Size(360, 800),
    const Size(375, 812),
    const Size(390, 844),
    const Size(412, 915),
  ]) {
    testWidgets('native home swipe and taps stay synchronized at $size', (
      t,
    ) async {
      await launch(t, size);
      final pages = find.byType(TabBarView);
      TabController controller() =>
          t.widget<TabBar>(find.byType(TabBar)).controller!;
      expect(controller().index, 0);
      // V8's greeting/compact visit can fill the short 320x568 viewport.
      // Reveal the content with the existing scroll owner before swiping it.
      await t.ensureVisible(pages);
      await t.pumpAndSettle();
      await t.drag(pages, Offset(-size.width * .8, 0));
      await t.pumpAndSettle();
      expect(controller().index, 1);
      expect(find.byType(PatientHomeDoctor), findsOneWidget);
      final card = t.widget<PatientHomeDoctor>(find.byType(PatientHomeDoctor));
      expect(card.preview.doctor['nama'], 'dr. Sindi QA');
      expect(card.preview.session?['id'], 'session-home');
      expect(find.text('Detail Dokter'), findsOneWidget);
      // Swipe on the doctor content, away from the independently scrollable
      // clinic chips (whose horizontal gesture deliberately stays local).
      await t.ensureVisible(find.byType(PatientHomeDoctor));
      await t.pumpAndSettle();
      await t.drag(find.byType(PatientHomeDoctor), Offset(size.width * .8, 0));
      await t.pumpAndSettle();
      expect(controller().index, 0);
      await t.tap(find.byKey(const ValueKey('home-mode-appointment')));
      await t.pumpAndSettle();
      expect(controller().index, 1);
      final filters = find.byType(SingleChildScrollView).first;
      await t.ensureVisible(filters);
      await t.pumpAndSettle();
      await t.drag(filters, const Offset(-180, 0));
      await t.pumpAndSettle();
      expect(
        controller().index,
        1,
        reason: 'Dragging clinic chips must not change service tab',
      );
      await t.tap(find.widgetWithText(NavigationDestination, 'Riwayat'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(NavigationDestination, 'Beranda'));
      await t.pumpAndSettle();
      expect(
        controller().index,
        1,
        reason: 'Home selection survives the bottom navigation',
      );
      expect(t.takeException(), isNull);
    });
  }

  testWidgets(
    'nested list scroll keeps auto-hide reversible and disposes the tab controller',
    (t) async {
      await launch(t, const Size(390, 844), many: true);
      await t.drag(find.byType(TabBarView), const Offset(-320, 0));
      await t.pumpAndSettle();
      await t.drag(find.byType(TabBarView), const Offset(0, -550));
      await t.pumpAndSettle();
      final bar = find.byKey(const ValueKey('patient-chrome-bottom'));
      expect(t.getSize(bar).height, 0);
      await t.drag(find.byType(TabBarView), const Offset(0, 100));
      await t.pumpAndSettle();
      expect(t.getSize(bar).height, greaterThanOrEqualTo(60));
      expect(t.widget<TabBar>(find.byType(TabBar)).controller!.index, 1);
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'home mode switch restores chrome with the same native controller',
    (t) async {
      await launch(t, const Size(390, 844), many: true);
      await t.drag(find.byType(TabBarView), const Offset(-320, 0));
      await t.pumpAndSettle();
      final controller = t.widget<TabBar>(find.byType(TabBar)).controller;
      await t.drag(find.byType(TabBarView), const Offset(0, -550));
      await t.pumpAndSettle();
      final bottom = find.byKey(const ValueKey('patient-chrome-bottom'));
      expect(t.getSize(bottom).height, 0);
      await t.tap(find.byKey(const ValueKey('home-mode-walkIn')));
      await t.pumpAndSettle();
      expect(
        t.widget<TabBar>(find.byType(TabBar)).controller,
        same(controller),
      );
      expect(controller!.index, 0);
      expect(t.getSize(bottom).height, greaterThan(0));
      expect(
        t.getSize(find.byKey(const ValueKey('patient-chrome-top'))).height,
        greaterThan(0),
      );
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'pinned tabs do not cover the filter strip at the start of the inner list',
    (t) async {
      await launch(t, const Size(390, 844));
      await t.drag(find.byType(TabBarView), const Offset(-320, 0));
      await t.pumpAndSettle();
      final outer = t
          .state<NestedScrollViewState>(find.byType(NestedScrollView))
          .outerController;
      outer.jumpTo(outer.position.maxScrollExtent);
      await t.pumpAndSettle();
      expect(
        t.getTopLeft(find.byType(SingleChildScrollView).first).dy,
        greaterThanOrEqualTo(t.getBottomLeft(find.byType(TabBar)).dy),
      );
      expect(t.takeException(), isNull);
    },
  );
}
