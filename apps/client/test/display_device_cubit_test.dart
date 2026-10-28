import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:queueb_client/src/api.dart';
import 'package:queueb_client/src/config.dart';
import 'package:queueb_client/src/display_selection.dart';
import 'package:queueb_client/src/features/display/application/display_device_cubit.dart';
import 'package:queueb_client/src/features/display/data/display_device_repository.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:queueb_client/src/features/display/models/display_models.dart';

import 'display_bloc_fixture.dart';

class ControlledDisplaySelection extends MemoryDisplaySelection {
  ControlledDisplaySelection({super.value});
  bool failClear = false, holdWrite = false;
  final entered = Completer<void>(), release = Completer<void>();
  @override
  Future<void> write(String id) async {
    if (holdWrite) {
      entered.complete();
      await release.future;
    }
    await super.write(id);
  }

  @override
  Future<void> clear() async {
    if (failClear) throw StateError('fixture storage failure');
    await super.clear();
  }
}

void main() {
  setUpAll(tz.initializeTimeZones);
  late DisplayFixture f;
  setUp(() => f = DisplayFixture(id: null));
  tearDown(() => f.dispose());
  test(
    '5A late selector write after close is cleaned without activating scope',
    () async {
      final selection = ControlledDisplaySelection()..holdWrite = true;
      final api = QueueApi(
        config: AppConfig(
          apiBaseUrl: 'http://fixture.invalid/api/v1',
          realtime: false,
        ),
        client: MockClient(f.backend.handle),
      );
      final repository = DisplayDeviceRepository(api, selection);
      final device = DisplayDeviceCubit(repository);
      final pending = device.pair(activationFixture);
      await selection.entered.future;
      await device.close();
      selection.release.complete();
      await pending;
      expect(selection.value, isNull);
      expect(device.state.scope, isNull);
      repository.dispose();
      api.dispose();
    },
  );
  test('5A confirmed revoke with failed selector clear is partial, never reuses credential', () async {
    final selection = ControlledDisplaySelection(value: displayA);
    final api = QueueApi(
      config: AppConfig(
        apiBaseUrl: 'http://fixture.invalid/api/v1',
        realtime: false,
      ),
      client: MockClient(f.backend.handle),
    );
    final repository = DisplayDeviceRepository(api, selection);
    final cubit = DisplayDeviceCubit(repository);
    await cubit.restore();
    selection.failClear = true;
    await cubit.disconnect();
    expect(cubit.state.phase, DisplayDevicePhase.failed);
    expect(cubit.state.scope, isNull);
    expect(repository.scope, isNull);
    expect(f.backend.denied, contains(displayA));
    expect(cubit.state.error, contains('telah dicabut server'));
    expect(f.backend.count('/display/putuskan', 'POST'), 1);
    selection.failClear = false;
    await cubit.close();
    repository.dispose();
    api.dispose();
  });
  test('5A fresh isolated tab never adopts ambient cookie', () async {
    f.backend.ambient = displayB;
    await f.device.restore();
    expect(f.device.state.phase, DisplayDevicePhase.unpaired);
    expect(f.backend.calls, isEmpty);
  });
  test(
    '5A pairing verifies session, stores selector only, then activates monitor',
    () async {
      await f.device.pair(activationFixture);
      await f.until((s) => s.snapshot != null);
      expect(f.device.state.phase, DisplayDevicePhase.ready);
      expect(f.selection.value, displayA);
      expect(f.device.state.scope!.deviceId, displayA);
      expect(f.device.state.scope!.serviceId, clinicA);
      final post = f.backend.calls.first;
      expect(jsonDecode(post.body), {
        'kode': activationFixture,
        'isolasiSesi': true,
      });
      expect(
        f.backend.calls
            .skip(1)
            .every((r) => r.headers['x-display-device-id'] == displayA),
        isTrue,
      );
    },
  );
  for (final code in [400, 401, 403, 409, 410, 429]) {
    test(
      '5A pairing $code preserves safe category, no retry or secret',
      () async {
        f.backend.failures['POST /display/pairing'] = code;
        await f.device.pair(activationFixture);
        expect(f.device.state.errorStatus, code);
        expect(f.device.state.error, isNot(contains(activationFixture)));
        expect(f.device.state.scope, isNull);
        expect(f.backend.count('/display/pairing', 'POST'), 1);
      },
    );
  }
  test('5A invalid code blocked before request', () async {
    await f.device.pair('bad');
    expect(f.backend.calls, isEmpty);
    expect(f.device.state.errorStatus, 400);
  });
  test('5A restore verifies selector and service metadata', () async {
    f.selection.value = displayB;
    await f.load();
    expect(f.device.state.scope!.deviceId, displayB);
    expect(f.device.state.scope!.serviceId, clinicB);
    expect(f.monitor.state.snapshot!['layanan']['id'], clinicB);
  });
  test('5A restore outage is not an unpaired/empty success', () async {
    f.selection.value = displayA;
    f.backend.failures['GET /display/sesi'] = 503;
    await f.device.restore();
    expect(f.device.state.phase, DisplayDevicePhase.failed);
    expect(f.devices.scope, isNull);
  });
  test('5A revoked restore requests new activation and no snapshot', () async {
    f.selection.value = displayA;
    f.backend.denied.add(displayA);
    await f.device.restore();
    expect(f.device.state.errorStatus, 401);
    expect(f.backend.count('/display/$clinicA/snapshot'), 0);
  });
  test('5A concurrent pairing submits once', () async {
    final gate = f.backend.block('/display/pairing', 'POST');
    final first = f.device.pair(activationFixture);
    await gate.entered.future;
    await f.device.pair('223456789012');
    expect(f.backend.count('/display/pairing', 'POST'), 1);
    gate.release.complete();
    await first;
  });
  test(
    '5A close during pairing ignores late response and clears state',
    () async {
      final gate = f.backend.block('/display/pairing', 'POST');
      final first = f.device.pair(activationFixture);
      await gate.entered.future;
      await f.device.close();
      gate.release.complete();
      await first;
      expect(f.device.state.scope, isNull);
      expect(f.devices.scope, isNull);
      expect(f.selection.value, isNull);
    },
  );
  test('5A scope invalidation ignores old pairing metadata', () async {
    final gate = f.backend.block('/display/pairing', 'POST');
    final first = f.device.pair(activationFixture);
    await gate.entered.future;
    f.devices.begin();
    gate.release.complete();
    await first;
    expect(f.devices.scope, isNull);
    expect(f.selection.value, isNull);
  });
  test(
    '5A timeout pairing never retries POST or reads ambient isolated session',
    () async {
      f.backend.losePair = true;
      await f.device.pair(activationFixture);
      expect(f.device.state.phase, DisplayDevicePhase.uncertain);
      await f.device.pair(activationFixture);
      await f.device.restore();
      expect(f.device.state.phase, DisplayDevicePhase.uncertain);
      expect(f.backend.count('/display/pairing', 'POST'), 1);
      expect(f.backend.count('/display/sesi'), 0);
    },
  );
  test('5A malformed pairing response does not activate', () async {
    f.backend.malformedPair = true;
    await f.device.pair(activationFixture);
    expect(f.device.state.phase, DisplayDevicePhase.uncertain);
    expect(f.devices.scope, isNull);
  });
  test(
    '5A pairing verified later via selector after read failure, no second POST',
    () async {
      f.backend.failures['GET /display/sesi'] = 503;
      await f.device.pair(activationFixture);
      expect(f.selection.value, displayA);
      f.backend.failures.clear();
      await f.load();
      expect(f.device.state.phase, DisplayDevicePhase.ready);
      expect(f.backend.count('/display/pairing', 'POST'), 1);
    },
  );
  test(
    '5A device metadata immutable and excludes credentials and patient extras',
    () async {
      await f.device.pair(activationFixture);
      expect(
        () => f.device.state.device!['nama'] = 'bad',
        throwsUnsupportedError,
      );
      final text = jsonEncode(f.device.state.device);
      expect(text, isNot(contains(activationFixture)));
      expect(text, isNot(contains('token')));
      expect(
        f.backend.calls.every((r) => !r.headers.containsKey('Authorization')),
        isTrue,
      );
    },
  );
  test(
    '5A disconnect revokes selected device before clearing selector',
    () async {
      await f.device.pair(activationFixture);
      await f.device.disconnect();
      expect(f.backend.denied, contains(displayA));
      expect(f.selection.value, isNull);
      expect(f.device.state.scope, isNull);
      expect(f.backend.calls.last.headers['x-display-device-id'], displayA);
    },
  );
}
