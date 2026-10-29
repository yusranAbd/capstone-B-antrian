import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:queueb_client/src/api.dart';
import 'package:queueb_client/src/app.dart';
import 'package:queueb_client/src/config.dart';
import 'package:queueb_client/src/routing/route_refresh_notifier.dart';
import 'package:timezone/data/latest.dart' as tz;

class RoutingApi extends QueueApi {
  RoutingApi()
    : super(
        config: AppConfig(
          apiBaseUrl: 'http://localhost/api/v1',
          realtime: false,
        ),
        client: MockClient((_) async => http.Response('[]', 200)),
      );
  SessionPhase phase = SessionPhase.ready;
  @override
  SessionPhase get sessionPhase => phase;
  void change({
    String? id,
    String? role,
    SessionPhase phase = SessionPhase.ready,
  }) {
    this.phase = phase;
    user = id == null ? null : {'id': id, 'peran': role, 'nama': 'Uji'};
    notifyListeners();
  }
}

void main() {
  setUpAll(tz.initializeTimeZones);
  test('filtered adapter ends scope once and never owns API', () {
    final api = RoutingApi()..change(id: '1', role: 'USER');
    final refresh = RouteRefreshNotifier(api);
    var calls = 0;
    refresh.addListener(() => calls++);
    api.notifyListeners();
    expect(calls, 0);
    final first = refresh.scopeKey;
    api.change(phase: SessionPhase.signingOut);
    api.change(id: '1', role: 'USER');
    expect(refresh.scopeKey, isNot(first));
    expect(refresh.epoch, 1);
    expect(calls, 2);
    refresh.dispose();
    api.notifyListeners();
    api.dispose();
  });
  testWidgets(
    'one router survives app rebuild, gates session and hides unknown role',
    (tester) async {
      final api = RoutingApi();
      await tester.pumpWidget(QueueBApp(api: api));
      await tester.pumpAndSettle();
      final first = tester
          .widget<MaterialApp>(find.byType(MaterialApp))
          .routerConfig;
      expect(find.byType(LoginPage), findsOneWidget);
      await tester.pumpWidget(QueueBApp(api: api));
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).routerConfig,
        same(first),
      );
      api.change(phase: SessionPhase.offline);
      await tester.pumpAndSettle();
      expect(find.text('Koneksi sesi belum tersedia'), findsOneWidget);
      expect(find.byType(LoginPage), findsNothing);
      api.change(id: '1', role: 'UNKNOWN');
      await tester.pumpAndSettle();
      expect(
        find.text('Halaman tidak dapat diakses oleh akun ini.'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      api.dispose();
    },
  );
}
