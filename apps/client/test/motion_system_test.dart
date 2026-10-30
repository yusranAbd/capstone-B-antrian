import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:queueb_client/src/admin_schedules.dart';
import 'package:queueb_client/src/mobile_ui.dart';
import 'package:queueb_client/src/queueb_motion.dart';

void main() {
  Widget feedback({
    bool confirmed = false,
    bool reduced = false,
    bool active = true,
  }) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduced),
      child: Scaffold(
        body: TickerMode(
          enabled: active,
          child: QueueBConfirmedFeedback(
            confirmed: confirmed,
            child: confirmed
                ? const AdminNotice('Data disimpan.')
                : const SizedBox.shrink(),
          ),
        ),
      ),
    ),
  );
  test(
    'motion tokens share V2 timing through the patient compatibility API',
    () {
      expect(QueueBMotion.instant, Duration.zero);
      expect(QueueBMotion.fast.inMilliseconds, 160);
      expect(QueueBMotion.standard.inMilliseconds, 260);
      expect(QueueBMotion.emphasis.inMilliseconds, 260);
      expect(QueueBMotion.minimumOpacity, .88);
      expect(QueueBMotion.verticalOffset, 10);
      expect(QueueBMotion.curve, Curves.easeOutCubic);
    },
  );
  testWidgets('initial confirmed hydration and remount never animate', (
    tester,
  ) async {
    await tester.pumpWidget(feedback(confirmed: true));
    expect(find.byType(Animate), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(feedback(confirmed: true));
    expect(find.byType(Animate), findsNothing);
    expect(find.text('Data disimpan.'), findsOneWidget);
  });
  for (final reduced in [false, true]) {
    testWidgets('only a confirmed edge animates once, reduced=$reduced', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(feedback(reduced: reduced));
        expect(find.text('Data disimpan.'), findsNothing);
        await tester.pumpWidget(feedback(confirmed: true, reduced: reduced));
        await tester.pump(Duration.zero);
        await tester.pump();
        expect(find.byType(Animate), reduced ? findsNothing : findsOneWidget);
        expect(find.bySemanticsLabel('Data disimpan.'), findsOneWidget);
        await tester.pump(
          QueueBMotion.component + const Duration(milliseconds: 10),
        );
        await tester.pumpWidget(feedback(confirmed: true, reduced: reduced));
        if (!reduced) {
          final opacity = tester
              .widget<FadeTransition>(
                find.descendant(
                  of: find.byType(QueueBMicroEntrance),
                  matching: find.byType(FadeTransition),
                ),
              )
              .opacity
              .value;
          expect(opacity, 1);
        }
        await tester.pump(const Duration(seconds: 1));
        expect(tester.binding.hasScheduledFrame, isFalse);
        await tester.pumpWidget(const SizedBox());
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    });
  }
  testWidgets('offstage arrival and return remain static', (tester) async {
    await tester.pumpWidget(feedback(active: false));
    await tester.pumpWidget(feedback(confirmed: true, active: false));
    await tester.pumpWidget(feedback(confirmed: true));
    expect(find.byType(Animate), findsNothing);
  });
  testWidgets('a separate confirmed action may animate again', (tester) async {
    await tester.pumpWidget(feedback());
    await tester.pumpWidget(feedback(confirmed: true));
    await tester.pump(Duration.zero);
    await tester.pumpAndSettle();
    await tester.pumpWidget(feedback());
    await tester.pumpWidget(feedback(confirmed: true));
    await tester.pump(Duration.zero);
    await tester.pump();
    expect(
      tester
          .widget<FadeTransition>(
            find.descendant(
              of: find.byType(QueueBMicroEntrance),
              matching: find.byType(FadeTransition),
            ),
          )
          .opacity
          .value,
      closeTo(.88, .001),
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 250));
    expect(tester.takeException(), isNull);
  });
  testWidgets('instant token renders without an Animate or controller', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: QueueBMicroEntrance(
          once: QueueBMotionOnce(),
          effectDuration: QueueBMotion.instant,
          child: const Text('Langsung tersedia'),
        ),
      ),
    );
    expect(find.byType(Animate), findsNothing);
    expect(find.text('Langsung tersedia'), findsOneWidget);
  });
  for (final size in [
    const Size(320, 568),
    const Size(360, 800),
    const Size(390, 844),
    const Size(412, 915),
    const Size(1280, 720),
    const Size(1366, 768),
    const Size(1440, 900),
    const Size(1920, 1080),
  ]) {
    for (final scale in [1.0, 1.5]) {
      testWidgets(
        'operational notices retain layout and focus at $size scale=$scale',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          final input = TextEditingController(), focus = FocusNode();
          addTearDown(() {
            input.dispose();
            focus.dispose();
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });
          await tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: Scaffold(
                  body: SingleChildScrollView(
                    child: Column(
                      children: [
                        QueueBMicroEntrance(
                          once: QueueBMotionOnce(),
                          child: const AdminNotice(
                            'Data disimpan. Konfigurasi telah diperbarui.',
                          ),
                        ),
                        QueueBMicroEntrance(
                          once: QueueBMotionOnce(),
                          child: const MobileNotice(
                            'Tindakan terkonfirmasi dari antrean terbaru.',
                          ),
                        ),
                        TextField(controller: input, focusNode: focus),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump(Duration.zero);
          await tester.enterText(find.byType(TextField), 'Draft tetap');
          focus.requestFocus();
          await tester.pump(const Duration(milliseconds: 100));
          expect(focus.hasFocus, isTrue);
          await tester.pump(const Duration(milliseconds: 110));
          expect(input.text, 'Draft tetap');
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
