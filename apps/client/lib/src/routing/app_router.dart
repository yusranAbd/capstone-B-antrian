import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../api.dart';
import '../app.dart';
import '../admin.dart';
import '../doctor.dart';
import '../patient.dart';
import '../queue.dart';
import '../display.dart';
import '../user_profile.dart';
import 'route_policy.dart';
import 'route_refresh_notifier.dart';
import 'account_overlay_observer.dart';

class AppRouting {
  AppRouting(this.api) {
    refresh = RouteRefreshNotifier(api);
    overlays = AccountOverlayObserver(
      refresh,
      () =>
          RoutePolicy.roleFor(router.routeInformationProvider.value.uri.path) !=
          null,
      () => router.routeInformationProvider.value.uri.toString(),
    );
    _configuration = ValueNotifier(_routes());
    _configuredScope = refresh.scopeKey;
    router = GoRouter.routingConfig(
      routingConfig: _configuration,
      navigatorKey: rootKey,
      observers: [overlays],
      refreshListenable: refresh,
      errorBuilder: (context, _) => _feedback(context, false),
    );
    overlays.watchLocation(router.routeInformationProvider);
    refresh.addListener(_scopeChanged);
  }

  void _scopeChanged() {
    if (_configuredScope == refresh.scopeKey) return;
    _configuredScope = refresh.scopeKey;
    // Fresh branch navigator identities evict retained private stacks even
    // when two accounts have the same role and the URL does not change.
    _configuration.value = _routes();
  }

