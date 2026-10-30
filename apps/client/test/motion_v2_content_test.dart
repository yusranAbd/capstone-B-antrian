import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:queueb_client/src/doctor_schedule_ui.dart';
import 'package:queueb_client/src/patient_design.dart';
import 'package:queueb_client/src/queueb_content_motion.dart';
import 'package:queueb_client/src/queueb_motion.dart';

void main() {
  testWidgets(
    'only first five visible cards qualify; lazy remount never replays',
    (t) async {
      t.view.physicalSize = const Size(320, 568);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final tokens = List.generate(20, (_) => QueueBMotionOnce());
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView.builder(
              controller: scroll,
              itemCount: 20,
              itemBuilder: (_, index) => QueueBContentEntrance(
                key: ValueKey('entrance-$index'),
                once: tokens[index],
                index: index,
                child: SizedBox(height: 160, child: Text('Service $index')),
              ),
            ),
          ),
        ),
      );
      await t.pump(Duration.zero);
      await t.pump();
      expect(find.byType(Animate).evaluate().length, inInclusiveRange(1, 5));
      for (final index in [4, 5]) {
        expect(
          find.descendant(
            of: find.byKey(ValueKey('entrance-$index')),
            matching: find.byType(Animate),
          ),
          findsNothing,
        );
      }
      await t.pumpAndSettle();
      scroll.jumpTo(2800);
      await t.pumpAndSettle();
      scroll.jumpTo(0);
      await t.pumpAndSettle();
      expect(find.text('Service 0'), findsOneWidget);
      expect(find.byType(Animate), findsNothing);
      await t.pumpWidget(const SizedBox());
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'same entrance token does not restart on rebuild or preference change',
    (t) async {
      final once = QueueBMotionOnce();
      Widget scene({bool reduced = false, String text = 'First'}) =>
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData.fromView(t.view)
                  .copyWith(disableAnimations: reduced),
              child: Center(
                child: QueueBContentEntrance(
                  once: once,
                  index: 0,
                  child: Text(text),
                ),
              ),
            ),
          );
      await t.pumpWidget(scene());
      await t.pump(Duration.zero);
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      final fade = find.descendant(
        of: find.byType(QueueBContentEntrance),
        matching: find.byType(Opacity),
      );
      final before = t.widget<Opacity>(fade).opacity;
      await t.pumpWidget(scene(text: 'Updated'));
      expect(t.widget<Opacity>(fade).opacity, greaterThanOrEqualTo(before));
      await t.pumpWidget(scene(reduced: true));
      expect(find.byType(Animate), findsNothing);
      await t.pumpWidget(scene());
      expect(find.byType(Animate), findsNothing);
      expect(find.text('First'), findsOneWidget);
    },
  );
  for (final reduced in [false, true]) {
    testWidgets(
      'delayed entrance disposal and reduced semantics stay safe, reduced=$reduced',
      (t) async {
        final semantics = t.ensureSemantics();
        try {
          await t.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: MediaQueryData.fromView(t.view)
                    .copyWith(disableAnimations: reduced),
                child: Center(
                  child: QueueBContentEntrance(
                    once: QueueBMotionOnce(),
                    index: 4,
                    child: const Text('Available'),
                  ),
                ),
              ),
            ),
          );
          await t.pump(Duration.zero);
          await t.pump();
          expect(find.text('Available'), findsOneWidget);
          if (reduced) expect(find.byType(Animate), findsNothing);
          await t.pumpWidget(const SizedBox());
          await t.pump(const Duration(seconds: 1));
          expect(t.takeException(), isNull);
          expect(t.binding.hasScheduledFrame, isFalse);
        } finally {
          semantics.dispose();
        }
      },
    );
  }
  for (final width in [320.0, 360.0, 390.0, 430.0, 768.0, 1366.0]) {
    for (final reduced in [false, true]) {
      testWidgets(
        'practice date selection keeps callback/date across month at width $width reduced=$reduced',
        (t) async {
          t.view.physicalSize = Size(width, 844);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.resetPhysicalSize);
          addTearDown(t.view.resetDevicePixelRatio);
          var selected = '2026-10-31', calls = 0;
          await t.pumpWidget(
            MaterialApp(
              theme: PatientDesign.theme,
              home: MediaQuery(
                data: MediaQueryData.fromView(t.view).copyWith(
                  disableAnimations: reduced,
                  textScaler: TextScaler.linear(2),
                ),
                child: Scaffold(
                  body: StatefulBuilder(
                    builder: (context, update) => PracticeDateStrip(
                      dates: const ['2026-10-31', '2026-11-02'],
                      value: selected,
                      onChanged: (date) => update(() {
                        calls++;
                        selected = date;
                      }),
                    ),
                  ),
                ),
              ),
            ),
          );
          await t.pumpAndSettle();
          await t.tap(find.text('2/11'));
          await t.pump();
          expect(selected, '2026-11-02');
          expect(calls, 1);
          expect(
            find.byType(TweenAnimationBuilder<double>),
            reduced ? findsNothing : findsOneWidget,
          );
          await t.pumpAndSettle();
          expect(calls, 1);
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
