import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:queueb_client/src/api.dart';
import 'package:queueb_client/src/app.dart';
import 'package:queueb_client/src/config.dart';

const uid = '11111111-1111-4111-8111-111111111111';

class FakeBackend {
  FakeBackend(this.role, {this.mode = 'HIBRIDA'});
  final String role, mode;
  final List<(String, String, Json)> requests = [];
  final List<Json> tickets = [], appointments = [];
  String status = 'DIPESAN';
  Json get user => {
    'id': uid,
    'nama': 'Akun $role',
    'email': 'test@test.local',
    'peran': role,
  };
  String get today =>
      calendarDate(DateTime.now().toUtc().add(const Duration(hours: 7)));
  Json get service => {
    'id': uid,
    'kode': 'UM',
    'nama': 'Poli Umum',
    'modeReservasi': mode,
    'aktif': true,
  };
  Json get room => {
    'id': uid,
    'nama': 'Ruang Umum',
    'kode': 'RU',
    'aktif': true,
    'layanan': service,
  };
  Json get ticket => {
    'id': uid,
    'tiketId': uid,
    'nomorAntrean': 'UM-001',
    'layanan': service,
    'tanggalPelayanan': today,
    'status': status,
  };
  http.Response reply(Object data, [int code = 200]) => http.Response(
    jsonEncode(data),
    code,
    headers: {'content-type': 'application/json'},
  );
  Future<http.Response> handle(http.Request request) async {
    final path = request.url.path.replaceFirst('/api/v1', '');
    final body = request.body.isEmpty
        ? <String, dynamic>{}
        : object(jsonDecode(request.body));
    requests.add((request.method, path, body));
    if (path == '/auth/login') {
      return reply({
        'accessToken': 'test',
        'refreshToken': 'refresh',
        'user': user,
      });
    }
    if (path == '/auth/me') return reply(user);
    if (path == '/auth/register' || path == '/auth/logout') return reply(user);
    if (path == '/layanan') {
      if (request.method == 'POST') return reply({...service, ...body}, 201);
      return reply([service]);
    }
    if (path == '/dokter') {
      return reply([
        {
          'id': uid,
          'kode': 'DR',
          'nama': 'Dokter Umum',
          'aktif': true,
          'dokterLayanan': [
            {'id': uid, 'aktif': true, 'layananId': uid, 'layanan': service},
          ],
        },
      ]);
    }
    if (path == '/loket') return reply([room]);
    if (path == '/jadwal-layanan') return reply([]);
    if (path == '/penugasan-petugas') {
      return reply([
        {
          'id': uid,
          'aktif': true,
          'loketId': uid,
          'tanggalMulai': today,
          'tanggalSelesai': null,
          'loket': room,
        },
      ]);
    }
    if (path == '/jadwal-praktik') {
      return reply([
        {
          'id': uid,
          'tanggal': today,
          'mulaiPada': '${today}T02:00:00Z',
          'selesaiPada': '${today}T04:00:00Z',
          'loket': room,
          'dokterLayanan': {
            'dokter': {'nama': 'Dokter Umum'},
          },
        },
      ]);
    }
    if (path == '/slot-praktik') {
      return reply([
        {
          'id': uid,
          'mulaiPada': '${today}T02:00:00Z',
          'selesaiPada': '${today}T02:15:00Z',
          'tersedia': true,
          'sisaKapasitas': 2,
        },
      ]);
    }
    if (path == '/reservasi') {
      tickets.add(ticket);
      return reply(ticket, 201);
    }
    if (path == '/janji-temu') {
      if (request.method == 'POST') {
        tickets.add(ticket);
        appointments.add({
          'id': '22222222-2222-4222-8222-222222222222',
          'tiket': ticket,
        });
        return reply({'id': 'appointment', 'tiket': ticket}, 201);
      }
      return reply(appointments);
    }
    if (path == '/tiket/saya') return reply(tickets);
    if (path == '/tiket/$uid') return reply(ticket);
    if (path == '/tiket/$uid/qr') {
      return reply({
        'tiketId': uid,
        'qrPayload': 'SQ1.fixture',
        'berlakuHingga': DateTime.now()
            .add(const Duration(minutes: 10))
            .toUtc()
            .toIso8601String(),
      });
    }
    if (path.contains('/batalkan')) {
      status = 'DIBATALKAN';
      tickets[0] = ticket;
      return reply({});
    }
    if (path == '/check-in') {
      status = 'CHECK_IN';
      return reply(ticket);
    }
    if (path == '/queue/snapshot') {
      return reply({
        'versiSkema': 1,
        'tanggalPelayanan': today,
        'diperolehPada': DateTime.now().toUtc().toIso8601String(),
        'menunggu': {
          'total': status == 'MENUNGGU' ? 1 : 0,
          'tiket': status == 'MENUNGGU' ? [ticket] : [],
        },
        'loket': [
          {
            ...room,
            'tiketAktif': ['DIPANGGIL', 'DILAYANI'].contains(status)
                ? [ticket]
                : [],
          },
        ],
      });
    }
    if (path.startsWith('/queue/')) {
      status = switch (path.split('/').last) {
        'masuk' || 'antre-ulang' => 'MENUNGGU',
        'panggil' || 'panggil-ulang' => 'DIPANGGIL',
        'lewati' => 'DILEWATI',
        'mulai-pelayanan' => 'DILAYANI',
        'selesaikan-pelayanan' => 'SELESAI',
        _ => status,
      };
      return reply(ticket);
    }
    if (path.startsWith('/display/')) {
      return reply({
        'versiSkema': 1,
        'layanan': {'nama': 'Poli Umum'},
        'tanggalPelayanan': today,
        'totalMenunggu': 1,
        'loket': [
          {
            'kode': 'RU',
            'nama': 'Ruang Umum',
            'tiketAktif': [
              {'nomorAntrean': 'UM-001', 'status': 'DIPANGGIL'},
            ],
          },
        ],
        'pengumumanTerakhir': null,
      });
    }
    return reply({'message': 'Tidak ditemukan'}, 404);
  }
}