  RoutingConfig _routes() {
    final adminKey = GlobalKey<NavigatorState>(debugLabel: 'admin');
    final patientKeys = List.generate(
      5,
      (i) => GlobalKey<NavigatorState>(debugLabel: 'patient-$i'),
    );
    return RoutingConfig(
      redirect: (_, state) => RoutePolicy.redirect(
        uri: state.uri,
        phase: api.sessionPhase,
        signedIn: api.user != null,
        role: api.user?['peran'] as String?,
      ),
      routes: [
        GoRoute(
          path: '/',
          name: 'entry',
          builder: (_, _) => const SizedBox.shrink(),
        ),
        for (final registration in [false, true])
          GoRoute(
            path: registration ? '/register' : '/login',
            name: registration ? 'register' : 'login',
            pageBuilder: (context, state) => NoTransitionPage<void>(
              key: const ValueKey('authentication'),
              child: LoginPage(
                key: const ValueKey('login-form'),
                api: api,
                notice: api.sessionMessage,
                registration: registration,
                onRegistrationChanged: (value) =>
                    context.go(value ? '/register' : '/login'),
                onDisplay: () => context.go('/display'),
              ),
            ),
          ),
        GoRoute(
          path: '/session',
          name: 'session',
          builder: (_, _) => ListenableBuilder(
            listenable: api,
            builder: (_, _) => SessionGate(api: api),
          ),
        ),
        GoRoute(
          path: '/forbidden',
          name: 'forbidden',
          builder: (context, _) => _feedback(context, true),
        ),
        ShellRoute(
          navigatorKey: adminKey,
          pageBuilder: (context, state, child) => NoTransitionPage<void>(
            key: ValueKey(('ADMIN', refresh.scopeKey)),
            child: _account(
              'ADMIN',
              PortalFrame(
                api: api,
                role: 'ADMIN',
                child: AdminPage(
                  api: api,
                  section: state.uri.path == '/admin/profile'
                      ? -1
                      : RoutePolicy.adminPaths.indexOf(state.uri.path) - 1,
                  onSection: (section) =>
                      context.go(RoutePolicy.adminPaths[section + 1]),
                  onProfile: () => context.go('/admin/profile'),
                  routeChild: child,
                ),
              ),
            ),
          ),
          routes: [
            for (final path in RoutePolicy.adminPaths)
              GoRoute(
                path: path,
                name: path == '/admin'
                    ? 'admin-home'
                    : 'admin-${path.split('/').last}',
                builder: (_, _) => const AdminRouteView(),
                routes: path == '/admin'
                    ? [
                        GoRoute(
                          path: 'profile',
                          name: 'admin-profile',
                          parentNavigatorKey: rootKey,
                          builder: (_, _) =>
                              _account('ADMIN', UserProfilePage(api: api)),
                        ),
                      ]
                    : [],
              ),
          ],
        ),
        StatefulShellRoute.indexedStack(
          pageBuilder: (context, state, shell) => NoTransitionPage<void>(
            key: ValueKey(('USER', refresh.scopeKey)),
            child: _account(
              'USER',
              PortalFrame(
                api: api,
                role: 'USER',
                child: PatientPage(
                  api: api,
                  navigationShell: shell,
                  location: state.uri,
                  onDisplay: () => context.go('/display'),
                ),
              ),
            ),
          ),
          branches: [
            StatefulShellBranch(
              navigatorKey: patientKeys[0],
              routes: [
                GoRoute(
                  path: '/patient',
                  name: 'patient-home',
                  builder: (_, _) => const PatientBranchView(index: 0),
                ),
              ],
            ),
            StatefulShellBranch(
              navigatorKey: patientKeys[1],
              routes: [
                GoRoute(
                  path: '/patient/reservations',
                  name: 'patient-reservations',
                  builder: (_, _) => const PatientBranchView(index: 1),
                  routes: [
                    GoRoute(
                      path: 'new',
                      name: 'patient-booking',
                      builder: (_, _) =>
                          const PatientBranchView(index: 1, bookingView: true),
                    ),
                    GoRoute(
                      path: 'doctors/:doctorId',
                      name: 'patient-doctor',
                      builder: (_, _) =>
                          const PatientBranchView(index: 1, bookingView: true),
                    ),
                  ],
                ),
              ],
            ),
            StatefulShellBranch(
              navigatorKey: patientKeys[2],
              routes: [
                GoRoute(
                  path: '/patient/tickets',
                  name: 'patient-tickets',
                  builder: (_, _) => const PatientBranchView(index: 2),
                  routes: [
                    GoRoute(
                      path: ':ticketId',
                      name: 'patient-ticket',
                      pageBuilder: (_, state) => NoTransitionPage<void>(
                        key: ValueKey(state.uri.path),
                        child: PatientTicketRoute(
                          ticketId: state.pathParameters['ticketId']!,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            StatefulShellBranch(
              navigatorKey: patientKeys[3],
              routes: [
                GoRoute(
                  path: '/patient/appointments',
                  name: 'patient-appointments',
                  builder: (_, _) => const PatientBranchView(index: 3),
                ),
              ],
            ),
            StatefulShellBranch(
              navigatorKey: patientKeys[4],
              routes: [
                GoRoute(
                  path: '/patient/profile',
                  name: 'patient-profile',
                  builder: (_, _) => const PatientBranchView(index: 4),
                ),
              ],
            ),
          ],
        ),
        for (final role in ['PETUGAS', 'DOKTER'])
          GoRoute(
            path: RoutePolicy.homes[role]!,
            name: '$role-home',
            pageBuilder: (context, _) => NoTransitionPage<void>(
              key: ValueKey((role, refresh.scopeKey)),
              child: _account(
                role,
                PortalFrame(
                  api: api,
                  role: role,
                  child: role == 'DOKTER'
                      ? DoctorPage(api: api)
                      : QueuePage(
                          api: api,
                          headerBuilder: (status) => portalHeader(
                            context,
                            api,
                            () => context.go('/staff/profile'),
                            staffContext: status,
                          ),
                        ),
                ),
              ),
            ),
            routes: [
              GoRoute(
                path: 'profile',
                name: '$role-profile',
                parentNavigatorKey: rootKey,
                builder: (_, _) => _account(role, UserProfilePage(api: api)),
              ),
            ],
          ),
        GoRoute(
          path: '/display',
          name: 'display',
          builder: (context, _) => DisplayPage(
            key: const ValueKey('display-host'),
            api: api,
            onExit: () => context.go('/'),
          ),
        ),
      ],
    );
  }

  final QueueApi api;
  late final ValueNotifier<RoutingConfig> _configuration;
  late Object _configuredScope;
  final rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');
  late final RouteRefreshNotifier refresh;
  late final AccountOverlayObserver overlays;
  late final GoRouter router;

  Widget _account(String role, Widget child) {
    final scope = refresh.scopeKey;
    return ListenableBuilder(
      listenable: refresh,
      builder: (_, _) =>
          scope == refresh.scopeKey &&
              api.sessionPhase == SessionPhase.ready &&
              api.user != null &&
              api.user?['peran'] == role
          ? KeyedSubtree(key: ValueKey(scope), child: child)
          : const SizedBox.shrink(),
    );
  }

  Widget _feedback(BuildContext context, bool forbidden) => Scaffold(
    appBar: AppBar(title: const Text('QueueB Hospital')),
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            forbidden
                ? 'Halaman tidak dapat diakses oleh akun ini.'
                : 'Halaman tidak tersedia.',
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => context.go('/'),
            child: const Text('Kembali'),
          ),
        ],
      ),
    ),
  );

  void dispose() {
    refresh.removeListener(_scopeChanged);
    overlays.dispose();
    router.dispose();
    _configuration.dispose();
    refresh.dispose();
  }
}
