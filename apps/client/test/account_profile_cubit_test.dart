import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:queueb_client/src/api.dart';
import 'package:queueb_client/src/config.dart';
import 'package:queueb_client/src/features/account/application/account_profile_cubit.dart';
import 'package:queueb_client/src/features/account/data/account_profile_repository.dart';
import 'package:queueb_client/src/user_profile.dart';
import 'package:timezone/data/latest.dart' as tz;

class ProfileFixture {
  ProfileFixture([String role = 'USER']) {
    profile = {
      'id': 'owner',
      'nama': 'Pasien Awal',
      'email': 'self@example.test',
      'peran': role,
      'aktif': true,
      'avatarProfil': null,
      'kataSandi': 'fixture-secret',
      'tokenHash': 'fixture-secret',
    };
    api = QueueApi(
      config: AppConfig(apiBaseUrl: 'http://localhost/api/v1', realtime: false),
      client: MockClient(handle),
    )..user = {...profile};
    controller = AccountProfileCubit(AccountProfileRepository(api));
  }
  late Json profile;
  late QueueApi api;
  late AccountProfileCubit controller;
  final calls = <http.Request>[];
  final gates = <(String, int), Completer<void>>{},
      waiters = <(String, int), Completer<void>>{};
  final reads = <String, int>{}, failures = <String, int>{};
  int? mutationFailure;
  int writes = 0;
  bool commitUnknown = false, failReloadAfterWrite = false;
  Completer<void>? writeGate, writeStarted;
  http.Response reply(Object value, [int status = 200]) =>
      http.Response(jsonEncode(value), status);
  Future<void> waitRead(String path, int n) => (reads[path] ?? 0) >= n
      ? Future.value()
      : (waiters[(path, n)] ??= Completer<void>()).future;
  Future<http.Response> handle(http.Request r) async {
    calls.add(r);
    final path = r.url.path.replaceFirst('/api/v1', '');
    if (path == '/auth/login') {
      return reply({
        'accessToken': 'fixture-access',
        'refreshToken': 'fixture-refresh',
        'user': profile,
      });
    }
    if (r.method == 'GET') {
      final n = reads.update(path, (v) => v + 1, ifAbsent: () => 1);
      final response =
          failures.containsKey(path) ||
              (path == '/auth/me' && writes > 0 && failReloadAfterWrite)
          ? reply({'message': 'fixture-secret'}, failures[path] ?? 503)
          : reply(
              path == '/auth/me'
                  ? profile
                  : path == '/portal-dokter/profil'
                  ? {
                      'nama': 'Profesional',
                      'poliklinik': [],
                      'kataSandi': 'fixture-secret',
                    }
                  : path == '/penugasan-petugas'
                  ? [
                      {
                        'id': 'assignment',
                        'aktif': true,
                        'loket': {'nama': 'Ruang', 'token': 'fixture-secret'},
                      },
                    ]
                  : [],
            );
      waiters.remove((path, n))?.complete();
      if (gates[(path, n)] case final gate?) await gate.future;
      return response;
    }
    writes++;
    writeStarted?.complete();
    writeStarted = null;
    if (writeGate case final gate?) await gate.future;
    if (mutationFailure == null || commitUnknown) {
      if (path == '/auth/me') {
        profile = {...profile, ...jsonDecode(r.body) as Json};
      }
      if (path == '/auth/me/avatar') {
        profile = {
          ...profile,
          'avatarProfil': r.method == 'DELETE'
              ? null
              : '/media/avatar/server.webp',
        };
      }
    }
    if (mutationFailure == 0) {
      throw http.ClientException('fixture response lost');
    }
    if (mutationFailure != null) {
      return reply({'message': 'fixture-secret'}, mutationFailure!);
    }
    return reply(path == '/auth/me' ? profile : {'ok': true});
  }

