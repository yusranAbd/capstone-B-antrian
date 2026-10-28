import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:queueb_client/src/api.dart';
import 'package:queueb_client/src/config.dart';
import 'package:queueb_client/src/features/staff/application/staff_queue_event.dart';
import 'package:queueb_client/src/features/staff/application/staff_queue_state.dart';

import 'staff_bloc_fixture.dart';

void main() {
  setUpAll(tz.initializeTimeZones);
  late StaffFixture f;
  setUp(() => f = StaffFixture());
  tearDown(() => f.dispose());
  test(
    '4A initial assignments, room, service date, snapshot and schedule',
    () async {
      await f.load();
      expect(f.bloc.state.roomId, staffRoomA);
      expect(f.bloc.state.date, f.api.config.today);
      expect(f.bloc.state.synchronized, isTrue);
      expect(f.bloc.state.schedules.single['loketId'], staffRoomA);
      expect(f.api.calls.last.query['tanggal'], f.api.config.today);
    },
  );
  for (final status in [
    'CHECK_IN',
    'MENUNGGU',
    'DILEWATI',
    'DIPANGGIL',
    'DILAYANI',
  ]) {
    test('4A backend $status retained in correct projection', () async {
      f.api.status = status;
      await f.load();
      final list = ['DIPANGGIL', 'DILAYANI'].contains(status)
          ? f.bloc.state.active
          : f.bloc.state.patients;
      expect(list.single['status'], status);
    });
  }
  test('4A assignment failure is distinct from an empty assignment', () async {
    f.api.failures['GET /penugasan-petugas'] = const ApiException(
      503,
      'secret',
    );
    await f.load();
    expect(f.bloc.state.load, StaffLoad.failed);
    expect(f.bloc.state.error, isNot(contains('secret')));
    expect(f.api.count('/queue/snapshot'), 0);
    f.api.failures.clear();
    f.api.noAssignments = true;
    await f.load();
    expect(f.bloc.state.load, StaffLoad.loaded);
    expect(f.bloc.state.assignments, isEmpty);
    expect(f.bloc.state.error, isNull);
    expect(f.feedCount, 0);
  });
  test(
    '4A failed snapshot preserves valid data; retry restores freshness',
    () async {
      await f.load();
      f.api.failures['GET /queue/snapshot'] = const ApiException(503, 'secret');
      await f.bloc.refresh();
      expect(f.bloc.state.snapshot, isNotNull);
      expect(f.bloc.state.synchronized, isFalse);
      f.api.failures.clear();
      await f.bloc.refresh();
      expect(f.bloc.state.synchronized, isTrue);
      expect(f.bloc.state.error, isNull);
    },
  );
  test(
    '4A malformed snapshot is failure rather than fabricated empty data',
    () async {
      f.api.malformed = true;
      await f.load();
      expect(f.bloc.state.load, StaffLoad.failed);
      expect(f.bloc.state.snapshot, isNull);
    },
  );
  test('4A empty schedule does not invent attendance', () async {
    f.api.noSchedules = true;
    f.api.status = 'SELESAI';
    await f.load();
    expect(f.bloc.state.schedules, isEmpty);
    expect(f.bloc.state.patients, isEmpty);
    expect(f.bloc.state.active, isEmpty);
    expect(f.bloc.state.synchronized, isTrue);
  });
  test(
    '4A schedule failure is independent from valid queue snapshot',
    () async {
      f.api.failures['GET /jadwal-praktik'] = const ApiException(
        503,
        'failure',
      );
      await f.load();
      expect(f.bloc.state.scheduleFailed, isTrue);
      expect(f.bloc.state.synchronized, isTrue);
      expect(f.bloc.state.patients, isNotEmpty);
    },
  );
  test('4A old room schedule cannot overwrite new room (S03)', () async {
    final gate = f.api.block('/jadwal-praktik');
    final initial = f.load();
    await gate.entered.future;
    f.bloc.add(StaffRoomSelected(staffRoomB));
    await f.until((s) => s.roomId == staffRoomB && s.synchronized);
    gate.release.complete();
    await initial;
    expect(f.bloc.state.schedules.single['loketId'], staffRoomB);
    expect(f.feedCount, 1);
  });
  test('4A unauthorized room selection sends no request', () async {
    await f.load();
    final count = f.api.calls.length;
    f.bloc.add(StaffRoomSelected('not-assigned'));
    await f.bloc.refresh();
    expect(f.bloc.state.roomId, staffRoomA);
    expect(
      f.api.calls.skip(count).any((c) => c.query['loketId'] == 'not-assigned'),
      isFalse,
    );
  });
  test('4A follow-up page uses backend page and clamps after shrink', () async {
    f.api.pages = 2;
    await f.load();
    f.bloc.add(StaffPageSelected(2));
    await f.until((s) => s.page == 2 && s.synchronized);
    expect(
      f.api.calls
          .lastWhere((c) => c.path == '/queue/snapshot')
          .query['halamanTindakLanjut'],
      '2',
    );
    f.api.pages = 1;
    await f.bloc.refresh();
    expect(f.bloc.state.page, 1);
    expect(f.bloc.state.synchronized, isTrue);
  });
  test('4A emitted nested lists/maps and projections are immutable', () async {
    await f.load();
    expect(() => f.bloc.state.assignments.add({}), throwsUnsupportedError);
    expect(
      () => object(f.bloc.state.assignments.first['loket'])['nama'] = 'copy',
      returnsNormally,
    );
    expect(
      () => (f.bloc.state.assignments.first['loket'] as Json)['nama'] = 'bad',
      throwsUnsupportedError,
    );
    expect(
      () => (f.bloc.state.snapshot!['loket'] as List).clear(),
      throwsUnsupportedError,
    );
    expect(
      () => f.bloc.state.patients.first['status'] = 'bad',
      throwsUnsupportedError,
    );
  });
  test(
    '4A logout during fetch clears private data and ignores late response',
    () async {
      final gate = f.api.block('/queue/snapshot');
      final initial = f.load();
      await gate.entered.future;
      await f.api.clearSession();
      await f.until((s) => s.load == StaffLoad.ended);
      gate.release.complete();
      await initial;
      expect(f.bloc.state.assignments, isEmpty);
      expect(f.bloc.state.snapshot, isNull);
      expect(f.feedCount, 0);
    },
  );
  for (final code in [401, 403]) {
    test(
      '4A $code snapshot denial removes private patients/schedules',
      () async {
        await f.load();
        f.api.failures['GET /queue/snapshot'] = ApiException(code, 'secret');
        await f.bloc.refresh();
        expect(f.bloc.state.snapshot, isNull);
        expect(f.bloc.state.schedules, isEmpty);
        expect(f.bloc.state.errorStatus, code);
      },
    );
  }
}
