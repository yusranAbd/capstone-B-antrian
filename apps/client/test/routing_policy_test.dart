import 'package:flutter_test/flutter_test.dart';
import 'package:queueb_client/src/api.dart';
import 'package:queueb_client/src/routing/route_policy.dart';

void main() {
  const id = '11111111-1111-4111-8111-111111111111';
  String? redirect(
    String path, {
    SessionPhase phase = SessionPhase.ready,
    String? role,
  }) => RoutePolicy.redirect(
    uri: Uri.parse(path),
    phase: phase,
    signedIn: role != null,
    role: role,
  );
  test(
    'all protected registered locations require login with a safe return',
    () {
      for (final path in [
        ...RoutePolicy.adminPaths,
        '/admin/profile',
        ...RoutePolicy.patientPaths,
        '/patient/reservations/new',
        '/patient/reservations/doctors/$id',
        '/patient/tickets/$id',
        '/staff',
        '/staff/profile',
        '/doctor',
        '/doctor/profile',
      ]) {
        final target = Uri.parse(redirect(path)!);
        expect(target.path, '/login', reason: path);
        expect(target.queryParameters['from'], path);
      }
    },
  );
  for (final entry in RoutePolicy.homes.entries) {
    test('home and role isolation ${entry.key}', () {
      expect(redirect('/', role: entry.key), entry.value);
      expect(redirect('/login', role: entry.key), entry.value);
      expect(redirect(entry.value, role: entry.key), isNull);
      for (final other in RoutePolicy.homes.entries.where(
        (e) => e.key != entry.key,
      )) {
        expect(redirect(other.value, role: entry.key), '/forbidden');
      }
    });
  }
  test('unknown role cannot fall back to patient', () {
    expect(redirect('/', role: 'UNKNOWN'), '/forbidden');
    expect(redirect('/patient', role: 'UNKNOWN'), '/forbidden');
  });
  test('all nonready phases retain safe target without looping', () {
    for (final phase in SessionPhase.values.where(
      (p) => p != SessionPhase.ready,
    )) {
      final target = redirect('/admin/doctors', phase: phase)!;
      expect(Uri.parse(target).path, '/session');
      expect(redirect(target, phase: phase), isNull);
      expect(redirect(target, role: 'ADMIN'), '/admin/doctors');
      expect(Uri.parse(redirect(target)!).path, '/login');
    }
  });
  test('display exemption is exact and independent of account phases', () {
    for (final phase in SessionPhase.values) {
      expect(redirect('/display', phase: phase), isNull);
      expect(redirect('/display', phase: phase, role: 'ADMIN'), isNull);
    }
    expect(RoutePolicy.registered('/display-anything'), isFalse);
    expect(redirect('/display?token=secret'), '/forbidden');
  });
  test('safe return revalidates current role and ignores extra', () {
    expect(
      RoutePolicy.safeReturn('/patient/tickets/$id', role: 'USER'),
      '/patient/tickets/$id',
    );
    expect(RoutePolicy.safeReturn('/admin/doctors', role: 'USER'), isNull);
    expect(
      redirect('/login?from=%2Fadmin%2Fdoctors', role: 'ADMIN'),
      '/admin/doctors',
    );
    expect(
      redirect('/login?from=%2Fadmin%2Fdoctors', role: 'USER'),
      '/patient',
    );
  });
  for (final value in [
    'https://example.org',
    '//example.org',
    '/\\example.org',
    '/admin//doctors',
    '/admin/../patient',
    '/admin/%2e%2e/patient',
    '/admin/%252e%252e/patient',
    '/admin%2fdoctors',
    '/patient?from=/admin',
    '/login',
    '/session',
    '/register',
    '/unknown',
    '/patient#secret',
    '/display',
    '/patient?token=secret',
    '/patient?password=secret',
    '/patient?qr=secret',
    '/display?apiBase=http://evil',
    '/patient/tickets/invalid',
    '/admin/staff-assignments?tab=invalid',
    '/admin/staff-assignments?tab=accounts&tab=assignments',
  ]) {
    test('reject adversarial return $value', () {
      expect(RoutePolicy.safeReturn(value), isNull);
    });
  }
  test(
    'unknown paths use safe error builder and invalid IDs are forbidden',
    () {
      expect(redirect('/unknown?token=hidden'), isNull);
      expect(redirect('/patient/tickets/invalid', role: 'USER'), '/forbidden');
    },
  );
  test(
    'malformed UTF-8 query is rejected without throwing during redirect',
    () {
      for (final value in [
        '/patient?x=%FF',
        '/patient?%FF=x',
        '/login?from=%FF',
      ]) {
        expect(RoutePolicy.safeReturn(value), isNull);
        expect(redirect(value), '/forbidden');
      }
    },
  );
}
