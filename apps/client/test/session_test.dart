import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:queueb_client/src/api.dart';
import 'package:queueb_client/src/app.dart';
import 'package:queueb_client/src/config.dart';
import 'package:queueb_client/src/session_store.dart';
import 'package:queueb_client/src/patient_sync.dart';

class FakeSessionStore extends MemorySessionStore {
  int reads = 0, writes = 0, clears = 0;
  bool failRead = false, failWrite = false, failClear = false;
  Completer<void>? writeGate;
  @override
  Future<SessionCredentials?> read() async {
    reads++;
    if (failRead) throw Exception('sensitive storage diagnostic');
    return super.read();
  }

  @override
  Future<void> write(SessionCredentials credentials) async {
    writes++;
    if (writeGate != null) await writeGate!.future;
    if (failWrite) throw Exception('sensitive storage diagnostic');
    await super.write(credentials);
  }

  @override
  Future<void> clear() async {
    clears++;
    if (failClear) throw Exception('sensitive storage diagnostic');
    await super.clear();
  }
}

class FaultSecureStorage extends Fake implements FlutterSecureStorage {
  final values = <String, String>{};
  bool failWrite = false, failDelete = false;
  @override
  dynamic noSuchMethod(Invocation call) {
    if ([#read, #write, #delete].contains(call.memberName)) {
      final key = call.namedArguments[#key] as String;
      if (call.memberName == #read) return Future<String?>.value(values[key]);
      if (call.memberName == #write) {
        return (() async {
          if (failWrite) throw Exception('unavailable');
          values[key] = call.namedArguments[#value] as String;
        })();
      }
      return (() async {
        if (failDelete) throw Exception('unavailable');
        values.remove(key);
      })();
    }
    return super.noSuchMethod(call);
  }
}

class SessionSocket extends Fake implements io.Socket {
  bool disposed = false;
  @override
  dynamic noSuchMethod(Invocation call) {
    if (call.memberName == #on) return () {};
    return super.noSuchMethod(call);
  }

  @override
  io.Socket connect() => this;
  @override
  void dispose() => disposed = true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(tz.initializeTimeZones);
  const initial = SessionCredentials('access-old', 'refresh-old');
  Json identity([String role = 'USER']) => {
    'id': 'account',
    'peran': role,
    'nama': 'Fixture',
    'email': 'fixture@test.local',
  };
  Json pair([String suffix = 'new']) => {
    'accessToken': 'access-$suffix',
    'refreshToken': 'refresh-$suffix',
    'user': identity(),
  };
  http.Response reply(Object value, [int status = 200]) =>
      http.Response(jsonEncode(value), status);
  QueueApi make(
    SessionStore store,
    Future<http.Response> Function(http.Request) handler,
  ) => QueueApi(
    config: AppConfig(
      apiBaseUrl: 'http://localhost:3000/api/v1',
      realtime: false,
    ),
    sessionStore: store,
    client: MockClient(handler),
  );
  Future<void> tick() => Future<void>.delayed(Duration.zero);

  test('login persists pair only; new API instance restores with backend role and no password', () async {
    final store = FakeSessionStore();
    final api = make(
      store,
      (r) async => r.url.path.endsWith('/login')
          ? reply(pair('old'))
          : reply(identity()),
    );
    await api.login('fixture@test.local', 'never-store-this-password');
    expect(store.value!.accessToken, initial.accessToken);
    expect(store.value!.refreshToken, initial.refreshToken);
    api.dispose();
    final reopened = make(store, (r) async {
      expect(r.url.path, '/api/v1/auth/me');
      expect(r.headers['Authorization'], 'Bearer access-old');
      return reply(identity('ADMIN'));
    });
    await Future.wait([reopened.restoreSession(), reopened.restoreSession()]);
    expect(store.reads, 1);
    expect(reopened.user?['peran'], 'ADMIN');
    expect(reopened.sessionPhase, SessionPhase.ready);
    reopened.dispose();
  });

  test(
    'cold start 401 rotates once and saves replacements before validating me',
    () async {
      final store = FakeSessionStore()..value = initial;
      int rotations = 0, meCalls = 0;
      final api = make(store, (r) async {
        if (r.url.path.endsWith('/refresh')) {
          rotations++;
          expect(jsonDecode(r.body)['refreshToken'], 'refresh-old');
          return reply(pair());
        }
        meCalls++;
        if (r.headers['Authorization'] == 'Bearer access-old') {
          return reply({}, 401);
        }
        expect(store.value!.refreshToken, 'refresh-new');
        return reply(identity());
      });
      await api.restoreSession();
      expect(rotations, 1);
      expect(meCalls, 2);
      expect(api.user?['peran'], 'USER');
      api.dispose();
      final reopened = make(store, (r) async {
        expect(r.headers['Authorization'], 'Bearer access-new');
        return reply(identity());
      });
      await reopened.restoreSession();
      expect(reopened.user, isNotNull);
      reopened.dispose();
    },
  );

  test('revoked refresh or repeated me 401 clears durable credentials without retry loop', () async {
    for (final denied in [true, false]) {
      final store = FakeSessionStore()..value = initial;
      int rotations = 0;
      final api = make(store, (r) async {
        if (r.url.path.endsWith('/refresh')) {
          rotations++;
          return denied ? reply({}, 401) : reply(pair());
        }
        return reply({}, 401);
      });
      await api.restoreSession();
      expect(rotations, 1);
      expect(store.value, isNull);
      expect(api.user, isNull);
      expect(api.sessionPhase, SessionPhase.ready);
      api.dispose();
    }
  });

  test('offline startup and server 503 preserve credentials; explicit retry restores', () async {
    for (final unavailable in [0, 503]) {
      final store = FakeSessionStore()..value = initial;
      bool offline = true;
      final api = make(store, (r) async {
        if (offline) {
          if (unavailable == 0) throw http.ClientException('offline');
          return reply({}, 503);
        }
        return reply(identity());
      });
      await api.restoreSession();
      expect(api.sessionPhase, SessionPhase.offline);
      expect(store.value, same(initial));
      expect(api.user, isNull);
      offline = false;
      await api.restoreSession();
      expect(api.user, isNotNull);
      api.dispose();
    }
  });

  test('failed refresh preserves pair and blocks repeated automatic requests until explicit retry', () async {
    final store = FakeSessionStore()..value = initial;
    int rotations = 0;
    bool offline = true;
    final api = make(store, (r) async {
      if (r.url.path.endsWith('/refresh')) {
        rotations++;
        if (offline) throw http.ClientException('offline');
        return reply(pair());
      }
      return reply(identity());
    });
    await api.restoreSession();
    await expectLater(api.refresh(), throwsA(isA<ApiException>()));
    await expectLater(api.refresh(), throwsA(isA<ApiException>()));
    await expectLater(
      api.request('GET', '/tiket/saya'),
      throwsA(isA<ApiException>()),
    );
    expect(rotations, 1);
    expect(store.value, same(initial));
    expect(api.sessionPhase, SessionPhase.offline);
    offline = false;
    await api.restoreSession();
    expect(rotations, 2);
    expect(api.user, isNotNull);
    expect(store.value!.refreshToken, 'refresh-new');
    api.dispose();
  });

  test('single flight includes persistence; listeners see pair only after durable write', () async {
    final store = FakeSessionStore()..value = initial;
    int rotations = 0, notifications = 0;
    final api = make(store, (r) async {
      if (r.url.path.endsWith('/refresh')) {
        rotations++;
        return reply(pair());
      }
      return reply(identity());
    });
    await api.restoreSession();
    store.writeGate = Completer<void>();
    api.addListener(() {
      notifications++;
      expect(store.value!.refreshToken, 'refresh-new');
    });
    final pending = List.generate(10, (_) => api.refresh());
    await tick();
    expect(rotations, 1);
    expect(notifications, 0);
    store.writeGate!.complete();
    await Future.wait(pending);
    expect(notifications, 1);
    api.dispose();
  });

  test(
    'storage read failure preserves unknown data and retries safely',
    () async {
      final store = FakeSessionStore()
        ..value = initial
        ..failRead = true;
      final api = make(store, (r) async => reply(identity()));
      await api.restoreSession();
      expect(api.sessionPhase, SessionPhase.storageError);
      expect(store.clears, 0);
      store.failRead = false;
      await api.restoreSession();
      expect(api.user, isNotNull);
      api.dispose();
    },
  );

  test('rotation write failure retains new pair; retry persists without rotating again', () async {
    final store = FakeSessionStore()..value = initial;
    int rotations = 0;
    final api = make(store, (r) async {
      if (r.url.path.endsWith('/refresh')) {
        rotations++;
        return reply(pair());
      }
      return reply(identity());
    });
    await api.restoreSession();
    store.failWrite = true;
    await expectLater(api.refresh(), throwsA(isA<ApiException>()));
    expect(api.sessionPhase, SessionPhase.storageError);
    expect(store.value, same(initial));
    store.failWrite = false;
    await api.restoreSession();
    expect(rotations, 1);
    expect(store.value!.refreshToken, 'refresh-new');
    expect(api.user, isNotNull);
    api.dispose();
  });

  test(
    'offline logout clears locally, warns about server, restart cannot restore',
    () async {
      final store = FakeSessionStore()..value = initial;
      final api = make(store, (r) async {
        if (r.url.path.endsWith('/logout')) {
          throw http.ClientException('offline');
        }
        return reply(identity());
      });
      await api.restoreSession();
      await api.logout();
      expect(store.value, isNull);
      expect(api.accessToken, isNull);
      expect(api.user, isNull);
      expect(api.sessionMessage, contains('belum terkonfirmasi'));
      api.dispose();
      final reopened = make(
        store,
        (r) async => throw StateError('No HTTP allowed'),
      );
      await reopened.restoreSession();
      expect(reopened.user, isNull);
      expect(reopened.sessionPhase, SessionPhase.ready);
      reopened.dispose();
    },
  );

  test('logout during rotation clears first and revokes replacement without persisting it', () async {
    final store = FakeSessionStore()..value = initial;
    final response = Completer<http.Response>();
    String? revoked;
    final api = make(store, (r) async {
      if (r.url.path.endsWith('/refresh')) return response.future;
      if (r.url.path.endsWith('/logout')) {
        revoked = jsonDecode(r.body)['refreshToken'] as String;
        return reply({});
      }
      return reply(identity());
    });
    await api.restoreSession();
    final rotating = api.refresh();
    await tick();
    final exiting = api.logout();
    await tick();
    expect(store.value, isNull);
    response.complete(reply(pair()));
    await Future.wait([rotating, exiting]);
    expect(store.value, isNull);
    expect(revoked, 'refresh-new');
    expect(api.user, isNull);
    api.dispose();
  });

  test('logout queued after in-flight secure write always wins', () async {
    final store = FakeSessionStore()..value = initial;
    final api = make(
      store,
      (r) async =>
          r.url.path.endsWith('/refresh') ? reply(pair()) : reply(identity()),
    );
    await api.restoreSession();
    store.writeGate = Completer<void>();
    final rotating = api.refresh();
    await tick();
    final exiting = api.logout();
    store.writeGate!.complete();
    await Future.wait([rotating, exiting]);
    expect(store.value, isNull);
    api.dispose();
  });

  test(
    'failed local clear blocks restoration and exposes safe retry',
    () async {
      final store = FakeSessionStore()..value = initial;
      final api = make(store, (r) async => reply(identity()));
      await api.restoreSession();
      store.failClear = true;
      await expectLater(api.logout(), throwsA(isA<ApiException>()));
      expect(api.sessionPhase, SessionPhase.storageError);
      store.failClear = false;
      await api.restoreSession();
      expect(store.value, isNull);
      expect(api.user, isNull);
      api.dispose();
    },
  );

  test('late restore and login cannot republish after logout', () async {
    for (final restoring in [true, false]) {
      final store = FakeSessionStore()..value = restoring ? initial : null;
      final me = Completer<http.Response>();
      final api = make(store, (r) async {
        if (r.url.path.endsWith('/login')) return reply(pair());
        if (r.url.path.endsWith('/logout')) return reply({});
        return me.future;
      });
      final pending = restoring
          ? api.restoreSession()
          : api.login('a@test.local', 'password');
      await tick();
      await api.logout();
      me.complete(reply(identity()));
      try {
        await pending;
      } catch (_) {}
      expect(api.user, isNull);
      expect(store.value, isNull);
      api.dispose();
    }
  });

  test(
    'no credentials/password in logs and storage errors are sanitized',
    () async {
      final store = FakeSessionStore()..failWrite = true;
      final logs = <String>[];
      await runZoned(
        () async {
          final api = make(store, (r) async => reply(pair()));
          try {
            await api.login('fixture@test.local', 'private-password');
          } catch (e) {
            expect('$e', isNot(contains('sensitive')));
            expect('$e', isNot(contains('access-new')));
          }
          expect('$initial', isNot(contains('access-old')));
          api.dispose();
        },
        zoneSpecification: ZoneSpecification(
          print: (_, _, _, line) => logs.add(line),
        ),
      );
      expect(logs, isEmpty);
    },
  );

  test('secure adapter uses one envelope per API; corrupt data clears without storing user/password', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final store = AndroidSessionStore(apiBase: 'https://api.example/api/v1');
    await store.write(initial);
    final raw = await const FlutterSecureStorage().readAll();
    expect(raw.length, 1);
    expect(
      (jsonDecode(raw.values.single) as Map).keys,
      unorderedEquals(['version', 'apiBase', 'accessToken', 'refreshToken']),
    );
    expect((await store.read())!.refreshToken, 'refresh-old');
    expect(
      await AndroidSessionStore(apiBase: 'https://other.example/api/v1').read(),
      isNull,
    );
    FlutterSecureStorage.setMockInitialValues({raw.keys.single: 'corrupt'});
    expect(await store.read(), isNull);
    expect(await const FlutterSecureStorage().readAll(), isEmpty);
    await store.write(initial);
    await store.clear();
    expect(await store.read(), isNull);
  });

  test(
    'only Android selects durable store; other platforms remain memory only',
    () {
      for (final target in TargetPlatform.values) {
        debugDefaultTargetPlatformOverride = target;
        expect(
          platformSessionStore('http://localhost/api/v1'),
          target == TargetPlatform.android
              ? isA<AndroidSessionStore>()
              : isA<MemorySessionStore>(),
        );
      }
      debugDefaultTargetPlatformOverride = null;
    },
  );

  test(
    'secure logout tombstone prevents restore even when delete fails',
    () async {
      final secure = FaultSecureStorage();
      final store = AndroidSessionStore(
        apiBase: 'https://api.example/api/v1',
        storage: secure,
      );
      await store.write(initial);
      secure.failDelete = true;
      await store.clear();
      expect(secure.values.values.single, '{"loggedOut":true}');
      expect(await store.read(), isNull);
      secure.failDelete = false;
      await store.write(initial);
      secure.failWrite = true;
      await store.clear();
      expect(secure.values, isEmpty);
    },
  );

  test(
    'backend unsupported role is rejected and durable pair cleared',
    () async {
      final store = FakeSessionStore()..value = initial;
      final api = make(store, (r) async => reply(identity('UNSUPPORTED')));
      await api.restoreSession();
      expect(api.user, isNull);
      expect(store.value, isNull);
      api.dispose();
    },
  );

  test(
    'server revocation is still attempted if local secure deletion fails',
    () async {
      final store = FakeSessionStore()..value = initial;
      int revocations = 0;
      final api = make(store, (r) async {
        if (r.url.path.endsWith('/logout')) revocations++;
        return reply(identity());
      });
      await api.restoreSession();
      store.failClear = true;
      await expectLater(api.logout(), throwsA(isA<ApiException>()));
      expect(revocations, 1);
      expect(api.sessionPhase, SessionPhase.storageError);
      expect(api.user, isNull);
      api.dispose();
    },
  );

  testWidgets(
    'restored session opens one patient socket, rotates after save, logout disposes',
    (tester) async {
      final store = FakeSessionStore()..value = initial;
      final api = QueueApi(
        config: AppConfig(apiBaseUrl: 'http://localhost/api/v1'),
        sessionStore: store,
        client: MockClient(
          (r) async => r.url.path.endsWith('/refresh')
              ? reply(pair())
              : reply(identity()),
        ),
      );
      await api.restoreSession();
      final sockets = <SessionSocket>[], tokens = <String>[];
      final feed = PatientUpdates(
        api: api,
        socketFactory: (url, options) {
          expect(url, 'http://localhost/patient');
          tokens.add((options['auth'] as Map)['token'] as String);
          final socket = SessionSocket();
          sockets.add(socket);
          return socket;
        },
      );
      expect(sockets.length, 1);
      await api.refresh();
      expect(tokens, ['access-old', 'access-new']);
      expect(store.value!.refreshToken, 'refresh-new');
      expect(sockets.first.disposed, isTrue);
      await api.logout();
      expect(sockets.length, 2);
      expect(sockets.last.disposed, isTrue);
      feed.dispose();
      api.dispose();
    },
  );

  testWidgets(
    'logout closes open ticket route and removes sensitive cached UI',
    (tester) async {
      final store = FakeSessionStore()..value = initial;
      final ticket = {
        'id': 'ticket-fixture',
        'nomorAntrean': 'QA-001',
        'status': 'DIPESAN',
        'tanggalAntrean': '2026-10-17',
        'layanan': {'nama': 'Fixture'},
      };
      final api = make(
        store,
        (r) async => reply(switch (r.url.path) {
          '/api/v1/auth/me' => identity(),
          '/api/v1/tiket/saya' => [ticket],
          '/api/v1/tiket/ticket-fixture' => ticket,
          _ => [],
        }),
      );
      await api.restoreSession();
      await tester.pumpWidget(QueueBApp(api: api));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(NavigationDestination, 'Tiket Saya'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lihat Tiket / QR'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      final exiting = api.logout();
      await tester.pumpAndSettle();
      await exiting;
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('QA-001'), findsNothing);
      expect(find.widgetWithText(TextFormField, 'Email'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      api.dispose();
    },
  );

  test(
    'failed local and server logout never claims credentials were cleared',
    () async {
      final store = FakeSessionStore()..value = initial;
      final api = make(store, (r) async {
        if (r.url.path.endsWith('/logout')) {
          throw http.ClientException('offline');
        }
        return reply(identity());
      });
      await api.restoreSession();
      store.failClear = true;
      await expectLater(api.logout(), throwsA(isA<ApiException>()));
      expect(api.sessionPhase, SessionPhase.storageError);
      expect(
        api.sessionMessage,
        contains('Kredensial lokal belum dapat dihapus'),
      );
      expect(api.sessionMessage, contains('server juga belum terkonfirmasi'));
      expect(api.sessionMessage, isNot(contains('Sesi lokal sudah dihapus')));
      api.dispose();
    },
  );

  for (final role in ['USER', 'PETUGAS', 'ADMIN']) {
    testWidgets('startup has no login flash and routes validated $role', (
      tester,
    ) async {
      final store = FakeSessionStore()..value = initial;
      final me = Completer<http.Response>();
      final api = make(
        store,
        (r) async => r.url.path.endsWith('/auth/me') ? me.future : reply([]),
      );
      final pending = api.restoreSession();
      await tester.pumpWidget(QueueBApp(api: api));
      await tester.pump();
      expect(find.text('Memulihkan sesi…'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Email'), findsNothing);
      me.complete(reply(identity(role)));
      await tester.pumpAndSettle();
      await pending;
      if (role == 'ADMIN') {
        await tester.tap(
          find.widgetWithText(OutlinedButton, 'Menu administrasi'),
        );
        await tester.pumpAndSettle();
      }
      expect(
        role == 'USER'
            ? find.widgetWithText(NavigationDestination, 'Profil')
            : find.byTooltip(
                role == 'PETUGAS' ? 'Profil petugas' : 'Profil akun',
              ),
        findsOneWidget,
      );
      if (role == 'ADMIN') {
        await tester.tapAt(const Offset(5, 5));
        await tester.pumpAndSettle();
      }
      expect(
        find.text(switch (role) {
          'ADMIN' => 'Poliklinik',
          'PETUGAS' => 'Ruang yang ditugaskan',
          _ => 'Akses cepat',
        }),
        findsWidgets,
      );
      await tester.pumpWidget(const SizedBox());
      api.dispose();
    });
  }

  testWidgets(
    'offline gate is explicit, hides role routes and keeps retry/logout',
    (tester) async {
      final store = FakeSessionStore()..value = initial;
      final api = make(
        store,
        (r) async => throw http.ClientException('offline'),
      );
      await api.restoreSession();
      await tester.pumpWidget(QueueBApp(api: api));
      await tester.pumpAndSettle();
      expect(find.text('Koneksi sesi belum tersedia'), findsOneWidget);
      expect(find.text('Coba lagi'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Email'), findsNothing);
      expect(store.value, same(initial));
      await tester.tap(find.text('Hapus sesi & kembali ke login'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextFormField, 'Email'), findsOneWidget);
      expect(store.value, isNull);
      await tester.pumpWidget(const SizedBox());
      api.dispose();
    },
  );
}
