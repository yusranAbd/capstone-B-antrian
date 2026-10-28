import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:queueb_client/src/config.dart';
import 'package:queueb_client/src/features/display/models/display_models.dart';

import 'display_bloc_fixture.dart';

void main() {
  setUpAll(tz.initializeTimeZones);
  late DisplayFixture f;
  setUp(() => f = DisplayFixture());
  tearDown(() => f.dispose());
  test('5B initial snapshot and server projections are retained', () async {
    await f.load();
    final data = f.monitor.state.snapshot!;
    expect(data['loket'][0]['tiketAktif'][0]['status'], 'DIPANGGIL');
    expect(data['antrianPasien'][0]['status'], 'MENUNGGU');
    expect(data['antrianPasien'][1]['status'], 'DILEWATI');
    expect(data['layanan']['id'], clinicA);
  });
  test('5B initial failure is explicit, not fabricated empty queue', () async {
    f.backend.failures['GET /display/$clinicA/snapshot'] = 503;
    await f.load();
    expect(f.monitor.state.snapshot, isNull);
    expect(f.monitor.state.errorStatus, 503);
    expect(f.monitor.state.loading, isFalse);
  });
  test(
    '5B empty snapshot preserves zero only when actually returned',
    () async {
      f.backend.snapshot(displayA).addAll({
        'menunggu': [],
        'antrianPasien': [],
        'loket': [],
        'totalMenunggu': 0,
        'totalAntrianPasien': 0,
      });
      await f.load();
      expect(f.monitor.state.snapshot!['totalAntrianPasien'], 0);
      expect(f.monitor.state.snapshot!['antrianPasien'], isEmpty);
    },
  );
  test('5B SKIP and REQUEUE status changes follow REST; order never sorted locally', () async {
    await f.load();
    final list = f.backend.snapshot(displayA)['antrianPasien'] as List;
    list[0]['status'] = 'DILEWATI';
    await f.monitor.refresh();
    expect(f.monitor.state.snapshot!['antrianPasien'][0]['status'], 'DILEWATI');
    list[0]['status'] = 'MENUNGGU';
    f.backend.snapshot(displayA)['antrianPasien'] = list.reversed.toList();
    await f.monitor.refresh();
    expect(
      f.monitor.state.snapshot!['antrianPasien'][0]['nomorAntrean'],
      'A-002',
    );
    expect(f.monitor.state.snapshot!['antrianPasien'][1]['status'], 'MENUNGGU');
  });
  test('5B all callers await active and trailing refresh (S02)', () async {
    await f.load();
    final first = f.backend.block('/display/$clinicA/snapshot'),
        last = f.backend.block('/display/$clinicA/snapshot');
    final read = f.monitor.refresh();
    await first.entered.future;
    final join = f.monitor.refresh();
    var done = false;
    unawaited(
      join.then((_) {
        done = true;
      }),
    );
    await f.until((s) => s.refreshing);
    f.feeds.single.status('trailing accepted');
    await f.until((s) => s.status == 'trailing accepted');
    first.release.complete();
    await last.entered.future;
    expect(done, isFalse);
    expect(f.backend.maxReads[displayA], 1);
    last.release.complete();
    await read;
    await join;
    expect(done, isTrue);
  });
  test('5B burst invalidations coalesce without parallel fetches', () async {
    await f.load();
    final before = f.backend.count('/display/$clinicA/snapshot');
    final gate = f.backend.block('/display/$clinicA/snapshot');
    final pending = f.monitor.refresh();
    await gate.entered.future;
    for (var i = 0; i < 20; i++) {
      f.feeds.single.changed('burst-$i', 'SKIP');
    }
    final join = f.monitor.refresh();
    f.feeds.single.status('burst accepted');
    await f.until((s) => s.status == 'burst accepted');
    gate.release.complete();
    await pending;
    await join;
    expect(f.backend.count('/display/$clinicA/snapshot'), before + 2);
    expect(f.backend.maxReads[displayA], 1);
  });
  test('5B invalidation during trailing read is retained', () async {
    await f.load();
    final before = f.backend.count('/display/$clinicA/snapshot');
    final a = f.backend.block('/display/$clinicA/snapshot'),
        b = f.backend.block('/display/$clinicA/snapshot');
    final pending = f.monitor.refresh();
    await a.entered.future;
    final join = f.monitor.refresh();
    f.feeds.single.status('a accepted');
    await f.until((s) => s.status == 'a accepted');
    a.release.complete();
    await b.entered.future;
    final third = f.monitor.refresh();
    f.feeds.single.status('b accepted');
    await f.until((s) => s.status == 'b accepted');
    b.release.complete();
    await pending;
    await join;
    await third;
    expect(f.backend.count('/display/$clinicA/snapshot'), before + 3);
  });
  test(
    '5B read failure preserves same-scope valid data and later recovers',
    () async {
      await f.load();
      f.backend.failures['GET /display/$clinicA/snapshot'] = 503;
      await f.monitor.refresh();
      expect(f.monitor.state.snapshot, isNotNull);
      expect(f.monitor.state.error, isNotNull);
      f.backend.failures.clear();
      await f.monitor.refresh();
      expect(f.monitor.state.error, isNull);
    },
  );
  test('5B stale old-device response never overwrites new device', () async {
    await f.load();
    final gate = f.backend.block('/display/$clinicA/snapshot');
    final old = f.monitor.refresh();
    await gate.entered.future;
    f.selection.value = displayB;
    await f.device.restore();
    await f.until((s) => s.scope?.deviceId == displayB && s.snapshot != null);
    gate.release.complete();
    await old;
    expect(f.monitor.state.snapshot!['layanan']['id'], clinicB);
    expect(f.activeFeeds, 1);
  });
  test(
    '5B invalid snapshot version preserves valid data with failure',
    () async {
      await f.load();
      f.backend.snapshot(displayA)['versiSkema'] = 9;
      await f.monitor.refresh();
      expect(f.monitor.state.error, isNotNull);
      expect(f.monitor.state.snapshot!['versiSkema'], 1);
    },
  );
  test('5B wrong clinic projection rejected before emission', () async {
    f.backend.snapshot(displayA)['layanan'] = {
      'id': clinicB,
      'nama': 'Other clinic',
    };
    await f.load();
    expect(f.monitor.state.snapshot, isNull);
    expect(f.monitor.state.error, isNotNull);
  });
  test('5B nested snapshot is copied and recursively immutable', () async {
    await f.load();
    final data = f.monitor.state.snapshot!;
    expect(
      () => (data['antrianPasien'] as List).clear(),
      throwsUnsupportedError,
    );
    expect(
      () => (data['layanan'] as Json)['nama'] = 'bad',
      throwsUnsupportedError,
    );
    f.backend.snapshot(displayA)['totalMenunggu'] = 99;
    expect(data['totalMenunggu'], 1);
  });
  test(
    '5B private fields from malformed extra payload never enter snapshot',
    () async {
      f.backend.snapshot(displayA).addAll({
        'cookie': 'SECRET',
        'email': 'PRIVATE',
        'qrPayload': 'RAW',
        'token': 'SECRET',
      });
      (f.backend.snapshot(displayA)['antrianPasien'] as List).first.addAll({
        'nik': 'PRIVATE',
        'penggunaId': 'PRIVATE',
      });
      await f.load();
      final text = jsonEncode(f.monitor.state.snapshot);
      expect(text, isNot(contains('SECRET')));
      expect(text, isNot(contains('PRIVATE')));
      expect(text, isNot(contains('RAW')));
    },
  );
  for (final code in [401, 403]) {
    test(
      '5B snapshot $code clears data, credential scope and subscription',
      () async {
        await f.load();
        f.backend.failures['GET /display/$clinicA/snapshot'] = code;
        await f.monitor.refresh();
        await f.until((s) => s.rejected);
        expect(f.monitor.state.snapshot, isNull);
        expect(f.activeFeeds, 0);
        expect(f.device.state.phase, DisplayDevicePhase.rejected);
        expect(f.devices.scope, isNull);
      },
    );
  }
  test(
    '5B close while fetching clears snapshot and ignores late response',
    () async {
      await f.load();
      final gate = f.backend.block('/display/$clinicA/snapshot');
      final read = f.monitor.refresh();
      await gate.entered.future;
      final close = f.monitor.close();
      gate.release.complete();
      await read;
      await close;
      expect(f.monitor.state.snapshot, isNull);
      expect(f.activeFeeds, 0);
      f.feeds.single.refresh();
      expect(f.monitor.isClosed, isTrue);
    },
  );
}
