import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:queueb_client/src/config.dart';
import 'package:queueb_client/src/display.dart';
import 'package:queueb_client/src/display_board.dart';
import 'package:queueb_client/src/features/display/application/display_device_cubit.dart';
import 'package:queueb_client/src/features/display/application/display_monitor_bloc.dart';
import 'package:queueb_client/src/features/display/models/display_models.dart';

import 'display_bloc_fixture.dart';

void main() {
  setUpAll(tz.initializeTimeZones);
  late DisplayBackend backend;
  final fixtures = <DisplayFixture>[];
  setUp(() {
    backend = DisplayBackend();
    fixtures.clear();
  });
  tearDown(() async {
    for (final fixture in fixtures) {
      await fixture.dispose();
    }
  });
  DisplayFixture create(String? id, {FakeDisplayTimer? timer}) {
    final fixture = DisplayFixture(backend: backend, id: id, timer: timer);
    fixtures.add(fixture);
    return fixture;
  }

  test('5D three fake tabs retain device selectors, two clinics and same-clinic identities', () async {
    final a = create(displayA), b = create(displayB), c = create(displayC);
    await Future.wait([a.load(), b.load(), c.load()]);
    expect({
      a.device.state.scope!.deviceId,
      b.device.state.scope!.deviceId,
      c.device.state.scope!.deviceId,
    }, hasLength(3));
    expect(a.device.state.scope!.serviceId, c.device.state.scope!.serviceId);
    expect(b.device.state.scope!.serviceId, clinicB);
    expect([a.activeFeeds, b.activeFeeds, c.activeFeeds], [1, 1, 1]);
    expect(a.selection.value, displayA);
    expect(b.selection.value, displayB);
    expect(c.selection.value, displayC);
  });
  test('5D pairing B leaves already active A unchanged', () async {
    final a = create(displayA), b = create(null);
    await a.load();
    await b.device.pair('223456789012');
    await b.until((s) => s.snapshot != null);
    expect(a.selection.value, displayA);
    expect(b.selection.value, displayB);
    await a.monitor.refresh();
    expect(a.monitor.state.snapshot!['layanan']['id'], clinicA);
  });
  for (final operation in ['revoke', 'rotate']) {
    test('5D fake backend $operation A leaves B and C scopes valid', () async {
      final a = create(displayA), b = create(displayB), c = create(displayC);
      await Future.wait([a.load(), b.load(), c.load()]);
      backend.denied.add(displayA);
      await a.monitor.refresh();
      await a.until((s) => s.rejected);
      await Future.wait([b.monitor.refresh(), c.monitor.refresh()]);
      expect(a.monitor.state.snapshot, isNull);
      expect(b.monitor.state.rejected, isFalse);
      expect(c.monitor.state.rejected, isFalse);
      expect(b.selection.value, displayB);
      expect(c.selection.value, displayC);
    });
  }
  test(
    '5D disconnect A leaves B credential, audio and subscription unchanged',
    () async {
      final a = create(displayA), b = create(displayB);
      await Future.wait([a.load(), b.load()]);
      await b.audio.toggle();
      final stopped = b.speech.stops;
      await a.device.disconnect();
      await a.until((s) => s.scope == null);
      expect(b.audio.enabled, isTrue);
      expect(b.speech.stops, stopped);
      expect(b.activeFeeds, 1);
      expect(b.selection.value, displayB);
      expect(backend.denied, isNot(contains(displayB)));
    },
  );
  test('5D reconnect A cannot change B clinic or play on B engine', () async {
    final a = create(displayA), b = create(displayB);
    await Future.wait([a.load(), b.load()]);
    await Future.wait([a.audio.toggle(), b.audio.toggle()]);
    a.feeds.single.ready();
    await a.monitor.refresh();
    backend.announcement(displayA, 'a-only');
    a.feeds.single.changed('a-event', 'CALL');
    await a.monitor.refresh();
    await a.audio.settled;
    expect(a.speech.spoken.last, contains('a-only'));
    expect(b.speech.spoken, hasLength(1));
    expect(b.monitor.state.snapshot!['layanan']['id'], clinicB);
  });
  test(
    '5D same event received by different monitors stays local to each instance',
    () async {
      final a = create(displayA), c = create(displayC);
      await Future.wait([a.load(), c.load()]);
      await Future.wait([a.audio.toggle(), c.audio.toggle()]);
      backend.announcement(displayA, 'shared');
      backend.announcement(displayC, 'shared');
      a.feeds.single.changed('same-event', 'CALL');
      c.feeds.single.changed('same-event', 'CALL');
      await Future.wait([a.monitor.refresh(), c.monitor.refresh()]);
      await Future.wait([a.audio.settled, c.audio.settled]);
      expect(a.speech.spoken.where((s) => s.contains('shared')), hasLength(1));
      expect(c.speech.spoken.where((s) => s.contains('shared')), hasLength(1));
      await a.audio.toggle();
      expect(c.audio.enabled, isTrue);
    },
  );
  test(
    '5D wrong service event rejected before REST/audio invalidation',
    () async {
      final a = create(displayA);
      await a.load();
      final before = backend.calls.length;
      a.feeds.single.changed('wrong', 'CALL', service: clinicB);
      // A subsequent explicit refresh is a deterministic barrier for queued events.
      await a.monitor.refresh();
      expect(backend.calls.length, before + 1);
      expect(a.monitor.state.snapshot!['layanan']['id'], clinicA);
    },
  );
  test('5D account JWT is never used for device endpoints', () async {
    final a = create(displayA);
    a.api.user = {'id': 'admin', 'peran': 'ADMIN'};
    a.api.accessToken = 'ACCOUNT-FIXTURE-ONLY';
    await a.load();
    await a.device.disconnect();
    expect(
      backend.calls.every((r) => !r.headers.containsKey('Authorization')),
      isTrue,
    );
    expect(
      backend.calls.every((r) => !r.headers.containsKey('x-display-token')),
      isTrue,
    );
  });
  for (final mode in ['SAMAR', 'LENGKAP', 'TANPA_NAMA']) {
    test(
      '5D privacy projection $mode is preserved for screen and TTS',
      () async {
        final a = create(displayA);
        final data = backend.snapshot(displayA);
        data['modeNama'] = mode;
        final name = mode == 'TANPA_NAMA'
            ? null
            : mode == 'LENGKAP'
            ? 'Pasien Fixture Lengkap'
            : 'Pasien F.';
        data['antrianPasien'] = [
          for (final row in data['antrianPasien'] as List)
            {...object(row), 'namaPasien': name},
        ];
        data['loket'] = [
          for (final room in data['loket'] as List)
            {
              ...object(room),
              'tiketAktif': [
                for (final row in room['tiketAktif'] as List)
                  {...object(row), 'namaPasien': name},
              ],
            },
        ];
        data['pengumumanTerakhir'] = {
          'peristiwaId': 'safe',
          'aksi': 'CALL',
          'teks': 'Teks aman dari server.',
        };
        await a.load();
        expect(a.monitor.state.snapshot!['modeNama'], mode);
        expect(
          a.monitor.state.snapshot!['pengumumanTerakhir']['teks'],
          'Teks aman dari server.',
        );
        expect(
          jsonEncode(a.monitor.state.snapshot),
          isNot(contains('ACCOUNT')),
        );
        expect(
          (a.monitor.state.snapshot!['antrianPasien'] as List)
              .first['namaPasien'],
          name,
        );
        await a.audio.toggle();
        final text = name == null
            ? 'Panggilan tanpa nama.'
            : 'Panggilan atas nama $name.';
        data['pengumumanTerakhir'] = {
          'peristiwaId': 'privacy-$mode',
          'aksi': 'CALL',
          'teks': text,
        };
        a.feeds.single.changed('event-$mode', 'CALL');
        await a.monitor.refresh();
        await a.audio.settled;
        expect(a.speech.spoken.last, text);
      },
    );
  }
  test(
    '5D 15-second fallback is bounded and close cancels timer/feed/audio',
    () async {
      final timer = FakeDisplayTimer(),
          a = create(displayA, timer: FakeDisplayTimer());
      // Inspect the explicitly injected timer on another independent device.
      final b = create(displayB, timer: timer);
      await Future.wait([a.load(), b.load()]);
      expect(timer.interval, const Duration(seconds: 15));
      final gate = backend.block('/display/$clinicB/snapshot');
      final read = b.monitor.refresh();
      await gate.entered.future;
      for (var i = 0; i < 30; i++) {
        timer.fire();
      }
      final join = b.monitor.refresh();
      b.feeds.single.status('timer accepted');
      await b.until((s) => s.status == 'timer accepted');
      expect(backend.maxReads[displayB], 1);
      gate.release.complete();
      await read;
      await join;
      await b.monitor.close();
      final count = backend.calls.length;
      for (var i = 0; i < 30; i++) {
        timer.fire();
      }
      b.feeds.single.refresh();
      expect(backend.calls.length, count);
      expect(timer.isActive, isFalse);
      expect(b.activeFeeds, 0);
    },
  );
  test(
    '5D old feed after device switch cannot update status or snapshot',
    () async {
      final a = create(displayA);
      await a.load();
      final old = a.feeds.single;
      a.selection.value = displayB;
      await a.device.restore();
      await a.until((s) => s.scope?.deviceId == displayB && s.snapshot != null);
      old.status('OLD STATUS');
      old.changed('old-event', 'CALL');
      await a.monitor.refresh();
      expect(a.monitor.state.status, isNot('OLD STATUS'));
      expect(a.activeFeeds, 1);
    },
  );
  for (final size in [
    const Size(1280, 720),
    const Size(1366, 768),
    const Size(1920, 1080),
  ]) {
    testWidgets(
      '5D integrated V3 $size: actual providers, clock/pagination never fetch or speak',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final a = (await tester.runAsync(() async {
          final fixture = create(displayA);
          await fixture.monitor.close();
          await fixture.device.close();
          return fixture;
        }))!;
        backend.snapshot(displayA)['antrianPasien'] = [
          for (var i = 0; i < 35; i++)
            {
              'nomorAntrean': 'QA-$i',
              'status': 'MENUNGGU',
              'namaPasien': 'Pasien Q.',
            },
        ];
        await tester.pumpWidget(
          MaterialApp(
            home: DisplayPage(
              api: a.api,
              onExit: () {},
              deviceRepository: a.devices,
              audioController: a.audio,
              feedFactory: a.feedFactory,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byType(BlocBuilder<DisplayDeviceCubit, DisplayDeviceState>),
          findsOneWidget,
        );
        expect(
          find.byType(BlocBuilder<DisplayMonitorBloc, DisplayMonitorState>),
          findsOneWidget,
        );
        expect(find.byType(DisplayBoard), findsOneWidget);
        expect(find.byType(Scrollable), findsNothing);
        final before = backend.calls.length;
        final board = tester.widget<DisplayBoard>(find.byType(DisplayBoard));
        final oldSnapshot = board.snapshot;
        await tester.pump(const Duration(seconds: 1));
        expect(
          identical(
            tester.widget<DisplayBoard>(find.byType(DisplayBoard)).snapshot,
            oldSnapshot,
          ),
          isTrue,
        );
        await tester.pump(const Duration(seconds: 12));
        expect(backend.calls.length, before);
        expect(a.speech.spoken, isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        final closed = backend.calls.length;
        await tester.pump(const Duration(seconds: 60));
        expect(backend.calls.length, closed);
        expect(a.activeFeeds, 0);
      },
    );
  }
}
