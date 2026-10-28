import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:queueb_client/src/admin.dart';
import 'package:queueb_client/src/admin_data.dart';
import 'package:queueb_client/src/admin_dashboard.dart';
import 'package:queueb_client/src/admin_ui.dart';
import 'package:queueb_client/src/features/admin/application/admin_catalog_cubit.dart';
import 'package:queueb_client/src/features/admin/application/admin_catalog_state.dart';

import 'admin_action_helpers.dart';
import 'admin_catalog_cubit_test.dart' show CatalogFixture;

void main() {
  setUpAll(tz.initializeTimeZones);
  late CatalogFixture f;
  setUp(() {
    f = CatalogFixture();
    f.data['/layanan']!.single.addAll({
      'prefixAntrean': 'A',
      'durasiDasarMenit': 15,
      'modeReservasi': 'HIBRIDA',
    });
  });
  tearDown(() => f.dispose());
  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AdminStyle.theme,
        home: Scaffold(body: AdminPage(api: f.api, initialSection: 0)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'master edit updates shared references and dashboard without duplicate master fetch',
    (tester) async {
      await open(tester);
      final clinic = tester
          .element(find.byType(AdminDataView))
          .read<PolyclinicCubit>();
      await adminAction(tester, 'Ubah');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nama'),
        'Renamed Clinic',
      );
      await tester.tap(find.text('Simpan'));
      await tester.pumpAndSettle();
      expect(clinic.rows.single['nama'], 'Renamed Clinic');
      expect(find.text('Data disimpan.'), findsOneWidget);
      expect(f.requests.where((r) => r.method == 'PATCH').length, 1);
      expect(
        f.requests
            .where((r) => r.method == 'GET' && r.url.path.endsWith('/layanan'))
            .length,
        2,
      );
      await tester.tap(find.widgetWithText(ListTile, 'Ruang & loket'));
      await tester.pumpAndSettle();
      final room = tester.element(find.byType(AdminDataView)).read<RoomCubit>();
      expect(room.repository, same(clinic.repository));
      await tester.tap(find.text('Tambah'));
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(DropdownButtonFormField<String>),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Renamed Clinic'), findsWidgets);
      await tester.tap(find.textContaining('Renamed Clinic').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kembali'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Dashboard'));
      await tester.pumpAndSettle();
      final dashboard = tester.widget<AdminDashboard>(
        find.byType(AdminDashboard),
      );
      expect(dashboard.catalog['/layanan']!.single['nama'], 'Renamed Clinic');
      expect(
        dashboard.catalog['/jadwal-praktik']!.single['layanan']['nama'],
        'Renamed Clinic',
      );
      await tester.pumpWidget(const SizedBox());
      expect(clinic.isClosed, isTrue);
      expect(room.isClosed, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'delete confirmation and backend relation rejection preserve filtered row',
    (tester) async {
      await open(tester);
      final clinic = tester
          .element(find.byType(AdminDataView))
          .read<PolyclinicCubit>();
      await tester.enterText(
        find.widgetWithText(TextField, 'Cari nama atau kode'),
        'Before',
      );
      await tester.pumpAndSettle();
      await adminAction(tester, 'Hapus');
      expect(f.requests.where((r) => r.method == 'DELETE'), isEmpty);
      await tester.enterText(
        find.widgetWithText(TextField, 'Konfirmasi kode/nama'),
        'ONE',
      );
      await tester.pumpAndSettle();
      f.failWrite = 409;
      await tester.tap(find.text('Hapus Permanen'));
      await tester.pumpAndSettle();
      expect(find.text('Hapus Data?'), findsOneWidget);
      expect(find.text('Relation conflict'), findsWidgets);
      expect(clinic.state.mutation, CatalogMutationStatus.failure);
      expect(clinic.rows.single['nama'], 'Before');
      await tester.tap(find.text('Batal'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'Before'), findsOneWidget);
      expect(f.requests.where((r) => r.method == 'DELETE').length, 1);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'empty catalog and reload error retain feature ownership across navigation',
    (tester) async {
      f.data['/layanan'] = [];
      await open(tester);
      final clinic = tester
          .element(find.byType(AdminDataView))
          .read<PolyclinicCubit>();
      expect(clinic.rows, isEmpty);
      expect(clinic.state.load, CatalogLoadStatus.loaded);
      f.failRead = 503;
      await tester.tap(find.text('Muat ulang'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Layanan sedang mengalami gangguan'),
        findsWidgets,
      );
      expect(clinic.state.load, CatalogLoadStatus.failure);
      f.failRead = null;
      await tester.tap(find.widgetWithText(ListTile, 'Dokter'));
      await tester.pumpAndSettle();
      final doctor = tester
          .element(find.byType(AdminDataView))
          .read<DoctorCatalogCubit>();
      expect(doctor.repository, same(clinic.repository));
      expect(doctor.rows.single['nama'], 'Before');
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
}
