import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:queueb_client/src/api.dart';
import 'package:queueb_client/src/app.dart';
import 'package:queueb_client/src/config.dart';
import 'package:queueb_client/src/session_store.dart';
import 'package:timezone/data/latest.dart' as tz;

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
    await tester.pumpWidget(QueueBApp(api: api));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      api.dispose();
    });

    Future<void> until(bool Function() ready) async {
      final deadline = DateTime.now().add(const Duration(seconds: 40));
      while (!ready()) {
        if (DateTime.now().isAfter(deadline)) {
          fail('Android QA condition not reached; no credential diagnostics');
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
      final submit = find.widgetWithText(FilledButton, 'Masuk');
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await until(
        () => api.user != null && api.sessionPhase == SessionPhase.ready,
      );
      expect(api.user?['id'], user['id']);
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
    }
    debugPrint('Final Android QA PASS: patient-five-navigation');
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
    await until(() => find.text('Pindai QR').evaluate().isNotEmpty);
    await logout();
    await login('doctor');
    await until(() => find.text('Dashboard Dokter').evaluate().isNotEmpty);
    await logout();
    await login('admin');
    await until(() => find.text('Poliklinik').evaluate().isNotEmpty);
    await logout();
    debugPrint('Final Android QA PASS: operational-role-login-logout');
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(minutes: 6)));
}
