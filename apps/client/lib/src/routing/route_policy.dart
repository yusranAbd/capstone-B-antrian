import '../api.dart';

/// Location policy only. QueueApi remains the authority for account identity.
abstract final class RoutePolicy {
  static const homes = {
    'ADMIN': '/admin',
    'USER': '/patient',
    'PETUGAS': '/staff',
    'DOKTER': '/doctor',
  };
  static const adminPaths = [
    '/admin',
    '/admin/polyclinics',
    '/admin/doctors',
    '/admin/rooms',
    '/admin/service-hours',
    '/admin/practice-schedules',
    '/admin/consultation-slots',
    '/admin/staff-assignments',
    '/admin/displays',
  ];
  static const patientPaths = [
    '/patient',
    '/patient/reservations',
    '/patient/tickets',
    '/patient/appointments',
    '/patient/profile',
    '/patient/information',
  ];
  static const systemPaths = [
    '/',
    '/login',
    '/register',
    '/session',
    '/forbidden',
  ];
  static final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
  );
  static bool validId(String value) => _uuid.hasMatch(value);

  static String? roleFor(String path) {
    if (adminPaths.contains(path) || path == '/admin/profile') return 'ADMIN';
    if (patientPaths.contains(path) ||
        path == '/patient/reservations/new' ||
        RegExp(r'^/patient/(tickets/[^/]+|reservations/doctors/[^/]+)$')
            .hasMatch(path)) {
      return 'USER';
    }
    if (path == '/staff' || path == '/staff/profile') return 'PETUGAS';
    if (path == '/doctor' || path == '/doctor/profile') return 'DOKTER';
    return null;
  }

  static bool registered(String path) =>
      systemPaths.contains(path) || path == '/display' || roleFor(path) != null;

  static bool validDestination(Uri uri, {bool allowReturn = false}) {
    try {
      return _validDestination(uri, allowReturn: allowReturn);
    } on FormatException {
      return false;
    }
  }

  static bool _validDestination(Uri uri, {required bool allowReturn}) {
    final raw = uri.toString();
    if (uri.hasScheme ||
        uri.hasAuthority ||
        uri.hasFragment ||
        !raw.startsWith('/') ||
        raw.startsWith('//') ||
        uri.path.contains('\\') ||
        uri.path.contains('//') ||
        raw.contains(RegExp(r'[\x00-\x20\x7f]')) ||
        uri.path.contains('%') ||
        uri.pathSegments.any((s) => s == '.' || s == '..') ||
        !registered(uri.path)) {
      return false;
    }
    final path = uri.path;
    if ((path.startsWith('/patient/tickets/') ||
            path.startsWith('/patient/reservations/doctors/')) &&
        !validId(uri.pathSegments.last)) {
      return false;
    }
    final allowed = <String>{
      if (allowReturn && ['/login', '/session'].contains(path)) 'from',
      if (path == '/patient/reservations/new') ...['mode', 'clinic'],
      if (path.startsWith('/patient/reservations/doctors/')) 'clinic',
    };
    if (uri.queryParametersAll.entries.any(
      (e) => !allowed.contains(e.key) || e.value.length != 1,
    )) {
      return false;
    }
    final q = uri.queryParameters;
    if (q.containsKey('mode') &&
        !['legacy', 'nearest', 'clinics', 'doctors'].contains(q['mode'])) {
      return false;
    }
    if (q.containsKey('clinic') && !validId(q['clinic']!)) return false;
    return true;
  }

  static String? safeReturn(String? value, {String? role}) {
    if (value == null ||
        value.split('?').first.split('/').any((s) => s == '.' || s == '..') ||
        value.contains('\\') ||
        value.length > 1024 ||
        value.contains(RegExp(r'%2[fFeE]|%5[cC]|%25', caseSensitive: false))) {
      return null;
    }
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !validDestination(uri) ||
        roleFor(uri.path) == null ||
        (role != null && roleFor(uri.path) != role)) {
      return null;
    }
    return uri.toString();
  }

  static String _withReturn(String path, String? target) => target == null
      ? path
      : Uri(path: path, queryParameters: {'from': target}).toString();

  static String? redirect({
    required Uri uri,
    required SessionPhase phase,
    required bool signedIn,
    required String? role,
  }) {
    // Device credentials and account credentials have independent lifetimes.
    if (uri.path == '/display' && validDestination(uri)) return null;
    if (!registered(uri.path)) return null; // safe errorBuilder, never echo URI
    if (!validDestination(uri, allowReturn: true)) return '/forbidden';
    if (uri.path == '/forbidden') return null;
    final from = safeReturn(uri.queryParameters['from']);
    final current = safeReturn(uri.toString());
    if (phase != SessionPhase.ready) {
      final target = _withReturn('/session', from ?? current);
      return target == uri.toString() ? null : target;
    }
    if (!signedIn) {
      if (uri.path == '/login' || uri.path == '/register') {
        final canonical = uri.path == '/login'
            ? _withReturn('/login', from)
            : '/register';
        return canonical == uri.toString() ? null : canonical;
      }
      return _withReturn('/login', from ?? current);
    }
    final home = homes[role];
    if (home == null) return '/forbidden';
    if (['/', '/login', '/register', '/session'].contains(uri.path)) {
      return safeReturn(from, role: role) ?? home;
    }
    if (roleFor(uri.path) != role) return '/forbidden';
    return null;
  }
}
