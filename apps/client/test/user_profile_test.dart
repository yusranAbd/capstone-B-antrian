import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:queueb_client/src/api.dart';
import 'package:queueb_client/src/config.dart';
import 'package:queueb_client/src/user_profile.dart';

void main() {
  setUpAll(tz.initializeTimeZones);
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
  );
  http.Response reply(Object? data, [int status = 200]) => http.Response(
    jsonEncode(data),
    status,
    headers: {'content-type': 'application/json'},
  );
  Json me(String role) => {
    'id': 'self-$role',
    'nama': 'Nama $role',
    'email': '${role.toLowerCase()}@profile.test',
    'peran': role,
    'aktif': true,
    'avatarProfil': null,
  };
  QueueApi apiFor(
    String role,
    Future<http.Response> Function(http.Request) handler,
  ) =>
      QueueApi(
          config: AppConfig(apiBaseUrl: 'http://localhost:3000/api/v1'),
          client: MockClient(handler),
        )
        ..user = me(role)
        ..accessToken = 'test-token';
  Future<void> tap(WidgetTester tester, String text) async {
    final f = find.text(text).last;
    await tester.ensureVisible(f);
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  for (final role in ['ADMIN', 'PETUGAS', 'DOKTER', 'USER']) {
    testWidgets('$role membuka Profil Saya dan informasi role tanpa overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = apiFor(role, (r) async {
        if (r.url.path.endsWith('/auth/me')) return reply(me(role));
        if (r.url.path.endsWith('/portal-dokter/profil')) {
          return reply({
            'nama': 'Profil Profesional',
            'spesialisasi': 'Anak',
            'tentangDokter': 'Biografi P1 tetap terpisah.',
            'fotoProfil': null,
            'poliklinik': [
              {'nama': 'Poli Anak'},
            ],
          });
        }
        if (r.url.path.endsWith('/penugasan-petugas')) {
          return reply([
            {
              'aktif': true,
              'tanggalMulai': '2026-01-01',
              'tanggalSelesai': null,
              'loket': {
                'kode': 'AN01',
                'nama': 'Ruang Anak',
                'layanan': {'nama': 'Poli Anak'},
              },
            },
          ]);
        }
        return reply([]);
      });
      addTearDown(api.dispose);
      await tester.pumpWidget(MaterialApp(home: UserProfilePage(api: api)));
      await tester.pumpAndSettle();
      expect(find.text('Profil Saya'), findsOneWidget);
      expect(find.text('Nama lengkap'), findsOneWidget);
      await tap(tester, 'Informasi Role/Penugasan');
      if (role == 'DOKTER') {
        expect(find.text('Profil Profesional'), findsOneWidget);
        expect(find.text('Biografi P1 tetap terpisah.'), findsOneWidget);
      }
      if (role == 'PETUGAS') {
        expect(find.text('AN01 · Ruang Anak'), findsOneWidget);
        expect(find.text('Tanpa batas akhir'), findsNothing);
        expect(find.textContaining('Tanpa batas akhir'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('mobile 360px menyimpan nama dan header mengikuti akun', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var state = me('USER');
    final mutations = <Json>[];
    final api = apiFor('USER', (r) async {
      if (r.method == 'PATCH') {
        final body = jsonDecode(r.body) as Json;
        mutations.add(body);
        state = {...state, ...body};
      }
      return reply(state);
    });
    addTearDown(api.dispose);
    await tester.pumpWidget(MaterialApp(home: UserProfilePage(api: api)));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nama lengkap'),
      'Nama Pasien Baru',
    );
    await tap(tester, 'Simpan Perubahan');
    expect(api.user!['nama'], 'Nama Pasien Baru');
    expect(mutations, [
      {'nama': 'Nama Pasien Baru'},
    ]);
    expect(tester.takeException(), isNull);
  });
  testWidgets('avatar dipilih, dipreview, disimpan, diganti dan dihapus', (
    tester,
  ) async {
    var state = me('USER');
    var uploads = 0, deletes = 0;
    final readHeaders = <String?>[];
    final api = apiFor('USER', (r) async {
      if (r.url.path.endsWith('/avatar')) {
        if (r.method == 'POST') {
          uploads++;
          state = {...state, 'avatarProfil': '/media/avatar/$uploads.webp'};
          return reply({
            'id': state['id'],
            'avatarProfil': state['avatarProfil'],
          }, 201);
        }
        if (r.method == 'DELETE') {
          deletes++;
          state = {...state, 'avatarProfil': null};
          return reply({'id': state['id'], 'avatarProfil': null});
        }
        readHeaders.add(r.headers['Authorization']);
        return http.Response.bytes(png, 200);
      }
      return reply(state);
    });
    addTearDown(api.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: UserProfilePage(
          api: api,
          pickPhoto: () async => XFile.fromData(png, name: 'avatar.png'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tap(tester, 'Ubah Foto Profil');
    await tap(tester, 'Pilih Foto');
    await tap(tester, 'Simpan Foto');
    expect(uploads, 1);
    expect(readHeaders.every((h) => h == 'Bearer test-token'), isTrue);
    await tap(tester, 'Ganti Foto');
    await tap(tester, 'Simpan Foto');
    expect(uploads, 2);
    await tap(tester, 'Hapus Foto');
    await tap(tester, 'Hapus Foto');
    expect(deletes, 1);
    expect(api.user!['avatarProfil'], isNull);
    expect(tester.takeException(), isNull);
  });
  testWidgets('ukuran foto berlebih ditolak sebelum upload', (tester) async {
    var upload = false;
    final api = apiFor('USER', (r) async {
      if (r.method == 'POST') upload = true;
      return reply(me('USER'));
    });
    addTearDown(api.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: UserProfilePage(
          api: api,
          pickPhoto: () async =>
              XFile.fromData(Uint8List(2 * 1024 * 1024 + 1), name: 'large.png'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tap(tester, 'Ubah Foto Profil');
    await tap(tester, 'Pilih Foto');
    expect(find.text('Ukuran foto maksimal 2 MB'), findsOneWidget);
    expect(upload, isFalse);
  });
  testWidgets('konfirmasi password tidak cocok menolak submit', (tester) async {
    var changed = false;
    final api = apiFor('USER', (r) async {
      if (r.method == 'POST') changed = true;
      return reply(me('USER'));
    });
    addTearDown(api.dispose);
    await tester.pumpWidget(MaterialApp(home: UserProfilePage(api: api)));
    await tester.pumpAndSettle();
    await tap(tester, 'Keamanan Akun');
    for (final item in [
      ('Kata sandi lama', 'RahasiaLama123'),
      ('Kata sandi baru', 'RahasiaBaru123'),
      ('Konfirmasi kata sandi baru', 'TidakSama123'),
    ]) {
      await tester.enterText(
        find.widgetWithText(TextFormField, item.$1),
        item.$2,
      );
    }
    await tap(tester, 'Ubah Kata Sandi');
    expect(find.text('Konfirmasi kata sandi tidak sesuai.'), findsOneWidget);
    expect(changed, isFalse);
  });
  test(
    'password salah mempertahankan sesi; perubahan sah menghapus sesi lokal',
    () async {
      var valid = false;
      final api = apiFor(
        'USER',
        (r) async => valid
            ? reply({'loginUlang': true})
            : reply({'message': 'Kata sandi lama tidak sesuai'}, 400),
      );
      addTearDown(api.dispose);
      await expectLater(
        api.changeOwnPassword('salah', 'RahasiaBaru123'),
        throwsA(isA<ApiException>()),
      );
      expect(api.user, isNotNull);
      expect(api.accessToken, 'test-token');
      valid = true;
      await api.changeOwnPassword('lama', 'RahasiaBaru123');
      expect(api.user, isNull);
      expect(api.accessToken, isNull);
      expect(api.sessionMessage, contains('masuk kembali'));
    },
  );
  test(
    'respons profil terlambat tidak mengembalikan sesi setelah logout',
    () async {
      final api = apiFor('USER', (r) async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return reply(me('USER'));
      });
      addTearDown(api.dispose);
      final request = api.updateOwnName('Nama Baru');
      await api.clearSession();
      await expectLater(request, throwsA(isA<ApiException>()));
      expect(api.user, isNull);
    },
  );
  for (final role in ['PETUGAS', 'DOKTER']) {
    testWidgets(
      '$role logout saat panel role terbuka tidak membaca snapshot lama',
      (tester) async {
        final api = apiFor(role, (r) async {
          if (r.url.path.endsWith('/auth/me')) return reply(me(role));
          if (r.url.path.endsWith('/portal-dokter/profil')) {
            return reply({'nama': 'Profesional Demo', 'poliklinik': []});
          }
          return reply(
            role == 'PETUGAS'
                ? [
                    {
                      'aktif': true,
                      'tanggalMulai': '2026-01-01',
                      'loket': {
                        'kode': 'QA',
                        'nama': 'Demo',
                        'layanan': {'nama': 'Demo'},
                      },
                    },
                  ]
                : [],
          );
        });
        addTearDown(api.dispose);
        await tester.pumpWidget(MaterialApp(home: UserProfilePage(api: api)));
        await tester.pumpAndSettle();
        await tap(tester, 'Informasi Role/Penugasan');
        await api.clearSession();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Informasi Role/Penugasan'), findsNothing);
      },
    );
  }
}
