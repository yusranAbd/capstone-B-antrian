import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:queueb_client/src/api.dart';
import 'package:queueb_client/src/app.dart';
import 'package:queueb_client/src/config.dart';
import 'package:timezone/data/latest.dart' as tz;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    tz.initializeTimeZones();
    // Measure with the actual Material font, rather than the test-only Ahem
    // monospace font. The SDK ships these files on Windows and CI Linux.
    final config = File('.dart_tool/package_config.json').absolute;
    final packages =
        jsonDecode(await config.readAsString())['packages'] as List;
    final flutter = packages.singleWhere((p) => p['name'] == 'flutter');
    final root = Directory.fromUri(
      config.uri.resolve(flutter['rootUri'] as String),
    ).parent.parent.path;
    final font = FontLoader('Roboto');
    for (final weight in ['regular', 'medium', 'bold']) {
      font.addFont(
        File('$root/bin/cache/artifacts/material_fonts/roboto-$weight.ttf')
            .readAsBytes()
            .then((b) => ByteData.sublistView(b)),
      );
    }
    await font.load();
  });

  final email = find.byKey(const ValueKey('login-email'));
  final password = find.byKey(const ValueKey('login-password'));
  final submit = find.widgetWithText(FilledButton, 'Masuk');
  final display = find.widgetWithText(
    OutlinedButton,
    'Masuk ke Public Display',
  );
  final register = find.text('Pasien baru? Daftar');

  Future<void> launch(
    WidgetTester tester,
    Size viewport, {
    double dpr = 1,
    Completer<http.Response>? gate,
  }) async {
    tester.view.devicePixelRatio = dpr;
    tester.view.physicalSize = viewport * dpr;
    final api = QueueApi(
      config: AppConfig(apiBaseUrl: 'http://localhost/api/v1', realtime: false),
      client: MockClient(
        (r) async => gate == null
            ? http.Response(
                jsonEncode({'message': 'Email atau kata sandi salah.'}),
                401,
              )
            : await gate.future,
      ),
    );
    await tester.pumpWidget(QueueBApp(api: api));
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      api.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  ScrollPosition position(WidgetTester tester) => tester
      .state<ScrollableState>(
        find
            .descendant(
              of: find.byKey(const ValueKey('login-page-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      )
      .position;

  void fits(
    WidgetTester tester,
    Size viewport, {
    bool registration = false,
    bool busy = false,
  }) {
    expect(
      position(tester).maxScrollExtent,
      closeTo(0, .01),
      reason: 'All content must fit the actual logical viewport',
    );
    final screen = Offset.zero & viewport;
    final buttons = [
      email,
      password,
      display,
      registration
          ? find.widgetWithText(FilledButton, 'Daftar pasien')
          : busy
          ? find.widgetWithText(FilledButton, 'Memproses…')
          : submit,
      registration ? find.text('Sudah punya akun? Masuk') : register,
    ];
    for (final control in buttons) {
      final rect = tester.getRect(control);
      expect(rect.left, greaterThanOrEqualTo(screen.left));
      expect(rect.top, greaterThanOrEqualTo(screen.top));
      expect(rect.right, lessThanOrEqualTo(screen.right));
      expect(rect.bottom, lessThanOrEqualTo(screen.bottom));
    }
    expect(tester.getSize(find.byType(Image)).height, greaterThan(0));
    expect(tester.takeException(), isNull);
  }

  for (final size in [
    const Size(1024, 768),
    const Size(1280, 720),
    const Size(1366, 768),
    const Size(1440, 900),
    const Size(1536, 864),
    const Size(1920, 1080),
  ]) {
    testWidgets(
      'Desktop $size fits initial, validation, error and registration without scrolling',
      (tester) async {
        await launch(tester, size);
        fits(tester, size);
        await tester.tap(submit);
        await tester.pumpAndSettle();
        expect(find.text('Masukkan email yang valid.'), findsOneWidget);
        fits(tester, size);
        await tester.enterText(email, 'fixture@example.invalid');
        await tester.enterText(password, 'fixture-only');
        await tester.tap(submit);
        await tester.pumpAndSettle();
        expect(find.text('Email atau kata sandi salah.'), findsOneWidget);
        fits(tester, size);
        await tester.tap(register);
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Daftar pasien'));
        await tester.pumpAndSettle();
        fits(tester, size, registration: true);
      },
    );
  }

  testWidgets('125 percent DPR uses the same 1366x768 logical constraints', (
    tester,
  ) async {
    const size = Size(1366, 768);
    await launch(tester, size, dpr: 1.25);
    fits(tester, size);
  });

  testWidgets('Loading keeps disabled controls within the laptop viewport', (
    tester,
  ) async {
    final gate = Completer<http.Response>();
    const size = Size(1280, 720);
    await launch(tester, size, gate: gate);
    await tester.enterText(email, 'fixture@example.invalid');
    await tester.enterText(password, 'fixture-only');
    await tester.tap(submit);
    await tester.pump();
    fits(tester, size, busy: true);
    expect(tester.widget<OutlinedButton>(display).onPressed, isNull);
    gate.complete(http.Response('{}', 401));
    await tester.pumpAndSettle();
  });

  testWidgets(
    'Very short desktop safely scrolls rather than clipping controls',
    (tester) async {
      await launch(tester, const Size(1280, 500));
      expect(position(tester).maxScrollExtent, greaterThan(0));
      await tester.ensureVisible(register);
      await tester.tap(register);
      await tester.pumpAndSettle();
      await tester.ensureVisible(display);
      expect(tester.takeException(), isNull);
    },
  );
}
