import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:queueb_client/src/mobile_ui.dart';

import 'patient_test_navigation.dart';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/testing.dart';
import 'package:queueb_client/src/admin.dart';
import 'package:queueb_client/src/admin_navigation.dart';
import 'package:queueb_client/src/api.dart';
import 'package:queueb_client/src/app.dart';
import 'package:queueb_client/src/config.dart';
import 'package:queueb_client/src/display.dart';
import 'package:queueb_client/src/patient.dart';
import 'package:queueb_client/src/user_profile.dart';
import 'package:queueb_client/src/features/patient/application/patient_overview_cubit.dart';
import 'package:queueb_client/src/features/patient/application/patient_ticket_cubit.dart';
import 'package:queueb_client/src/routing/route_policy.dart';
import 'package:timezone/data/latest.dart' as tz;

import 'routing_foundation_test.dart' show RoutingApi;
import 'ui_test.dart' show FakeBackend, uid;

class Owners extends BlocObserver {
  final created = <BlocBase<dynamic>>[], closed = <BlocBase<dynamic>>[];
  @override
  void onCreate(BlocBase<dynamic> bloc) {
    created.add(bloc);
    super.onCreate(bloc);
  }

  @override
  void onClose(BlocBase<dynamic> bloc) {
    closed.add(bloc);
    super.onClose(bloc);
  }
}

void metric(Map<String, Object?> value) =>
    debugPrint('ROUTING_METRIC ${jsonEncode(value)}');

