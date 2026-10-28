import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:queueb_client/src/admin.dart';
import 'package:queueb_client/src/admin_data.dart';
import 'package:queueb_client/src/admin_dashboard.dart';
import 'package:queueb_client/src/admin_practice_form.dart';
import 'package:queueb_client/src/admin_schedules.dart';
import 'package:queueb_client/src/admin_ui.dart';
import 'package:queueb_client/src/features/admin/application/practice_schedule_cubit.dart';
import 'package:queueb_client/src/features/admin/application/slot_session_cubit.dart';
import 'package:queueb_client/src/features/admin/application/admin_catalog_state.dart';

import 'admin_action_helpers.dart';
import 'admin_practice_form_test.dart' as practice show catalog, session;
import 'admin_schedule_cubit_test.dart' show SchedulingFixture;

void main() {
  setUpAll(tz.initializeTimeZones);
  late SchedulingFixture f;
  setUp(() {
    f = SchedulingFixture();
    f.data.addAll(practice.catalog);
    f.data['/jadwal-praktik'] = [practice.session()];
  });
  tearDown(() => f.dispose());

  Future<void> open(WidgetTester tester, int section) async {
    tester.view.physicalSize = const Size(1440, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AdminStyle.theme,
        locale: const Locale('id'),
        supportedLocales: const [Locale('id'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(
          body: AdminPage(api: f.api, initialSection: section),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> navigate(WidgetTester tester, String title) async {
    await tester.tap(find.widgetWithText(ListTile, title));
    await tester.pumpAndSettle();
  }

  Future<void> chooseClinic(WidgetTester tester, String name) async {
    await tester.tap(
      find.descendant(
        of: find.byType(BulkScheduleEditor),
        matching: find.byType(DropdownButtonFormField<String>),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining(name).last);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'partial batch stays partial in dialog and updates canonical list on close',
    (tester) async {
      f.dayFailures['SELASA'] = 400;
      await open(tester, 3);
      final c = tester
          .element(find.byType(GroupedClinicSchedules))
          .read<ServiceScheduleCubit>();
      await tester.tap(find.text('Tambah'));
      await tester.pumpAndSettle();
      await chooseClinic(tester, 'Penyakit Dalam');
      await tester.tap(find.text('Simpan Jadwal Terpilih'));
      await tester.pumpAndSettle();
      expect(
        find.text('4 berhasil · 0 dilewati · 1 gagal/belum terverifikasi'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Schedule conflict or linked slots'),
        findsWidgets,
      );
      expect(find.text('Simpan Jadwal Terpilih'), findsNothing);
      expect(c.rows, hasLength(4));
      await tester.tap(find.text('Tutup & muat ulang'));
      await tester.pumpAndSettle();
      expect(f.posts, hasLength(5));
      expect(c.rows, hasLength(4));
      expect(f.calls.any((r) => r.url.path.endsWith('/slot-praktik')), isFalse);
      await tester.pumpWidget(const SizedBox());
      expect(c.isClosed, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('polyclinic refresh updates choices while batch dialog is open', (
    tester,
  ) async {
    await open(tester, 3);
    final c = tester
        .element(find.byType(GroupedClinicSchedules))
        .read<ServiceScheduleCubit>();
    await tester.tap(find.text('Tambah'));
    await tester.pumpAndSettle();
    f.data['/layanan'] = [
      {...f.data['/layanan']!.first, 'nama': 'Nama Poli Terbaru'},
    ];
    await tester.runAsync(() => c.repository.refresh(['/layanan']));
    await tester.pumpAndSettle();
    await chooseClinic(tester, 'Nama Poli Terbaru');
    expect(find.textContaining('Nama Poli Terbaru'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  for (final reject in [false, true]) {
    testWidgets(
      'practice form uses Cubit and ${reject ? 'retains backend conflict' : 'reconciles agenda without duplicate fetch'}',
      (tester) async {
        await open(tester, 4);
        final c = tester
            .element(find.byType(AdminDataView))
            .read<PracticeScheduleCubit>();
        expect(find.text('Dari tanggal'), findsNothing);
        expect(find.text('Sampai tanggal'), findsNothing);
        await adminAction(tester, 'Ubah');
        await tester.tap(find.byType(SwitchListTile));
        f.writeFailure = reject ? 409 : null;
        await tester.tap(find.text('Simpan Jadwal'));
        await tester.pumpAndSettle();
        final writes = f.calls.where((r) => r.method == 'PATCH');
        expect(writes, hasLength(1));
        expect(jsonDecode(writes.single.body), {'aktif': false});
        expect(
          c.state.mutation,
          reject
              ? CatalogMutationStatus.failure
              : CatalogMutationStatus.success,
        );
        expect(c.rows.single['aktif'], reject);
        if (reject) {
          expect(find.byType(PracticeScheduleEditor), findsOneWidget);
          expect(
            find.textContaining('Schedule conflict or linked slots'),
            findsWidgets,
          );
          expect(find.text('Data disimpan.'), findsNothing);
          await tester.tap(find.text('Batal'));
          await tester.pumpAndSettle();
        } else {
          expect(find.byType(PracticeScheduleEditor), findsNothing);
          expect(
            f.calls.where(
              (r) =>
                  r.method == 'GET' && r.url.path.endsWith('/jadwal-praktik'),
            ),
            hasLength(2),
          );
          await navigate(tester, 'Dashboard');
          final dashboard = tester.widget<AdminDashboard>(
            find.byType(AdminDashboard),
          );
          expect(
            dashboard.catalog['/jadwal-praktik']!.single['aktif'],
            isFalse,
          );
        }
        await tester.pumpWidget(const SizedBox());
        expect(c.isClosed, isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('service edit choices use current shared clinic references', (
    tester,
  ) async {
    f.data['/jadwal-layanan'] = [
      {
        'id': 'hours',
        'layananId': 'clinic-pd',
        'hari': 'SENIN',
        'layanan': f.data['/layanan']!.first,
        'aktif': true,
        'jamBuka': '08:00',
        'jamTutup': '16:00',
        'kapasitasHarian': 24,
      },
    ];
    await open(tester, 3);
    final c = tester
        .element(find.byType(GroupedClinicSchedules))
        .read<ServiceScheduleCubit>();
    await tester.tap(find.text('Penyakit Dalam').last);
    await tester.pumpAndSettle();
    await adminAction(tester, 'Ubah');
    f.data['/layanan'] = [
      {...f.data['/layanan']!.first, 'nama': 'Nama Poli Edit'},
    ];
    await tester.runAsync(() => c.repository.refresh(['/layanan']));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.textContaining('Nama Poli Edit'),
      ),
      findsWidgets,
    );
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('doctor refresh updates practice form references while open', (
    tester,
  ) async {
    await open(tester, 4);
    final c = tester
        .element(find.byType(AdminDataView))
        .read<PracticeScheduleCubit>();
    await tester.tap(find.text('Tambah'));
    await tester.pumpAndSettle();
    final old = f.data['/dokter']!.first;
    f.data['/dokter'] = [
      {...old, 'nama': 'dr. Nama Terbaru'},
    ];
    await tester.runAsync(() => c.repository.refresh(['/dokter']));
    await tester.pumpAndSettle();
    final field = find.descendant(
      of: find.byKey(const ValueKey('practice-doctor')),
      matching: find.byType(TextField),
    );
    await tester.tap(field);
    await tester.enterText(field, 'Nama Terbaru');
    await tester.pumpAndSettle();
    expect(find.textContaining('dr. Nama Terbaru'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'legacy slots remain lazy and expanded data refreshes on scheduling revision',
    (tester) async {
      await open(tester, 4);
      final c = tester
          .element(find.byType(AdminDataView))
          .read<PracticeScheduleCubit>();
      await navigate(tester, 'Slot konsultasi');
      expect(f.calls.any((r) => r.url.path.endsWith('/slot-praktik')), isFalse);
      await tester.tap(find.text('Penyakit Dalam').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('dr. Indah Suci Permatasari').last);
      await tester.pumpAndSettle();
      final tile = find.descendant(
        of: find.byType(AdminSlotSession),
        matching: find.byType(ExpansionTile),
      );
      await tester.tap(tile.first);
      await tester.pumpAndSettle();
      final reads = f.calls.where((r) => r.url.path.endsWith('/slot-praktik'));
      expect(reads, hasLength(1));
      expect(reads.single.url.queryParameters, {
        'jadwalPraktikId': 'practice-1',
      });
      final slots = tester.element(tile.first).read<SlotSessionCubit>();
      await tester.runAsync(() async {
        await c.save({'aktif': false}, id: 'practice-1');
        await slots.settled;
      });
      await tester.pumpAndSettle();
      expect(
        f.calls.where((r) => r.url.path.endsWith('/slot-praktik')),
        hasLength(2),
      );
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
}
