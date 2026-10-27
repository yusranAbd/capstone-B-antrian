import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:queueb_client/src/admin_data.dart';
import 'package:queueb_client/src/admin_display.dart';
import 'package:queueb_client/src/admin_navigation.dart';
import 'package:queueb_client/src/admin_schema.dart';
import 'package:queueb_client/src/admin_schedules.dart';
import 'package:queueb_client/src/admin_staff.dart';
import 'package:queueb_client/src/admin_ui.dart';
import 'package:queueb_client/src/api.dart';
import 'package:queueb_client/src/app.dart';
import 'package:queueb_client/src/config.dart';

import 'ui_test.dart' show FakeBackend, uid;

class AdminV41Backend extends FakeBackend {
  AdminV41Backend() : super('ADMIN');
  final reads = <Uri>[];
  Json get doctor => {
    'id': uid,
    'nama': 'Dokter V41',
    'kode': 'DR41',
    'aktif': true,
    'spesialisasi': 'Anak',
    'dokterLayanan': [
      {'id': uid, 'layananId': uid, 'layanan': service, 'aktif': true},
    ],
  };
  Json get practice => {
    'id': uid,
    'tanggal': today,
    'aktif': true,
    'mulaiPada': '${today}T01:00:00Z',
    'selesaiPada': '${today}T05:00:00Z',
    'loketId': uid,
    'loket': room,
    'dokterLayanan': {
      'dokter': doctor,
      'dokterId': uid,
      'layanan': service,
      'layananId': uid,
    },
  };
  Json get account => {
    'id': uid,
    'nama': 'Petugas V41',
    'email': 'staff@fixture.local',
    'aktif': true,
    'peran': 'PETUGAS',
  };
  Json get assignment => {
    'id': uid,
    'aktif': true,
    'petugas': account,
    'petugasId': uid,
    'loket': room,
    'loketId': uid,
    'tanggalMulai': today,
  };
  Json get slot => {
    'id': uid,
    'aktif': true,
    'mulaiPada': '${today}T01:00:00Z',
    'selesaiPada': '${today}T01:30:00Z',
    'kapasitas': 2,
    'jumlahJanjiTemu': 0,
    'sisaKapasitas': 2,
    'tersedia': true,
  };
  Json get daily => {
    'id': uid,
    'layananId': uid,
    'layanan': service,
    'hari': 'SENIN',
    'aktif': true,
    'jamBuka': '08:00',
    'jamTutup': '12:00',
    'kapasitasHarian': 24,
  };
  Json get device => {
    'id': uid,
    'nama': 'TV V41',
    'layanan': service,
    'layananId': uid,
    'aktif': true,
  };
  Map<String, List<Json>> get catalog => {
    '/layanan': [service],
    '/dokter': [doctor],
    '/loket': [room],
    '/jadwal-praktik': [practice],
    '/slot-praktik': [slot],
    '/jadwal-layanan': [daily],
    '/penugasan-petugas': [assignment],
    '/akun-petugas': [account],
    '/perangkat-display': [device],
  };
  @override
  Future<http.Response> handle(http.Request r) async {
    if (r.method == 'GET') {
      reads.add(r.url);
      final p = r.url.path.replaceFirst('/api/v1', '');
      if (catalog.containsKey(p)) return reply(catalog[p]!);
    }
    return super.handle(r);
  }
}

