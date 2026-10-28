import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:queueb_client/src/api.dart';
import 'package:queueb_client/src/app.dart';
import 'package:queueb_client/src/config.dart';

import 'ui_test.dart' show FakeBackend, uid;

class StaffBackend extends FakeBackend {
  StaffBackend() : super('PETUGAS');
  Completer<void>? gate;
  bool failCall = false;
  List<Json> waiting = [];
  @override
  Future<http.Response> handle(http.Request request) async {
    if (request.url.path.endsWith('/queue/snapshot')) {
      requests.add((request.method, '/queue/snapshot', {}));
      return reply({
        'tanggalPelayanan': today,
        'diperolehPada': DateTime.now().toUtc().toIso8601String(),
        'menunggu': {
          'total': 12,
          'ditampilkan': waiting.length,
          'tiket': waiting,
        },
        'loket': [
          {...room, 'tiketAktif': <Json>[]},
        ],
      });
    }
    if (request.url.path.endsWith('/queue/panggil')) {
      await gate?.future;
      if (failCall) {
        return reply({'message': 'Antrean berubah. Muat ulang.'}, 409);
      }
    }
    return super.handle(request);
  }
}

void main() {
  setUpAll(tz.initializeTimeZones);
  Future<void> launch(
    WidgetTester tester,
    StaffBackend backend,
    Size size,
  ) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    final api = QueueApi(
      config: AppConfig(apiBaseUrl: 'http://localhost/api/v1', realtime: false),
      client: MockClient(backend.handle),
    );
    await api.login('test@test.local', 'password');
    await tester.pumpWidget(QueueBApp(api: api));
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      api.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  for (final size in [
    const Size(1366, 768),
    const Size(1440, 900),
    const Size(1920, 1080),
  ]) {
    testWidgets('Essential controls fit first viewport $size', (tester) async {
      await launch(tester, StaffBackend(), size);
      for (final finder in [
        find.text('Daftar antrean poli'),
        find.text('Pelayanan ruang ini'),
        find.text('Pindai QR'),
        find.text('Ruang yang ditugaskan'),
      ]) {
        expect(finder, findsOneWidget);
        expect(tester.getBottomLeft(finder).dy, lessThan(size.height));
      }
      expect(find.text('Total belum tersedia dari API'), findsNothing);
      expect(find.text('Tiket diterima / dilewati'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Server ranking, eligibility and counts survive local search', (
    tester,
  ) async {
    final backend = StaffBackend()
      ..waiting = [
        {
          'tiketId': uid,
          'nomorAntrean': 'UM-009',
          'jenisAntrean': 'JANJI_TEMU',
          'layakDipanggil': false,
          'alasanTidakLayak': 'SLOT_BELUM_MULAI',
        },
        {
          'tiketId': 'other',
          'nomorAntrean': 'UM-002',
          'jenisAntrean': 'WALK_IN',
          'layakDipanggil': true,
        },
      ];
    await launch(tester, backend, const Size(1366, 768));
    final semantics = tester.ensureSemantics();
    try {
      await tester.pump();
      final searchNode = tester.getSemantics(
        find.bySemanticsLabel('Cari nomor antrean atau nama pasien'),
      );
      expect(searchNode.label, contains('Cari nomor antrean atau nama pasien'));
      expect(searchNode.label, isNot(contains('Pelayanan ruang ini')));
    } finally {
      semantics.dispose();
    }
    expect(
      tester.getTopLeft(find.text('UM-009')).dy,
      lessThan(tester.getTopLeft(find.text('UM-002')).dy),
    );
    expect(find.textContaining('SLOT BELUM MULAI'), findsOneWidget);
    final initial = backend.requests.length;
    await tester.enterText(
      find.widgetWithText(TextField, 'Cari nomor antrean atau nama pasien'),
      '002',
    );
    await tester.pumpAndSettle();
    expect(find.text('UM-009'), findsNothing);
    expect(find.text('UM-002'), findsOneWidget);
    expect(find.textContaining('2/12 tiket dimuat'), findsOneWidget);
    expect(backend.requests.length, initial);
    await tester.enterText(
      find.widgetWithText(TextField, 'Cari nomor antrean atau nama pasien'),
      '',
    );
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('UM-009')).dy,
      lessThan(tester.getTopLeft(find.text('UM-002')).dy),
    );
  });

  for (final size in [
    const Size(1366, 768),
    const Size(320, 900),
    const Size(375, 900),
  ]) {
    testWidgets(
      'Busy action is gated; conflict keeps snapshot and reports error $size',
      (tester) async {
        final backend = StaffBackend()
          ..gate = Completer<void>()
          ..failCall = true;
        await launch(tester, backend, size);
        final call = find.widgetWithText(FilledButton, 'Panggil berikutnya');
        await tester.tap(call);
        await tester.pump();
        expect(tester.widget<FilledButton>(call).onPressed, isNull);
        expect(find.bySemanticsLabel('Memproses tindakan'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.text('Mulai Pelayanan'), findsNothing);
        backend.gate!.complete();
        await tester.pumpAndSettle();
        expect(find.textContaining('Antrean berubah.'), findsOneWidget);
        expect(tester.widget<FilledButton>(call).onPressed, isNotNull);
        expect(find.text('Mulai Pelayanan'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('Recovery panels and UUID fields are absent', (tester) async {
    await launch(tester, StaffBackend(), const Size(1366, 768));
    expect(find.text('Pemulihan ID tiket'), findsNothing);
    expect(find.text('Tiket diterima / dilewati'), findsNothing);
    expect(
      find.widgetWithText(TextField, 'ID tiket untuk masuk / antre ulang'),
      findsNothing,
    );
  });
}
