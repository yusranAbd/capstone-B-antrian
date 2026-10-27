import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:queueb_client/src/patient_scroll_shell.dart';

void main() {
  Future<void> launch(
    WidgetTester t, {
    bool accessible = false,
    bool reduced = false,
    int count = 40,
  }) async {
    t.view.physicalSize = const Size(320, 568);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            accessibleNavigation: accessible,
            disableAnimations: reduced,
          ),
          child: PatientScrollShell(
            pageKey: 0,
            header: AppBar(title: const Text('Header')),
            bottomNavigationBar: const SizedBox(
              height: 60,
              child: Text('Navigation'),
            ),
            body: ListView(
              children: [
                SizedBox(
                  height: 50,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: const [SizedBox(width: 1000)],
                  ),
                ),
                for (var i = 0; i < count; i++)
                  SizedBox(height: 48, child: Text('Item $i')),
              ],
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  final bottom = find.byKey(const ValueKey('patient-chrome-bottom'));
  final vertical = find.byWidgetPredicate(
    (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
  );
  testWidgets(
    'Horizontal and programmatic scroll do not hide controls; vertical drag releases space smoothly',
    (t) async {
      await launch(t);
      await t.drag(
        find.byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.right,
        ),
        const Offset(-100, 0),
      );
      await t.pumpAndSettle();
      expect(t.getSize(bottom).height, 60);
      t.state<ScrollableState>(vertical).position.jumpTo(100);
      await t.pumpAndSettle();
      expect(t.getSize(bottom).height, 60);
      await t.drag(vertical, const Offset(0, -100));
      await t.pump(); // Start the first animation frame before sampling its midpoint.
      await t.pump(const Duration(milliseconds: 60));
      expect(t.getSize(bottom).height, inExclusiveRange(0, 60));
      await t.pumpAndSettle();
      expect(t.getSize(bottom).height, 0);
      await t.drag(vertical, const Offset(0, 80));
      await t.pumpAndSettle();
      expect(t.getSize(bottom).height, 60);
      await t.pumpWidget(const SizedBox());
      await t.pump();
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('A page that fits after chrome collapses restores navigation', (
    t,
  ) async {
    await launch(t, count: 10);
    await t.drag(vertical, const Offset(0, -180));
    await t.pumpAndSettle();
    expect(t.getSize(bottom).height, 60);
    expect(t.takeException(), isNull);
  });
  testWidgets('Accessible navigation keeps chrome available', (t) async {
    await launch(t);
    await t.drag(vertical, const Offset(0, -120));
    await t.pumpAndSettle();
    expect(t.getSize(bottom).height, 0);
    await launch(t, accessible: true);
    await t.drag(vertical, const Offset(0, -120));
    await t.pumpAndSettle();
    expect(t.getSize(bottom).height, 60);
  });
  testWidgets('Reduced motion hides and reveals without animation', (t) async {
    await launch(t, reduced: true);
    await t.drag(vertical, const Offset(0, -120));
    await t.pump();
    expect(t.getSize(bottom).height, 0);
    await t.drag(vertical, const Offset(0, 80));
    await t.pump();
    expect(t.getSize(bottom).height, 60);
    expect(t.takeException(), isNull);
  });
}
