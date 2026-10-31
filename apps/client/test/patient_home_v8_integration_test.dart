import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:timezone/data/latest.dart' as tz;
import 'package:queueb_client/src/api.dart';
import 'package:queueb_client/src/app.dart';
import 'package:queueb_client/src/config.dart';
import 'package:queueb_client/src/patient.dart';

import 'patient_home_v3_test.dart' show HomeBackend;

class _HoursBackend extends HomeBackend {
  bool failHours = false;
  @override
  Future<http.Response> handle(http.Request request) async {
    if (request.url.path.endsWith('/jadwal-layanan')) {
      requests.add((request.method, '/jadwal-layanan', {}));
      if (failHours) return reply({'message': 'Jadwal tidak tersedia'}, 503);
      const days = [
        'SENIN',
        'SELASA',
        'RABU',
        'KAMIS',
        'JUMAT',
        'SABTU',
        'MINGGU',
      ];
      return reply([
        {
          'id': 'hours',
          'layananId': '22222222-2222-4222-8222-222222222222',
          'hari': days[DateTime.parse(today).weekday - 1],
          'jamBuka': '1970-01-01T08:00:00Z',
          'jamTutup': '1970-01-01T16:00:00Z',
          'aktif': true,
        },
      ]);
    }
    return super.handle(request);
  }
}

void main() {
  setUpAll(tz.initializeTimeZones);
  testWidgets(
    'same-account profile update refreshes greeting without network reads or replacing the owner',
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
            ..accessToken = 'fixture'
            ..user = {...backend.user, 'nama': 'Nama Awal Sesi'};
      await t.pumpWidget(QueueBApp(api: api));
      await t.pumpAndSettle();
      final owner = t.state(find.byType(PatientPage)),
          reads = backend.requests.length;
      expect(find.text('Nama Awal Sesi'), findsOneWidget);
      api.user = {...api.user!, 'nama': 'Nama Profil Terbaru'};
      api.notifyListeners();
      await t.pumpAndSettle();
      expect(find.text('Nama Profil Terbaru'), findsOneWidget);
      expect(find.text('Nama Awal Sesi'), findsNothing);
      expect(t.state(find.byType(PatientPage)), same(owner));
      expect(backend.requests.length, reads);
      await t.pumpWidget(const SizedBox());
      api.dispose();
    },
  );
  for (final fail in [false, true]) {
    testWidgets(
      'Information shares catalog hours and avoids forbidden assignment reads, failure=$fail',
      (t) async {
        final backend = _HoursBackend()..failHours = fail;
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
        final owner = t.state(find.byType(PatientPage)),
            initial = backend.requests.length;
        expect(
          backend.requests.where((r) => r.$2 == '/jadwal-layanan'),
          hasLength(1),
        );
        if (fail) {
          expect(find.text('Jam & petugas belum tersedia'), findsOneWidget);
        } else {
          expect(find.textContaining('08.00–16.00'), findsOneWidget);
        }
        await t.tap(find.widgetWithText(NavigationDestination, 'Informasi'));
        await t.pumpAndSettle();
        expect(find.text('Informasi layanan'), findsOneWidget);
        expect(backend.requests.length, initial);
        expect(t.state(find.byType(PatientPage)), same(owner));
        if (fail) {
          expect(
            find.text(
              'Jam operasional belum dapat dimuat. Coba muat ulang informasi.',
            ),
            findsOneWidget,
          );
          backend.failHours = false;
          await t.tap(find.byTooltip('Muat ulang informasi'));
          await t.pumpAndSettle();
          expect(
            backend.requests.where((r) => r.$2 == '/jadwal-layanan'),
            hasLength(2),
          );
        }
        expect(find.text('08.00–16.00'), findsOneWidget);
        expect(
          backend.requests.where((r) => r.$2.startsWith('/penugasan-petugas')),
          isEmpty,
        );
        expect(backend.requests.where((r) => r.$1 != 'GET'), isEmpty);
        await t.pumpWidget(const SizedBox());
        api.dispose();
      },
    );
  }
}
