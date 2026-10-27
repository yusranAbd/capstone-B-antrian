import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:queueb_client/src/admin_ui.dart';
import 'package:queueb_client/src/display_board.dart';
import 'package:queueb_client/src/doctor_visual.dart';
import 'package:queueb_client/src/mobile_ui.dart';
import 'package:queueb_client/src/patient_design.dart';
import 'package:queueb_client/src/queueb_palette.dart';
import 'package:queueb_client/src/staff_ui.dart';

import 'display_v3_test.dart' show monitorSnapshot;

void main() {
  test(
    'All role themes share blue colors while retaining their type scales',
    () {
      for (final theme in [
        QueueBStyle.theme,
        AdminStyle.theme,
        StaffStyle.theme,
        DoctorStyle.theme,
        PatientDesign.theme,
      ]) {
        expect(theme.colorScheme.primary, QueueBPalette.primary);
        expect(theme.scaffoldBackgroundColor, QueueBPalette.background);
      }
      expect(DoctorStyle.deepNavy, QueueBPalette.console);
      expect(DoctorStyle.deepTeal, QueueBPalette.consoleEnd);
      expect(AdminStyle.sky, QueueBPalette.soft);
      expect(StaffStyle.theme.textTheme.bodyMedium!.fontSize, 12);
      expect(PatientDesign.theme.textTheme.bodyMedium!.fontSize, 14);
      expect(QueueBStyle.theme.extension<PatientAppearance>(), isNull);
    },
  );

  test('Operational and signage foreground pairs retain readable contrast', () {
    double ratio(Color a, Color b) {
      final x = a.computeLuminance(), y = b.computeLuminance();
      return x > y ? (x + .05) / (y + .05) : (y + .05) / (x + .05);
    }

    for (final pair in [
      (Colors.white, QueueBPalette.primary),
      (Colors.white, QueueBPalette.hero),
      (QueueBPalette.ink, QueueBPalette.background),
      (QueueBPalette.muted, QueueBPalette.paper),
      (QueueBPalette.primary, QueueBPalette.soft),
      (QueueBPalette.onConsole, QueueBPalette.console),
      (QueueBPalette.onConsoleMuted, QueueBPalette.consoleEnd),
    ]) {
      expect(ratio(pair.$1, pair.$2), greaterThanOrEqualTo(4.5));
    }
  });

  testWidgets(
    'Display call panel and staff console use their shared blue surfaces',
    (t) async {
      t.view.physicalSize = const Size(1280, 720);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(
        MaterialApp(
          theme: QueueBStyle.theme,
          home: Scaffold(
            body: DisplayBoard(
              snapshot: monitorSnapshot(waiting: 30),
              now: DateTime(2026, 10, 28),
              status: 'Realtime terhubung',
              onRefresh: () {},
              onAudio: () {},
              onConfigure: () {},
              onFullscreen: () {},
            ),
          ),
        ),
      );
      await t.pump();
      final panel = t.widget<Container>(
        find.byKey(const ValueKey('display-call-panel')),
      );
      expect((panel.decoration! as BoxDecoration).color, QueueBPalette.hero);
      expect(find.byKey(const ValueKey('display-call-number')), findsOneWidget);
      expect(find.byType(Scrollable), findsNothing);
      expect(t.takeException(), isNull);
      await t.pumpWidget(
        MaterialApp(
          theme: StaffStyle.theme,
          home: const Scaffold(
            body: StaffPanel(
              title: 'Pelayanan ruang ini',
              icon: Icons.campaign_outlined,
              dark: true,
              child: Text('AN-001'),
            ),
          ),
        ),
      );
      final materials = t.widgetList<Material>(
        find.descendant(
          of: find.byType(StaffPanel),
          matching: find.byType(Material),
        ),
      );
      expect(materials.first.color, QueueBPalette.console);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
}
