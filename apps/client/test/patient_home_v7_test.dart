import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:queueb_client/src/api.dart';
import 'package:queueb_client/src/app.dart';
import 'package:queueb_client/src/config.dart';
import 'package:queueb_client/src/features/patient/application/patient_overview_cubit.dart';
import 'package:queueb_client/src/patient.dart';
import 'package:queueb_client/src/patient_design.dart';
import 'package:queueb_client/src/patient_home_v6.dart';
import 'package:queueb_client/src/patient_home_v7.dart';
import 'package:queueb_client/src/user_profile.dart';

import 'patient_home_v3_test.dart' show HomeBackend;
import 'routing_portals_test.dart' show Owners;

const _registration = <String, dynamic>{
  'id': 'registration',
  'kode': 'PENDAFTARAN',
  'nama': 'Pendaftaran',
  'modeReservasi': 'ANTREAN_HARIAN',
};

class _V7Backend extends HomeBackend {
  @override
  Future<http.Response> handle(http.Request request) async {
    if (request.url.path.endsWith('/layanan')) {
      return reply([
        service,
        for (final code in ['APOTEK', 'ADMINISTRASI', 'PENDAFTARAN', 'APOTIK'])
          {
            ...service,
            'id': code == 'PENDAFTARAN'
                ? '22222222-2222-4222-8222-222222222222'
                : code,
            'kode': code,
            'nama': code == 'PENDAFTARAN' ? 'Pendaftaran' : code,
            'modeReservasi': 'ANTREAN_HARIAN',
          },
      ]);
    }
    return super.handle(request);
  }
}

class _IdentityApi extends QueueApi {
  _IdentityApi(http.Client client)
    : super(
        config: AppConfig(apiBaseUrl: 'http://localhost/api/v1'),
        client: client,
      );
  void replaceUser(Json? next) {
    user = next;
    notifyListeners();
  }
}

