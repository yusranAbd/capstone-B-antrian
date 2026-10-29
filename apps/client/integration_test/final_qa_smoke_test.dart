import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:queueb_client/src/api.dart';
import 'package:queueb_client/src/app.dart';
import 'package:queueb_client/src/config.dart';
import 'package:queueb_client/src/session_store.dart';
import 'package:queueb_client/src/staff_qr_scanner.dart';
import 'package:timezone/data/latest.dart' as tz;

class _QaLifecycleRecorder with WidgetsBindingObserver {
  final states = <AppLifecycleState>[];
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => states.add(state);
}

class _QaBackRecorder with WidgetsBindingObserver {
  int pops = 0, keys = 0;
  bool key(KeyEvent event) {
    if (event.logicalKey == LogicalKeyboardKey.goBack &&
        event is KeyDownEvent) {
      keys++;
    }
    return false;
  }

  @override
  Future<bool> didPopRoute() async {
    pops++;
    return false;
  }
}

// Only android-final-qa.cjs supplies ephemeral synthetic accounts over loopback.
// No QR, credentials, screenshots or response bodies are written to artifacts.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Android QA: four-role sessions and secure-store restore', (
    tester,
  ) async {
    tz.initializeTimeZones();
    final config = AppConfig.fromEnvironment();
    expect(config.apiBase.toString(), 'http://127.0.0.1:3001/api/v1');
    final response = await http.get(Uri.parse('http://127.0.0.1:3002/fixture'));
    expect(response.statusCode, 200);
    final fixture = object(jsonDecode(response.body));
    final store = platformSessionStore('${config.apiBase}');
    expect(store, isA<AndroidSessionStore>());
    await store
        .clear(); // This test runs only in a read-only QA emulator overlay.
    var api = QueueApi(config: config, sessionStore: store);
    final backEvents = _QaBackRecorder();
    WidgetsBinding.instance.addObserver(backEvents);
    HardwareKeyboard.instance.addHandler(backEvents.key);
    final frameworkBack = <bool>[];
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemNavigator.setFrameworkHandlesBack') {
        frameworkBack.add(call.arguments as bool);
      }
      final reply = await messenger.delegate.send(
        SystemChannels.platform.name,
        SystemChannels.platform.codec.encodeMethodCall(call),
      );
      if (reply == null) {
        throw MissingPluginException(
          'QA platform forwarding returned no reply',
        );
      }
      return SystemChannels.platform.codec.decodeEnvelope(reply);
    });
    addTearDown(() {
      WidgetsBinding.instance.removeObserver(backEvents);
      HardwareKeyboard.instance.removeHandler(backEvents.key);
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    });
    await tester.pumpWidget(QueueBApp(api: api));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      api.dispose();
    });

    Future<void> until(
      bool Function() ready, {
      String phase = 'condition',
    }) async {
      final deadline = DateTime.now().add(const Duration(seconds: 40));
      while (!ready()) {
        if (DateTime.now().isAfter(deadline)) {
          fail(
            'Android QA condition not reached: $phase; no credential diagnostics',
          );
        }
        await tester.pump(const Duration(milliseconds: 200));
      }
      await tester.pumpAndSettle();
    }

    Future<void> login(String account) async {
      debugPrint('Final Android QA phase: $account');
      final user = object(fixture[account]);
      await until(
        () => find.widgetWithText(TextFormField, 'Email').evaluate().isNotEmpty,
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email'),
        '${user['email']}',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Kata sandi'),
        '${user['password']}',
      );
      TextInput.finishAutofillContext(shouldSave: false);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      final submit = find.widgetWithText(FilledButton, 'Masuk');
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await until(
        () => api.user != null && api.sessionPhase == SessionPhase.ready,
      );
      expect(api.user?['id'], user['id']);
      // Test input must release the IME before testing route Back, rather than
      // accidentally consuming the first Android Back to dismiss a keyboard.
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
    }

    Future<void> logout() async {
      await api.logout();
      await until(
        () => find.widgetWithText(TextFormField, 'Email').evaluate().isNotEmpty,
      );
      expect(api.user, isNull);
      expect(await store.read(), isNull);
    }

    await login('patient1');
    GoRouter router() =>
        tester.widget<MaterialApp>(find.byType(MaterialApp)).routerConfig!
            as GoRouter;
    var backSequence = 0;
    Future<void> systemBack(bool Function() completed) async {
      final scopes = tester
          .widgetList<Widget>(find.byWidgetPredicate((w) => w is PopScope))
          .cast<PopScope<dynamic>>()
          .map((w) => w.canPop)
          .join(',');
      debugPrint(
        'Final Android QA diagnostic: before-$backSequence-framework=${frameworkBack.lastOrNull}-pop=${backEvents.pops}-keys=${backEvents.keys}-scopes=$scopes',
      );
      debugPrint(
        'Final Android QA before-back: ${router().routeInformationProvider.value.uri.path} focus=${FocusManager.instance.primaryFocus?.hasFocus}',
      );
      debugPrint('Final Android QA request: system-back ${++backSequence}');
      try {
        await until(completed);
      } finally {
        debugPrint(
          'Final Android QA diagnostic: after-$backSequence-framework=${frameworkBack.lastOrNull}-pop=${backEvents.pops}-keys=${backEvents.keys}',
        );
        debugPrint(
          'Final Android QA after-back: ${router().routeInformationProvider.value.uri.path}',
        );
      }
    }

    const patientPaths = [
      '/patient',
      '/patient/reservations',
      '/patient/tickets',
      '/patient/appointments',
      '/patient/profile',
    ];
    var branch = 0;
    for (final label in [
      'Beranda',
      'Reservasi',
      'Tiket Saya',
      'Janji Temu',
      'Profil',
    ]) {
      final destination = find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text(label),
      );
      await tester.tap(destination);
      await tester.pumpAndSettle();
      expect(
        router().routeInformationProvider.value.uri.path,
        patientPaths[branch++],
      );
    }
    debugPrint('Final Android QA PASS: patient-five-navigation');
    await systemBack(
      () => router().routeInformationProvider.value.uri.path == '/patient',
    );
    expect(router().routeInformationProvider.value.uri.path, '/patient');
    router().go('/patient/reservations/new');
    await tester.pumpAndSettle();
    await systemBack(
      () =>
          router().routeInformationProvider.value.uri.path ==
          '/patient/reservations',
    );
    expect(
      router().routeInformationProvider.value.uri.path,
      '/patient/reservations',
    );
    await systemBack(
      () => router().routeInformationProvider.value.uri.path == '/patient',
    );
    expect(router().routeInformationProvider.value.uri.path, '/patient');
    debugPrint('Final Android QA PASS: router-native-back');
    // Recreate the API and widget root, reading the real Android secure store.
    await tester.pumpWidget(const SizedBox.shrink());
    api.dispose();
    api = QueueApi(config: config, sessionStore: store);
    await api.restoreSession();
    expect(api.user?['id'], object(fixture['patient1'])['id']);
    await tester.pumpWidget(QueueBApp(api: api));
    await tester.pumpAndSettle();
    debugPrint('Final Android QA PASS: secure-store-restore');
    await logout();
    await login('patient2');
    expect(api.user?['id'], isNot(object(fixture['patient1'])['id']));
    await logout();
    debugPrint('Final Android QA PASS: patient-account-isolation');
    await login('petugas');
    final scanButton = find.byKey(const ValueKey('staff-scan-fab'));
    await until(
      () =>
          scanButton.evaluate().isNotEmpty &&
          tester.widget<FloatingActionButton>(scanButton).onPressed != null,
      phase: 'staff-snapshot-ready',
    );
    debugPrint('Final Android QA phase: staff-snapshot-ready');
    expect(router().routeInformationProvider.value.uri.path, '/staff');
    await tester.tap(scanButton);
    await until(
      () => find.byType(StaffQrScanner).evaluate().isNotEmpty,
      phase: 'scanner-open',
    );
    debugPrint('Final Android QA phase: camera-startup');
    await until(
      () =>
          find.byType(MobileScanner).evaluate().isNotEmpty &&
          tester
                  .widget<MobileScanner>(find.byType(MobileScanner))
                  .controller
                  ?.value
                  .isRunning ==
              true,
      phase: 'camera-startup',
    );
    final cameraController = tester
        .widget<MobileScanner>(find.byType(MobileScanner))
        .controller!;
    debugPrint('Final Android QA camera-state: running-before-pause');
    final lifecycle = _QaLifecycleRecorder();
    WidgetsBinding.instance.addObserver(lifecycle);
    try {
      debugPrint('Final Android QA request: background-resume');
      await until(
        () =>
            lifecycle.states.contains(AppLifecycleState.paused) &&
            WidgetsBinding.instance.lifecycleState ==
                AppLifecycleState.resumed &&
            cameraController.value.isRunning,
      );
      expect(find.byType(StaffQrScanner), findsOneWidget);
      expect(
        tester.widget<MobileScanner>(find.byType(MobileScanner)).controller,
        same(cameraController),
      );
      debugPrint('Final Android QA camera-state: running-after-resume');
    } finally {
      WidgetsBinding.instance.removeObserver(lifecycle);
    }
    debugPrint('Final Android QA PASS: scanner-background-resume');
    await systemBack(() => find.byType(StaffQrScanner).evaluate().isEmpty);
    expect(find.byType(StaffQrScanner), findsNothing);
    router().go('/staff/profile');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Keluar Akun'));
    await tester.tap(find.text('Keluar Akun'));
    await until(
      () => find.widgetWithText(TextFormField, 'Email').evaluate().isNotEmpty,
    );
    expect(api.user, isNull);
    expect(await store.read(), isNull);
    debugPrint('Final Android QA PASS: nested-profile-ui-logout');
    debugPrint('Final Android QA PASS: scanner-back-nested-logout');
    await login('doctor');
    await until(() => find.text('Dashboard Dokter').evaluate().isNotEmpty);
    expect(router().routeInformationProvider.value.uri.path, '/doctor');
    router().go('/doctor/profile');
    await tester.pumpAndSettle();
    await logout();
    await login('admin');
    await until(() => find.text('Poliklinik').evaluate().isNotEmpty);
    expect(router().routeInformationProvider.value.uri.path, '/admin');
    await logout();
    debugPrint('Final Android QA PASS: operational-role-login-logout');
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(minutes: 6)));
}
