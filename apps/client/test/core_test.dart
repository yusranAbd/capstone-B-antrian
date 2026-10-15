import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:queueb_client/src/api.dart';
import 'package:queueb_client/src/admin_schema.dart';
import 'package:queueb_client/src/config.dart';
import 'package:queueb_client/src/display.dart';
import 'package:queueb_client/src/realtime.dart';

void main() {
  setUpAll(tz.initializeTimeZones);
  AppConfig config() =>
      AppConfig(apiBaseUrl: 'http://localhost:3000/api/v1', realtime: false);
  Json session(String token, String refresh) => {
    'accessToken': token,
    'refreshToken': refresh,
    'user': {'id': 'user', 'peran': 'USER', 'nama': 'Pasien'},
  };
  http.Response reply(Object data, [int status = 200]) =>
      http.Response(jsonEncode(data), status);
  test(
    'Service date and instants follow SERVICE_TIME_ZONE, not device zone',
    () {
      expect(config().instantLabel('2026-10-13T17:15:00Z'), '2026-10-14 00:15');
      expect(
        config().toInstant('2026-10-14T09:30'),
        '2026-10-14T02:30:00.000Z',
      );
      expect(
        AppConfig(
          apiBaseUrl: 'https://api.example/api/v1',
          serviceTimeZone: 'Asia/Jayapura',
        ).toInstant('2026-10-14T09:30'),
        '2026-10-14T00:30:00.000Z',
      );
    },
  );
  test('Postgres DATE and TIME are read without timezone shifts', () {
    expect(dateOnly('2026-10-14T00:00:00.000Z'), '2026-10-14');
    expect(clockOnly('1970-01-01T08:30:00.000Z'), '08:30');
  });
  test('Invalid calendar/instant inputs rejected', () {
    expect(() => config().toInstant('2026-02-30T09:00'), throwsFormatException);
    expect(
      () => config().toInstant('2026-10-14T09:00Z'),
      throwsFormatException,
    );
    expect(
      validateAdminField(
        const AdminField('tanggal', 'Tanggal', kind: FieldKind.date),
        '2026-02-30',
        config(),
      ),
      isNotNull,
    );
  });
  test('API URL rejects embedded credentials and unknown timezone', () {
    expect(
      () => AppConfig(apiBaseUrl: 'http://secret@localhost/api/v1'),
      throwsArgumentError,
    );
    expect(
      () =>
          AppConfig(apiBaseUrl: 'http://localhost', serviceTimeZone: 'Unknown'),
      throwsA(anything),
    );
  });
  test('Assignment requires active chain and service date', () {
    final a = {
      'aktif': true,
      'tanggalMulai': '2026-10-14T00:00:00Z',
      'tanggalSelesai': '2026-10-14T00:00:00Z',
      'loket': {
        'aktif': true,
        'layanan': {'aktif': true},
      },
    };
    expect(assignmentValid(a, '2026-10-14'), isTrue);
    expect(assignmentValid(a, '2026-10-15'), isFalse);
    expect(assignmentValid({...a, 'aktif': false}, '2026-10-14'), isFalse);
    expect(
      assignmentValid({
        ...a,
        'loket': {
          'aktif': true,
          'layanan': {'aktif': false},
        },
      }, '2026-10-14'),
      isFalse,
    );
  });
  test('Admin PATCH excludes immutable mode and slot parent', () {
    expect(
      adminPayload(
        resources[0],
        {'nama': 'Poli Baru', 'aktif': 'true', 'modeReservasi': 'HIBRIDA'},
        true,
        config(),
      ),
      {'nama': 'Poli Baru', 'aktif': true, 'deskripsi': null},
    );
    final slot = adminPayload(
      resources[5],
      {'jadwalPraktikId': 'old', 'kapasitas': '3', 'aktif': 'true'},
      true,
      config(),
    );
    expect(slot, {'kapasitas': 3, 'aktif': true});
  });
  test('Admin create converts zoned times, integers and nullable fields', () {
    expect(
      adminPayload(
        resources[5],
        {
          'jadwalPraktikId': 'session',
          'mulaiPada': '2026-10-14T09:00',
          'selesaiPada': '2026-10-14T09:15',
          'kapasitas': '2',
        },
        false,
        config(),
      ),
      {
        'jadwalPraktikId': 'session',
        'mulaiPada': '2026-10-14T02:00:00.000Z',
        'selesaiPada': '2026-10-14T02:15:00.000Z',
        'kapasitas': 2,
      },
    );
  });
  test('Login uses /me role and is not published before validation', () async {
    final me = Completer<http.Response>();
    final api = QueueApi(
      config: config(),
      client: MockClient(
        (r) async => r.url.path.endsWith('/login')
            ? reply(session('old', 'refresh'))
            : me.future,
      ),
    );
    final pending = api.login('patient@test.local', 'password');
    await Future<void>.delayed(Duration.zero);
    expect(api.user, isNull);
    me.complete(reply({'id': 'admin', 'peran': 'ADMIN', 'nama': 'Admin'}));
    await pending;
    expect(api.user?['peran'], 'ADMIN');
    api.dispose();
  });
  test(
    'Concurrent 401s rotate refresh once and retry with new Bearer token',
    () async {
      int rotations = 0;
      final api = QueueApi(
        config: config(),
        client: MockClient((r) async {
          if (r.url.path.endsWith('/login')) {
            return reply(session('old', 'refresh1'));
          }
          if (r.url.path.endsWith('/me')) {
            return reply({'id': 'user', 'peran': 'USER'});
          }
          if (r.url.path.endsWith('/refresh')) {
            rotations++;
            expect(jsonDecode(r.body)['refreshToken'], 'refresh1');
            await Future<void>.delayed(const Duration(milliseconds: 10));
            return reply(session('new', 'refresh2'));
          }
          return r.headers['Authorization'] == 'Bearer new'
              ? reply([])
              : reply({'message': 'Expired'}, 401);
        }),
      );
      await api.login('patient@test.local', 'password');
      await Future.wait([
        api.request('GET', '/layanan'),
        api.request('GET', '/dokter'),
      ]);
      expect(rotations, 1);
      expect(api.accessToken, 'new');
      api.dispose();
    },
  );
  test(
    'Domain conflict is not retried; validation array kept readable',
    () async {
      int calls = 0;
      final api = QueueApi(
        config: config(),
        client: MockClient((r) async {
          calls++;
          return reply({
            'message': ['Kapasitas penuh', 'Slot tidak tersedia'],
          }, 409);
        }),
      );
      await expectLater(
        api.request('POST', '/janji-temu', body: {'slotPraktikId': 'slot'}),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            'Kapasitas penuh\nSlot tidak tersedia',
          ),
        ),
      );
      expect(calls, 1);
      api.dispose();
    },
  );
  test('Network failure is never blindly retried', () async {
    int calls = 0;
    final api = QueueApi(
      config: config(),
      client: MockClient((r) async {
        calls++;
        throw http.ClientException('offline');
      }),
    );
    await expectLater(
      api.request('POST', '/reservasi', body: {}),
      throwsA(isA<ApiException>().having((e) => e.status, 'status', 0)),
    );
    expect(calls, 1);
    api.dispose();
  });
  test(
    'Timeout also covers connection before response headers, without retry',
    () async {
      int calls = 0;
      final stalled = Completer<http.Response>();
      final api = QueueApi(
        config: config(),
        requestTimeout: const Duration(milliseconds: 10),
        client: MockClient((r) {
          calls++;
          return stalled.future;
        }),
      );
      await expectLater(
        api.request('POST', '/reservasi', body: {}),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 0)),
      );
      expect(calls, 1);
      stalled.complete(reply({}));
      api.dispose();
    },
  );
  test('Refresh failure clears user and token', () async {
    final api = QueueApi(
      config: config(),
      client: MockClient((r) async {
        if (r.url.path.endsWith('/login')) {
          return reply(session('old', 'refresh'));
        }
        if (r.url.path.endsWith('/me')) {
          return reply({'id': 'user', 'peran': 'USER'});
        }
        return reply({'message': 'Revoked'}, 401);
      }),
    );
    await api.login('a@test.local', 'password');
    await expectLater(
      api.request('GET', '/tiket/saya'),
      throwsA(isA<ApiException>()),
    );
    expect(api.user, isNull);
    expect(api.accessToken, isNull);
    api.dispose();
  });
  test('Late refresh cannot restore a logged out session', () async {
    final rotation = Completer<http.Response>();
    final api = QueueApi(
      config: config(),
      client: MockClient((r) async {
        if (r.url.path.endsWith('/login')) {
          return reply(session('old', 'refresh'));
        }
        if (r.url.path.endsWith('/me')) {
          return reply({'id': 'user', 'peran': 'USER'});
        }
        return rotation.future;
      }),
    );
    await api.login('a@test.local', 'password');
    final pending = api.refresh();
    api.clearSession();
    rotation.complete(reply(session('new', 'rotated')));
    await pending;
    expect(api.user, isNull);
    expect(api.accessToken, isNull);
    api.dispose();
  });
  test('Display token header only; never Bearer or URL', () async {
    final api = QueueApi(
      config: config(),
      client: MockClient((r) async {
        expect(r.headers['x-display-token'], 'device');
        expect(r.headers.containsKey('Authorization'), isFalse);
        expect(r.url.query, isEmpty);
        return reply({'versiSkema': 1});
      }),
    );
    await api.request(
      'GET',
      '/display/service/snapshot',
      authenticated: false,
      displayToken: 'device',
    );
    api.dispose();
  });
  test('Registration never sends a role', () async {
    final api = QueueApi(
      config: config(),
      client: MockClient((r) async {
        expect(jsonDecode(r.body), {
          'nama': 'Pasien',
          'email': 'a@test.local',
          'kataSandi': 'password',
        });
        return reply({}, 201);
      }),
    );
    await api.register(' Pasien ', 'a@test.local', 'password');
    api.dispose();
  });
  test('Snapshot loader fetches again for mid-request events, no parallel requests', () async {
    final first = Completer<Json>();
    int calls = 0;
    final seen = <int>[];
    final loader = SnapshotLoader(
      fetch: () async => ++calls == 1 ? first.future : {'version': calls},
      onData: (data) => seen.add(data['version']),
      onError: (e) => fail('$e'),
    );
    final pending = loader.refresh();
    await loader.refresh();
    await loader.refresh();
    expect(calls, 1);
    first.complete({'version': 1});
    await pending;
    expect(calls, 2);
    expect(seen, [1, 2]);
    loader.dispose();
  });
  test('Disposed loader cannot update another room', () async {
    final result = Completer<Json>();
    bool delivered = false;
    final loader = SnapshotLoader(
      fetch: () => result.future,
      onData: (_) => delivered = true,
      onError: (_) => fail('Unexpected'),
    );
    final pending = loader.refresh();
    loader.dispose();
    result.complete({});
    await pending;
    expect(delivered, isFalse);
  });
  test(
    'Display skips history, deduplicates CALL, distinguishes RECALL audit id',
    () {
      final gate = AnnouncementGate();
      Json announcement(String id) => {
        'peristiwaId': id,
        'teks': 'Nomor A-001',
      };
      expect(gate.observe(announcement('history'), callSignal: true), isNull);
      expect(
        gate.observe(announcement('call'), callSignal: true),
        'Nomor A-001',
      );
      expect(gate.observe(announcement('call'), callSignal: true), isNull);
      expect(gate.observe(null, callSignal: false), isNull);
      expect(
        gate.observe(announcement('recall'), callSignal: true),
        'Nomor A-001',
      );
      expect(gate.observe(announcement('offline'), callSignal: false), isNull);
    },
  );
}
