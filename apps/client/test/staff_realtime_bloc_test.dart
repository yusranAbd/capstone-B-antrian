import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:queueb_client/src/api.dart';
import 'package:queueb_client/src/features/staff/application/staff_queue_bloc.dart';
import 'package:queueb_client/src/features/staff/application/staff_queue_event.dart';
import 'package:queueb_client/src/features/staff/application/staff_queue_state.dart';
import 'package:queueb_client/src/features/staff/models/staff_queue_models.dart';
import 'package:queueb_client/src/queue.dart';
import 'package:queueb_client/src/staff_qr_scanner.dart';

import 'staff_bloc_fixture.dart';

void main() {
  setUpAll(tz.initializeTimeZones);
  late StaffFixture f;
  setUp(() => f = StaffFixture());
  tearDown(() => f.dispose());
  test(
    '4D queue event only invalidates REST instead of applying socket status',
    () async {
      await f.load();
      final count = f.api.count('/queue/snapshot');
      f.api.status = 'DILEWATI';
      f.feeds.single.refresh();
      await f.api.waitCount('/queue/snapshot', count + 1);
      await f.until(
        (s) => s.synchronized && s.patients.single['status'] == 'DILEWATI',
      );
      expect(f.feedCount, 1);
    },
  );
  test('4D burst invalidations coalesce to one trailing fetch and every waiter awaits it', () async {
    await f.load();
    final count = f.api.count('/queue/snapshot');
    final first = f.api.block('/queue/snapshot'),
        last = f.api.block('/queue/snapshot');
    final pending = f.bloc.refresh();
    await first.entered.future;
    for (var i = 0; i < 20; i++) {
      f.feeds.single.refresh();
    }
    final join = f.bloc.refresh();
    // This final invalidation is ordered after the burst's queued refresh events.
    final status = f.bloc.stream.firstWhere(
      (s) => s.liveStatus == 'burst accepted',
    );
    f.feeds.single.status('burst accepted');
    await status;
    var done = false;
    unawaited(
      join.then((_) {
        done = true;
      }),
    );
    first.release.complete();
    await last.entered.future;
    expect(done, isFalse);
    expect(f.api.count('/queue/snapshot'), count + 2);
    expect(f.api.maxReads['/queue/snapshot:$staffRoomA'], 1);
    last.release.complete();
    await pending;
    await join;
    expect(done, isTrue);
  });
  test('4D invalidation during trailing read is not lost', () async {
    await f.load();
    final count = f.api.count('/queue/snapshot');
    final a = f.api.block('/queue/snapshot'),
        b = f.api.block('/queue/snapshot');
    final pending = f.bloc.refresh();
    await a.entered.future;
    final join = f.bloc.refresh();
    await f.until((s) => s.load == StaffLoad.refreshing);
    a.release.complete();
    await b.entered.future;
    final third = f.bloc.refresh();
    f.feeds.single.status('third accepted');
    await f.until((s) => s.liveStatus == 'third accepted');
    b.release.complete();
    await pending;
    await join;
    await third;
    expect(f.api.count('/queue/snapshot'), count + 3);
  });
  test(
    '4D reconnect invalidates snapshot without creating another feed',
    () async {
      await f.load();
      final feed = f.feeds.single, count = f.api.count('/queue/snapshot');
      feed.status('Realtime terputus · sinkronisasi berkala aktif');
      await f.until((s) => s.liveStatus.contains('terputus'));
      feed.status('Realtime terhubung');
      feed.refresh();
      await f.api.waitCount('/queue/snapshot', count + 1);
      await f.until(
        (s) => s.synchronized && s.liveStatus == 'Realtime terhubung',
      );
      expect(f.feeds, hasLength(1));
      expect(f.feedCount, 1);
    },
  );
  test('4D same-scope refresh never recreates realtime owner', () async {
    await f.load();
    await Future.wait([
      f.bloc.refresh(),
      f.bloc.refresh(),
      f.bloc.refresh(assignments: true),
    ]);
    expect(f.feeds, hasLength(1));
    expect(f.feedCount, 1);
  });
  test(
    '4D old room snapshot and old feed callbacks ignored after scope switch',
    () async {
      await f.load();
      final oldFeed = f.feeds.single;
      final gate = f.api.block('/queue/snapshot');
      final old = f.bloc.refresh();
      await gate.entered.future;
      f.bloc.add(StaffRoomSelected(staffRoomB));
      await f.until((s) => s.roomId == staffRoomB && s.synchronized);
      final sequence = f.bloc.state.snapshot!['sequence'];
      oldFeed.refresh();
      oldFeed.status('stale status');
      gate.release.complete();
      await old;
      expect(f.bloc.state.snapshot!['sequence'], sequence);
      expect(f.bloc.state.liveStatus, isNot('stale status'));
      expect(oldFeed.disposed, isTrue);
      expect(f.feedCount, 1);
    },
  );
  for (final role in ['PETUGAS', 'ADMIN', 'USER']) {
    test(
      '4D account/role change to $role during command cannot publish old result',
      () async {
        await f.load();
        final gate = f.api.block('/queue/panggil', 'POST');
        final command = f.bloc.execute(StaffOperation.call);
        final failed = expectLater(command, throwsA(isA<ApiException>()));
        await gate.entered.future;
        f.api.changeIdentity('another-account', role: role);
        await f.until((s) => s.load == StaffLoad.ended);
        await failed;
        gate.release.complete();
        await f.bloc.refresh();
        expect(f.bloc.state.snapshot, isNull);
        expect(f.bloc.state.assignments, isEmpty);
        expect(f.bloc.state.message, isNull);
        expect(f.feedCount, 0);
      },
    );
  }
  test('4D logout stops feed and stale callbacks permanently', () async {
    await f.load();
    final feed = f.feeds.single;
    await f.api.clearSession();
    await f.until((s) => s.load == StaffLoad.ended);
    final count = f.api.calls.length;
    feed.refresh();
    feed.status('stale');
    await f.bloc.refresh();
    expect(f.api.calls.length, count);
    expect(f.bloc.state.liveStatus, isNot('stale'));
    expect(f.feedCount, 0);
  });
  test('4D close during snapshot read emits no late state', () async {
    await f.load();
    final gate = f.api.block('/queue/snapshot');
    final read = f.bloc.refresh();
    await gate.entered.future;
    final values = <StaffQueueState>[];
    final sub = f.bloc.stream.listen(values.add);
    final closed = f.bloc.close();
    gate.release.complete();
    await read;
    await closed;
    final count = values.length;
    f.feeds.single.refresh();
    expect(values.length, count);
    expect(f.bloc.isClosed, isTrue);
    expect(f.bloc.state.snapshot, isNull);
    expect(f.bloc.state.assignments, isEmpty);
    expect(f.feedCount, 0);
    await sub.cancel();
  });
  test('4D room cannot change during POST and reconciliation', () async {
    await f.load();
    final post = f.api.block('/queue/panggil', 'POST');
    final read = f.api.block('/queue/snapshot');
    final command = f.bloc.execute(StaffOperation.call);
    await post.entered.future;
    f.bloc.add(StaffRoomSelected(staffRoomB));
    post.release.complete();
    await read.entered.future;
    expect(f.bloc.state.roomId, staffRoomA);
    f.bloc.add(StaffRoomSelected(staffRoomB));
    read.release.complete();
    await command;
    expect(f.bloc.state.roomId, staffRoomA);
  });
  test('4D unknown result remains guarded across room changes', () async {
    await f.load();
    f.api.loseWithoutCommit = true;
    await expectLater(
      f.bloc.execute(StaffOperation.call),
      throwsA(isA<ApiException>()),
    );
    f.bloc.add(StaffRoomSelected(staffRoomB));
    await f.until((s) => s.roomId == staffRoomB && s.synchronized);
    await expectLater(
      f.bloc.execute(StaffOperation.call),
      throwsA(isA<ApiException>()),
    );
    expect(f.api.count('/queue/panggil', 'POST'), 1);
  });
  test('4D long disconnect retains existing 15-second fallback and disposal stops it', () async {
    await f.dispose();
    final timer = StaffManualTimer();
    f = StaffFixture(polling: true, timer: timer);
    await f.load();
    expect(timer.interval, const Duration(seconds: 15));
    final feed = f.feeds.single;
    feed.status('Realtime terputus · sinkronisasi berkala aktif');
    await f.until((s) => s.liveStatus.contains('terputus'));
    final count = f.api.count('/queue/snapshot');
    for (var i = 0; i < 10; i++) {
      timer.fire();
      await f.api.waitCount('/queue/snapshot', count + i + 1);
      await f.until(
        (s) => s.synchronized && s.snapshot!['sequence'] == count + i + 1,
      );
    }
    expect(f.api.count('/queue/snapshot'), count + 10);
    expect(f.api.maxReads['/queue/snapshot:$staffRoomA'], 1);
    expect(f.feeds, hasLength(1));
    await f.bloc.close();
    final closedCount = f.api.count('/queue/snapshot');
    for (var i = 0; i < 20; i++) {
      timer.fire();
    }
    expect(f.api.count('/queue/snapshot'), closedCount);
    expect(timer.isActive, isFalse);
  });
  test('4D fallback ticks coalesce while fetch is held', () async {
    await f.dispose();
    final timer = StaffManualTimer();
    f = StaffFixture(polling: true, timer: timer);
    await f.load();
    final count = f.api.count('/queue/snapshot');
    final gate = f.api.block('/queue/snapshot');
    final refresh = f.bloc.refresh();
    await gate.entered.future;
    for (var i = 0; i < 5; i++) {
      timer.fire();
    }
    final events = f.bloc.stream.firstWhere(
      (s) => s.liveStatus == 'timer accepted',
    );
    f.feeds.single.status('timer accepted');
    await events;
    expect(f.api.count('/queue/snapshot'), count + 1);
    gate.release.complete();
    await refresh;
    expect(f.api.count('/queue/snapshot'), count + 2);
  });
  testWidgets(
    '4D V4 provides actual StaffQueueBloc, single feed, no rebuild fetch, session closes scanner',
    (tester) async {
      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      // The fixture BLoC is idle; the page alone owns the injected repository feed.
      await tester.pumpWidget(
        MaterialApp(
          home: QueuePage(api: f.api, repository: f.repository),
        ),
      );
      await tester.pumpAndSettle();
      final element = tester.element(find.byType(QueuePage));
      expect(element, isNotNull);
      final consumer = tester.element(
        find.byType(BlocConsumer<StaffQueueBloc, StaffQueueState>),
      );
      final bloc = BlocProvider.of<StaffQueueBloc>(consumer);
      expect(bloc.state.patients.single['nomorAntrean'], 'U-001');
      expect(find.text('Dokter room-a'), findsOneWidget);
      final count = f.api.calls.length;
      await tester.enterText(
        find.widgetWithText(TextField, 'Cari nomor antrean atau nama pasien'),
        'U-',
      );
      await tester.pumpAndSettle();
      expect(f.api.calls.length, count);
      expect(f.feedCount, 1);
      await tester.tap(find.byKey(const ValueKey('staff-scan-fab')));
      await tester.pumpAndSettle();
      expect(find.byType(StaffQrScanner), findsOneWidget);
      await tester.runAsync(() => f.api.clearSession());
      await tester.pumpAndSettle();
      expect(find.byType(StaffQrScanner), findsNothing);
      expect(bloc.state.assignments, isEmpty);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(f.feedCount, 0);
    },
  );
}