void main() {
  setUpAll(tz.initializeTimeZones);
  Future<QueueApi> launch(
    WidgetTester tester,
    FakeBackend backend, {
    Size size = const Size(1280, 1000),
    bool login = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final api = QueueApi(
      config: AppConfig(apiBaseUrl: 'http://localhost/api/v1', realtime: false),
      client: MockClient(backend.handle),
    );
    await tester.pumpWidget(QueueBApp(api: api));
    if (login) {
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email'),
        'test@test.local',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Kata sandi'),
        'password',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Masuk'));
      await tester.pumpAndSettle();
    }
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      api.dispose();
    });
    return api;
  }

  Future<void> press(WidgetTester tester, String text, {Type? type}) async {
    final finder = type == null
        ? find.text(text).last
        : find.widgetWithText(type, text).last;
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('Login validates input and registration is USER only', (
    tester,
  ) async {
    final server = FakeBackend('USER');
    await launch(tester, server, login: false);
    await press(tester, 'Masuk', type: FilledButton);
    expect(find.text('Masukkan email yang valid.'), findsOneWidget);
    expect(server.requests, isEmpty);
    await press(tester, 'Pasien baru? Daftar');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nama lengkap'),
      'Pasien Baru',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'test@test.local',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Kata sandi'),
      'password',
    );
    await press(tester, 'Daftar pasien', type: FilledButton);
    expect(server.requests.single.$3.containsKey('peran'), isFalse);
    expect(find.text('Akun pasien dibuat. Silakan masuk.'), findsOneWidget);
  });
  testWidgets(
    'ADMIN creates service with contracted mode and numeric duration',
    (tester) async {
      final server = FakeBackend('ADMIN');
      await launch(tester, server);
      expect(find.text('Tambah'), findsOneWidget);
      await press(tester, 'Tambah');
      await tester.enterText(find.widgetWithText(TextFormField, 'Kode'), 'PU');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nama'),
        'Poli Uji',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Prefix antrean'),
        'PU',
      );
      await press(tester, 'Simpan');
      final post = server.requests
          .where((r) => r.$1 == 'POST' && r.$2 == '/layanan')
          .single;
      expect(post.$3['modeReservasi'], 'HIBRIDA');
      expect(post.$3['durasiDasarMenit'], 15);
      expect(find.text('Data disimpan.'), findsOneWidget);
    },
  );
  testWidgets(
    'PETUGAS complete QR → ENQUEUE → CALL → RECALL → SKIP → REQUEUE → START → COMPLETE',
    (tester) async {
      final server = FakeBackend('PETUGAS');
      await launch(tester, server);
      await tester.enterText(
        find.widgetWithText(TextField, 'Payload QR (SQ1…)'),
        'SQ1.fixture',
      );
      await press(tester, 'Check-In', type: FilledButton);
      expect(server.status, 'CHECK_IN');
      expect(server.requests.where((r) => r.$2.endsWith('/masuk')), isEmpty);
      await press(tester, 'Masuk Antrean', type: TextButton);
      expect(server.status, 'MENUNGGU');
      await press(tester, 'Panggil berikutnya');
      await press(tester, 'Panggil Ulang');
      await press(tester, 'Lewati');
      expect(server.status, 'DILEWATI');
      await press(tester, 'Antre Ulang', type: TextButton);
      await press(tester, 'Panggil berikutnya');
      await press(tester, 'Mulai Pelayanan');
      await press(tester, 'Selesaikan Pelayanan');
      expect(server.status, 'SELESAI');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('USER walk-in → own ticket → QR, responsive narrow layout', (
    tester,
  ) async {
    final server = FakeBackend('USER', mode: 'ANTREAN_HARIAN');
    await launch(tester, server, size: const Size(390, 844));
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('UM · Poli Umum').last);
    await tester.pumpAndSettle();
    await press(tester, 'Reservasi walk-in');
    await press(tester, 'Lanjutkan');
    expect(find.text('UM-001'), findsOneWidget);
    await press(tester, 'Lihat tiket / QR');
    await press(tester, 'Terbitkan QR');
    expect(find.text('SQ1.fixture'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await press(tester, 'Tutup');
  });
  testWidgets(
    'USER appointment uses slot id; cancellation uses appointment id',
    (tester) async {
      final server = FakeBackend('USER');
      await launch(tester, server);
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('UM · Poli Umum').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dokter Umum · ').last);
      await tester.pumpAndSettle();
      await press(tester, 'Lihat jadwal dokter');
      await press(tester, 'Lihat slot');
      await press(tester, 'Tersedia · Sisa slot 2');
      await press(tester, 'Booking janji temu');
      await press(tester, 'Lanjutkan');
      expect(
        server.requests
            .where((r) => r.$1 == 'POST' && r.$2 == '/janji-temu')
            .single
            .$3,
        {'slotPraktikId': uid},
      );
      await press(tester, 'Batalkan janji temu');
      await press(tester, 'Lanjutkan');
      expect(
        server.requests.any(
          (r) =>
              r.$2 ==
              '/janji-temu/22222222-2222-4222-8222-222222222222/batalkan',
        ),
        isTrue,
      );
    },
  );
  testWidgets('Public Display uses device credentials and public snapshot', (
    tester,
  ) async {
    final server = FakeBackend('USER');
    await launch(tester, server, login: false);
    await press(tester, 'Buka Public Display');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'ID layanan'),
      uid,
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Token perangkat'),
      'a' * 64,
    );
    await press(tester, 'Hubungkan display');
    expect(find.text('UM-001'), findsOneWidget);
    expect(find.text('Menunggu: 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('ADMIN narrow navigation and profile remain usable', (
    tester,
  ) async {
    final server = FakeBackend('ADMIN');
    await launch(tester, server, size: const Size(390, 844));
    expect(find.byType(NavigationRail), findsNothing);
    await tester.tap(find.byTooltip('Profil akun'));
    await tester.pumpAndSettle();
    expect(find.textContaining('ID akun:'), findsOneWidget);
    await press(tester, 'Tutup');
    expect(tester.takeException(), isNull);
  });
}
