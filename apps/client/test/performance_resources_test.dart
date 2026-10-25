import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:queueb_client/src/display_board.dart';
import 'package:queueb_client/src/image_sizing.dart';
import 'package:queueb_client/src/mobile_ui.dart';

void main() {
  test('immutable shared theme is reused without changing QueueB colors', () {
    expect(identical(QueueBStyle.theme, QueueBStyle.theme), isTrue);
    expect(QueueBStyle.theme.colorScheme.primary, QueueBStyle.darkTeal);
    expect(QueueBStyle.theme.scaffoldBackgroundColor, QueueBStyle.background);
  });

  test('avatar decode follows DPR with a bounded set of reusable sizes', () {
    expect(imageDecodeWidth(56, 2), 128);
    expect(imageDecodeWidth(60, 2), 128);
    expect(imageDecodeWidth(112, 3), 512);
    expect(imageDecodeWidth(600, 2), 1200);
  });

  test('thumbnail decode retains source aspect and reduces decoded allocation', () async {
    final bytes = await File('assets/illustrations/doctor_avatar.png')
        .readAsBytes();
    final originalCodec = await ui.instantiateImageCodec(bytes);
    final resizedCodec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: 128,
    );
    final original = (await originalCodec.getNextFrame()).image;
    final resized = (await resizedCodec.getNextFrame()).image;
    try {
      expect(resized.width, 128);
      expect(resized.height, 128);
      expect(
        resized.width * resized.height,
        lessThan(original.width * original.height),
      );
      // Encoded bytes and GPU/JS/process memory are separate measurements.
      // ignore: avoid_print
      print(
        'Decoded RGBA bytes: ${original.width * original.height * 4} -> ${resized.width * resized.height * 4}',
      );
    } finally {
      original.dispose();
      resized.dispose();
      originalCodec.dispose();
      resizedCodec.dispose();
    }
  });

  testWidgets('display clock ticks without rebuilding queue snapshot widgets', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final clock = ValueNotifier(DateTime.utc(2026, 10, 25, 8));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DisplayBoard(
            snapshot: const {
              'layanan': {'nama': 'Poliklinik QA'},
              'loket': [],
              'jumlahMenunggu': 0,
            },
            now: clock.value,
            clock: clock,
            status: 'Realtime terhubung',
            onRefresh: () {},
            onAudio: () {},
            onConfigure: () {},
            onFullscreen: () {},
          ),
        ),
      ),
    );
    final waiting = tester.widget(
      find.byKey(const ValueKey('display-waiting-count')),
    );
    for (var i = 1; i <= 60; i++) {
      clock.value = DateTime.utc(2026, 10, 25, 8, 0, i);
      await tester.pump();
      expect(
        identical(
          waiting,
          tester.widget(find.byKey(const ValueKey('display-waiting-count'))),
        ),
        isTrue,
      );
    }
    expect(find.text('08:01:00'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    clock.dispose();
    expect(tester.takeException(), isNull);
  });
}
