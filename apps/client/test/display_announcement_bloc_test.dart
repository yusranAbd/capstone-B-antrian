import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:queueb_client/src/features/display/models/display_models.dart';

import 'display_bloc_fixture.dart';

void main() {
  setUpAll(tz.initializeTimeZones);
  late DisplayFixture f;
  setUp(() => f = DisplayFixture(realtime: true));
  tearDown(() => f.dispose());
  Future<void> ready({bool audio = true}) async {
    await f.device.restore();
    await f.until((s) => s.scope != null);
    expect(f.backend.count('/display/$clinicA/snapshot'), 0);
    f.feeds.single.ready();
    await f.until((s) => s.snapshot != null);
    if (audio) await f.audio.toggle();
  }

  Future<void> signal(String id, {String action = 'CALL'}) async {
    f.backend.announcement(displayA, id, action: action);
    f.feeds.single.changed('event-$id', action);
    await f.monitor.refresh();
    await f.audio.settled;
  }

  test(
    '5C live bootstrap waits ready and historical call remains silent',
    () async {
      await ready(audio: false);
      expect(f.speech.spoken, isEmpty);
      await f.audio.toggle();
      expect(f.speech.spoken, ['Suara pengumuman QueueB aktif.']);
      expect(f.activeFeeds, 1);
    },
  );
  test(
    '5C CALL once, duplicate event and REST never double announce',
    () async {
      await ready();
      await signal('call-1');
      f.feeds.single.changed('event-call-1', 'CALL');
      await f.monitor.refresh();
      await f.audio.settled;
      expect(f.speech.spoken.where((s) => s.contains('call-1')), hasLength(1));
      expect(f.speech.languages.every((s) => s == 'id-ID'), isTrue);
    },
  );
  test(
    '5C valid RECALL for same ticket uses distinct server announcement ID',
    () async {
      await ready();
      await signal('call-1');
      await signal('recall-1', action: 'RECALL');
      expect(f.speech.spoken, hasLength(3));
      expect(f.speech.spoken.last, contains('recall-1'));
    },
  );
  test(
    '5C CALL during active fetch announced from trailing REST exactly once',
    () async {
      await ready();
      final gate = f.backend.block('/display/$clinicA/snapshot');
      final read = f.monitor.refresh();
      await gate.entered.future;
      final accepted = f.monitor.stream.firstWhere((s) => s.refreshing);
      f.backend.announcement(displayA, 'during-call');
      f.feeds.single.changed('new-during-call', 'CALL');
      await accepted;
      final join = f.monitor.refresh();
      gate.release.complete();
      await read;
      await join;
      await f.audio.settled;
      expect(
        f.speech.spoken.where((s) => s.contains('during-call')),
        hasLength(1),
      );
    },
  );
  test('5C non-consecutive duplicate announcement never replayed', () async {
    await ready();
    await signal('one');
    await signal('two');
    f.backend.announcement(displayA, 'one');
    f.feeds.single.changed('new-socket-event', 'CALL');
    await f.monitor.refresh();
    await f.audio.settled;
    expect(f.speech.spoken.where((s) => s.contains('one')), hasLength(1));
  });
  for (final action in ['SKIP', 'REQUEUE', 'START', 'COMPLETE', 'ENQUEUE']) {
    test('5C $action refreshes REST without TTS', () async {
      await ready();
      await signal('not-a-call', action: action);
      expect(f.speech.spoken, hasLength(1));
    });
  }
  test('5C manual refresh and fallback-like reads never announce', () async {
    await ready();
    f.backend.announcement(displayA, 'manual');
    await f.monitor.refresh(silent: true);
    await f.monitor.refresh();
    await f.audio.settled;
    expect(f.speech.spoken, hasLength(1));
    await signal('next', action: 'RECALL');
    expect(f.speech.spoken, hasLength(2));
  });
  test('5C reconnect rebases missed call, resumes only new RECALL', () async {
    await ready();
    await signal('before');
    f.feeds.single.status('Realtime terputus · sinkronisasi berkala aktif');
    await f.until((s) => s.status.contains('terputus'));
    f.backend.announcement(displayA, 'offline');
    f.feeds.single.ready();
    await f.monitor.refresh();
    await f.audio.settled;
    expect(f.speech.spoken.where((s) => s.contains('offline')), isEmpty);
    await signal('after', action: 'RECALL');
    expect(f.speech.spoken.last, contains('after'));
    expect(f.feeds, hasLength(1));
  });
  test('snapshot 500 does not synthesize unverified CALL; new RECALL works after recovery', () async {
    await ready();
    final path = 'GET /display/$clinicA/snapshot';
    f.backend.failures[path] = 500;
    await signal('upstream-failed-call');
    expect(f.monitor.state.errorStatus, 500);
    expect(f.speech.spoken, hasLength(1));
    f.backend.failures.remove(path);
    await f.monitor.refresh(silent: true);
    await f.audio.settled;
    expect(f.monitor.state.errorStatus, isNull);
    expect(f.speech.spoken, hasLength(1));
    await signal('recovered-recall', action: 'RECALL');
    expect(f.speech.spoken.last, contains('recovered-recall'));
    expect(f.speech.spoken, hasLength(2));
    f.feeds.single.changed('event-recovered-recall', 'RECALL');
    await f.monitor.refresh();
    await f.audio.settled;
    expect(f.speech.spoken, hasLength(2));
  });
  test(
    '5C muted calls consumed without backlog when user activates audio',
    () async {
      await ready(audio: false);
      await signal('muted');
      expect(f.speech.spoken, isEmpty);
      await f.audio.toggle();
      await f.monitor.refresh();
      expect(f.speech.spoken, ['Suara pengumuman QueueB aktif.']);
      await signal('future');
      expect(f.speech.spoken.last, contains('future'));
    },
  );
  test('5C unavailable voice never enables audio', () async {
    await ready(audio: false);
    f.speech.noVoice = true;
    await f.audio.toggle();
    expect(f.audio.enabled, isFalse);
    expect(f.audio.error, isNotNull);
    expect(f.speech.spoken, isEmpty);
  });
  test(
    '5C synthesis failure keeps visual monitor and disables audio',
    () async {
      await ready();
      f.speech.fail = true;
      await signal('failure');
      expect(f.audio.enabled, isFalse);
      expect(f.audio.error, isNotNull);
      expect(f.monitor.state.snapshot, isNotNull);
    },
  );
  test(
    '5C asynchronous engine failure safe; cancellation is expected',
    () async {
      await ready();
      f.speech.callback!('canceled');
      expect(f.audio.enabled, isTrue);
      f.speech.callback!('interrupted');
      expect(f.audio.enabled, isTrue);
      f.speech.callback!('PRIVATE engine data');
      expect(f.audio.enabled, isFalse);
      expect(f.audio.error, isNot(contains('PRIVATE')));
    },
  );
  test('5C revoke stops speech immediately and drops subscription', () async {
    await ready();
    final before = f.speech.stops;
    f.feeds.single.status(
      'Token perangkat ditolak. Aktifkan ulang dari ADMIN.',
    );
    await f.until((s) => s.rejected);
    expect(f.speech.stops, greaterThan(before));
    expect(f.audio.enabled, isFalse);
    expect(f.activeFeeds, 0);
    expect(f.device.state.phase, DisplayDevicePhase.rejected);
  });
  test(
    '5C context invalidation while audio enabling cannot enable old device',
    () async {
      await ready(audio: false);
      final gate = f.speech.voiceGate = Completer<void>();
      final pending = f.audio.toggle();
      f.devices.begin();
      gate.complete();
      await pending;
      expect(f.audio.enabled, isFalse);
      expect(f.speech.spoken, isEmpty);
    },
  );
  test('5C pause prevents speech while hidden and resume is silent', () async {
    await ready();
    f.monitor.pause();
    await signal('hidden');
    expect(f.speech.spoken, hasLength(1));
    await f.monitor.resume();
    await signal('visible', action: 'RECALL');
    expect(f.speech.spoken.last, contains('visible'));
  });
  test(
    '5C event during fetch belongs to trailing read, no premature announcement',
    () async {
      await ready();
      final gate = f.backend.block('/display/$clinicA/snapshot');
      final read = f.monitor.refresh();
      await gate.entered.future;
      f.backend.announcement(displayA, 'during-read');
      f.feeds.single.changed('during-event', 'CALL');
      final join = f.monitor.refresh();
      f.feeds.single.status('Realtime terhubung');
      await f.until((s) => s.status == 'Realtime terhubung' && s.refreshing);
      gate.release.complete();
      await read;
      await join;
      await f.audio.settled;
      // Reconnect status intentionally establishes a silent baseline.
      expect(f.speech.spoken, hasLength(1));
      await signal('fresh', action: 'RECALL');
      expect(f.speech.spoken.last, contains('fresh'));
    },
  );
  test(
    '5C monitor close stops engine, controller disposal releases handler',
    () async {
      await ready();
      final before = f.speech.stops;
      await f.monitor.close();
      expect(f.speech.stops, greaterThan(before));
      f.audio.dispose();
      expect(f.speech.callback, isNull);
      f.feeds.single.changed('late', 'CALL');
      expect(f.speech.spoken, hasLength(1));
    },
  );
}
