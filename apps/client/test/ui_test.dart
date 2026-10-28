import 'patient_test_navigation.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:queueb_client/src/api.dart';
import 'package:queueb_client/src/app.dart';
import 'package:queueb_client/src/config.dart';
import 'package:queueb_client/src/mobile_ui.dart';
import 'package:queueb_client/src/patient_reservations.dart';
import 'package:qr_flutter/qr_flutter.dart';

const uid = '11111111-1111-4111-8111-111111111111';

class FakeBackend {
  FakeBackend(this.role, {this.mode = 'HIBRIDA'});
  final String role, mode;
  final List<(String, String, Json)> requests = [];
  final List<Json> tickets = [], appointments = [];
  String status = 'DIPESAN';
  bool offline = false, slotsAvailable = true;
  Completer<void>? catalogGate;
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
      await catalogGate?.future;
      if (offline) return reply({'message': 'Koneksi layanan terputus.'}, 503);
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
            'dokterId': uid,
            'dokter': {'id': uid, 'nama': 'Dokter Umum'},
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
          'tersedia': slotsAvailable,
          'sisaKapasitas': slotsAvailable ? 2 : 0,
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
    if (path == '/check-in/auto-antrean') {
      final duplicate = status == 'MENUNGGU';
      status = 'MENUNGGU';
      return reply({
        ...ticket,
        'namaPasien': 'Pasien Uji',
        'namaPoliklinik': service['nama'],
        'sudahTerdaftar': duplicate,
      });
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
        'daftarPasien': {
          'total': ['MENUNGGU', 'DILEWATI', 'CHECK_IN'].contains(status)
              ? 1
              : 0,
          'tiket': ['MENUNGGU', 'DILEWATI', 'CHECK_IN'].contains(status)
              ? [
                  {
                    ...ticket,
                    'namaPasien': 'Pasien Uji',
                    'checkInPada': DateTime.now().toUtc().toIso8601String(),
                    'bisaAntreUlang': status == 'DILEWATI',
                    'bisaMasukAntrean': status == 'CHECK_IN',
                  },
                ]
              : [],
        },
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
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Masuk'));
      await tester.tap(find.widgetWithText(FilledButton, 'Masuk'));
      await tester.pumpAndSettle();
      if (backend.role == 'ADMIN') {
        if (size.width < 960) {
          await tester.tap(find.byTooltip('Menu administrasi'));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.widgetWithText(ListTile, 'Poliklinik'));
        await tester.pumpAndSettle();
      }
    }
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      api.dispose();
    });
    return api;
  }

  Future<void> press(WidgetTester tester, String text, {Type? type}) async {
    final base = type == null
        ? find.text(text)
        : find.widgetWithText(type, text);
    if (base.evaluate().isEmpty) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 5000));
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
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Calendar remains usable after manual date outside supported range',
    (tester) async {
      await launch(tester, FakeBackend('USER'));
      await openPatientCatalog(tester, walkIn: true);
      await tester.tap(find.byType(ClinicCard).first);
      await tester.pumpAndSettle();
      for (final input in ['2020-01-01', '2099-12-31', 'tidak valid']) {
        await tester.enterText(
          find.widgetWithText(TextField, 'Tanggal pelayanan (YYYY-MM-DD)'),
          input,
        );
        await tester.tap(find.byTooltip('Pilih tanggal pelayanan'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(DatePickerDialog), findsOneWidget);
        await tester.tap(find.text('Batal'));
        await tester.pumpAndSettle();
      }
    },
  );

  Future<void> displayForSpeech(
    WidgetTester tester, {
    bool failSpeak = false,
    bool unavailableLanguage = false,
  }) async {
    const channel = MethodChannel('flutter_tts');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'isLanguageAvailable' && unavailableLanguage) {
        return false;
      }
      if (call.method == 'speak' && failSpeak) {
        throw PlatformException(code: 'synthesis-failed');
      }
      return 1;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await launch(tester, FakeBackend('USER'), login: false);
    await press(tester, 'Masuk ke Public Display');
    await press(tester, 'Konfigurasi lanjutan (token existing)');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'ID layanan'),
      uid,
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Token perangkat'),
      'a' * 64,
    );
    await press(tester, 'Hubungkan display');
  }

  testWidgets('Failed TTS activation must not show audio enabled', (
    tester,
  ) async {
    await displayForSpeech(tester, failSpeak: true);
    await press(tester, 'Aktifkan suara');
    expect(find.text('Aktifkan suara'), findsOneWidget);
    expect(find.text('Matikan suara'), findsNothing);
    expect(
      find.text('Suara tidak tersedia. Gunakan pengumuman visual.'),
      findsOneWidget,
    );
  });
  testWidgets(
    'Missing Indonesian voice leaves audio disabled with visual fallback',
    (tester) async {
      await displayForSpeech(tester, unavailableLanguage: true);
      await press(tester, 'Aktifkan suara');
      expect(find.text('Aktifkan suara'), findsOneWidget);
      expect(find.text('Matikan suara'), findsNothing);
      expect(
        find.text('Suara tidak tersedia. Gunakan pengumuman visual.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('Asynchronous speech engine failure disables audio', (
    tester,
  ) async {
    await displayForSpeech(tester);
    await press(tester, 'Aktifkan suara');
    expect(find.text('Matikan suara'), findsOneWidget);
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter_tts',
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('speak.onError', 'synthesis-unavailable'),
      ),
      (_) {},
    );
    await tester.pumpAndSettle();
    expect(find.text('Aktifkan suara'), findsOneWidget);
    expect(
      find.text('Suara tidak tersedia. Gunakan pengumuman visual.'),
      findsOneWidget,
    );
  });

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
      await press(tester, 'Input Manual');
      await tester.enterText(
        find.widgetWithText(TextField, 'Payload QR (SQ1…)'),
        'SQ1.${'A' * 43}',
      );
      await press(tester, 'Proses QR & Masuk Antrean', type: OutlinedButton);
      expect(server.status, 'MENUNGGU');
      expect(server.requests.where((r) => r.$2.endsWith('/masuk')), isEmpty);
      expect(server.status, 'MENUNGGU');
      await press(tester, 'Panggil berikutnya');
      await press(tester, 'Panggil Ulang');
      await press(tester, 'Lewati');
      expect(server.status, 'DILEWATI');
      await tester.ensureVisible(find.byTooltip('Aksi UM-001'));
      await tester.tap(find.byTooltip('Aksi UM-001'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kembalikan ke Antrean'));
      await tester.pumpAndSettle();
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
    await press(tester, 'Reservasi');
    await press(tester, 'Buat Reservasi');
    await press(tester, 'Pilih Poliklinik');
    await tester.tap(find.byType(ClinicCard).first);
    await tester.pumpAndSettle();
    await press(tester, 'Reservasi walk-in');
    await press(tester, 'Lanjutkan');
    expect(find.text('UM-001'), findsOneWidget);
    await press(tester, 'Lihat Tiket / QR');
    await press(tester, 'Terbitkan QR');
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.text('SQ1.fixture'), findsNothing);
    expect(
      server.requests
          .where((r) => r.$1 == 'POST' && r.$2.endsWith('/qr'))
          .length,
      1,
    );
    final technical = find.text('Detail teknis tiket');
    await tester.ensureVisible(technical);
    await tester.pumpAndSettle();
    await tester.tap(technical);
    await tester.pumpAndSettle();
    expect(find.text('SQ1.fixture'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await press(tester, 'Tutup');
  });
  testWidgets(
    'USER appointment uses slot id; cancellation uses appointment id',
    (tester) async {
      final server = FakeBackend('USER');
      await launch(tester, server);
      await press(tester, 'Reservasi');
      await press(tester, 'Buat Reservasi');
      await press(tester, 'Pilih Poliklinik');
      await tester.tap(find.byType(ClinicCard).first);
      await tester.pumpAndSettle();
      await press(tester, 'Lihat Detail Dokter');
      await press(tester, 'Buat Janji Temu');
      await press(tester, 'Lihat slot');
      await press(tester, 'Sisa slot 2');
      await press(tester, 'Lanjutkan');
      await press(tester, 'Konfirmasi Janji Temu');
      expect(
        server.requests
            .where((r) => r.$1 == 'POST' && r.$2 == '/janji-temu')
            .single
            .$3,
        {'slotPraktikId': uid},
      );
      await press(tester, 'Reservasi');
      await press(tester, 'Batalkan Reservasi');
      await press(tester, 'Ya, Batalkan');
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
    await press(tester, 'Masuk ke Public Display');
    await press(tester, 'Konfigurasi lanjutan (token existing)');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'ID layanan'),
      uid,
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Token perangkat'),
      'a' * 64,
    );
    await press(tester, 'Hubungkan display');
    expect(find.text('UM-001'), findsWidgets);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('display-waiting-count')))
          .data,
      '1',
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('ADMIN narrow navigation and profile remain usable', (
    tester,
  ) async {
    final server = FakeBackend('ADMIN');
    await launch(tester, server, size: const Size(390, 844));
    expect(find.byType(NavigationRail), findsNothing);
    await press(tester, 'Menu administrasi');
    await tester.tap(find.byTooltip('Profil akun'));
    await tester.pumpAndSettle();
    expect(find.text('Profil Saya'), findsOneWidget);
    expect(find.text('Informasi Pribadi'), findsWidgets);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets('Patient home navigation, empty tickets and catalog search', (
    tester,
  ) async {
    await launch(tester, FakeBackend('USER'), size: const Size(375, 812));
    expect(find.text('Selamat datang,'), findsOneWidget);
    await openPatientCatalog(tester);
    expect(find.text('Buat Reservasi'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Cari poliklinik atau dokter'),
      'Tidak ada',
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Tidak ada poliklinik yang sesuai pencarian.'),
      findsOneWidget,
    );
    await press(tester, 'Tiket Saya');
    expect(
      find.text(
        'Belum ada tiket. Daftar janji temu atau walk-in terlebih dahulu.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
  for (final width in [320.0, 375.0, 414.0, 768.0]) {
    testWidgets('Mobile home layout at width $width', (tester) async {
      await launch(tester, FakeBackend('USER'), size: Size(width, 900));
      expect(tester.takeException(), isNull);
      await press(tester, 'Reservasi');
      expect(tester.takeException(), isNull);
      expect(find.byTooltip('Keluar akun'), findsNothing);
      await tester.tap(find.widgetWithText(NavigationDestination, 'Profil'));
      await tester.pumpAndSettle();
      await press(tester, 'Keluar Akun');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('Catalog loading and offline recovery remain visible', (
    tester,
  ) async {
    final server = FakeBackend('USER')..catalogGate = Completer<void>();
    final api = QueueApi(
      config: AppConfig(apiBaseUrl: 'http://localhost/api/v1', realtime: false),
      client: MockClient(server.handle),
    );
    await api.login('test@test.local', 'password');
    await tester.pumpWidget(QueueBApp(api: api));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    server.offline = true;
    server.catalogGate!.complete();
    await tester.pumpAndSettle();
    expect(
      find.textContaining(
        'Layanan sedang mengalami gangguan. Muat ulang data dan coba lagi nanti.',
      ),
      findsOneWidget,
    );
    server.offline = false;
    await press(tester, 'Coba lagi');
    expect(
      find.textContaining(
        'Layanan sedang mengalami gangguan. Muat ulang data dan coba lagi nanti.',
      ),
      findsNothing,
    );
    await tester.pumpWidget(const SizedBox());
    api.dispose();
  });
  for (final status in [
    'DIPESAN',
    'CHECK_IN',
    'MENUNGGU',
    'DIPANGGIL',
    'DILAYANI',
    'DILEWATI',
    'SELESAI',
  ]) {
    testWidgets('Digital ticket displays actual status $status', (
      tester,
    ) async {
      final server = FakeBackend('USER')..status = status;
      server.tickets.add(server.ticket);
      await launch(tester, server, size: const Size(320, 900));
      await press(tester, 'Tiket Saya');
      expect(find.text(reservationStatus(status)), findsOneWidget);
      await press(tester, 'Lihat Tiket / QR');
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(reservationStatus(status)),
        ),
        findsOneWidget,
      );
      if (status != 'DIPESAN') expect(find.text('Terbitkan QR'), findsNothing);
      expect(tester.takeException(), isNull);
      await press(tester, 'Tutup');
    });
  }
  for (final width in [320.0, 375.0, 414.0, 768.0]) {
    testWidgets('Mobile staff layout and state gated controls at $width', (
      tester,
    ) async {
      await launch(tester, FakeBackend('PETUGAS'), size: Size(width, 900));
      expect(find.text('Daftar antrean poli'), findsOneWidget);
      expect(find.text('Mulai Pelayanan'), findsNothing);
      expect(find.text('Selesaikan Pelayanan'), findsNothing);
      await press(tester, 'Panggil berikutnya');
      expect(find.text('Mulai Pelayanan'), findsOneWidget);
      expect(find.text('Selesaikan Pelayanan'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'Doctor card opens booking and unavailable slots cannot be booked',
    (tester) async {
      final server = FakeBackend('USER')..slotsAvailable = false;
      await launch(tester, server, size: const Size(375, 900));
      await openPatientCatalog(tester);
      await tester.tap(find.byType(ClinicCard).first);
      await tester.pumpAndSettle();
      await press(tester, 'Lihat Detail Dokter');
      await press(tester, 'Buat Janji Temu');
      expect(find.byTooltip('Kembali'), findsOneWidget);
      await press(tester, 'Lihat slot');
      final unavailable = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Sisa slot 0'),
      );
      expect(unavailable.onPressed, isNull);
      final book = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Lanjutkan'),
      );
      expect(book.onPressed, isNull);
      expect(
        server.requests.where((r) => r.$1 == 'POST' && r.$2 == '/janji-temu'),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
