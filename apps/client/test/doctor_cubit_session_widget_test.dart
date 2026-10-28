import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:queueb_client/src/api.dart';
import 'package:queueb_client/src/app.dart';
import 'package:queueb_client/src/config.dart';
import 'package:queueb_client/src/doctor_dashboard.dart';
import 'package:queueb_client/src/features/doctor/application/doctor_portal_cubit.dart';
import 'package:queueb_client/src/features/doctor/application/doctor_portal_state.dart';

void main() {
  setUpAll(tz.initializeTimeZones);

  testWidgets('account switch closes old owner and ignores pending profile', (
    tester,
  ) async {
    var identity = <String, dynamic>{
      'id': 'one',
      'peran': 'DOKTER',
      'nama': 'One',
    };
    final blocked = Completer<void>();
    var profileReads = 0;
    final api = QueueApi(
      config: AppConfig(
        apiBaseUrl: 'http://localhost:3000/api/v1',
        realtime: false,
      ),
      client: MockClient((r) async {
        Object body = [];
        if (r.url.path.endsWith('/me')) body = identity;
        if (r.url.path.endsWith('/profil')) {
          final name = identity['nama'];
          if (++profileReads == 1) await blocked.future;
          body = {'nama': name};
        }
        return http.Response(
          jsonEncode(body),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    )..user = identity;
    await tester.pumpWidget(QueueBApp(api: api));
    await tester.pump();
    final old = tester
        .element(find.byType(DoctorDashboard))
        .read<DoctorPortalCubit>();
    identity = {'id': 'two', 'peran': 'DOKTER', 'nama': 'Two'};
    await api.reloadOwnProfile();
    expect(old.state.status, DoctorPortalStatus.sessionEnded);
    expect(old.state.data.profile, isEmpty);
    await tester.pumpAndSettle();
    expect(old.isClosed, isTrue);
    final current = tester
        .element(find.byType(DoctorDashboard))
        .read<DoctorPortalCubit>();
    expect(current, isNot(same(old)));
    expect(current.state.data.profile['nama'], 'Two');
    blocked.complete();
    await tester.pumpAndSettle();
    expect(current.state.data.profile['nama'], 'Two');
    expect(profileReads, 2);
    await tester.pumpWidget(const SizedBox());
    expect(current.isClosed, isTrue);
    api.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets('role change unmounts and closes doctor scope', (tester) async {
    var role = 'DOKTER';
    final api = QueueApi(
      config: AppConfig(
        apiBaseUrl: 'http://localhost:3000/api/v1',
        realtime: false,
      ),
      client: MockClient((r) async {
        final Object body = r.url.path.endsWith('/me')
            ? {'id': 'one', 'peran': role, 'nama': 'One'}
            : r.url.path.endsWith('/profil')
            ? {'nama': 'Doctor'}
            : [];
        return http.Response(
          jsonEncode(body),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    )..user = {'id': 'one', 'peran': 'DOKTER'};
    await tester.pumpWidget(QueueBApp(api: api));
    await tester.pumpAndSettle();
    final cubit = tester
        .element(find.byType(DoctorDashboard))
        .read<DoctorPortalCubit>();
    role = 'ADMIN';
    await api.reloadOwnProfile();
    expect(cubit.state.status, DoctorPortalStatus.sessionEnded);
    await tester.pumpAndSettle();
    expect(find.byType(DoctorDashboard), findsNothing);
    expect(cubit.isClosed, isTrue);
    await tester.pumpWidget(const SizedBox());
    api.dispose();
    expect(tester.takeException(), isNull);
  });
}
