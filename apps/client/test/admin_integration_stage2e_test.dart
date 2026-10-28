import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:queueb_client/src/admin.dart';
import 'package:queueb_client/src/admin_dashboard.dart';
import 'package:queueb_client/src/admin_data.dart';
import 'package:queueb_client/src/admin_display.dart';
import 'package:queueb_client/src/admin_navigation.dart';
import 'package:queueb_client/src/admin_schedules.dart';
import 'package:queueb_client/src/admin_staff.dart';
import 'package:queueb_client/src/admin_ui.dart';
import 'package:queueb_client/src/features/admin/application/admin_catalog_cubit.dart';
import 'package:queueb_client/src/features/admin/application/admin_catalog_state.dart';
import 'package:queueb_client/src/features/admin/application/practice_schedule_cubit.dart';
import 'package:queueb_client/src/features/admin/application/staff_management_cubit.dart';
import 'package:queueb_client/src/features/admin/application/display_management_cubit.dart';
import 'package:queueb_client/src/features/admin/models/admin_display_models.dart';
import 'package:timezone/data/latest.dart' as tz;

import 'admin_display_cubit_test.dart' show DisplayFixture;

void main() {
  setUpAll(tz.initializeTimeZones);
  late DisplayFixture f;
  setUp(() {
    f = DisplayFixture();
    final clinic = f.data['/layanan']!.first;
    clinic.addAll({
      'prefixAntrean': 'P',
      'durasiDasarMenit': 15,
      'modeReservasi': 'HIBRIDA',
    });
    f.data['/dokter'] = [
      {
        'id': 'doctor',
        'nama': 'Dokter Awal',
        'kode': 'DR01',
        'aktif': true,
        'dokterLayanan': [
          {
            'id': 'link',
            'layananId': 'clinic',
            'aktif': true,
            'layanan': clinic,
          },
        ],
      },
    ];
    f.data['/loket'] = [
      {
        'id': 'room',
        'nama': 'Ruang Awal',
        'kode': 'R01',
        'layananId': 'clinic',
        'aktif': true,
        'layanan': clinic,
      },
    ];
    f.data['/jadwal-layanan'] = [
      {
        'id': 'hours',
        'layananId': 'clinic',
        'layanan': clinic,
        'hari': 'SENIN',
        'jamBuka': '08:00',
        'jamTutup': '16:00',
        'kapasitasHarian': 24,
        'aktif': true,
      },
    ];
    f.data['/jadwal-praktik'] = [
      {
        'id': 'practice',
        'tanggal': f.api.config.today,
        'aktif': true,
        'loketId': 'room',
        'mulaiPada': f.api.config.toInstant('${f.api.config.today}T08:00'),
        'selesaiPada': f.api.config.toInstant('${f.api.config.today}T12:00'),
        'loket': f.data['/loket']!.first,
        'dokterLayanan': {
          'id': 'link',
          'layananId': 'clinic',
          'dokterId': 'doctor',
          'layanan': clinic,
          'dokter': f.data['/dokter']!.first,
        },
      },
    ];
    f.data['/akun-petugas'] = [
      {
        'id': '11111111-1111-4111-8111-111111111111',
        'nama': 'Petugas',
        'email': 'staff@example.test',
        'peran': 'PETUGAS',
        'aktif': true,
      },
    ];
    f.data['/penugasan-petugas'] = [
      {
        'id': 'assignment',
        'petugasId': f.data['/akun-petugas']!.first['id'],
        'loketId': 'room',
        'tanggalMulai': f.api.config.today,
        'tanggalSelesai': null,
        'aktif': true,
      },
    ];
  });
  tearDown(() => f.dispose());
  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AdminStyle.theme,
        home: Scaffold(body: AdminPage(api: f.api)),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> navigate(WidgetTester tester, int index) async {
    final nav = tester.widget<AdminNavigation>(find.byType(AdminNavigation));
    nav.onSelect!(index);
    await tester.pumpAndSettle();
  }

  bool hasSlots() => f.calls.any((r) => r.url.path.contains('slot-praktik'));

  testWidgets(
    'partial dashboard snapshots show unknown metrics instead of invented zeroes',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AdminDashboard(
                catalog: {'/layanan': f.data['/layanan']!},
                config: f.api.config,
                loading: false,
                onSelect: (_) {},
              ),
            ),
          ),
        ),
      );
      expect(find.text('Data belum tersedia'), findsNWidgets(3));
      expect(find.text('—'), findsNWidgets(3));
      expect(find.text('0 aktif'), findsNothing);
      expect(f.calls, isEmpty);
    },
  );
  testWidgets(
    'all nine menus share migrated owners and never eagerly read slots',
    (tester) async {
      await open(tester);
      final element = tester.element(find.byType(AdminDashboard));
      final poly = element.read<PolyclinicCubit>(),
          doctor = element.read<DoctorCatalogCubit>(),
          room = element.read<RoomCubit>();
      final practice = element.read<PracticeScheduleCubit>(),
          staff = element.read<StaffAccountCubit>(),
          assignment = element.read<AssignmentCubit>();
      final display = element.read<DisplayManagementCubit>();
      for (final index in [-1, 0, 1, 2, 3, 4, 5, 6, 7]) {
        await navigate(tester, index);
        if (index == -1) {
          expect(find.byType(AdminDashboard), findsOneWidget);
        } else if (index == 3) {
          expect(find.byType(GroupedClinicSchedules), findsOneWidget);
        } else if (index == 6) {
          expect(find.byType(AdminStaffAccounts), findsOneWidget);
        } else if (index == 7) {
          expect(find.byType(AdminDisplayPage), findsOneWidget);
        } else {
          expect(find.byType(AdminDataView), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      }
      expect(hasSlots(), isFalse);
      expect(
        f.reads[adminDisplayPath],
        1,
      ); // Devices load only when Display is first opened.
      expect(display.repository.catalog, same(poly.repository));
      expect(doctor.repository, same(room.repository));
      expect(practice.repository, same(staff.repository));
      expect(assignment.repository, same(poly.repository));
      await tester.pumpWidget(const SizedBox());
      expect([
        poly.isClosed,
        doctor.isClosed,
        room.isClosed,
        practice.isClosed,
        staff.isClosed,
        assignment.isClosed,
        display.isClosed,
      ], everyElement(isTrue));
    },
  );
  testWidgets(
    'master mutations update dashboard, display and assignment projections without duplicating doctors',
    (tester) async {
      await open(tester);
      await navigate(tester, 7);
      await navigate(tester, -1);
      final element = tester.element(find.byType(AdminDashboard));
      final poly = element.read<PolyclinicCubit>(),
          doctors = element.read<DoctorCatalogCubit>(),
          rooms = element.read<RoomCubit>();
      final assignments = element.read<AssignmentCubit>(),
          display = element.read<DisplayManagementCubit>();
      await tester.runAsync(
        () => poly.save({'nama': 'Poli Terbaru'}, id: 'clinic'),
      );
      await tester.pumpAndSettle();
      var dashboard = tester.widget<AdminDashboard>(
        find.byType(AdminDashboard),
      );
      expect(dashboard.catalog['/layanan']!.single['nama'], 'Poli Terbaru');
      expect(display.devices.first['layanan']['nama'], 'Poli Terbaru');
      await tester.runAsync(
        () => doctors.save({
          'nama': 'Dokter Baru',
          'aktif': true,
          'dokterLayanan': [],
        }),
      );
      await tester.pumpAndSettle();
      dashboard = tester.widget<AdminDashboard>(find.byType(AdminDashboard));
      expect(dashboard.catalog['/dokter'], hasLength(2));
      expect(
        dashboard.catalog['/dokter']!.map((d) => d['id']).toSet(),
        hasLength(2),
      );
      await tester.runAsync(
        () => rooms.save({'nama': 'Ruang Terbaru'}, id: 'room'),
      );
      await tester.pumpAndSettle();
      expect(assignments.rows.single['loket']['nama'], 'Ruang Terbaru');
      expect(
        identical(dashboard.catalog, display.state.snapshot.collections),
        isFalse,
      ); // A newer snapshot replaced it.
      expect(hasSlots(), isFalse);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'display metadata remains shared across dashboard navigation and rebuilds',
    (tester) async {
      await open(tester);
      expect(f.reads[adminDisplayPath] ?? 0, 0);
      await navigate(tester, 7);
      final c = tester
          .element(find.byType(AdminDisplayPage))
          .read<DisplayManagementCubit>();
      expect(f.reads[adminDisplayPath], 1);
      await tester.tap(find.byTooltip('Ciutkan sidebar'));
      await tester.pumpAndSettle();
      expect(f.reads[adminDisplayPath], 1);
      await navigate(tester, -1);
      expect(f.reads[adminDisplayPath], 1);
      final dashboard = tester.widget<AdminDashboard>(
        find.byType(AdminDashboard),
      );
      expect(
        identical(dashboard.catalog, c.state.snapshot.collections),
        isTrue,
      );
      await navigate(tester, 7);
      expect(f.reads[adminDisplayPath], 1);
      expect(hasSlots(), isFalse);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'dashboard error keeps metrics unknown and explicit reload recovers',
    (tester) async {
      f.readError = 503;
      await open(tester);
      expect(find.byType(AdminDashboard), findsOneWidget);
      expect(find.text('Data belum tersedia'), findsNWidgets(4));
      f.readError = null;
      tester.widget<AdminDashboard>(find.byType(AdminDashboard)).onRefresh!();
      await tester.pumpAndSettle();
      expect(find.text('Data belum tersedia'), findsNothing);
      expect(hasSlots(), isFalse);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'logout while dashboard refresh is pending clears every ADMIN projection',
    (tester) async {
      await open(tester);
      final element = tester.element(find.byType(AdminDashboard));
      final poly = element.read<PolyclinicCubit>(),
          doctor = element.read<DoctorCatalogCubit>(),
          room = element.read<RoomCubit>();
      final practice = element.read<PracticeScheduleCubit>(),
          staff = element.read<StaffAccountCubit>(),
          assignment = element.read<AssignmentCubit>();
      final display = element.read<DisplayManagementCubit>();
      final gate = Completer<void>();
      f.gates[('/layanan', 2)] = gate;
      tester.widget<AdminDashboard>(find.byType(AdminDashboard)).onRefresh!();
      await tester.pump();
      await tester.runAsync(f.api.clearSession);
      gate.complete();
      await tester.pumpAndSettle();
      for (final c in [poly, doctor, room, practice, staff, assignment]) {
        expect(c.state.load, CatalogLoadStatus.sessionEnded);
        expect(c.state.snapshot.collections, isEmpty);
      }
      expect(display.state.snapshot.collections, isEmpty);
      expect(find.text('TV a'), findsNothing);
      expect(
        tester.widget<AdminDashboard>(find.byType(AdminDashboard)).catalog,
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
}
