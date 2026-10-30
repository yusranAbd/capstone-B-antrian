import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:queueb_client/src/patient_scroll_shell.dart';

void main() {
  Future<void> launch(
    WidgetTester t, {
    bool accessible = false,
    bool reduced = false,
    int count = 40,
    Object pageKey = 0,
    VoidCallback? onNavigation,
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
            pageKey: pageKey,
            header: AppBar(title: const Text('Header')),
            bottomNavigationBar: SizedBox(
              height: 60,
              child: TextButton(
                onPressed: onNavigation,
                child: const Text('Navigation'),
              ),
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
  final top = find.byKey(const ValueKey('patient-chrome-top'));
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

  testWidgets(
    'Both bars release space and input, then become tappable after reverse scroll',
    (t) async {
      var taps = 0;
      final semantics = t.ensureSemantics();
      await launch(t, onNavigation: () => taps++);
      final topHeight = t.getSize(top).height;
      final initialBodyHeight = t.getSize(vertical).height;
      await t.drag(vertical, const Offset(0, -180));
      await t.pumpAndSettle();
      expect(t.getSize(top).height, 0);
      expect(t.getSize(bottom).height, 0);
      expect(
        t.getSize(vertical).height,
        closeTo(initialBodyHeight + topHeight + 60, .01),
      );
      expect(find.text('Navigation').hitTestable(), findsNothing);
      // The retained widget still has a label, but is excluded from the tree.
      expect(
        t
            .widget<ExcludeSemantics>(
              find
                  .ancestor(of: bottom, matching: find.byType(ExcludeSemantics))
                  .first,
            )
            .excluding,
        isTrue,
      );
      final excludes = find.ancestor(
        of: bottom,
        matching: find.byType(IgnorePointer),
      );
      expect(t.widget<IgnorePointer>(excludes.first).ignoring, isTrue);
      await t.drag(vertical, const Offset(0, 80));
      await t.pumpAndSettle();
      expect(t.getSize(top).height, topHeight);
      expect(t.getSize(bottom).height, 60);
      await t.tap(find.text('Navigation'));
      expect(taps, 1);
      semantics.dispose();
    },
  );

  testWidgets(
    '1–2 pixel input never flickers and returning to top restores chrome',
    (t) async {
      await launch(t);
      final position = t.state<ScrollableState>(vertical).position;
      position.jumpTo(100);
      await t.pumpAndSettle();
      final gesture = await t.startGesture(t.getCenter(vertical));
      // Cross the platform touch slop, then reverse by only two pixels.
      await gesture.moveBy(const Offset(0, -40));
      await t.pumpAndSettle();
      expect(t.getSize(bottom).height, 0);
      await gesture.moveBy(const Offset(0, 2));
      await t.pumpAndSettle();
      expect(t.getSize(bottom).height, 0);
      await gesture.up();
      position.jumpTo(0);
      await t.pumpAndSettle();
      expect(t.getSize(top).height, greaterThan(0));
      expect(t.getSize(bottom).height, 60);
    },
  );

  testWidgets('A page change restores reduced-motion chrome immediately', (
    t,
  ) async {
    await launch(t, reduced: true);
    await t.drag(vertical, const Offset(0, -160));
    await t.pump();
    expect(t.getSize(top).height, 0);
    await launch(t, reduced: true, pageKey: 1);
    expect(t.getSize(top).height, greaterThan(0));
    expect(t.getSize(bottom).height, 60);
    expect(t.binding.transientCallbackCount, 0);
  });
}
