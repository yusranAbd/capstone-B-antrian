import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:queueb_client/src/api.dart';
import 'package:queueb_client/src/app.dart';

import 'patient_home_v3_test.dart' show HomeBackend;

import 'package:queueb_client/src/config.dart';
import 'package:queueb_client/src/mobile_ui.dart';
import 'package:queueb_client/src/patient_agenda.dart';
import 'package:queueb_client/src/patient_design.dart';
import 'package:queueb_client/src/patient_ui.dart';
import 'package:timezone/data/latest.dart' as tz;

void main() {
  setUpAll(tz.initializeTimeZones);
  double contrast(Color a, Color b) {
    final x = a.computeLuminance(), y = b.computeLuminance();
    return x > y ? (x + .05) / (y + .05) : (y + .05) / (x + .05);
  }

  test('Blue periwinkle readable text and status pairs meet WCAG AA', () {
    for (final pair in [
      (PatientDesign.ink, PatientDesign.paper),
      (PatientDesign.muted, PatientDesign.paper),
      (PatientDesign.muted, PatientDesign.background),
      (Colors.white, PatientDesign.primary),
      (Colors.white, PatientDesign.hero),
      (Colors.white, PatientDesign.accent),
      for (final state in [
        'DIPESAN',
        'CHECK_IN',
        'MENUNGGU',
        'DIPANGGIL',
        'DILAYANI',
        'DILEWATI',
        'SELESAI',
        'DIBATALKAN',
      ])
        (PatientDesign.statusInk(state), PatientDesign.statusSurface(state)),
    ]) {
      expect(
        contrast(pair.$1, pair.$2),
        greaterThanOrEqualTo(4.5),
        reason: '${pair.$1} on ${pair.$2}',
      );
    }
    expect(PatientDesign.primary, const Color(0xff4c60cc));
    expect(PatientDesign.hero, const Color(0xff4169d5));
    expect(PatientDesign.background, const Color(0xfff2f5ff));
    expect(PatientDesign.theme.extension<PatientAppearance>(), isNotNull);
    expect(QueueBStyle.theme.extension<PatientAppearance>(), isNull);
    expect(QueueBStyle.teal, const Color(0xff009f9a));
  });
  test(
    '5xx errors keep status, suppress server internals and never retry',
    () async {
      var calls = 0;
      final api = QueueApi(
        config: AppConfig(
          apiBaseUrl: 'https://fixture.invalid/api/v1',
          realtime: false,
        ),
        client: MockClient((_) async {
          calls++;
          return http.Response(
            jsonEncode({'message': 'Prisma SQL password=private stack trace'}),
            500,
          );
        }),
      );
      addTearDown(api.dispose);
      await expectLater(
        api.request('POST', '/reservasi', body: {'layananId': 'fixture'}),
        throwsA(
          isA<ApiException>()
              .having((e) => e.status, 'status', 500)
              .having(
                (e) => e.toString(),
                'message',
                allOf(
                  contains('Layanan sedang mengalami gangguan'),
                  isNot(contains('private')),
                  isNot(contains('Prisma')),
                ),
              ),
        ),
      );
      expect(calls, 1);
    },
  );
  testWidgets('Patient dialogs and bottom sheets inherit the scoped palette', (
    t,
  ) async {
    final backend = HomeBackend();
    backend.tickets.add(backend.ticket);
    final api =
        QueueApi(
            config: AppConfig(
              apiBaseUrl: 'http://localhost/api/v1',
              realtime: false,
            ),
            client: MockClient(backend.handle),
          )
          ..user = backend.user
          ..accessToken = 'fixture';
    await t.pumpWidget(QueueBApp(api: api));
    await t.pumpAndSettle();
    addTearDown(() async {
      await t.pumpWidget(const SizedBox());
      api.dispose();
    });
    await t.tap(find.widgetWithText(NavigationDestination, 'Reservasi'));
    await t.pumpAndSettle();
    await t.tap(find.byType(FloatingActionButton));
    await t.pumpAndSettle();
    expect(
      Theme.of(t.element(find.text('Pilih cara membuat reservasi.')))
          .colorScheme
          .primary,
      PatientDesign.primary,
    );
    await t.tap(find.byTooltip('Tutup pilihan reservasi'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(NavigationDestination, 'Tiket Saya'));
    await t.pumpAndSettle();
    await t.tap(find.text('Lihat Tiket / QR'));
    await t.pumpAndSettle();
    expect(
      Theme.of(t.element(find.byType(AlertDialog))).colorScheme.primary,
      PatientDesign.primary,
    );
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'Home search text and filter remain aligned across tabs and can be cleared',
    (t) async {
      final backend = HomeBackend();
      final api =
          QueueApi(
              config: AppConfig(
                apiBaseUrl: 'http://localhost/api/v1',
                realtime: false,
              ),
              client: MockClient(backend.handle),
            )
            ..user = backend.user
            ..accessToken = 'fixture';
      await t.pumpWidget(QueueBApp(api: api));
      await t.pumpAndSettle();
      addTearDown(() async {
        await t.pumpWidget(const SizedBox());
        api.dispose();
      });
      final search = find.widgetWithText(
        TextField,
        'Cari dokter, poliklinik, atau layanan...',
      );
      await t.enterText(search, 'tidak-ada-dokter');
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(NavigationDestination, 'Tiket Saya'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(NavigationDestination, 'Beranda'));
      await t.pumpAndSettle();
      expect(t.widget<TextField>(search).controller!.text, 'tidak-ada-dokter');
      await t.tap(find.byTooltip('Bersihkan pencarian'));
      await t.pumpAndSettle();
      expect(t.widget<TextField>(search).controller!.text, '');
      expect(t.takeException(), isNull);
    },
  );
  for (final width in [320.0, 390.0]) {
    testWidgets(
      'Agenda uses actual dates, filters without mutating and supports large text at $width',
      (t) async {
        t.view.physicalSize = Size(width, 844);
        t.view.devicePixelRatio = 1;
        t.platformDispatcher.textScaleFactorTestValue = 1.5;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        final config = AppConfig(
          apiBaseUrl: 'https://fixture.invalid/api/v1',
          realtime: false,
        );
        final appointments = <Json>[];
        for (var i = 0; i < 20; i++) {
          final day = calendarDate(
            DateTime.parse(config.today).add(Duration(days: i)),
          );
          appointments.add({
            'id': 'visit-$i',
            'tiket': {
              'id': 'ticket-$i',
              'status': 'DIPESAN',
              'tanggalPelayanan': day,
            },
            'slotPraktik': {
              'mulaiPada': '${day}T01:00:00Z',
              'selesaiPada': '${day}T01:30:00Z',
              'jadwalPraktik': {
                'tanggal': day,
                'loket': {'nama': 'Ruang Anak 1'},
                'dokterLayanan': {
                  'dokter': {
                    'nama': 'Dokter dengan Nama Sangat Panjang untuk Pengujian',
                  },
                  'layanan': {'nama': 'Poliklinik Anak'},
                },
              },
            },
          });
        }
        final selected = <String>[];
        await t.pumpWidget(
          MaterialApp(
            theme: PatientDesign.theme,
            home: Scaffold(
              body: PatientAgenda(
                appointments: appointments,
                config: config,
                loading: false,
                busy: false,
                onRefresh: () {},
                onTicket: (ticket) => selected.add('${ticket['id']}'),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        final chip = find.widgetWithText(
          ChoiceChip,
          patientCompactDate(config.today),
        );
        await t.ensureVisible(chip);
        await t.pumpAndSettle();
        await t.tap(chip);
        await t.pumpAndSettle();
        expect(find.text('08:00 – 08:30'), findsOneWidget);
        final action = find.text('Lihat tiket');
        await t.ensureVisible(action);
        await t.pumpAndSettle();
        await t.tap(action);
        expect(selected, ['ticket-0']);
        expect(appointments.length, 20);
        expect(t.takeException(), isNull);
      },
    );
  }
}
