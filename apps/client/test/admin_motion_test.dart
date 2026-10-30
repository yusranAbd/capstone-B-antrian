import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:queueb_client/src/admin.dart';
import 'package:queueb_client/src/admin_data.dart';
import 'package:queueb_client/src/admin_ui.dart';
import 'package:queueb_client/src/features/admin/application/admin_catalog_cubit.dart';
import 'package:timezone/data/latest.dart' as tz;

import 'admin_action_helpers.dart';
import 'admin_catalog_cubit_test.dart' show CatalogFixture;
import 'routing_portals_test.dart' show Owners;

void main() {
  setUpAll(tz.initializeTimeZones);
  late CatalogFixture f;
  late Owners owners;
  late BlocObserver previous;
  setUp(() {
    f = CatalogFixture();
    f.data['/layanan']!.single.addAll({
      'prefixAntrean': 'A',
      'durasiDasarMenit': 15,
      'modeReservasi': 'HIBRIDA',
    });
    previous = Bloc.observer;
    owners = Owners();
    Bloc.observer = owners;
  });
  tearDown(() {
    f.dispose();
    Bloc.observer = previous;
  });
  Widget page() => MaterialApp(
    theme: AdminStyle.theme,
    home: Scaffold(body: AdminPage(api: f.api, initialSection: 0)),
  );
  Future<PolyclinicCubit> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() async {
      if (f.writeBarrier?.isCompleted == false) f.writeBarrier!.complete();
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    return tester.element(find.byType(AdminDataView)).read<PolyclinicCubit>();
  }

  final feedback = find.byKey(const ValueKey('admin-crud-feedback'));
  double opacity(WidgetTester tester) => tester
      .widget<FadeTransition>(
        find.descendant(of: feedback, matching: find.byType(FadeTransition)),
      )
      .opacity
      .value;
  Future<void> reachFeedback(WidgetTester tester) async {
    for (var frame = 0; frame < 20 && feedback.evaluate().isEmpty; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(feedback, findsOneWidget);
    await tester.pump(Duration.zero);
    await tester.pump();
  }

  testWidgets(
    'pending save, confirmed repeated save, rebuild and repository ownership',
    (tester) async {
      final cubit = await open(tester);
      final repository = cubit.repository, count = owners.created.length;
      for (final name in ['First saved clinic', 'Second saved clinic']) {
        await adminAction(tester, 'Ubah');
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Nama'),
          name,
        );
        final barrier = f.writeBarrier = Completer<void>();
        await tester.tap(find.text('Simpan'));
        await tester.pump();
        // The second save retains existing feedback, but must not restart it.
        if (feedback.evaluate().isNotEmpty) expect(opacity(tester), 1);
        expect(find.byType(AlertDialog), findsOneWidget);
        barrier.complete();
        f.writeBarrier = null;
        await reachFeedback(tester);
        expect(opacity(tester), lessThan(1));
        await tester.pump(const Duration(milliseconds: 240));
        await tester.pumpAndSettle();
        expect(opacity(tester), 1);
        expect(cubit.rows.single['nama'], name);
        final reads = f.requests.length;
        await tester.pumpWidget(page());
        await tester.pump();
        expect(opacity(tester), 1);
        expect(f.requests.length, reads);
        expect(
          tester.element(find.byType(AdminDataView)).read<PolyclinicCubit>(),
          same(cubit),
        );
        expect(cubit.repository, same(repository));
        expect(owners.created.length, count);
      }
      expect(f.requests.where((r) => r.method == 'PATCH'), hasLength(2));
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(cubit.isClosed, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
  for (final operation in ['create', 'deactivate', 'delete']) {
    testWidgets(
      '$operation keeps the existing confirmation and animates verified feedback',
      (tester) async {
        await open(tester);
        if (operation == 'create') {
          await tester.tap(find.text('Tambah'));
          await tester.pumpAndSettle();
          for (final field in [
            ('Kode', 'NEW'),
            ('Nama', 'New Clinic'),
            ('Prefix antrean', 'NC'),
          ]) {
            await tester.enterText(
              find.widgetWithText(TextFormField, field.$1),
              field.$2,
            );
          }
          await tester.tap(find.text('Simpan'));
        } else if (operation == 'deactivate') {
          await adminAction(tester, 'Nonaktifkan');
          expect(f.requests.where((r) => r.method == 'DELETE'), isEmpty);
          await tester.tap(find.text('Lanjutkan'));
        } else {
          await adminAction(tester, 'Hapus');
          expect(f.requests.where((r) => r.method == 'DELETE'), isEmpty);
          await tester.enterText(
            find.widgetWithText(TextField, 'Konfirmasi kode/nama'),
            'ONE',
          );
          await tester.pump();
          await tester.tap(find.text('Hapus Permanen'));
        }
        await reachFeedback(tester);
        await tester.pumpAndSettle();
        expect(opacity(tester), 1);
        expect(
          f.requests.where(
            (r) => ['POST', 'PATCH', 'DELETE'].contains(r.method),
          ),
          hasLength(1),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final failure in [409, 0]) {
    testWidgets(
      'failed/uncertain save $failure stays in the editor without success motion',
      (tester) async {
        await open(tester);
        f.failWrite = failure;
        await adminAction(tester, 'Ubah');
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Nama'),
          'Rejected Clinic',
        );
        await tester.tap(find.text('Simpan'));
        await tester.pumpAndSettle();
        expect(feedback, findsNothing);
        expect(find.byType(Animate), findsNothing);
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(f.requests.where((r) => r.method == 'PATCH'), hasLength(1));
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('logout during modal pending write discards late presentation', (
    tester,
  ) async {
    await open(tester);
    await adminAction(tester, 'Ubah');
    final barrier = f.writeBarrier = Completer<void>();
    await tester.tap(find.text('Simpan'));
    await tester.pump();
    await tester.runAsync(f.api.clearSession);
    barrier.complete();
    f.writeBarrier = null;
    await tester.pumpAndSettle();
    expect(feedback, findsNothing);
    expect(find.byType(Animate), findsNothing);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
}
