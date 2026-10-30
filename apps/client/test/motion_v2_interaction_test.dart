import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:queueb_client/src/patient_home_v7.dart';
import 'package:queueb_client/src/patient_home_v6.dart';
import 'package:queueb_client/src/queueb_interaction_motion.dart';
import 'package:queueb_client/src/queueb_motion.dart';

void main() {
  testWidgets(
    'changing reduced motion preserves the tab controller, selection and single callback',
    (t) async {
      var mode = PatientHomeMode.walkIn, callbacks = 0;
      Widget scene(bool reduced) => MaterialApp(
        home: MediaQuery(
          data: MediaQueryData.fromView(t.view)
              .copyWith(disableAnimations: reduced),
          child: Scaffold(
            body: StatefulBuilder(
              builder: (context, update) => PatientHomeTabs(
                value: mode,
                onChanged: (value) => update(() {
                  callbacks++;
                  mode = value;
                }),
                headerSlivers: const [],
                walkInSlivers: const [
                  SliverToBoxAdapter(child: Text('Walk-in body')),
                ],
                appointmentSlivers: const [
                  SliverToBoxAdapter(child: Text('Appointment body')),
                ],
              ),
            ),
          ),
        ),
      );
      await t.pumpWidget(scene(false));
      await t.pumpAndSettle();
      final controller = t.widget<TabBar>(find.byType(TabBar)).controller!;
      await t.pumpWidget(scene(true));
      expect(
        identical(t.widget<TabBar>(find.byType(TabBar)).controller, controller),
        isTrue,
      );
      expect(controller.animationDuration, Duration.zero);
      await t.tap(find.text('Janji Temu'));
      await t.pump();
      expect(mode, PatientHomeMode.appointment);
      expect(callbacks, 1);
      await t.pumpWidget(scene(false));
      expect(controller.animationDuration, QueueBMotion.component);
      expect(controller.index, 1);
      expect(callbacks, 1);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    },
  );
  test('V2 has one duration source and bounded distances', () {
    expect(
      [
        QueueBMotion.instant.inMilliseconds,
        QueueBMotion.press.inMilliseconds,
        QueueBMotion.micro.inMilliseconds,
        QueueBMotion.component.inMilliseconds,
        QueueBMotion.navigation.inMilliseconds,
        QueueBMotion.realtime.inMilliseconds,
        QueueBMotion.highlight.inMilliseconds,
        QueueBMotion.display.inMilliseconds,
      ],
      [0, 120, 180, 260, 320, 280, 600, 400],
    );
    expect(QueueBMotion.pressedScale, .985);
    expect(QueueBMotion.routeOffset, 12);
    expect(QueueBMotion.scrollThreshold, inInclusiveRange(16, 24));
  });

  for (final reduced in [false, true]) {
    testWidgets(
      'real service card press has one activation, reduced=$reduced',
      (t) async {
        var calls = 0;
        final semantics = t.ensureSemantics();
        try {
          await t.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(disableAnimations: reduced),
                child: Scaffold(
                  body: PatientServiceCardV7(
                    clinic: const {
                      'id': 'registration',
                      'kode': 'PENDAFTARAN',
                      'nama': 'Pendaftaran',
                    },
                    onTap: () => calls++,
                  ),
                ),
              ),
            ),
          );
          final card = find.byType(PatientServiceCardV7);
          final gesture = await t.startGesture(t.getCenter(card));
          await t.pump(const Duration(milliseconds: 150));
          await t.pump();
          final scale = t.widget<AnimatedScale>(
            find.descendant(of: card, matching: find.byType(AnimatedScale)),
          );
          expect(scale.scale, reduced ? 1 : .985);
          expect(scale.duration, reduced ? Duration.zero : QueueBMotion.press);
          expect(calls, 0);
          await gesture.up();
          await t.pumpAndSettle();
          expect(calls, 1);
          expect(t.getSemantics(card).label, contains('Pendaftaran'));
          expect(t.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
          expect(t.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      },
    );
  }

  testWidgets(
    'press keeps native keyboard focus and does not add a tap handler',
    (t) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      var calls = 0;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QueueBPressMotion(
              builder: (highlight) => Material(
                child: InkWell(
                  focusNode: focus,
                  onHighlightChanged: highlight,
                  onTap: () => calls++,
                  child: const SizedBox(
                    width: 150,
                    height: 60,
                    child: Text('Pilih layanan'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      focus.requestFocus();
      await t.pump();
      await t.sendKeyDownEvent(LogicalKeyboardKey.space);
      await t.pump(QueueBMotion.press);
      await t.sendKeyUpEvent(LogicalKeyboardKey.space);
      await t.pumpAndSettle();
      expect(calls, 1);
      expect(focus.hasFocus, isTrue);
    },
  );

  testWidgets(
    'route is perceptible, settles on reduced motion and resumes only for a real pop',
    (t) async {
      final controller = AnimationController(
        vsync: t,
        duration: QueueBMotion.navigation,
      );
      addTearDown(controller.dispose);
      Widget scene(bool reduced) => MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduced),
          child: QueueBRouteMotion(
            animation: controller,
            child: const Text('Detail'),
          ),
        ),
      );
      await t.pumpWidget(scene(false));
      controller.forward();
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      final opacity = find.descendant(
        of: find.byType(QueueBRouteMotion),
        matching: find.byType(Opacity),
      );
      expect(t.widget<Opacity>(opacity).opacity, inExclusiveRange(0, 1));
      await t.pumpWidget(scene(true));
      expect(t.widget<Opacity>(opacity).opacity, 1);
      await t.pumpWidget(scene(false));
      expect(t.widget<Opacity>(opacity).opacity, 1);
      await t.pumpAndSettle();
      controller.reverse();
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      expect(t.widget<Opacity>(opacity).opacity, inExclusiveRange(0, 1));
      await t.pumpAndSettle();
      expect(t.widget<Opacity>(opacity).opacity, 0);
      await t.pumpWidget(const SizedBox());
      expect(t.takeException(), isNull);
    },
  );

  for (final reduced in [false, true]) {
    testWidgets(
      'native modal retains barrier, focus, result and scaling, reduced=$reduced',
      (t) async {
        bool? result;
        await t.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                disableAnimations: reduced,
                textScaler: TextScaler.linear(1.5),
              ),
              child: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () async => result = await showDialog<bool>(
                      context: context,
                      barrierDismissible: false,
                      animationStyle: QueueBMotion.modalStyle(context),
                      builder: (_) => QueueBModalMotion(
                        child: AlertDialog(
                          title: const Text('Konfirmasi'),
                          content: const TextField(autofocus: true),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('Simpan'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    child: const Text('Buka'),
                  ),
                ),
              ),
            ),
          ),
        );
        await t.tap(find.text('Buka'));
        await t.pumpAndSettle();
        final context = t.element(find.byType(AlertDialog));
        expect(
          ModalRoute.of(context)!.transitionDuration,
          reduced ? Duration.zero : QueueBMotion.component,
        );
        await t.enterText(find.byType(TextField), 'Tetap fokus');
        await t.tapAt(const Offset(2, 2));
        await t.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(result, isNull);
        await t.tap(find.text('Simpan'));
        await t.pumpAndSettle();
        expect(result, true);
        expect(find.byType(AlertDialog), findsNothing);
        expect(t.takeException(), isNull);
      },
    );
  }
}
