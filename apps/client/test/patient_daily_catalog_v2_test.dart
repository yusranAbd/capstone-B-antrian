import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:queueb_client/src/api.dart';
import 'package:queueb_client/src/app.dart';
import 'package:queueb_client/src/config.dart';
import 'package:queueb_client/src/patient_home_v6.dart';
import 'package:queueb_client/src/patient_home_v7.dart';

import 'patient_home_v3_test.dart' show HomeBackend;

const dailyNames = [
  'Pendaftaran',
  'Apotek',
  'Laboratorium',
  'Radiologi',
  'Kasir/Pembayaran',
  'Rekam Medis',
];
List<Json> dailyCatalog() => [
  for (var n = 0; n < patientDailyServiceOrder.length; n++)
    {
      'id': '30000000-0000-4000-8000-${(n + 1).toString().padLeft(12, '0')}',
      'kode': patientDailyServiceOrder[n],
      'nama': dailyNames[n],
      'aktif': true,
      'modeReservasi': 'ANTREAN_HARIAN',
    },
];

void main() {
  setUpAll(tz.initializeTimeZones);

  test('six supported backend identities are stably ordered without catalog fabrication', () {
    final catalog = dailyCatalog().reversed.toList();
    final original = [...catalog];
    final ordered = homeWalkInClinics(catalog, [], '');
    expect(ordered.map((s) => s['kode']), patientDailyServiceOrder);
    expect(
      ordered.map((s) => s['id']).toSet(),
      catalog.map((s) => s['id']).toSet(),
    );
    expect(catalog, orderedEquals(original));
    expect(
      homeWalkInClinics(catalog, [], 'radiologi').single['kode'],
      'RADIOLOGI',
    );
    expect(homeWalkInClinics([], [], ''), isEmpty);
    final other = <Json>[
      {'kode': 'ZZ'},
      {'kode': 'UMUM'},
      ...catalog,
      {'kode': 'YY'},
    ];
    expect(registrationFirst(other).skip(6).map((s) => s['kode']), [
      'ZZ',
      'UMUM',
      'YY',
    ]);
  });

  test('active mode and category are required; names never grant unsupported booking', () {
    for (final service in dailyCatalog()) {
      expect(supportsHomeWalkIn(service), isTrue);
      expect(supportsHomeAppointment(service), isFalse);
      expect(supportsHomeWalkIn({...service, 'aktif': false}), isFalse);
      expect(
        supportsHomeWalkIn({...service, 'modeReservasi': 'JANJI_TEMU_DOKTER'}),
        isFalse,
      );
      expect(
        supportsHomeWalkIn({...service, 'modeReservasi': 'UNKNOWN'}),
        isFalse,
      );
    }
    expect(
      supportsHomeWalkIn({
        'nama': 'Laboratorium',
        'kode': 'UNKNOWN',
        'modeReservasi': 'ANTREAN_HARIAN',
      }),
      isFalse,
    );
    expect(
      supportsHomeAppointment({
        'kode': 'BEDAH',
        'aktif': true,
        'modeReservasi': 'ANTREAN_HARIAN',
      }),
      isTrue,
    );
    expect(
      homeWalkInClinics(
        [
          {'kode': 'REGISTRASI', 'modeReservasi': 'HIBRIDA'},
          {'kode': 'APOTIK', 'modeReservasi': 'ANTREAN_HARIAN'},
        ],
        [],
        '',
      ).length,
      2,
    );
  });

  for (var index = 2; index < patientDailyServiceOrder.length; index++) {
    testWidgets(
      '${patientDailyServiceOrder[index]} opens the existing reservation route without mutation',
      (t) async {
        t.view.physicalSize = const Size(390, 844);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final backend = HomeBackend();
        final catalog = dailyCatalog();
        var posts = 0;
        final api = QueueApi(
          config: AppConfig(
            apiBaseUrl: 'http://localhost/api/v1',
            realtime: false,
          ),
          client: MockClient((r) async {
            if (r.method == 'POST') posts++;
            if (r.url.path.endsWith('/layanan')) {
              return http.Response(jsonEncode(catalog), 200);
            }
            if (r.url.path.endsWith('/layanan/antrean')) {
              return http.Response(
                jsonEncode({
                  'versiSkema': 1,
                  'tanggalPelayanan': r.url.queryParameters['tanggal'],
                  'diperolehPada': DateTime.now().toUtc().toIso8601String(),
                  'layanan': [
                    for (final id in r.url.queryParameters['layananId']!.split(
                      ',',
                    ))
                      {
                        'layananId': id,
                        'totalCheckIn': 0,
                        'jumlahMenunggu': 0,
                        'sedangDilayani': [],
                      },
                  ],
                }),
                200,
              );
            }
            return backend.handle(r);
          }),
        )..accessToken = 'fixture';
        api.user = backend.user;
        await t.pumpWidget(QueueBApp(api: api));
        await t.pumpAndSettle();
        await t.enterText(find.byType(TextField).first, dailyNames[index]);
        await t.pumpAndSettle();
        expect(find.byType(PatientServiceCardV7), findsOneWidget);
        expect(posts, 0);
        await t.tap(find.byType(PatientServiceCardV7));
        await t.pumpAndSettle();
        final router =
            t.widget<MaterialApp>(find.byType(MaterialApp)).routerConfig!
                as GoRouter;
        expect(
          router.routeInformationProvider.value.uri.path,
          '/patient/reservations/new',
        );
        expect(find.textContaining(dailyNames[index]), findsWidgets);
        expect(posts, 0);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        api.dispose();
      },
    );
  }

  for (final size in const [
    Size(320, 568),
    Size(360, 800),
    Size(390, 844),
    Size(412, 915),
    Size(1280, 720),
    Size(1366, 768),
    Size(1440, 900),
    Size(1920, 1080),
  ]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'six V7 cards retain honest fallback and touch action at $size scale $scale',
        (t) async {
          t.view.physicalSize = size;
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.resetPhysicalSize);
          addTearDown(t.view.resetDevicePixelRatio);
          await t.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: Scaffold(
                  body: SingleChildScrollView(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 760),
                        child: Column(
                          children: [
                            for (final service in dailyCatalog())
                              PatientServiceCardV7(
                                clinic: service,
                                onTap: () {},
                              ),
                          ],
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
          expect(find.byType(PatientServiceCardV7), findsNWidgets(6));
          expect(find.text('Live'), findsNothing);
          expect(find.text('Nomor Antreanmu'), findsNWidgets(6));
          expect(find.byIcon(Icons.science_outlined), findsOneWidget);
          expect(find.byIcon(Icons.image_outlined), findsOneWidget);
          expect(find.byIcon(Icons.payments_outlined), findsOneWidget);
          expect(
            find.byIcon(Icons.medical_information_outlined),
            findsOneWidget,
          );
        },
      );
    }
  }
}