void main() {
  setUpAll(tz.initializeTimeZones);
  late Owners owners;
  late BlocObserver previous;
  setUp(() {
    previous = Bloc.observer;
    owners = Owners();
    Bloc.observer = owners;
  });
  tearDown(() => Bloc.observer = previous);

  Future<(QueueApi, FakeBackend, GoRouter)> launch(
    WidgetTester tester,
    String role, {
    String? cold,
    bool missingTicket = false,
    Completer<void>? postGate,
  }) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    if (cold != null) {
      tester.platformDispatcher.defaultRouteNameTestValue = cold;
    }
    final backend = FakeBackend(role);
    final api =
        QueueApi(
            config: AppConfig(
              apiBaseUrl: 'http://localhost/api/v1',
              realtime: false,
            ),
            client: MockClient((r) async {
              if (r.method == 'POST' && r.url.path.endsWith('/reservasi')) {
                await postGate?.future;
              }
              if (r.url.path.endsWith('/tiket/$uid') && missingTicket) {
                return backend.reply({'message': 'Tidak ditemukan'}, 404);
              }
              return backend.handle(r);
            }),
          )
          ..accessToken = 'test'
          ..user = backend.user;
    await tester.pumpWidget(QueueBApp(api: api));
    await tester.pumpAndSettle();
    final router =
        tester.widget<MaterialApp>(find.byType(MaterialApp)).routerConfig!
            as GoRouter;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      api.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearDefaultRouteNameTestValue();
    });
    return (api, backend, router);
  }

  testWidgets('ADMIN nine URLs share one owner and URI-derived selection', (
    tester,
  ) async {
    final (_, backend, router) = await launch(tester, 'ADMIN');
    final host = tester.state(find.byType(AdminPage));
    final initialOwners = [...owners.created];
    for (var i = 0; i < RoutePolicy.adminPaths.length; i++) {
      router.go(RoutePolicy.adminPaths[i]);
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(AdminPage)), same(host));
      expect(
        tester.widget<AdminNavigation>(find.byType(AdminNavigation)).selected,
        i - 1,
      );
      expect(owners.created, orderedEquals(initialOwners));
    }
    metric({
      'portal': 'admin',
      'modules': RoutePolicy.adminPaths.length,
      'created': owners.created.length,
      'closed': owners.closed.length,
    });
    expect(backend.requests.where((r) => r.$1 == 'POST'), isEmpty);
    router.go('/admin/profile');
    await tester.pumpAndSettle();
    expect(find.byType(UserProfilePage), findsOneWidget);
    expect(
      tester.state(find.byType(AdminPage, skipOffstage: false)),
      same(host),
    );
  });

  testWidgets('ADMIN small-screen menu closes and projects routed selection', (
    tester,
  ) async {
    final (_, _, router) = await launch(tester, 'ADMIN');
    final host = tester.state(find.byType(AdminPage));
    final created = [...owners.created];
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(AdminNavigation),
        matching: find.text('Dokter'),
      ),
    );
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/admin/doctors');
    expect(find.byType(BottomSheet), findsNothing);
    expect(tester.state(find.byType(AdminPage)), same(host));
    expect(owners.created, orderedEquals(created));
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    expect(
      tester.widget<AdminNavigation>(find.byType(AdminNavigation)).selected,
      1,
    );
    await tester.tap(
      find.descendant(
        of: find.byType(AdminNavigation),
        matching: find.text('Dashboard'),
      ),
    );
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/admin');
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets(
    'patient five lazy branches retain one repository/feed and Cubits without navigation reads',
    (tester) async {
      final (_, backend, router) = await launch(tester, 'USER');
      final host = tester.state(find.byType(PatientPage));
      expect(
        find.byType(PatientBranchView, skipOffstage: false),
        findsOneWidget,
      );
      expect(find.byType(UserProfilePage, skipOffstage: false), findsNothing);
      final overview = owners.created.whereType<PatientOverviewCubit>().single;
      final repository = overview.repository;
      final feed = repository.updates;
      final initialOwners = [...owners.created];
      for (final path in RoutePolicy.patientPaths.take(4)) {
        router.go(path);
        await tester.pumpAndSettle();
      }
      final reads = backend.requests.length;
      for (var i = 0; i < 3; i++) {
        for (final path in RoutePolicy.patientPaths.take(4)) {
          router.go(path);
          await tester.pumpAndSettle();
          expect(tester.state(find.byType(PatientPage)), same(host));
          expect(overview.repository, same(repository));
          expect(repository.updates, same(feed));
        }
      }
      expect(owners.created, orderedEquals(initialOwners));
      expect(owners.closed, isEmpty);
      expect(backend.requests.length, reads);
      metric({
        'portal': 'patient',
        'createdBeforeProfile': initialOwners.length,
        'createdAfterNavigation': owners.created.length,
        'closedAfterNavigation': owners.closed.length,
        'navigationLoops': 12,
        'readsBefore': reads,
        'readsAfter': backend.requests.length,
      });
      router.go('/patient/profile');
      await tester.pumpAndSettle();
      expect(find.byType(UserProfilePage, skipOffstage: false), findsOneWidget);
      router.go('/patient');
      await tester.pumpAndSettle();
      router.go('/patient/profile');
      await tester.pumpAndSettle();
      expect(find.byType(UserProfilePage, skipOffstage: false), findsOneWidget);
      metric({
        'portal': 'patient-profile',
        'createdAfterProfile': owners.created.length,
        'retainedProfileWidgets': find
            .byType(UserProfilePage, skipOffstage: false)
            .evaluate()
            .length,
      });
      expect(backend.requests.where((r) => r.$1 == 'POST'), isEmpty);
      await tester.pumpWidget(const SizedBox());
      for (
        var n = 0;
        n < 10 && owners.closed.length < owners.created.length;
        n++
      ) {
        await tester.pump();
      }
      expect(owners.created.every((owner) => owner.isClosed), isTrue);
      expect(
        owners.closed.whereType<Cubit>().toSet(),
        owners.created.whereType<Cubit>().toSet(),
      );
    },
  );

  for (final path in [
    '/patient/reservations/new',
    '/patient/reservations/doctors/$uid?clinic=$uid',
    '/patient/tickets/$uid',
  ]) {
    testWidgets('cold URL $path hydrates without POST or extra', (
      tester,
    ) async {
      final (_, backend, router) = await launch(tester, 'USER', cold: path);
      expect(router.routeInformationProvider.value.uri.toString(), path);
      expect(backend.requests.where((r) => r.$1 != 'GET'), isEmpty);
      if (path.contains('/tickets/')) {
        expect(
          backend.requests.where((r) => r.$2 == '/tiket/$uid'),
          hasLength(1),
        );
        expect(owners.created.whereType<PatientTicketCubit>(), hasLength(1));
        expect(find.text('Lihat tiket & QR'), findsOneWidget);
        await tester.tap(find.text('Lihat tiket & QR'));
        await tester.pumpAndSettle();
        expect(owners.created.whereType<PatientTicketCubit>(), hasLength(1));
        expect(backend.requests.where((r) => r.$1 != 'GET'), isEmpty);
        router.go('/patient/tickets');
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        metric({
          'portal': 'ticket',
          'created': owners.created.whereType<PatientTicketCubit>().length,
          'closed': owners.closed.whereType<PatientTicketCubit>().length,
          'nonGetRequests': backend.requests.where((r) => r.$1 != 'GET').length,
        });
      } else if (path.contains('/doctors/')) {
        expect(find.text('Detail Dokter'), findsOneWidget);
      }
    });
  }

  testWidgets('ticket GET 404 cannot show QR action', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      final (_, backend, _) = await launch(
        tester,
        'USER',
        cold: '/patient/tickets/$uid',
        missingTicket: true,
      );
      expect(
        find.text('Tiket tidak tersedia atau tidak dapat diakses.'),
        findsOneWidget,
      );
      expect(find.text('Lihat tiket & QR'), findsNothing);
      expect(
        find.bySemanticsLabel('Tiket tidak tersedia atau tidak dapat diakses.'),
        findsOneWidget,
      );
      expect(backend.requests.where((r) => r.$1 != 'GET'), isEmpty);
    } finally {
      semantics.dispose();
    }
  });

  for (final role in ['PETUGAS', 'DOKTER']) {
    testWidgets('$role profile retains parent owner and logout evicts all', (
      tester,
    ) async {
      final (api, _, router) = await launch(tester, role);
      final initial = [...owners.created];
      router.go('${RoutePolicy.homes[role]}/profile');
      await tester.pumpAndSettle();
      expect(find.byType(UserProfilePage), findsOneWidget);
      expect(
        owners.created.where(
          (owner) => owner.runtimeType == initial.first.runtimeType,
        ),
        hasLength(1),
      );
      metric({
        'portal': role,
        'parentOwnersBefore': initial.length,
        'totalOwnersWithProfile': owners.created.length,
      });
      for (final owner in initial) {
        expect(owners.closed.contains(owner), isFalse);
      }
      await api.logout();
      await tester.pumpAndSettle();
      expect(find.byType(LoginPage), findsOneWidget);
      expect(find.byType(UserProfilePage, skipOffstage: false), findsNothing);
      for (
        var n = 0;
        n < 10 && owners.closed.length < owners.created.length;
        n++
      ) {
        await tester.pump();
      }
      expect(owners.created.every((owner) => owner.isClosed), isTrue);
      expect(
        owners.closed.whereType<Cubit>().toSet(),
        owners.created.whereType<Cubit>().toSet(),
      );
    });
  }

  testWidgets(
    'Display identity survives account changes and explicit router refresh',
    (tester) async {
      tester.platformDispatcher.defaultRouteNameTestValue = '/display';
      final api = RoutingApi();
      await tester.pumpWidget(QueueBApp(api: api));
      await tester.pumpAndSettle();
      final display = tester.state(find.byType(DisplayPage));
      final initialOwners = [...owners.created];
      final router =
          tester.widget<MaterialApp>(find.byType(MaterialApp)).routerConfig!
              as GoRouter;
      for (final phase in SessionPhase.values) {
        api.change(
          id: phase == SessionPhase.ready ? '1' : null,
          role: 'ADMIN',
          phase: phase,
        );
        router.refresh();
        await tester.pump();
        expect(tester.state(find.byType(DisplayPage)), same(display));
        expect(router.routeInformationProvider.value.uri.path, '/display');
        expect(owners.created, orderedEquals(initialOwners));
      }
      metric({
        'portal': 'display',
        'createdBefore': initialOwners.length,
        'createdAfterRefresh': owners.created.length,
        'phases': SessionPhase.values.length,
      });
      await tester.pumpWidget(const SizedBox());
      api.dispose();
      tester.platformDispatcher.clearDefaultRouteNameTestValue();
      for (
        var n = 0;
        n < 10 && owners.closed.length < owners.created.length;
        n++
      ) {
        await tester.pump();
      }
      expect(owners.created.every((owner) => owner.isClosed), isTrue);
      expect(
        owners.closed.whereType<Cubit>().toSet(),
        owners.created.whereType<Cubit>().toSet(),
      );
    },
  );

  testWidgets(
    'same-role account switch evicts ADMIN modal and creates a fresh scope',
    (tester) async {
      final api = RoutingApi()..change(id: 'first', role: 'ADMIN');
      await tester.pumpWidget(QueueBApp(api: api));
      await tester.pumpAndSettle();
      final router =
          tester.widget<MaterialApp>(find.byType(MaterialApp)).routerConfig!
              as GoRouter;
      router.go('/admin/polyclinics');
      await tester.pumpAndSettle();
      final oldOwner = tester.state(find.byType(AdminPage));
      await tester.tap(find.widgetWithText(FilledButton, 'Tambah'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      api.change(id: 'second', role: 'ADMIN');
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.state(find.byType(AdminPage)), isNot(same(oldOwner)));
      await tester.pumpWidget(const SizedBox());
      api.dispose();
    },
  );

  testWidgets(
    'native Back returns patient detail to branch, branch to Home; retap resets booking',
    (tester) async {
      final (_, backend, router) = await launch(tester, 'USER');
      router.go('/patient/tickets/$uid');
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.path,
        '/patient/tickets',
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/patient');
      router.go('/patient/reservations/new');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(NavigationDestination, 'Reservasi'));
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.path,
        '/patient/reservations',
      );
      expect(backend.requests.where((r) => r.$1 != 'GET'), isEmpty);
    },
  );
  testWidgets('patient profile advertises framework Back and returns Home', (
    tester,
  ) async {
    final lifecycle =
        tester.binding.lifecycleState ?? AppLifecycleState.detached;
    addTearDown(() => tester.binding.handleAppLifecycleStateChanged(lifecycle));
    final notifications = <bool>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'SystemNavigator.setFrameworkHandlesBack') {
          notifications.add(call.arguments as bool);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final (_, _, router) = await launch(tester, 'USER');
    for (final label in [
      'Beranda',
      'Reservasi',
      'Tiket Saya',
      'Janji Temu',
      'Profil',
    ]) {
      await tester.tap(find.widgetWithText(NavigationDestination, label));
      await tester.pumpAndSettle();
    }
    expect(router.routeInformationProvider.value.uri.path, '/patient/profile');
    expect(notifications, isNotEmpty);
    expect(notifications.last, isTrue);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/patient');
    expect(notifications.last, isFalse);
  });
  testWidgets('same-role patient switch discards all retained branch owners', (
    tester,
  ) async {
    final api = RoutingApi()..change(id: 'first', role: 'USER');
    await tester.pumpWidget(QueueBApp(api: api));
    await tester.pumpAndSettle();
    final router =
        tester.widget<MaterialApp>(find.byType(MaterialApp)).routerConfig!
            as GoRouter;
    router.go('/patient/profile');
    await tester.pumpAndSettle();
    final firstProfile = tester.state(find.byType(UserProfilePage));
    final firstOwners = [...owners.created];
    api.change(id: 'second', role: 'USER');
    await tester.pumpAndSettle();
    expect(
      tester.state(find.byType(UserProfilePage)),
      isNot(same(firstProfile)),
    );
    expect(firstOwners.every((owner) => owner.isClosed), isTrue);
    expect(owners.created.whereType<PatientOverviewCubit>(), hasLength(2));
    await tester.pumpWidget(const SizedBox());
    api.dispose();
  });
  testWidgets(
    'busy booking blocks native Back but session eviction wins and late POST never replays',
    (tester) async {
      final gate = Completer<void>();
      final (api, backend, router) = await launch(
        tester,
        'USER',
        postGate: gate,
      );
      await openPatientCatalog(tester, walkIn: true);
      await tester.tap(find.byType(ClinicCard).first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Reservasi walk-in'));
      await tester.tap(find.text('Reservasi walk-in'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Lanjutkan'));
      await tester.pump();
      final path = router.routeInformationProvider.value.uri.toString();
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(router.routeInformationProvider.value.uri.toString(), path);
      await api.logout();
      await tester.pumpAndSettle();
      expect(find.byType(LoginPage), findsOneWidget);
      expect(find.byType(PatientPage, skipOffstage: false), findsNothing);
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byType(LoginPage), findsOneWidget);
      expect(
        backend.requests.where((r) => r.$1 == 'POST' && r.$2 == '/reservasi'),
        hasLength(1),
      );
    },
  );
  testWidgets(
    'switching ticket ID discards old detail and renders missing GET feedback',
    (tester) async {
      final (_, _, router) = await launch(
        tester,
        'USER',
        cold: '/patient/tickets/$uid',
      );
      expect(find.text('Lihat tiket & QR'), findsOneWidget);
      router.go('/patient/tickets/22222222-2222-4222-8222-222222222222');
      await tester.pumpAndSettle();
      expect(
        find.text('Tiket tidak tersedia atau tidak dapat diakses.'),
        findsOneWidget,
      );
      expect(find.text('Lihat tiket & QR'), findsNothing);
    },
  );
}
