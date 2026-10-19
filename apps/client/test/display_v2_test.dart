import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:queueb_client/src/api.dart';
import 'package:queueb_client/src/config.dart';
import 'package:queueb_client/src/display.dart';
import 'package:queueb_client/src/display_board.dart';
import 'package:queueb_client/src/mobile_ui.dart';
import 'package:timezone/data/latest.dart' as tz;

const _service = '11111111-1111-4111-8111-111111111111';

Json _snapshot({
  int rooms = 1,
  String? status = 'DIPANGGIL',
  int waiting = 0,
}) => {
  'versiSkema': 1,
  'tanggalPelayanan': '2026-10-18',
  'diperolehPada': '2026-10-18T05:00:00.000Z',
  'layanan': {'nama': 'Poliklinik Mata', 'kode': 'MAT'},
  'totalMenunggu': waiting,
  'loket': [
    for (var n = 1; n <= rooms; n++)
      {
        'nama': 'Ruang Mata $n',
        'kode': 'M$n',
        'tiketAktif': [
          if (status != null)
            {
              'nomorAntrean': 'MAT-${n.toString().padLeft(3, '0')}',
              'status': status,
              'dipanggilPada': '2026-10-18T05:00:00Z',
            },
        ],
      },
  ],
  'pengumumanTerakhir': status == 'DIPANGGIL'
      ? {
          'peristiwaId': 'audit-call',
          'aksi': 'CALL',
          'nomorAntrean': 'MAT-001',
          'kodeLoket': 'M1',
          'teks': 'Nomor antrean MAT-001, silakan menuju loket M1.',
          'bahasa': 'id-ID',
        }
      : null,
};

