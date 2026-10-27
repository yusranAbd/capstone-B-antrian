import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:queueb_client/src/api.dart';
import 'package:queueb_client/src/app.dart';
import 'package:queueb_client/src/config.dart';
import 'package:queueb_client/src/patient_home.dart';
import 'package:queueb_client/src/patient_mobile_v5.dart';
import 'package:queueb_client/src/patient_reservations.dart';
import 'package:queueb_client/src/user_profile.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:timezone/data/latest.dart' as tz;

import 'patient_home_v3_test.dart' show HomeBackend;

class V5Backend extends HomeBackend {
  @override
  Future<http.Response> handle(http.Request r) async {
    final id = r.url.path.split('/').last;
    if (r.method == 'GET' && r.url.path.contains('/tiket/') && id != 'saya') {
      final item = tickets.where((t) => t['id'] == id).firstOrNull;
      if (item != null) return reply(item);
    }
    return super.handle(r);
  }
}

void main() {
  setUpAll(tz.initializeTimeZones);
  Future<QueueApi> launch(
    WidgetTester t,
    V5Backend b,
    Size size, {
    double scale = 1,
  }) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final api =
        QueueApi(
            config: AppConfig(
              apiBaseUrl: 'http://localhost/api/v1',
              realtime: false,
            ),
            client: MockClient(b.handle),
          )
          ..user = b.user
          ..accessToken = 'test';
    await t.pumpWidget(QueueBApp(api: api));
    await t.pumpAndSettle();
    if (scale != 1) {
      t.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      await t.pumpAndSettle();
    }
    addTearDown(() async {
      await t.pumpWidget(const SizedBox());
      api.dispose();
    });
    return api;
  }

  Future<void> nav(WidgetTester t, String label) async {
    await t.tap(find.widgetWithText(NavigationDestination, label));
    await t.pumpAndSettle();
  }

  for (final size in [
    const Size(320, 568),
    const Size(360, 800),
    const Size(375, 812),
    const Size(390, 844),
    const Size(412, 915),
  ]) {
    for (final scale in [1.0, 1.5]) {
      testWidgets(
        'V5 five tabs, solid visit, floating actions and profile fit $size scale $scale',
        (t) async {
          final b = V5Backend();
          b.tickets.add(b.ticket);
          b.appointments.add(b.appointmentFixture);
          await launch(t, b, size, scale: scale);
          expect(find.byType(NavigationDestination), findsNWidgets(5));
          expect(find.byTooltip('Profil akun'), findsNothing);
          expect(find.byType(PatientHomeIdentity), findsOneWidget);
          expect(
            t
                .widget<Text>(find.text('Bagaimana kabar Anda hari ini?'))
                .style!
                .fontSize,
            lessThanOrEqualTo(20),
          );
          final visit = find.byType(PatientHomeVisit);
          expect(visit, findsOneWidget);
          final surface = t.widget<Container>(
            find.byKey(const ValueKey('patient-nearest-visit')),
          );
          expect((surface.decoration as BoxDecoration).gradient, isNull);
          expect(t.takeException(), isNull);
          await nav(t, 'Reservasi');
          final fab = find.byType(FloatingActionButton);
          expect(fab, findsOneWidget);
          expect(
            t.getBottomLeft(fab).dy,
            lessThanOrEqualTo(t.getTopLeft(find.byType(NavigationBar)).dy),
          );
          final scaffold = t.widget<Scaffold>(
            find.ancestor(of: fab, matching: find.byType(Scaffold)).first,
          );
          expect(scaffold.floatingActionButton, isNotNull);
          await t.tap(fab);
          await t.pumpAndSettle();
          for (final label in [
            'Cari Dokter',
            'Pilih Poliklinik',
            'Jadwal Terdekat',
          ]) {
            expect(find.text(label), findsOneWidget);
          }
          await t.tap(find.byTooltip('Tutup pilihan reservasi'));
          await t.pumpAndSettle();
          await nav(t, 'Tiket Saya');
          expect(find.byType(PatientTicketCard), findsOneWidget);
          await t.ensureVisible(find.text('Lihat Tiket / QR'));
          await t.pumpAndSettle();
          await t.tap(find.text('Lihat Tiket / QR'));
          await t.pumpAndSettle();
          expect(find.text('Tiket UM-001'), findsOneWidget);
          await t.ensureVisible(find.text('Terbitkan QR'));
          await t.tap(find.text('Terbitkan QR'));
          await t.pumpAndSettle();
          expect(find.byType(QrImageView), findsOneWidget);
          await t.tap(find.text('Tutup'));
          await t.pumpAndSettle();
          await nav(t, 'Janji Temu');
          expect(find.text('Janji temu saya'), findsOneWidget);
          await nav(t, 'Profil');
          expect(find.byType(UserProfilePage), findsOneWidget);
          expect(find.text('Profil Saya'), findsOneWidget);
          expect(
            t.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
            4,
          );
          await nav(t, 'Beranda');
          expect(find.byType(PatientHomeWelcome), findsOneWidget);
          expect(t.takeException(), isNull);
        },
      );
    }
  }
  testWidgets(
    'V5 cancelled ticket is historical, list is lazy, filters survive profile and last card clears FAB',
    (t) async {
      final b = V5Backend();
      b.tickets.add({...b.ticket, 'status': 'DIBATALKAN'});
      for (var i = 1; i <= 30; i++) {
        b.tickets.add({
          ...b.ticket,
          'id': 'history-$i',
          'nomorAntrean': 'QA-$i',
          'status': 'SELESAI',
        });
      }
      await launch(t, b, const Size(320, 568));
      expect(find.text('Kunjungan Terdekat'), findsNothing);
      await nav(t, 'Tiket Saya');
      expect(find.byType(PatientTicketCard).evaluate().length, lessThan(31));
      // Search the reservation projection so the cancelled ticket is selected explicitly.
      await nav(t, 'Reservasi');
      await t.enterText(find.byType(TextField), 'UM-001');
      await t.pumpAndSettle();
      await nav(t, 'Profil');
      await nav(t, 'Reservasi');
      expect(
        t.widget<TextField>(find.byType(TextField)).controller!.text,
        'UM-001',
      );
      await t.ensureVisible(find.text('Lihat Detail'));
      await t.pumpAndSettle();
      await t.tap(find.text('Lihat Detail'));
      await t.pumpAndSettle();
      expect(find.byType(QrImageView), findsNothing);
      expect(find.text('Terbitkan QR'), findsNothing);
      expect(b.requests.where((r) => r.$1 == 'POST'), isEmpty);
      await t.tap(find.text('Tutup'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), '');
      await t.pumpAndSettle();
      final scrollable = find.descendant(
        of: find.byKey(const PageStorageKey('reservation-list')),
        matching: find.byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
        ),
      );
      final position = t.state<ScrollableState>(scrollable).position;
      for (var step = 0; step < 6; step++) {
        position.jumpTo(position.maxScrollExtent);
        await t.pumpAndSettle();
      }
      final last = find.byType(ReservationCard).last;
      expect(
        t.getBottomLeft(last).dy,
        lessThan(t.getTopLeft(find.byType(FloatingActionButton)).dy),
      );
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('Profile name input stays above keyboard at 320x568', (t) async {
    await launch(t, V5Backend(), const Size(320, 568));
    await nav(t, 'Profil');
    t.view.viewInsets = const FakeViewPadding(bottom: 240);
    addTearDown(t.view.resetViewInsets);
    await t.pumpAndSettle();
    final field = find.widgetWithText(TextFormField, 'Nama lengkap');
    await t.showKeyboard(field);
    await t.enterText(field, 'Nama Pasien Pengujian');
    await t.ensureVisible(field);
    await t.pumpAndSettle();
    expect(t.getBottomLeft(field).dy, lessThanOrEqualTo(328));
    expect(t.takeException(), isNull);
  });
}