void main() {
  setUpAll(tz.initializeTimeZones);

  test(
    'registration moves first without fabricating or reordering other rows',
    () {
      final rows = <Json>[
        {'id': 'a', 'kode': 'APOTEK', 'modeReservasi': 'HIBRIDA'},
        {'id': 'b', 'kode': 'ADMINISTRASI', 'modeReservasi': 'HIBRIDA'},
        _registration,
        {'id': 'c', 'kode': 'APOTIK', 'modeReservasi': 'ANTREAN_HARIAN'},
        {'id': 'd', 'kode': 'POLI_UMUM', 'modeReservasi': 'HIBRIDA'},
      ];
      final before = [...rows];
      expect(homeWalkInClinics(rows, [], '').map((c) => c['id']), [
        'registration',
        'a',
        'b',
        'c',
      ]);
      expect(rows, orderedEquals(before));
      expect(homeWalkInClinics(rows, [], 'apot').map((c) => c['id']), [
        'a',
        'c',
      ]);
      expect(homeWalkInClinics([rows.first], [], ''), [rows.first]);
      expect(homeWalkInClinics([], [], ''), isEmpty);
      expect(rows.where(supportsHomeAppointment).map((c) => c['id']), ['d']);
    },
  );

  test(
    'category uses the catalog code and readable ink, never a free name',
    () {
      final cases = {
        'PENDAFTARAN': (PatientServiceCategory.registration, 0xff10b981),
        'APOTEK': (PatientServiceCategory.pharmacy, 0xff3b82f6),
        'POLI_UMUM': (PatientServiceCategory.general, 0xff8b5cf6),
        'POLI_GIGI': (PatientServiceCategory.dental, 0xfff59e0b),
      };
      for (final entry in cases.entries) {
        final category = homeServiceCategory({'kode': entry.key.toLowerCase()});
        expect(category, entry.value.$1);
        expect(PatientServiceAccent.color(category), Color(entry.value.$2));
        final surface = Color.alphaBlend(
          PatientServiceAccent.color(category).withValues(alpha: .06),
          Colors.white,
        );
        expect(
          (surface.computeLuminance() + .05) /
              (PatientServiceAccent.ink(category).computeLuminance() + .05),
          greaterThanOrEqualTo(4.5),
        );
      }
      expect(
        homeServiceCategory({'nama': 'Pendaftaran'}),
        PatientServiceCategory.other,
      );
      expect(
        PatientServiceAccent.color(PatientServiceCategory.other),
        PatientDesign.primary,
      );
    },
  );

  test(
    'personal number requires a valid scoped ticket for this service and day',
    () {
      const ticket = <String, dynamic>{
        'id': 'ticket',
        'layananId': 'registration',
        'penggunaId': 'patient',
        'tanggalPelayanan': '2026-10-30',
        'status': 'MENUNGGU',
        'nomorAntrean': 'PEN-008',
      };
      Json? select(Json row, {String? userId = 'patient'}) =>
          homeServiceTicket([row], 'registration', '2026-10-30', userId);
      expect(select(ticket), same(ticket));
      final scoped = {...ticket}..remove('penggunaId');
      expect(
        select(scoped),
        same(scoped),
      ); // /tiket/saya already enforces ownership.
      for (final invalid in <Json>[
        {...ticket, 'id': ''},
        {...ticket, 'id': null},
        {...ticket, 'penggunaId': 'other'},
        {...ticket, 'layananId': 'other'},
        {...ticket, 'tanggalPelayanan': '2026-10-31'},
        {...ticket, 'nomorAntrean': '  '},
        for (final status in ['SELESAI', 'DIBATALKAN', 'UNKNOWN', null])
          {...ticket, 'status': status},
      ]) {
        expect(select(invalid), isNull);
      }
      expect(select(ticket, userId: null), isNull);
      expect(select(ticket, userId: ''), isNull);
      expect(
        homeServiceTicket([], 'registration', '2026-10-30', 'patient'),
        isNull,
      );
    },
  );

  testWidgets(
    'one card action covers header and facts, keyboard and semantics',
    (t) async {
      var taps = 0;
      final semantics = t.ensureSemantics();
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: PatientServiceCardV7(
                clinic: _registration,
                onTap: () => taps++,
              ),
            ),
          ),
        ),
      );
      final card = find.byType(PatientServiceCardV7);
      expect(
        find.descendant(of: card, matching: find.byType(InkWell)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text('Pantau Live')),
        findsNothing,
      );
      expect(
        find.descendant(of: card, matching: find.text('Ambil Antrean')),
        findsNothing,
      );
      expect(find.text('Live'), findsNothing);
      expect(find.text('Belum tersedia'), findsOneWidget);
      final action = find.bySemanticsLabel(
        RegExp('Pendaftaran.*Belum ada tiket'),
      );
      expect(
        t
            .getSemantics(action)
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isTrue,
      );
      await t.tap(find.text('Pendaftaran'));
      await t.pumpAndSettle();
      expect(taps, 1);
      await t.tap(find.text('Total hari ini'));
      await t.pumpAndSettle();
      expect(taps, 2);
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pumpAndSettle();
      final material = t.widget<Material>(
        find.descendant(of: card, matching: find.byType(Material)).first,
      );
      expect((material.shape! as RoundedRectangleBorder).side.width, 2);
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pumpAndSettle();
      expect(taps, 3);
      expect(t.takeException(), isNull);
      semantics.dispose();
    },
  );

  testWidgets(
    'only an explicitly supplied personal ticket is labeled personal',
    (t) async {
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                PatientServiceCardV7(
                  clinic: {
                    ..._registration,
                    'nomorAntrean': 'GLOBAL-999',
                    'total': 42,
                    'menunggu': 31,
                  },
                ),
                const PatientServiceCardV7(
                  clinic: _registration,
                  ticket: {'nomorAntrean': 'PEN-008'},
                ),
              ],
            ),
          ),
        ),
      );
      expect(find.text('GLOBAL-999'), findsNothing);
      expect(find.text('42'), findsNothing);
      expect(find.text('31 menunggu'), findsNothing);
      expect(find.text('Nomor Antreanmu'), findsOneWidget);
      expect(find.text('PEN-008'), findsOneWidget);
      expect(find.text('Belum ada tiket'), findsOneWidget);
    },
  );

  for (final width in [320.0, 360.0, 390.0, 430.0, 768.0, 1366.0]) {
    for (final scale in [1.0, 1.3, 1.5, 2.0]) {
      testWidgets('card and personal header fit width $width text $scale', (
        t,
      ) async {
        t.view.physicalSize = Size(width, 1000);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        var reads = 0;
        final api =
            QueueApi(
                config: AppConfig(
                  apiBaseUrl: 'http://localhost/api/v1',
                  realtime: false,
                ),
                client: MockClient((_) async {
                  reads++;
                  return http.Response('{}', 200);
                }),
              )
              ..user = {
                'id': 'patient',
                'nama': 'Nama Pasien Sangat Panjang dengan Banyak Bagian',
              };
        addTearDown(api.dispose);
        await t.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Builder(
                builder: (context) => Scaffold(
                  appBar: PatientHomeAppBarV7(
                    api: api,
                    height: PatientHomeAppBarV7.heightFor(context),
                    onProfile: () {},
                    onNotifications: () {},
                  ),
                  body: SingleChildScrollView(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 760),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: PatientServiceCardV7(
                            clinic: {
                              ..._registration,
                              'nama': 'Layanan Pendaftaran Administrasi Rawat Jalan dengan Nama Panjang',
                            },
                            ticket: const {
                              'nomorAntrean':
                                  'PENDAFTARAN-12345678901234567890',
                            },
                            onTap: () {},
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(find.text('Selamat datang,'), findsOneWidget);
        expect(find.byTooltip('Notifikasi').hitTestable(), findsOneWidget);
        expect(find.byTooltip('Profil pasien').hitTestable(), findsOneWidget);
        expect(reads, 0);
        final card = t.getRect(find.byType(PatientServiceCardV7));
        final number = t.getRect(find.text('PENDAFTARAN-12345678901234567890'));
        expect(card.contains(number.topLeft), isTrue);
        expect(card.contains(number.bottomRight), isTrue);
      });
    }
  }

  testWidgets(
    'AppBar identity updates and clears without duplicate profile reads',
    (t) async {
      var reads = 0, profiles = 0, notifications = 0;
      final api = _IdentityApi(
        MockClient((_) async {
          reads++;
          return http.Response('{}', 200);
        }),
      );
      addTearDown(api.dispose);
      api.replaceUser({'id': 'a', 'nama': 'Pasien Pertama'});
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: PatientHomeAppBarV7(
              api: api,
              height: 66,
              onProfile: () => profiles++,
              onNotifications: () => notifications++,
            ),
          ),
        ),
      );
      expect(find.text('Pasien Pertama'), findsOneWidget);
      expect(find.byType(AccountAvatar), findsOneWidget);
      expect(find.text('QueueB Hospital'), findsNothing);
      await t.tap(find.byTooltip('Profil pasien'));
      await t.tap(find.byTooltip('Notifikasi'));
      expect(profiles, 1);
      expect(notifications, 1);
      api.replaceUser({'id': 'b', 'nama': 'Pasien Kedua'});
      await t.pumpAndSettle();
      expect(find.text('Pasien Pertama'), findsNothing);
      expect(find.text('Pasien Kedua'), findsOneWidget);
      api.replaceUser(null);
      await t.pumpAndSettle();
      expect(find.text('Pasien Kedua'), findsNothing);
      expect(find.text('Pasien'), findsOneWidget);
      expect(reads, 0);
    },
  );

  testWidgets(
    'real Home scroll retains owners, opens one existing flow, avatar and safe bell',
    (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final previous = Bloc.observer, owners = Owners();
      Bloc.observer = owners;
      addTearDown(() => Bloc.observer = previous);
      final backend = _V7Backend();
      var reads = 0;
      final api =
          QueueApi(
              config: AppConfig(
                apiBaseUrl: 'http://localhost/api/v1',
                realtime: false,
              ),
              client: MockClient((request) {
                reads++;
                return backend.handle(request);
              }),
            )
            ..accessToken = 'test'
            ..user = backend.user;
      addTearDown(api.dispose);
      await t.pumpWidget(QueueBApp(api: api));
      await t.pumpAndSettle();
      final host = t.state(find.byType(PatientPage));
      final overview = owners.created.whereType<PatientOverviewCubit>().single;
      final repository = overview.repository,
          feed = overview.repository.updates;
      final originalOwners = [...owners.created], initialReads = reads;
      final top = find.byKey(const ValueKey('patient-chrome-top'));
      final bottom = find.byKey(const ValueKey('patient-chrome-bottom'));
      final list = find.byKey(const PageStorageKey('home-walk-in-list'));
      final first = t.widget<PatientServiceCardV7>(
        find.byType(PatientServiceCardV7).first,
      );
      expect(first.clinic['kode'], 'PENDAFTARAN');
      expect(t.getSize(top).height, greaterThan(0));
      await t.drag(list, const Offset(0, -350));
      await t.pumpAndSettle();
      expect(t.getSize(top).height, 0);
      expect(t.getSize(bottom).height, 0);
      await t.drag(list, const Offset(0, 250));
      await t.pumpAndSettle();
      expect(t.getSize(top).height, greaterThan(0));
      expect(t.getSize(bottom).height, greaterThan(0));
      expect(t.state(find.byType(PatientPage)), same(host));
      expect(overview.repository, same(repository));
      expect(repository.updates, same(feed));
      expect(owners.created, orderedEquals(originalOwners));
      expect(owners.closed, isEmpty);
      expect(reads, initialReads);
      await t.drag(list, const Offset(0, 1800));
      await t.pumpAndSettle();
      await t.tap(find.text('Pendaftaran').first);
      await t.pumpAndSettle();
      expect(find.text('Reservasi walk-in'), findsOneWidget);
      expect(backend.requests.where((r) => r.$1 == 'POST'), isEmpty);
      await t.tap(find.widgetWithText(NavigationDestination, 'Beranda'));
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Notifikasi'));
      await t.pumpAndSettle();
      expect(
        find.text(
          'Notifikasi belum tersedia. Periksa status terbaru melalui Tiket Saya.',
        ),
        findsOneWidget,
      );
      await t.tap(find.text('Tutup'));
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Profil pasien'));
      await t.pumpAndSettle();
      expect(find.byType(UserProfilePage), findsOneWidget);
      expect(backend.requests.where((r) => r.$1 == 'POST'), isEmpty);
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
      expect(owners.created.every((owner) => owner.isClosed), isTrue);
      expect(t.takeException(), isNull);
    },
  );
}
