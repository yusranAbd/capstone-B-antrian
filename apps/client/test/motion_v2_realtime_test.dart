import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:queueb_client/src/admin_ui.dart';
import 'package:queueb_client/src/display_board.dart';
import 'package:queueb_client/src/mobile_ui.dart';
import 'package:queueb_client/src/features/patient/models/patient_queue_models.dart';
import 'package:queueb_client/src/patient_home_v7.dart';
import 'package:queueb_client/src/queueb_motion.dart';
import 'package:queueb_client/src/queueb_value_motion.dart';

import 'display_v3_test.dart' show monitorSnapshot;

void main() {
  Widget value(
    int? number, {
    bool available = true,
    bool reduced = false,
    bool active = true,
    Object scope = 'A',
  }) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduced),
      child: TickerMode(
        enabled: active,
        child: Center(
          child: QueueBValueMotion(
            scope: scope,
            value: number,
            available: available,
            highlight: true,
            highlightColor: Colors.blue,
            child: Text(number == null ? '—' : '$number'),
          ),
        ),
      ),
    ),
  );
  testWidgets(
    'authoritative counter switches once, exposes only latest semantics and handles correction down',
    (t) async {
      final handle = t.ensureSemantics();
      try {
        await t.pumpWidget(value(42));
        await t.pump();
        expect(t.binding.hasScheduledFrame, isFalse);
        expect(find.text('42'), findsOneWidget);
        await t.pumpWidget(value(43));
        expect(
          t.widget<AnimatedSwitcher>(find.byType(AnimatedSwitcher)).duration,
          QueueBMotion.realtime,
        );
        expect(find.text('42'), findsOneWidget);
        expect(find.text('43'), findsOneWidget);
        expect(find.bySemanticsLabel('42'), findsNothing);
        expect(find.bySemanticsLabel('43'), findsOneWidget);
        await t.pumpAndSettle();
        expect(find.text('42'), findsNothing);
        await t.pumpWidget(value(43));
        await t.pump();
        expect(t.binding.hasScheduledFrame, isFalse);
        await t.pumpWidget(value(41));
        expect(find.text('41'), findsOneWidget);
        expect(find.text('+1'), findsNothing);
        await t.pumpAndSettle();
        expect(find.text('43'), findsNothing);
      } finally {
        handle.dispose();
      }
    },
  );
  testWidgets(
    'unavailable, hydration and scope changes remove stale values immediately',
    (t) async {
      await t.pumpWidget(value(42));
      await t.pumpWidget(value(43));
      await t.pumpWidget(value(null, available: false));
      expect(find.text('42'), findsNothing);
      expect(find.text('43'), findsNothing);
      expect(find.text('—'), findsOneWidget);
      await t.pumpWidget(value(44));
      await t.pump();
      expect(t.binding.hasScheduledFrame, isFalse);
      await t.pumpWidget(value(12, scope: 'B'));
      expect(find.text('44'), findsNothing);
      await t.pump();
      expect(t.binding.hasScheduledFrame, isFalse);
    },
  );
  testWidgets(
    'reduced motion and offstage updates settle without replay on return',
    (t) async {
      await t.pumpWidget(value(42));
      await t.pumpWidget(value(43));
      await t.pump(const Duration(milliseconds: 60));
      await t.pumpWidget(value(43, reduced: true));
      expect(find.text('42'), findsNothing);
      await t.pumpWidget(value(43));
      await t.pump();
      expect(t.binding.hasScheduledFrame, isFalse);
      await t.pumpWidget(value(44, active: false));
      await t.pumpWidget(value(44));
      await t.pump();
      expect(t.binding.hasScheduledFrame, isFalse);
      await t.pumpAndSettle();
      expect(t.binding.hasScheduledFrame, isFalse);
    },
  );
  testWidgets(
    'rapid updates retain latest, at most one outgoing value and dispose cleanly',
    (t) async {
      await t.pumpWidget(value(1));
      await t.pumpWidget(value(2));
      await t.pump(const Duration(milliseconds: 20));
      await t.pumpWidget(value(3));
      expect(find.text('1'), findsNothing);
      expect(find.text('3'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 1));
      expect(t.takeException(), isNull);
      expect(t.binding.hasScheduledFrame, isFalse);
    },
  );

  testWidgets(
    'patient card reacts to scalar values, not snapshot timestamps or freshness',
    (t) async {
      Widget card(
        int count,
        String serving, {
        bool live = true,
        String date = '2026-10-31',
      }) => MaterialApp(
        home: Scaffold(
          body: PatientServiceCardV7(
            clinic: const {
              'id': 'PEN',
              'kode': 'PENDAFTARAN',
              'nama': 'Pendaftaran',
            },
            queue: PatientQueueView(
              live: live,
              summary: PatientQueueSummary(
                'PEN',
                date,
                DateTime.now().toUtc(),
                count,
                1,
                [PatientServingNumber('room', 'PEN01', serving)],
              ),
            ),
            onTap: () {},
          ),
        ),
      );
      await t.pumpWidget(card(42, 'PEN-007'));
      await t.pumpWidget(card(42, 'PEN-007', live: false));
      await t.pump();
      expect(t.binding.hasScheduledFrame, isFalse);
      await t.pumpWidget(card(43, 'PEN-008'));
      expect(
        t
            .widgetList<AnimatedSwitcher>(find.byType(AnimatedSwitcher))
            .where((w) => w.duration == QueueBMotion.realtime)
            .length,
        2,
      );
      await t.pumpAndSettle();
      await t.pumpWidget(card(43, 'PEN-008'));
      await t.pump();
      expect(t.binding.hasScheduledFrame, isFalse);
      await t.pumpWidget(card(0, 'PEN-001', date: '2026-11-02'));
      expect(find.textContaining('PEN-008'), findsNothing);
    },
  );

  for (final reduced in [false, true]) {
    testWidgets(
      'Display value change/recall is visual only, reduced=$reduced',
      (t) async {
        t.view.physicalSize = const Size(1366, 768);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        var calls = 0;
        Widget board(Map<String, dynamic> snapshot) => MaterialApp(
          theme: QueueBStyle.theme,
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduced),
            child: Scaffold(
              body: DisplayBoard(
                snapshot: snapshot,
                now: DateTime(2026, 10, 31),
                status: 'Realtime terhubung',
                onRefresh: () => calls++,
                onAudio: () => calls++,
                onConfigure: () => calls++,
                onFullscreen: () => calls++,
              ),
            ),
          ),
        );
        final first = monitorSnapshot();
        await t.pumpWidget(board(first));
        final second = Map<String, dynamic>.from(jsonDecode(jsonEncode(first)));
        second['loket'][0]['tiketAktif'][0]['nomorAntrean'] = 'AN-002';
        second['pengumumanTerakhir']['nomorAntrean'] = 'AN-002';
        second['pengumumanTerakhir']['peristiwaId'] = 'second-fixture-call';
        await t.pumpWidget(board(second));
        final hero = find.descendant(
          of: find.byKey(const ValueKey('display-call-panel')),
          matching: find.byType(AnimatedSwitcher),
        );
        expect(
          t.widget<AnimatedSwitcher>(hero).duration,
          reduced ? Duration.zero : QueueBMotion.display,
        );
        await t.pump(QueueBMotion.highlight);
        await t.pumpWidget(board(second));
        await t.pump();
        expect(find.text('AN-001'), findsNothing);
        expect(find.text('AN-002'), findsWidgets);
        final third = Map<String, dynamic>.from(jsonDecode(jsonEncode(second)));
        third['layanan']['kode'] = 'OTHER';
        third['tanggalPelayanan'] = '2026-11-02';
        third['loket'][0]['tiketAktif'][0]['nomorAntrean'] = 'OTHER-001';
        third['pengumumanTerakhir']['nomorAntrean'] = 'OTHER-001';
        await t.pumpWidget(board(third));
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('display-call-panel')),
            matching: find.text('AN-002'),
          ),
          findsNothing,
        );
        await t.pump();
        expect(calls, 0);
        await t.pumpWidget(const SizedBox());
        await t.pump();
        expect(t.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'ADMIN status cell is scoped to row identity and does not reorder or replay',
    (t) async {
      Widget table(bool active) => MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 700,
            child: AdminTable(
              rows: [
                {'id': 'a', 'nama': 'A', 'aktif': active},
                {'id': 'b', 'nama': 'B', 'aktif': true},
              ],
              columns: [
                AdminColumn('Nama', (r) => r['nama']),
                AdminColumn(
                  'Status',
                  (r) => r['aktif'] == true ? 'Aktif' : 'Nonaktif',
                ),
              ],
            ),
          ),
        ),
      );
      await t.pumpWidget(table(true));
      await t.pumpAndSettle();
      await t.pumpWidget(table(false));
      await t.pump();
      final a = find.byKey(const ValueKey<Object>(('a', 'Status')));
      final b = find.byKey(const ValueKey<Object>(('b', 'Status')));
      expect(t.widget<QueueBValueMotion>(a).value, 'Nonaktif');
      expect(t.widget<QueueBValueMotion>(b).value, 'Aktif');
      await t.pumpAndSettle();
      await t.pumpWidget(table(false));
      await t.pump();
      expect(t.binding.hasScheduledFrame, isFalse);
      expect(t.takeException(), isNull);
    },
  );
}