  Future<void> dispose() async {
    await controller.close();
    api.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(tz.initializeTimeZones);
  late ProfileFixture f;
  setUp(() => f = ProfileFixture());
  tearDown(() => f.dispose());
  test('profile uses QueueApi canonical identity and emits immutable metadata only', () async {
    await f.controller.load();
    expect(f.controller.state.profile['nama'], f.api.user?['nama']);
    expect(
      jsonEncode(f.controller.state.profile),
      isNot(contains('fixture-secret')),
    );
    expect(
      () => f.controller.state.profile['nama'] = 'bad',
      throwsUnsupportedError,
    );
    expect(f.controller.state.loading, isFalse);
  });
  test('profile load failure is explicit and can be recovered', () async {
    f.failures['/auth/me'] = 503;
    await f.controller.load();
    expect(f.controller.state.error, isNotNull);
    expect(f.controller.state.error, isNot(contains('fixture-secret')));
    f.failures.clear();
    await f.controller.load();
    expect(f.controller.state.error, isNull);
  });
  test(
    'name updates global identity with exactly the existing PATCH payload',
    () async {
      expect(await f.controller.updateName('  Nama Baru  '), isTrue);
      expect(f.api.user?['nama'], 'Nama Baru');
      expect(f.controller.state.mutation, AccountProfileMutation.success);
      expect(jsonDecode(f.calls.singleWhere((r) => r.method == 'PATCH').body), {
        'nama': 'Nama Baru',
      });
    },
  );
  test(
    'rejected name change does not overwrite the canonical profile',
    () async {
      f.mutationFailure = 400;
      expect(await f.controller.updateName('Ditolak'), isFalse);
      expect(f.api.user?['nama'], 'Pasien Awal');
      expect(f.controller.state.mutation, AccountProfileMutation.failure);
    },
  );
  test('lost name response can be reconciled without a second PATCH', () async {
    f.mutationFailure = 0;
    f.commitUnknown = true;
    expect(await f.controller.updateName('Nama Tersimpan'), isTrue);
    expect(f.api.user?['nama'], 'Nama Tersimpan');
    expect(f.writes, 1);
  });
  for (final remove in [false, true]) {
    test(
      'avatar ${remove ? 'delete' : 'upload'} preserves transport and refreshes metadata',
      () async {
        final result = remove
            ? await f.controller.removeAvatar()
            : await f.controller.uploadAvatar([1, 2, 3]);
        expect(result, isTrue);
        expect(
          f.api.user?['avatarProfil'],
          remove ? isNull : '/media/avatar/server.webp',
        );
        final request = f.calls.singleWhere((r) => r.method != 'GET');
        expect(request.method, remove ? 'DELETE' : 'POST');
        expect(request.url.path, '/api/v1/auth/me/avatar');
      },
    );
  }
  test('avatar committed but reload failed is partial and never repeats the upload automatically', () async {
    f.failReloadAfterWrite = true;
    expect(await f.controller.uploadAvatar([1, 2, 3]), isTrue);
    expect(f.controller.state.mutation, AccountProfileMutation.partial);
    expect(f.controller.state.needsReconciliation, isTrue);
    expect(await f.controller.uploadAvatar([1, 2, 3]), isFalse);
    expect(f.writes, 1);
    f.failReloadAfterWrite = false;
    await f.controller.load();
    expect(f.controller.state.needsReconciliation, isFalse);
    expect(f.api.user?['avatarProfil'], '/media/avatar/server.webp');
  });
  test('password stays outside state and successful change uses existing session cleanup', () async {
    final states = <AccountProfileState>[];
    final sub = f.controller.stream.listen(states.add);
    await f.controller.changePassword(
      'fixture-old-password',
      'fixture-new-password',
    );
    expect(f.api.user, isNull);
    expect(f.controller.state.ended, isTrue);
    for (final state in states) {
      expect(
        jsonEncode(state.profile),
        isNot(contains('fixture-old-password')),
      );
      expect(state.error, isNot(contains('fixture-new-password')));
    }
    final request = f.calls.singleWhere(
      (r) => r.url.path.endsWith('/password'),
    );
    expect(jsonDecode(request.body), {
      'kataSandiLama': 'fixture-old-password',
      'kataSandiBaru': 'fixture-new-password',
    });
    await sub.cancel();
  });
  test('password failure is safe and unknown outcome stays guarded after profile GET', () async {
    f.mutationFailure = 0;
    expect(
      await f.controller.changePassword(
        'fixture-old-password',
        'fixture-new-password',
      ),
      isFalse,
    );
    expect(f.controller.state.credentialUnknown, isTrue);
    await f.controller.load();
    expect(
      await f.controller.changePassword(
        'fixture-old-password',
        'fixture-new-password',
      ),
      isFalse,
    );
    expect(f.writes, 1);
    expect(f.controller.state.error, isNot(contains('fixture-old-password')));
  });
  test(
    'duplicate mutation is prevented while a profile command is in flight',
    () async {
      final gate = Completer<void>();
      f.writeGate = gate;
      final started = f.writeStarted = Completer<void>();
      final first = f.controller.updateName('Nama Baru');
      await started.future;
      expect(await f.controller.updateName('Nama Kedua'), isFalse);
      gate.complete();
      await first;
      expect(f.writes, 1);
    },
  );
  test(
    'burst profile refresh completes only after the trailing read',
    () async {
      final a = Completer<void>(), b = Completer<void>();
      f.gates[('/auth/me', 1)] = a;
      f.gates[('/auth/me', 2)] = b;
      bool done = false;
      final first = f.controller.load().then((_) => done = true);
      await f.waitRead('/auth/me', 1);
      final burst = [for (var i = 0; i < 10; i++) f.controller.load()];
      a.complete();
      await f.waitRead('/auth/me', 2);
      expect(done, isFalse);
      b.complete();
      await Future.wait([first, ...burst]);
      expect(f.reads['/auth/me'], 2);
    },
  );
  for (final ending in ['close', 'logout', 'account', 'role']) {
    test(
      '$ending ignores a pending profile load without resurrecting old identity',
      () async {
        final gate = Completer<void>();
        f.gates[('/auth/me', 1)] = gate;
        final pending = f.controller.load();
        await f.waitRead('/auth/me', 1);
        if (ending == 'close') {
          await f.controller.close();
        } else if (ending == 'logout') {
          await f.api.clearSession();
        } else {
          f.profile = {
            ...f.profile,
            'id': ending == 'account' ? 'other' : 'owner',
            'peran': ending == 'role' ? 'ADMIN' : 'USER',
          };
          await f.api.login('other@example.test', 'fixture-login-password');
        }
        gate.complete();
        await pending;
        if (ending != 'close') expect(f.controller.state.profile, isEmpty);
        if (ending == 'account') expect(f.api.user?['id'], 'other');
        if (ending == 'role') expect(f.api.user?['peran'], 'ADMIN');
      },
    );
  }
  for (final role in ['PETUGAS', 'DOKTER']) {
    test(
      '$role uses the same profile adapter and sanitizes read-only role information',
      () async {
        final other = ProfileFixture(role);
        try {
          await other.controller.load();
          expect(other.controller.state.roleData, isNotNull);
          expect(
            jsonEncode(other.controller.state.roleData),
            isNot(contains('fixture-secret')),
          );
        } finally {
          await other.dispose();
        }
      },
    );
  }
  testWidgets(
    'failed password attempt clears controllers while keeping safe operation state',
    (tester) async {
      f.mutationFailure = 400;
      await tester.pumpWidget(MaterialApp(home: UserProfilePage(api: f.api)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keamanan Akun').last);
      await tester.pumpAndSettle();
      for (final pair in [
        ('Kata sandi lama', 'fixture-old-password'),
        ('Kata sandi baru', 'fixture-new-password'),
        ('Konfirmasi kata sandi baru', 'fixture-new-password'),
      ]) {
        await tester.enterText(
          find.widgetWithText(TextFormField, pair.$1),
          pair.$2,
        );
      }
      final submit = find.text('Ubah Kata Sandi');
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      for (final field in tester.widgetList<EditableText>(
        find.byType(EditableText),
      )) {
        if (field.obscureText) expect(field.controller.text, isEmpty);
      }
      final owner = tester
          .element(
            find.byType(BlocConsumer<AccountProfileCubit, AccountProfileState>),
          )
          .read<AccountProfileCubit>();
      expect(owner.state.error, isNot(contains('fixture-old-password')));
      await tester.pumpWidget(const SizedBox());
    },
  );
}
