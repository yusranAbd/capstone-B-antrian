import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:queueb_client/src/admin.dart';
import 'package:queueb_client/src/api.dart';
import 'package:queueb_client/src/app.dart';
import 'package:queueb_client/src/config.dart';
import 'package:queueb_client/src/display.dart';
import 'package:queueb_client/src/doctor.dart';
import 'package:queueb_client/src/login_ui.dart';
import 'package:queueb_client/src/patient.dart';
import 'package:queueb_client/src/queue.dart';
import 'package:timezone/data/latest.dart' as tz;

import 'ui_test.dart' show FakeBackend;

void main() {
  setUpAll(tz.initializeTimeZones);
  final email = find.widgetWithText(TextFormField, 'Email');
  final password = find.widgetWithText(TextFormField, 'Kata sandi');
  final submit = find.widgetWithText(FilledButton, 'Masuk');

  Future<QueueApi> launch(
    WidgetTester tester, {
    Size size = const Size(1440, 1000),
    Future<http.Response> Function(http.Request)? handle,
    double scale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    final api = QueueApi(
      config: AppConfig(apiBaseUrl: 'http://localhost/api/v1', realtime: false),
      client: MockClient(handle ?? (r) async => http.Response('{}', 401)),
    );
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: QueueBApp(api: api),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      api.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.view.resetViewInsets();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    return api;
  }

  Future<void> press(WidgetTester tester, Finder target) async {
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  for (final size in const [
    Size(320, 700),
    Size(360, 800),
    Size(375, 800),
    Size(390, 844),
    Size(414, 800),
    Size(500, 800),
    Size(768, 1024),
    Size(1024, 768),
    Size(1366, 768),
    Size(1440, 900),
    Size(1920, 1080),
  ]) {
    testWidgets(
      'Login V3 $size: centered card, all actions visible without scrolling',
      (tester) async {
        await launch(tester, size: size);
        expect(find.byType(LoginLayout), findsOneWidget);
        expect(email, findsOneWidget);
        expect(password, findsOneWidget);
        expect(
          find.text('Akses mudah untuk pelayanan lebih baik'),
          findsNothing,
        );
        expect(
          find.textContaining('Pendaftaran, tiket, dan antrean'),
          findsNothing,
        );
        expect(find.textContaining('Daftar, dapatkan tiket'), findsNothing);
        expect(find.text('Ambil tiket antrean'), findsNothing);
        expect(find.text('Pantau antrean real-time'), findsNothing);
        expect(find.text('Pelayanan lebih efisien'), findsNothing);
        expect(find.text('Layanan digital rumah sakit'), findsNothing);
        expect(find.byType(Image), findsNothing);
        expect(find.text('Akses sistem antrean rumah sakit'), findsOneWidget);
        final card = tester.getRect(find.byType(LoginFormCard));
        expect(card.width, lessThanOrEqualTo(LoginStyle.cardWidth));
        expect(card.center.dx, closeTo(size.width / 2, .5));
        expect(card.center.dy, closeTo(size.height / 2, .5));
        expect(card.top, greaterThanOrEqualTo(24));
        expect(card.bottom, lessThanOrEqualTo(size.height - 24));
        expect(
          find.descendant(
            of: find.byType(LoginFormCard),
            matching: find.text('QueueB Hospital'),
          ),
          findsOneWidget,
        );
        final scroll = tester.state<ScrollableState>(
          find
              .descendant(
                of: find.byKey(const ValueKey('login-scroll')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(scroll.position.maxScrollExtent, 0);
        expect(
          tester.getBottomRight(find.text('Pasien baru? Daftar')).dy,
          lessThan(size.height),
        );
        expect(find.text('Lupa kata sandi?'), findsNothing);
        expect(find.textContaining('Google'), findsNothing);
        expect(find.textContaining('Apple'), findsNothing);
        await press(tester, submit);
        expect(find.text('Masukkan email yang valid.'), findsOneWidget);
        expect(find.text('Kata sandi wajib diisi.'), findsOneWidget);
        await press(tester, find.text('Pasien baru? Daftar'));
        expect(
          find.widgetWithText(TextFormField, 'Nama lengkap'),
          findsOneWidget,
        );
        await press(tester, find.widgetWithText(FilledButton, 'Daftar pasien'));
        expect(find.text('Nama 3–150 karakter.'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final width in [375.0, 1024.0]) {
    testWidgets('Large text at $width remains scrollable without overflow', (
      tester,
    ) async {
      await launch(tester, size: Size(width, 800), scale: 2);
      await press(tester, submit);
      await tester.ensureVisible(find.text('Masuk ke Public Display'));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'Resize preserves email and password across desktop and mobile layouts',
    (tester) async {
      await launch(tester);
      await tester.enterText(email, 'fixture@test.local');
      await tester.enterText(password, 'fixture-only');
      for (final width in [375.0, 1024.0, 1440.0]) {
        tester.view.physicalSize = Size(width, 1000);
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextFormField>(email).controller!.text,
          'fixture@test.local',
        );
        expect(
          tester.widget<TextFormField>(password).controller!.text,
          'fixture-only',
        );
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'Registration does not inherit validation state from another field',
    (tester) async {
      await launch(tester);
      await press(tester, submit);
      await tester.enterText(email, 'fixture@test.local');
      await tester.enterText(password, 'fixture-only');
      await press(tester, find.text('Pasien baru? Daftar'));
      final name = find.byKey(const ValueKey('login-name'));
      expect(
        find.descendant(
          of: name,
          matching: find.text('Masukkan email yang valid.'),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: email,
          matching: find.text('Kata sandi wajib diisi.'),
        ),
        findsNothing,
      );
      expect(tester.widget<TextFormField>(name).controller!.text, isEmpty);
      expect(
        tester.widget<TextFormField>(email).controller!.text,
        'fixture@test.local',
      );
      expect(
        tester.widget<TextFormField>(password).controller!.text,
        'fixture-only',
      );
      await press(tester, find.widgetWithText(FilledButton, 'Daftar pasien'));
      expect(
        find.descendant(of: name, matching: find.text('Nama 3–150 karakter.')),
        findsOneWidget,
      );
      expect(find.text('Masukkan email yang valid.'), findsNothing);
      expect(find.text('Kata sandi wajib diisi.'), findsNothing);
    },
  );

  testWidgets('Short mobile viewport with keyboard remains scrollable', (
    tester,
  ) async {
    await launch(tester, size: const Size(375, 600));
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await tester.pump();
    await tester.ensureVisible(password);
    await tester.enterText(password, 'fixture-only');
    await press(tester, find.byTooltip('Tampilkan kata sandi'));
    expect(
      tester.widget<TextFormField>(password).controller!.text,
      'fixture-only',
    );
    expect(
      tester
          .widget<EditableText>(
            find.descendant(of: password, matching: find.byType(EditableText)),
          )
          .obscureText,
      isFalse,
    );
    await press(tester, find.byTooltip('Sembunyikan kata sandi'));
    expect(
      tester
          .widget<EditableText>(
            find.descendant(of: password, matching: find.byType(EditableText)),
          )
          .obscureText,
      isTrue,
    );
    await tester.ensureVisible(find.text('Masuk ke Public Display'));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Slow login disables duplicate submits and reports error without losing inputs',
    (tester) async {
      final gate = Completer<http.Response>();
      var calls = 0;
      await launch(
        tester,
        handle: (r) {
          calls++;
          return gate.future;
        },
      );
      await tester.enterText(email, 'fixture@test.local');
      await tester.enterText(password, 'fixture-only');
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pump();
      expect(find.text('Memproses…'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(
        tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull,
      );
      expect(calls, 1);
      gate.complete(
        http.Response(
          jsonEncode({'message': 'Email atau kata sandi salah.'}),
          401,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Email atau kata sandi salah.'), findsOneWidget);
      expect(
        tester.widget<TextFormField>(email).controller!.text,
        'fixture@test.local',
      );
      expect(
        tester.widget<TextFormField>(password).controller!.text,
        'fixture-only',
      );
      expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
    },
  );

  testWidgets('Keyboard Tab reaches fields; Enter submits existing login', (
    tester,
  ) async {
    final server = FakeBackend('USER');
    await launch(tester, handle: server.handle);
    await tester.tap(email);
    await tester.enterText(email, 'fixture@test.local');
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(
      tester
          .widget<EditableText>(
            find.descendant(of: password, matching: find.byType(EditableText)),
          )
          .focusNode
          .hasFocus,
      isTrue,
    );
    await tester.enterText(password, 'fixture-only');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.byType(PatientPage), findsOneWidget);
    expect(server.requests.where((r) => r.$2 == '/auth/login').length, 1);
  });

  for (final role in ['ADMIN', 'PETUGAS', 'DOKTER', 'USER']) {
    testWidgets(
      'Backend role $role controls redirect and logout returns login',
      (tester) async {
        final server = FakeBackend(role);
        final api = await launch(tester, handle: server.handle);
        await tester.enterText(email, 'fixture@test.local');
        await tester.enterText(password, 'fixture-only');
        await press(tester, submit);
        expect(api.user?['peran'], role);
        expect(
          find.byType(switch (role) {
            'ADMIN' => AdminPage,
            'PETUGAS' => QueuePage,
            'DOKTER' => DoctorPage,
            _ => PatientPage,
          }),
          findsOneWidget,
        );
        if (role == 'USER') {
          await press(tester, find.byTooltip('Profil akun'));
          await press(tester, find.text('Keluar Akun'));
        } else if (role == 'PETUGAS') {
          await press(tester, find.byTooltip('Profil petugas'));
          await press(tester, find.text('Keluar akun'));
        } else {
          await press(tester, find.byTooltip('Keluar akun'));
        }
        expect(email, findsOneWidget);
        expect(api.user, isNull);
      },
    );
  }

  testWidgets(
    'Patient registration keeps the existing public API and returns to login',
    (tester) async {
      http.Request? registration;
      await launch(
        tester,
        size: const Size(360, 800),
        handle: (r) async {
          if (r.url.path.endsWith('/auth/register')) {
            registration = r;
            return http.Response('{}', 201);
          }
          return http.Response('{}', 401);
        },
      );
      await press(tester, find.text('Pasien baru? Daftar'));
      await tester.enterText(
        find.byKey(const ValueKey('login-name')),
        'Pasien Fixture',
      );
      await tester.enterText(email, 'fixture@test.local');
      await tester.enterText(password, 'fixture-only');
      await press(tester, find.widgetWithText(FilledButton, 'Daftar pasien'));
      expect(registration, isNotNull);
      expect(registration!.method, 'POST');
      final body = jsonDecode(registration!.body) as Map<String, dynamic>;
      expect(body['nama'], 'Pasien Fixture');
      expect(body.containsKey('peran'), isFalse);
      expect(find.text('Akun pasien dibuat. Silakan masuk.'), findsOneWidget);
      expect(submit, findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Public Display opens existing route anonymously; no login request or bearer token',
    (tester) async {
      final requests = <http.Request>[];
      final api = await launch(
        tester,
        handle: (r) async {
          requests.add(r);
          return http.Response('{}', 401);
        },
      );
      await press(tester, find.text('Masuk ke Public Display'));
      expect(find.byType(DisplayPage), findsOneWidget);
      expect(api.user, isNull);
      expect(requests.single.url.path, '/api/v1/display/sesi');
      expect(requests.single.headers.containsKey('Authorization'), isFalse);
      await press(tester, find.byTooltip('Kembali ke login'));
      await tester.pumpAndSettle();
      expect(email, findsOneWidget);
    },
  );
}
