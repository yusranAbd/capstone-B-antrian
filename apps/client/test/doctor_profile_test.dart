import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:queueb_client/src/admin_doctor_profile.dart';
import 'package:queueb_client/src/api.dart';
import 'package:queueb_client/src/config.dart';
import 'package:queueb_client/src/doctor_professional.dart';
import 'package:queueb_client/src/patient_ui.dart';
import 'package:timezone/data/latest.dart' as tz;

void main() {
  setUpAll(tz.initializeTimeZones);
  const ref = '/media/dokter/11111111-1111-4111-8111-111111111111.webp';
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
  );
  AppConfig config() => AppConfig(apiBaseUrl: 'http://localhost:3000/api/v1');
  http.Response reply(Object data, [int status = 200]) => http.Response(
    jsonEncode(data),
    status,
    headers: {'content-type': 'application/json'},
  );
  Future<void> press(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> editor(
    WidgetTester tester,
    QueueApi api, {
    Json? row,
    DoctorPhotoPicker? picker,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<bool>(
                context: context,
                builder: (_) => AdminDoctorEditor(
                  api: api,
                  row: row,
                  pickPhoto:
                      picker ??
                      () async => XFile.fromData(png, name: 'foto.png'),
                ),
              ),
              child: const Text('Editor'),
            ),
          ),
        ),
      ),
    );
    await press(tester, find.text('Editor'));
  }

  test('media references use configured API origin and never accept arbitrary URLs or paths', () {
    expect(doctorPhotoUrl(config(), ref), 'http://localhost:3000/api/v1$ref');
    for (final value in [
      null,
      'https://example.com/photo.webp',
      'data:image/png;base64,abc',
      '/media/dokter/../secret',
      'C:\\private\\photo.png',
    ]) {
      expect(doctorPhotoUrl(config(), value), isNull);
    }
  });
  testWidgets(
    'ADMIN saves biography and photo with authenticated multipart, then can remove photo',
    (tester) async {
      final requests = <http.Request>[];
      final api = QueueApi(
        config: config(),
        client: MockClient((r) async {
          requests.add(r);
          return reply(
            r.url.path.endsWith('/foto')
                ? {
                    'id': 'doctor',
                    'fotoProfil': r.method == 'DELETE' ? null : ref,
                  }
                : {'id': 'doctor'},
          );
        }),
      )..accessToken = 'test-access';
      addTearDown(api.dispose);
      await editor(
        tester,
        api,
        row: {
          'id': 'doctor',
          'nama': 'Dokter Anak',
          'kode': 'DR-AN',
          'aktif': true,
        },
      );
      await press(tester, find.text('Upload Foto'));
      expect(find.byType(Image), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Tentang Dokter (opsional)'),
        'Profil profesional anak.',
      );
      await press(tester, find.text('Simpan'));
      expect(
        jsonDecode(requests[0].body)['tentangDokter'],
        'Profil profesional anak.',
      );
      expect(requests[1].url.path, '/api/v1/dokter/doctor/foto');
      expect(
        requests[1].headers['content-type'],
        startsWith('multipart/form-data; boundary='),
      );
      expect(requests[1].bodyBytes, containsAllInOrder(png));
      expect(requests[1].headers['authorization'], 'Bearer test-access');
      await editor(
        tester,
        api,
        row: {
          'id': 'doctor',
          'nama': 'Dokter Anak',
          'kode': 'DR-AN',
          'aktif': true,
          'fotoProfil': ref,
        },
      );
      await press(tester, find.text('Hapus Foto'));
      await press(tester, find.text('Simpan'));
      expect(requests.last.method, 'DELETE');
      expect(requests.last.url.path, '/api/v1/dokter/doctor/foto');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'photo failure after creation retries the same profile without a duplicate POST',
    (tester) async {
      final requests = <http.Request>[];
      var uploadCount = 0;
      final api = QueueApi(
        config: config(),
        client: MockClient((r) async {
          requests.add(r);
          if (r.url.path.endsWith('/foto') && ++uploadCount == 1) {
            return reply({'message': 'Penyimpanan tidak tersedia'}, 503);
          }
          return reply({'id': 'created-doctor', 'fotoProfil': ref});
        }),
      )..accessToken = 'test-access';
      addTearDown(api.dispose);
      await editor(tester, api);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nama dokter'),
        'Dokter Baru',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Kode'),
        'DR-NEW',
      );
      await press(tester, find.text('Upload Foto'));
      await press(tester, find.text('Simpan'));
      expect(find.textContaining('Profil sudah tersimpan.'), findsOneWidget);
      await press(tester, find.text('Simpan'));
      expect(
        requests
            .where((r) => r.method == 'POST' && r.url.path == '/api/v1/dokter')
            .length,
        1,
      );
      expect(
        requests
            .where(
              (r) =>
                  r.method == 'PATCH' &&
                  r.url.path == '/api/v1/dokter/created-doctor',
            )
            .length,
        1,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'oversized selection and picker cancellation do not mutate the API',
    (tester) async {
      var count = 0, selected = 0;
      final api = QueueApi(
        config: config(),
        client: MockClient((_) async {
          count++;
          return reply({});
        }),
      );
      addTearDown(api.dispose);
      await editor(
        tester,
        api,
        picker: () async => selected++ == 0
            ? null
            : XFile.fromData(Uint8List(2 * 1024 * 1024 + 1), name: 'large.png'),
      );
      await press(tester, find.text('Upload Foto'));
      expect(find.textContaining('Foto belum dapat dipilih.'), findsNothing);
      await press(tester, find.text('Upload Foto'));
      expect(find.textContaining('maksimal 2 MB.'), findsWidgets);
      expect(count, 0);
    },
  );
  testWidgets(
    'DOKTER reads own professional profile without any edit control',
    (tester) async {
      final paths = <String>[];
      final api = QueueApi(
        config: config(),
        client: MockClient((r) async {
          paths.add('${r.method} ${r.url.path}');
          return reply({
            'nama': 'Dokter Anak',
            'spesialisasi': 'Anak',
            'tentangDokter': 'Profil profesional anak.',
            'poliklinik': [
              {'nama': 'Poli Anak'},
            ],
          });
        }),
      )..accessToken = 'test-access';
      addTearDown(api.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: DoctorProfessionalDialog(api: api)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Profil profesional anak.'), findsOneWidget);
      expect(find.text('Poli Anak'), findsOneWidget);
      expect(find.text('Upload Foto'), findsNothing);
      expect(find.byType(TextFormField), findsNothing);
      expect(paths, ['GET /api/v1/portal-dokter/profil']);
    },
  );
  testWidgets(
    'patient cards use backend photo and biography expands, with a safe empty fallback',
    (tester) async {
      final bio = List.filled(35, 'Dokter melayani konsultasi anak.').join(' ');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                PatientDoctorCard(
                  config: config(),
                  doctor: {
                    'nama': 'Dokter Anak',
                    'fotoProfil': ref,
                    'spesialisasi': 'Anak',
                    'dokterLayanan': [
                      {
                        'layanan': {'nama': 'Poli Anak'},
                      },
                    ],
                  },
                  schedule: 'Jadwal dari API',
                  onDetails: () {},
                ),
                DoctorBiography(text: bio),
              ],
            ),
          ),
        ),
      );
      expect(
        tester
            .widget<ProfessionalDoctorAvatar>(
              find.byType(ProfessionalDoctorAvatar),
            )
            .photo,
        ref,
      );
      expect(find.text('Poli Anak'), findsOneWidget);
      await press(tester, find.text('Baca Selengkapnya'));
      expect(find.text('Tampilkan lebih sedikit'), findsOneWidget);
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: DoctorBiography(text: null))),
      );
      expect(
        find.text('Informasi tentang dokter belum dicantumkan.'),
        findsOneWidget,
      );
      expect(find.text('Baca Selengkapnya'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  for (final width in [320.0, 375.0, 414.0, 768.0]) {
    testWidgets('profile editor and patient detail fit width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = QueueApi(config: config());
      addTearDown(api.dispose);
      await editor(
        tester,
        api,
        row: {
          'id': 'd',
          'nama': 'Dokter dengan nama panjang untuk responsivitas',
          'kode': 'DR-A',
        },
      );
      expect(tester.takeException(), isNull);
      await press(tester, find.text('Kembali'));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                PatientDoctorCard(
                  config: config(),
                  doctor: {
                    'nama': 'Dokter dengan nama panjang untuk responsivitas',
                  },
                  schedule: 'Jadwal belum tersedia.',
                  onDetails: () {},
                ),
                const DoctorBiography(text: 'Informasi profesional dokter.'),
              ],
            ),
          ),
        ),
      );
      expect(find.byIcon(Icons.person_outline_rounded), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