void main() {
  setUpAll(tz.initializeTimeZones);
  Json announcement(String id, {String action = 'CALL'}) => {
    'peristiwaId': id,
    'aksi': action,
    'teks': 'Nomor antrean MAT-001, silakan menuju loket M1.',
  };

  test('Reconnect and resume silently baseline a missed CALL then allow a new RECALL', () {
    final gate = AnnouncementGate();
    expect(gate.observe(announcement('initial'), callSignal: true), isNull);
    expect(gate.observe(announcement('call'), callSignal: true), isNotNull);
    gate.rebase();
    expect(
      gate.observe(announcement('offline-call'), callSignal: true),
      isNull,
    );
    expect(
      gate.observe(announcement('recall', action: 'RECALL'), callSignal: true),
      isNotNull,
    );
    expect(
      gate.observe(announcement('recall', action: 'RECALL'), callSignal: true),
      isNull,
    );
  });

  test('Non-consecutive duplicate audit IDs and a muted/manual snapshot never replay', () {
    final gate = AnnouncementGate();
    gate.observe(null, callSignal: false);
    expect(gate.observe(announcement('first'), callSignal: true), isNotNull);
    expect(gate.observe(announcement('second'), callSignal: true), isNotNull);
    expect(gate.observe(announcement('first'), callSignal: true), isNull);
    expect(gate.observe(announcement('polled'), callSignal: false), isNull);
    expect(gate.observe(announcement('polled'), callSignal: true), isNull);
    gate.rebase();
    expect(gate.observe(announcement('manual'), callSignal: true), isNull);
  });

  test(
    'START and COMPLETE cannot select a serving or stale call as the hero',
    () {
      expect(DisplayBoard.currentCall(_snapshot(status: 'DILAYANI')), isNull);
      final completed = _snapshot(status: null);
      completed['pengumumanTerakhir'] = announcement('old');
      expect(DisplayBoard.currentCall(completed), isNull);
    },
  );

  test('RECALL selects the exact room among simultaneous calls', () {
    final data = _snapshot(rooms: 3);
    data['pengumumanTerakhir'] = {
      ...object(data['pengumumanTerakhir']),
      'aksi': 'RECALL',
      'peristiwaId': 'recall-room-3',
      'kodeLoket': 'M3',
      'nomorAntrean': 'MAT-003',
    };
    expect(DisplayBoard.currentCall(data)?.room['kode'], 'M3');
    data['pengumumanTerakhir'] = null;
    rows(data['loket']).last['tiketAktif'][0]['dipanggilPada'] =
        '2026-10-18T06:00:00Z';
    expect(DisplayBoard.currentCall(data)?.room['kode'], 'M3');
  });

  Future<void> board(
    WidgetTester tester,
    Size size,
    Json? data, {
    String? error,
    bool rejected = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: QueueBStyle.theme,
        home: Scaffold(
          body: DisplayBoard(
            snapshot: data,
            now: DateTime.utc(2026, 10, 18, 12, 34, 56),
            status: error == null
                ? 'Realtime terhubung'
                : 'Realtime terputus · sinkronisasi berkala aktif',
            error: error,
            rejected: rejected,
            onRefresh: () {},
            onAudio: () {},
            onConfigure: () {},
            onFullscreen: () {},
          ),
        ),
      ),
    );
    await tester.pump();
  }

  for (final size in [const Size(1280, 720), const Size(1920, 1080)]) {
    for (final count in [1, 3, 6]) {
      testWidgets(
        'TV $size: all $count clinic rooms, prominent call and true zero waiting',
        (tester) async {
          await board(tester, size, _snapshot(rooms: count));
          expect(tester.takeException(), isNull);
          expect(find.text('Poliklinik Mata'), findsOneWidget);
          expect(
            find.byKey(const ValueKey('display-call-number')),
            findsOneWidget,
          );
          expect(
            tester
                .getSize(find.byKey(const ValueKey('display-call-number')))
                .height,
            greaterThan(140),
          );
          expect(
            tester
                .widget<Text>(
                  find.byKey(const ValueKey('display-waiting-count')),
                )
                .data,
            '0',
          );
          for (var n = 1; n <= count; n++) {
            expect(find.text('Ruang Mata $n'), findsWidgets);
          }
          expect(find.text('12:34:56'), findsOneWidget);
        },
      );
    }
  }

  for (final width in [320.0, 375.0, 414.0, 768.0]) {
    testWidgets(
      'Display preview remains readable without horizontal overflow at $width',
      (tester) async {
        await board(tester, Size(width, 900), _snapshot(rooms: 3));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'TV cycles overflow room rows automatically without leaving the clinic',
    (tester) async {
      await board(tester, const Size(1280, 720), _snapshot(rooms: 12));
      expect(find.text('Ruang Mata 1'), findsWidgets);
      await tester.pump(const Duration(seconds: 12));
      await tester.pump();
      expect(find.text('Ruang Mata 12'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'No waiting/active patients shows no fake queue number or estimate',
    (tester) async {
      await board(
        tester,
        const Size(1280, 720),
        _snapshot(rooms: 2, status: null),
      );
      expect(find.text('Belum ada nomor dipanggil.'), findsOneWidget);
      expect(find.text('Siap melayani'), findsNWidgets(2));
      expect(find.byKey(const ValueKey('display-call-number')), findsNothing);
      expect(find.textContaining('menit'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Stale data visibly marked during reconnect; sensitive extras never rendered',
    (tester) async {
      final data = _snapshot()
        ..['pasien'] = {
          'nama': 'Private Patient',
          'email': 'private@example.test',
          'qrPayload': 'SQ1.private',
        };
      await board(tester, const Size(1280, 720), data, error: 'offline');
      expect(find.textContaining('menampilkan data terakhir'), findsOneWidget);
      expect(find.text('MAT-001'), findsWidgets);
      expect(find.textContaining('Private Patient'), findsNothing);
      expect(find.textContaining('private@example.test'), findsNothing);
      expect(find.textContaining('SQ1.'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Loading and rejected token are distinct and unknown total is not zero',
    (tester) async {
      await board(tester, const Size(1280, 720), null);
      expect(find.text('Memuat antrean…'), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('display-waiting-count')))
            .data,
        '—',
      );
      expect(tester.takeException(), isNull);
      await board(
        tester,
        const Size(1280, 720),
        null,
        error: 'denied',
        rejected: true,
      );
      expect(find.text('Akses display ditolak'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Ganti perangkat'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Invalid device token stops REST polling and clears the token input',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      var requests = 0;
      final api = QueueApi(
        config: AppConfig(
          apiBaseUrl: 'http://localhost:3000/api/v1',
          realtime: false,
        ),
        client: MockClient((r) async {
          if (r.url.path.endsWith('/display/sesi')) {
            return http.Response('{}', 401);
          }
          requests++;
          expect(r.headers['x-display-token'], 'a' * 64);
          expect(r.url.hasQuery, isFalse);
          return http.Response(jsonEncode({'message': 'Forbidden'}), 403);
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: DisplayPage(api: api, onExit: () {}),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Konfigurasi lanjutan (token existing)'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'ID layanan'),
        _service,
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Token perangkat'),
        'a' * 64,
      );
      await tester.ensureVisible(find.text('Hubungkan display'));
      await tester.tap(find.text('Hubungkan display'));
      await tester.pumpAndSettle();
      expect(find.text('Akses display ditolak'), findsOneWidget);
      await tester.pump(const Duration(seconds: 45));
      expect(requests, 1);
      await tester.ensureVisible(find.text('Ganti perangkat'));
      await tester.tap(find.text('Ganti perangkat'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(
              find.widgetWithText(TextFormField, 'Token perangkat'),
            )
            .controller!
            .text,
        isEmpty,
      );
      expect(
        tester
            .widget<TextFormField>(
              find.widgetWithText(TextFormField, 'ID layanan'),
            )
            .controller!
            .text,
        _service,
      );
      await tester.pumpWidget(const SizedBox());
      api.dispose();
    },
  );
}
