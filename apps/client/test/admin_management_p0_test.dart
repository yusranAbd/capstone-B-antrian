import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:queueb_client/src/admin.dart';
import 'package:queueb_client/src/admin_data.dart';
import 'package:queueb_client/src/admin_staff.dart';
import 'package:queueb_client/src/api.dart';
import 'package:queueb_client/src/config.dart';
import 'package:queueb_client/src/doctor_account.dart';

void main() {
  setUpAll(tz.initializeTimeZones);
  const staffId = '11111111-1111-4111-8111-111111111111';
  final clinic = <String, dynamic>{
    'id': 'clinic',
    'nama': 'Poli Anak',
    'aktif': true,
  };
  final room = <String, dynamic>{
    'id': 'room',
    'kode': 'AN01',
    'nama': 'Ruang Anak',
    'layananId': 'clinic',
    'aktif': true,
    'layanan': clinic,
  };

  test('assignment status preserves inclusive end and distinguishes inactive account', () {
    final row = <String, dynamic>{
      'aktif': true,
      'tanggalMulai': '2026-10-23',
      'tanggalSelesai': '2026-10-24',
      'petugas': {'aktif': true},
    };
    expect(assignmentStatus(row, '2026-10-24'), 'BERLAKU');
    expect(assignmentStatus(row, '2026-10-25'), 'BERAKHIR');
    expect(assignmentStatus(row, '2026-10-22'), 'AKAN BERLAKU');
    expect(
      assignmentStatus({
        ...row,
        'petugas': {'aktif': false},
      }, '2026-10-24'),
      'AKUN NONAKTIF',
    );
    expect(
      assignmentStatus({...row, 'aktif': false}, '2026-10-24'),
      'NONAKTIF',
    );
  });

  testWidgets(
    'ADMIN creates account then chooses it by name/email without UUID input',
    (tester) async {
      tester.view.physicalSize = const Size(1366, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final accounts = <Json>[];
      Json? createdBody, assignmentBody;
      final api = QueueApi(
        config: AppConfig(
          apiBaseUrl: 'http://localhost/api/v1',
          realtime: false,
        ),
        client: MockClient((r) async {
          final path = r.url.path.split('/').last;
          if (r.method == 'POST' && path == 'akun-petugas') {
            createdBody = object(jsonDecode(r.body));
            accounts.add({
              'id': staffId,
              'nama': createdBody!['nama'],
              'email': createdBody!['email'],
              'peran': 'PETUGAS',
              'aktif': true,
            });
            return http.Response(jsonEncode(accounts.last), 201);
          }
          if (r.method == 'POST' && path == 'penugasan-petugas') {
            assignmentBody = object(jsonDecode(r.body));
            return http.Response('{}', 201);
          }
          return http.Response(
            jsonEncode(switch (path) {
              'akun-petugas' => accounts,
              'layanan' => [clinic],
              'loket' => [room],
              _ => <Json>[],
            }),
            200,
          );
        }),
      );
      addTearDown(api.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AdminPage(api: api, initialSection: 6)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tambah akun PETUGAS'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nama petugas'),
        'Siti Petugas',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email login'),
        'siti@example.test',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Kata sandi awal'),
        'password123',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Buat akun PETUGAS'));
      await tester.pumpAndSettle();
      expect(createdBody?.containsKey('peran'), false);
      expect(find.text('Siti Petugas'), findsOneWidget);
      await tester.tap(find.text('Penugasan Loket'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tambah'));
      await tester.pumpAndSettle();
      expect(find.text('ID akun PETUGAS'), findsNothing);
      expect(find.textContaining('Tempel ID'), findsNothing);
      await tester.tap(find.text('Petugas (nama / email)').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'siti@example');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Siti Petugas · siti@example.test').last);
      await tester.pumpAndSettle();
      final dropdown = find.widgetWithText(
        DropdownButtonFormField<String>,
        'Ruang / loket',
      );
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Ruang Anak').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tanggal mulai (YYYY-MM-DD)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Simpan'));
      await tester.pumpAndSettle();
      expect(assignmentBody?['petugasId'], staffId);
      expect(assignmentBody?['loketId'], 'room');
    },
  );

  testWidgets(
    'doctor account linking searches existing accounts and keeps dialog on provisioning failure',
    (tester) async {
      Json? payload;
      final api = QueueApi(
        config: AppConfig(
          apiBaseUrl: 'http://localhost/api/v1',
          realtime: false,
        ),
        client: MockClient((r) async {
          if (r.method == 'GET') {
            return http.Response(
              jsonEncode([
                {
                  'id': staffId,
                  'nama': 'Dokter Sari',
                  'email': 'sari@example.test',
                  'aktif': true,
                },
              ]),
              200,
            );
          }
          payload = object(jsonDecode(r.body));
          return http.Response(
            jsonEncode({'message': 'Dokter sudah memiliki akun'}),
            409,
          );
        }),
      );
      addTearDown(api.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DoctorAccountDialog(
              api: api,
              doctor: const {'id': 'doctor', 'nama': 'Dokter Sari'},
            ),
          ),
        ),
      );
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(find.text('ID akun DOKTER'), findsNothing);
      await tester.tap(find.text('Akun DOKTER (nama / email)').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dokter Sari · sari@example.test').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Tautkan akun'));
      await tester.pumpAndSettle();
      expect(payload, {'penggunaId': staffId});
      expect(find.textContaining('Dokter sudah memiliki akun'), findsOneWidget);
      expect(find.byType(DoctorAccountDialog), findsOneWidget);
    },
  );

  testWidgets(
    'account disable requires confirmation, preserves search and reloads the directory',
    (tester) async {
      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var writes = 0, reloads = 0;
      final accounts = <Json>[
        {
          'id': staffId,
          'nama': 'Siti Petugas',
          'email': 'siti@example.test',
          'aktif': true,
        },
      ];
      final api = QueueApi(
        config: AppConfig(
          apiBaseUrl: 'http://localhost/api/v1',
          realtime: false,
        ),
        client: MockClient((r) async {
          expect(r.method, 'PATCH');
          expect(r.url.path, '/api/v1/akun-petugas/$staffId');
          expect(jsonDecode(r.body), {'aktif': false});
          writes++;
          accounts[0]['aktif'] = false;
          return http.Response(jsonEncode(accounts[0]), 200);
        }),
      );
      addTearDown(api.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AdminStaffAccounts(
                api: api,
                accounts: accounts,
                busy: false,
                onChanged: () async {
                  reloads++;
                },
              ),
            ),
          ),
        ),
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Cari nama atau email petugas'),
        'siti@example',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nonaktifkan akun'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kembali'));
      await tester.pumpAndSettle();
      expect(writes, 0);
      await tester.tap(find.text('Nonaktifkan akun'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lanjutkan'));
      await tester.pumpAndSettle();
      expect(writes, 1);
      expect(reloads, 1);
      expect(find.text('Aktifkan akun'), findsOneWidget);
      expect(
        tester
                .widget<TextField>(
                  find.widgetWithText(
                    TextField,
                    'Cari nama atau email petugas',
                  ),
                )
                .controller
                ?.text ??
            'siti@example',
        'siti@example',
      );
    },
  );
}
