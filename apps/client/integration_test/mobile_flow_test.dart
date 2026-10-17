import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:queueb_client/src/api.dart';
import 'package:queueb_client/src/app.dart';
import 'package:queueb_client/src/config.dart';

// Instrumentation only. Ephemeral credentials are supplied in memory by the
// loopback test harness, never bundled in the application or written to Git.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Android: seven screens, appointment and walk-in through COMPLETE',
    (tester) async {
      tz.initializeTimeZones();
      final response = await http.get(
        Uri.parse('http://127.0.0.1:3002/fixture'),
      );
      expect(response.statusCode, 200);
      final fixture = object(jsonDecode(response.body));
      final api = QueueApi(config: AppConfig.fromEnvironment());
      await tester.pumpWidget(QueueBApp(api: api));
      await binding.convertFlutterSurfaceToImage();
      await tester.pumpAndSettle();
      addTearDown(api.dispose);

      Future<void> reveal(Finder target) async {
        if (target.evaluate().isEmpty) {
          await tester.drag(
            find.byType(Scrollable).first,
            const Offset(0, 5000),
          );
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            target,
            300,
            scrollable: find.byType(Scrollable).first,
          );
        }
        await tester.ensureVisible(target);
        await tester.pumpAndSettle();
      }

      Future<void> press(String text, {Type? type}) async {
        final base = type == null
            ? find.text(text)
            : find.widgetWithText(type, text);
        if (base.evaluate().isEmpty) {
          await tester.drag(
            find.byType(Scrollable).first,
            const Offset(0, 5000),
          );
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            base,
            300,
            scrollable: find.byType(Scrollable).first,
          );
        }
        final finder = base.last;
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
        await tester.tap(finder);
        await tester.pumpAndSettle(
          const Duration(milliseconds: 100),
          EnginePhase.sendSemanticsUpdate,
          const Duration(seconds: 40),
        );
      }

      Future<void> capture(String name) async {
        await tester.pumpAndSettle();
        debugPrint('Android QA: $name');
        final bytes = await binding.takeScreenshot(name);
        final saved = await http.post(
          Uri.parse('http://127.0.0.1:3002/capture/$name'),
          body: bytes,
        );
        expect(saved.statusCode, 201);
      }

      Future<void> login(String account) async {
        final user = object(fixture[account]);
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Email'),
          '${user['email']}',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Kata sandi'),
          '${user['password']}',
        );
        await press('Masuk', type: FilledButton);
      }

      Future<void> logout() async {
        await tester.tap(find.byTooltip('Keluar akun'));
        await tester.pumpAndSettle();
      }

      Future<void> select(String text) async {
        await tester.ensureVisible(find.text(text).last);
        await tester.tap(find.text(text).last);
        await tester.pumpAndSettle();
      }

      Future<void> clinic() async {
        await press('Pendaftaran');
        final dropdown = find.byType(DropdownButtonFormField<String>).first;
        await tester.ensureVisible(dropdown);
        await tester.pumpAndSettle();
        await tester.tap(dropdown);
        await tester.pumpAndSettle();
        await select('${fixture['serviceCode']} · Poli Fixture Flutter');
      }

      Future<(Json, String)> ticketAndQR() async {
        final tickets = rows(await api.request('GET', '/tiket/saya'));
        final ticket = tickets.single;
        await press('Lihat tiket / QR');
        await press('Terbitkan QR');
        final texts = tester.widgetList<SelectableText>(
          find.byType(SelectableText),
        );
        final payload = texts
            .map((t) => t.data ?? '')
            .singleWhere((t) => t.startsWith('SQ1.'));
        return (ticket, payload);
      }

      await capture('01-login');
      await login('patient1');
      await capture('02-beranda');
      await clinic();
      await press('Walk-in');
      await press('Reservasi walk-in');
      await press('Lanjutkan');
      final (walk, walkQR) = await ticketAndQR();
      await press('Tutup');
      await logout();

      await login('patient2');
      await clinic();
      await capture('03-poliklinik-dokter');
      await press('Lihat Jadwal');
      await capture('07-detail-dokter');
      await press('Lihat slot');
      await press('Sisa slot 2');
      await tester.ensureVisible(find.text('Slot konsultasi'));
      await capture('04-booking-slot');
      await press('Booking janji temu');
      await press('Lanjutkan');
      final (appointment, appointmentQR) = await ticketAndQR();
      await capture('05-tiket-qr');
      await press('Tutup');
      await logout();

      await login('petugas');
      await press('Pindai kamera');
      final scanner = tester.widget<MobileScanner>(find.byType(MobileScanner));
      final deadline = DateTime.now().add(const Duration(seconds: 20));
      while (!scanner.controller!.value.isRunning &&
          DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(scanner.controller!.value.hasCameraPermission, isTrue);
      expect(scanner.controller!.value.isRunning, isTrue);
      await press('Tutup');

      for (final qr in [walkQR, appointmentQR]) {
        final input = find.widgetWithText(TextField, 'Payload QR (SQ1…)');
        await reveal(input);
        await tester.enterText(input, qr);
        await press('Check-In', type: FilledButton);
        await press('Masuk Antrean', type: TextButton);
      }
      final start = DateTime.parse('${fixture['slotStart']}');
      while (DateTime.now().isBefore(start)) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      await press('Panggil berikutnya');
      expect(find.text('${appointment['nomorAntrean']}'), findsWidgets);
      await tester.ensureVisible(find.text('Pelayanan ruang ini'));
      await capture('06-petugas');
      await press('Panggil Ulang');
      await press('Lewati');
      await press('Antre Ulang', type: TextButton);
      await press('Panggil berikutnya');
      await press('Mulai Pelayanan');
      await press('Selesaikan Pelayanan');
      await press('Panggil berikutnya');
      expect(find.text('${walk['nomorAntrean']}'), findsWidgets);
      await press('Mulai Pelayanan');
      await press('Selesaikan Pelayanan');
      await logout();
      for (final account in ['patient1', 'patient2']) {
        await login(account);
        await press('Tiket Saya');
        expect(find.text('SELESAI'), findsOneWidget);
        await logout();
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
