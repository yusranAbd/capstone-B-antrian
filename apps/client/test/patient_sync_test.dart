import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:timezone/data/latest.dart' as tz;
import 'package:queueb_client/src/api.dart';
import 'package:queueb_client/src/config.dart';
import 'package:queueb_client/src/patient_sync.dart';

class FakePatientSocket extends Fake implements io.Socket {
  final handlers = <String, Function>{};
  int connects = 0;
  bool disposed = false;
  @override
  dynamic noSuchMethod(Invocation call) {
    if (call.memberName == #on) {
      handlers[call.positionalArguments[0] as String] =
          call.positionalArguments[1] as Function;
      return () => handlers.remove(call.positionalArguments[0]);
    }
    return super.noSuchMethod(call);
  }

  @override
  io.Socket connect() {
    connects++;
    return this;
  }

  @override
  void dispose() {
    disposed = true;
    handlers.clear();
  }

  void fire(String event, dynamic value) => handlers[event]?.call(value);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(tz.initializeTimeZones);
  QueueApi api({http.Client? client}) =>
      QueueApi(
          config: AppConfig(apiBaseUrl: 'http://localhost:3000/api/v1'),
          client: client,
        )
        ..accessToken = 'initial'
        ..user = {'id': 'owner', 'peran': 'USER'};
  Json event(String id) => {'versiSkema': 1, 'eventId': id, 'jenis': 'TIKET'};
  for (final role in ['USER', 'DOKTER']) {
    testWidgets(
      'repeated $role portal disposal releases sockets, timers and API listeners',
      (tester) async {
        final a = api()..user = {'id': 'owner', 'peran': role};
        final sockets = <FakePatientSocket>[];
        for (var i = 0; i < 40; i++) {
          final feed = PatientUpdates(
            api: a,
            role: role,
            namespace: role == 'DOKTER' ? 'doctor' : 'patient',
            socketFactory: (_, _) {
              final socket = FakePatientSocket();
              sockets.add(socket);
              return socket;
            },
          );
          feed.dispose();
        }
        a.accessToken = 'rotated-after-disposal';
        a.notifyListeners();
        await tester.pump(const Duration(minutes: 3));
        expect(sockets, hasLength(40));
        expect(
          sockets.every(
            (s) => s.disposed && s.handlers.isEmpty && s.connects == 1,
          ),
          isTrue,
        );
        a.dispose();
        expect(tester.takeException(), isNull);
      },
    );
  }
  test(
    'reads are serialized with exactly one trailing read for a burst',
    () async {
      final first = Completer<void>();
      int calls = 0, running = 0, peak = 0;
      final gate = RefreshGate(() async {
        calls++;
        running++;
        if (running > peak) peak = running;
        if (calls == 1) await first.future;
        running--;
      });
      final pending = gate.refresh();
      for (int i = 0; i < 20; i++) {
        gate.refresh();
      }
      expect(calls, 1);
      first.complete();
      await pending;
      expect(calls, 2);
      expect(peak, 1);
      gate.dispose();
      await gate.refresh();
      expect(calls, 2);
    },
  );
  test('a failed read releases the gate for recovery', () async {
    int calls = 0;
    final gate = RefreshGate(() async {
      if (++calls == 1) throw StateError('offline');
    });
    await expectLater(gate.refresh(), throwsStateError);
    await gate.refresh();
    expect(calls, 2);
    gate.dispose();
  });
  testWidgets(
    'patient namespace uses JWT only; duplicate/invalid events are coalesced',
    (tester) async {
      final a = api(), socket = FakePatientSocket();
      String? url;
      Map<String, dynamic>? options;
      final feed = PatientUpdates(
        api: a,
        socketFactory: (u, o) {
          url = u;
          options = o;
          return socket;
        },
      );
      int reads = 0;
      feed.addListener(() => reads++);
      try {
        expect(url, 'http://localhost:3000/patient');
        expect(options?['auth'], {'token': 'initial'});
        socket.fire('patient:ready', {'versiSkema': 1});
        await tester.pump(const Duration(milliseconds: 260));
        expect(reads, 1);
        for (int i = 0; i < 10; i++) {
          socket.fire('patient:updated', event('same'));
        }
        socket.fire('patient:updated', {
          'versiSkema': 2,
          'eventId': 'wrong',
          'jenis': 'TIKET',
        });
        socket.fire('patient:updated', {
          'versiSkema': 1,
          'eventId': 'wrong',
          'jenis': 'PRIVATE',
        });
        await tester.pump(const Duration(milliseconds: 260));
        expect(reads, 2);
        socket.fire('patient:updated', event('same'));
        await tester.pump(const Duration(milliseconds: 260));
        expect(reads, 2);
      } finally {
        feed.dispose();
        a.dispose();
      }
      expect(socket.disposed, isTrue);
      expect(socket.handlers, isEmpty);
    },
  );
  testWidgets(
    'background suspends reads; resume and disconnect recover without manual refresh',
    (tester) async {
      final a = api(), sockets = <FakePatientSocket>[];
      final feed = PatientUpdates(
        api: a,
        socketFactory: (_, _) {
          final s = FakePatientSocket();
          sockets.add(s);
          return s;
        },
      );
      int reads = 0;
      feed.addListener(() => reads++);
      try {
        feed.didChangeAppLifecycleState(AppLifecycleState.paused);
        sockets.last.fire('patient:updated', event('background'));
        await tester.pump(const Duration(seconds: 31));
        expect(reads, 0);
        feed.didChangeAppLifecycleState(AppLifecycleState.resumed);
        await tester.pump(const Duration(milliseconds: 260));
        expect(reads, 1);
        sockets.last.fire('patient:ready', {'versiSkema': 1});
        await tester.pump(const Duration(milliseconds: 260));
        sockets.last.fire('disconnect', 'transport close');
        await tester.pump(const Duration(seconds: 31));
        expect(reads, greaterThanOrEqualTo(3));
        expect(sockets.last.connects, greaterThan(1));
      } finally {
        feed.dispose();
        a.dispose();
      }
    },
  );
  testWidgets(
    'token rotation replaces the socket; late events from old socket are ignored',
    (tester) async {
      final a = api(), sockets = <FakePatientSocket>[];
      final feed = PatientUpdates(
        api: a,
        socketFactory: (_, _) {
          final s = FakePatientSocket();
          sockets.add(s);
          return s;
        },
      );
      int reads = 0;
      feed.addListener(() => reads++);
      try {
        final old = sockets.single,
            callback = sockets.single.handlers['patient:updated']!;
        a.accessToken = 'rotated';
        a.notifyListeners();
        expect(old.disposed, isTrue);
        expect(sockets.length, 2);
        callback(event('late'));
        await tester.pump(const Duration(milliseconds: 260));
        expect(reads, 0);
        sockets.last.fire('patient:updated', event('fresh'));
        await tester.pump(const Duration(milliseconds: 260));
        expect(reads, 1);
      } finally {
        feed.dispose();
        a.dispose();
      }
    },
  );
  testWidgets(
    'unauthorized socket errors share one refresh and reopen with new JWT',
    (tester) async {
      final response = Completer<http.Response>();
      int rotations = 0;
      final a = api(
            client: MockClient((r) {
              if (r.url.path.endsWith('/auth/login')) {
                return Future.value(
                  http.Response(
                    jsonEncode({
                      'accessToken': 'initial',
                      'refreshToken': 'initial-refresh',
                      'user': {'id': 'owner', 'peran': 'USER'},
                    }),
                    200,
                  ),
                );
              }
              if (r.url.path.endsWith('/auth/me')) {
                return Future.value(
                  http.Response(
                    jsonEncode({'id': 'owner', 'peran': 'USER'}),
                    200,
                  ),
                );
              }
              rotations++;
              return response.future;
            }),
          ),
          sockets = <FakePatientSocket>[];
      await a.login('fixture@test.local', 'test-password');
      final feed = PatientUpdates(
        api: a,
        socketFactory: (_, _) {
          final s = FakePatientSocket();
          sockets.add(s);
          return s;
        },
      );
      try {
        sockets.last.fire('connect_error', 'UNAUTHORIZED');
        sockets.last.fire('connect_error', 'UNAUTHORIZED');
        await tester.pump();
        expect(rotations, 1);
        response.complete(
          http.Response(
            jsonEncode({
              'accessToken': 'new',
              'refreshToken': 'new-refresh',
              'user': {'id': 'owner', 'peran': 'USER'},
            }),
            200,
          ),
        );
        await tester.pump();
        await tester.pump();
        expect(a.accessToken, 'new');
        expect(sockets.length, 2);
      } finally {
        feed.dispose();
        a.dispose();
      }
    },
  );
}