void main() {
  setUpAll(tz.initializeTimeZones);
  QueueApi apiFor(AdminV41Backend b) =>
      QueueApi(
          config: AppConfig(
            apiBaseUrl: 'http://localhost/api/v1',
            realtime: false,
          ),
          client: MockClient(b.handle),
        )
        ..user = b.user
        ..accessToken = 'fixture';
  Future<void> mount(WidgetTester t, Widget child) async {
    t.view.physicalSize = const Size(1366, 768);
    t.view.devicePixelRatio = 1;
    addTearDown(() {
      t.view.resetPhysicalSize();
      t.view.resetDevicePixelRatio();
    });
    await t.pumpWidget(
      MaterialApp(
        theme: AdminStyle.theme,
        home: Scaffold(
          body: SingleChildScrollView(
            child: child is AdminDisplayPage
                ? SizedBox(height: 600, child: child)
                : child,
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  for (final path in [
    '/layanan',
    '/dokter',
    '/loket',
    '/jadwal-praktik',
    '/penugasan-petugas',
  ]) {
    testWidgets(
      '$path uses one contextual menu; supported callbacks stay intact',
      (t) async {
        final b = AdminV41Backend();
        final api = apiFor(b);
        addTearDown(api.dispose);
        final calls = <String>[];
        await mount(
          t,
          AdminDataView(
            resource: resources.firstWhere((r) => r.path == path),
            data: b.catalog[path]!,
            catalog: b.catalog,
            api: api,
            busy: false,
            revision: 1,
            detail: (_) => '',
            onEdit: (_) => calls.add('edit'),
            onDeactivate: (_) => calls.add('off'),
            onDelete: (_) => calls.add('delete'),
            onDoctorLinks: (_) => calls.add('links'),
            onDoctorAccount: (_) => calls.add('account'),
          ),
        );
        if (find.byType(AdminRowActions).evaluate().isEmpty) {
          await t.tap(find.byType(ExpansionTile).first);
          await t.pumpAndSettle();
        }
        expect(find.byType(AdminRowActions), findsOneWidget);
        expect(find.byIcon(Icons.delete_outline), findsNothing);
        for (final action in [
          path == '/dokter' ? 'Ubah profil' : 'Ubah',
          path == '/dokter' ? 'Nonaktifkan profil' : 'Nonaktifkan',
          path == '/dokter' ? 'Hapus profil' : 'Hapus',
        ]) {
          await t.ensureVisible(find.byType(AdminRowActions));
          await t.tap(find.byType(AdminRowActions));
          await t.pumpAndSettle();
          await t.tap(find.text(action));
          await t.pumpAndSettle();
        }
        expect(calls, ['edit', 'off', 'delete']);
        expect(t.takeException(), isNull);
        expect(find.textContaining('Dari tanggal'), findsNothing);
        expect(find.textContaining('Sampai tanggal'), findsNothing);
      },
    );
  }
  testWidgets(
    'daily, slot, account and display all use the reusable menu with no invented account CRUD',
    (t) async {
      final b = AdminV41Backend();
      final api = apiFor(b);
      addTearDown(api.dispose);
      for (final child in <Widget>[
        GroupedClinicSchedules(
          clinics: [b.service],
          schedules: [b.daily],
          search: '',
          onSearch: (_) {},
          onEdit: (_) {},
          onDeactivate: (_) {},
          onDelete: (_) {},
        ),
        AdminStaffAccounts(
          api: api,
          accounts: [b.account],
          busy: false,
          onChanged: () async {},
        ),
        AdminDisplayPage(api: api),
      ]) {
        await mount(t, child);
        expect(find.byType(AdminRowActions), findsWidgets);
        await t.ensureVisible(find.byType(AdminRowActions).first);
        await t.tap(find.byType(AdminRowActions).first);
        await t.pumpAndSettle();
        if (child is AdminStaffAccounts) {
          expect(find.text('Nonaktifkan akun'), findsOneWidget);
          expect(find.text('Hapus'), findsNothing);
          expect(find.text('Ubah'), findsNothing);
        }
        await t.tapAt(const Offset(5, 5));
        await t.pumpAndSettle();
      }
      await mount(
        t,
        AdminSlotSession(
          session: b.practice,
          api: api,
          revision: 1,
          status: '',
          search: '',
          busy: false,
          onEdit: (_) {},
          onDeactivate: (_) {},
          onDelete: (_) {},
        ),
      );
      await t.tap(find.byType(ExpansionTile));
      await t.pumpAndSettle();
      expect(find.byType(AdminRowActions), findsOneWidget);
      expect(
        b.reads.every(
          (u) =>
              !u.queryParameters.containsKey('dariTanggal') &&
              !u.queryParameters.containsKey('sampaiTanggal'),
        ),
        isTrue,
      );
    },
  );
  for (final size in [
    const Size(1366, 768),
    const Size(1920, 1080),
    const Size(768, 1024),
    const Size(390, 844),
  ]) {
    testWidgets('minimal ADMIN header, profile footer and logout at $size', (
      t,
    ) async {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      final b = AdminV41Backend();
      final api = apiFor(b);
      addTearDown(() async {
        await t.pumpWidget(const SizedBox());
        api.dispose();
        t.view.resetPhysicalSize();
        t.view.resetDevicePixelRatio();
      });
      await t.pumpWidget(QueueBApp(api: api));
      await t.pumpAndSettle();
      final bar = find.byType(AppBar);
      expect(t.getSize(bar).height, 52);
      expect(
        find.descendant(of: bar, matching: find.byType(CircleAvatar)),
        findsNothing,
      );
      expect(
        find.descendant(of: bar, matching: find.text('Akun ADMIN')),
        findsNothing,
      );
      expect(
        find.descendant(of: bar, matching: find.byTooltip('Profil akun')),
        findsNothing,
      );
      expect(find.byTooltip('Keluar akun'), findsOneWidget);
      if (size.width < 960) {
        await t.tap(find.widgetWithText(OutlinedButton, 'Menu administrasi'));
        await t.pumpAndSettle();
      }
      expect(find.byType(AdminNavigation), findsOneWidget);
      final profile = find.byTooltip('Profil akun');
      await t.ensureVisible(profile);
      await t.tap(profile);
      await t.pumpAndSettle();
      expect(find.text('Profil Saya'), findsOneWidget);
      await t.tap(find.byType(BackButton));
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Keluar akun'));
      await t.pumpAndSettle();
      expect(api.user, isNull);
      expect(t.takeException(), isNull);
    });
  }
  testWidgets('open menu retains action identity when rows refresh', (t) async {
    var changed = false;
    late StateSetter update;
    final calls = <String>[];
    await mount(
      t,
      StatefulBuilder(
        builder: (context, setState) {
          update = setState;
          return AdminRowActions(
            tooltip: 'Aksi race',
            actions: [
              if (!changed)
                AdminRowAction(
                  'Nonaktifkan',
                  Icons.block,
                  () => calls.add('off'),
                ),
              AdminRowAction('Hapus', Icons.delete, () => calls.add('delete')),
            ],
          );
        },
      ),
    );
    await t.tap(find.byType(AdminRowActions));
    await t.pumpAndSettle();
    update(() => changed = true);
    await t.pump();
    await t.tap(find.text('Nonaktifkan'));
    await t.pumpAndSettle();
    expect(calls, ['off']);
  });
  testWidgets('busy transition blocks an already-open action', (t) async {
    var busy = false;
    var calls = 0;
    late StateSetter update;
    await mount(
      t,
      StatefulBuilder(
        builder: (context, setState) {
          update = setState;
          return AdminRowActions(
            tooltip: 'Aksi busy',
            busy: busy,
            actions: [AdminRowAction('Hapus', Icons.delete, () => calls++)],
          );
        },
      ),
    );
    await t.tap(find.byType(AdminRowActions));
    await t.pumpAndSettle();
    update(() => busy = true);
    await t.pump();
    await t.tap(find.text('Hapus'));
    await t.pumpAndSettle();
    expect(calls, 0);
  });
}
