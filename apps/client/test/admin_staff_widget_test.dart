import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:queueb_client/src/admin.dart';
import 'package:queueb_client/src/admin_data.dart';
import 'package:queueb_client/src/admin_staff.dart';
import 'package:queueb_client/src/admin_ui.dart';
import 'package:queueb_client/src/features/admin/application/admin_catalog_state.dart';
import 'package:queueb_client/src/features/admin/application/staff_management_cubit.dart';
import 'package:timezone/data/latest.dart' as tz;

import 'admin_action_helpers.dart';
import 'admin_staff_cubit_test.dart'
    show StaffFixture, existingStaffId, createdStaffId, fakePassword;

void main() {
  setUpAll(tz.initializeTimeZones);
  late StaffFixture f;
  setUp(() => f = StaffFixture());
  tearDown(() => f.dispose());
  Future<void> open(WidgetTester tester, {bool settle = true}) async {
    tester.view.physicalSize = const Size(1440, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AdminStyle.theme,
        home: Scaffold(body: AdminPage(api: f.api, initialSection: 6)),
      ),
    );
    if (settle) await tester.pumpAndSettle();
  }

  StaffAccountCubit accountScope(WidgetTester tester) =>
      tester.element(find.byType(AdminStaffAccounts)).read<StaffAccountCubit>();
  AssignmentCubit assignmentScope(WidgetTester tester) =>
      tester.element(find.byType(AdminDataView)).read<AssignmentCubit>();
  Future<void> startAccount(WidgetTester tester) async {
    await tester.tap(find.text('Tambah akun PETUGAS'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nama petugas'),
      'Petugas Baru',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email login'),
      'baru@example.test',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Kata sandi awal'),
      fakePassword,
    );
  }

  Future<void> submitAccount(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Buat akun PETUGAS'));
    await tester.pumpAndSettle();
  }

  Future<void> assignmentsTab(WidgetTester tester) async {
    await tester.tap(find.text('Penugasan Loket'));
    await tester.pumpAndSettle();
  }

  Future<void> fillAssignment(
    WidgetTester tester, {
    String email = 'baru@example.test',
    String name = 'Petugas Baru',
  }) async {
    await tester.tap(find.text('Tambah'));
    await tester.pumpAndSettle();
    final search = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(AdminSearchChoice),
    );
    final input = find.descendant(of: search, matching: find.byType(TextField));
    await tester.tap(input);
    await tester.enterText(input, email);
    await tester.pumpAndSettle();
    await tester.tap(find.text('$name · $email').last);
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(DropdownButtonFormField<String>, 'Ruang / loket'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Ruang Awal').last);
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(TextFormField, 'Tanggal mulai (YYYY-MM-DD)'),
    );
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'one shared owner loads account and assignment tabs without duplicate fetch',
    (tester) async {
      await open(tester);
      final accounts = accountScope(tester);
      expect(find.text('Petugas Lama'), findsOneWidget);
      expect(f.reads['/akun-petugas'], 1);
      expect(f.reads['/penugasan-petugas'], 1);
      await assignmentsTab(tester);
      final assignments = assignmentScope(tester);
      expect(assignments.repository, same(accounts.repository));
      expect(assignments.rows.single['petugasId'], existingStaffId);
      expect(f.reads['/akun-petugas'], 1);
      expect(f.reads['/penugasan-petugas'], 1);
      await tester.pumpWidget(const SizedBox());
      expect(accounts.isClosed, isTrue);
      expect(assignments.isClosed, isTrue);
    },
  );
  testWidgets(
    'initial loading/error/empty distinguish verified empty from failed fetch',
    (tester) async {
      final gate = Completer<void>();
      f.gates[('/akun-petugas', 1)] = gate;
      f.readError = 503;
      await open(tester, settle: false);
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsWidgets);
      gate.complete();
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Layanan sedang mengalami gangguan'),
        findsWidgets,
      );
      expect(find.textContaining('Belum ada akun yang sesuai'), findsNothing);
      f.readError = null;
      f.data['/akun-petugas'] = [];
      await tester.tap(find.text('Muat ulang'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Belum ada akun yang sesuai'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'account form double submit guarded and successful account is assignable by actual backend ID',
    (tester) async {
      await open(tester);
      final accounts = accountScope(tester);
      await startAccount(tester);
      final gate = Completer<void>();
      f.writeGate = gate;
      await tester.tap(find.widgetWithText(FilledButton, 'Buat akun PETUGAS'));
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Menyimpan…'),
            )
            .onPressed,
        isNull,
      );
      expect(f.calls.where((r) => r.method == 'POST'), hasLength(1));
      gate.complete();
      await tester.pumpAndSettle();
      expect(accounts.rows.any((a) => a['id'] == createdStaffId), isTrue);
      expect(f.reads['/akun-petugas'], 2);
      await assignmentsTab(tester);
      await fillAssignment(tester);
      await tester.tap(find.text('Simpan'));
      await tester.pumpAndSettle();
      final sent = jsonDecode(
        f.calls
            .singleWhere(
              (r) =>
                  r.method == 'POST' &&
                  r.url.path.endsWith('/penugasan-petugas'),
            )
            .body,
      );
      expect(sent['petugasId'], createdStaffId);
      expect(sent['loketId'], 'room');
      expect(sent['tanggalMulai'], f.api.config.today);
      expect(sent['tanggalSelesai'], isNull);
      expect(find.text('Data disimpan.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'account backend rejection keeps form, clears credential and never starts assignment',
    (tester) async {
      await open(tester);
      final accounts = accountScope(tester);
      await startAccount(tester);
      f.failures['/akun-petugas'] = 400;
      f.errorMessage = 'kataSandi=$fakePassword accessToken=fixture-token';
      await submitAccount(tester);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(
              find.widgetWithText(TextFormField, 'Kata sandi awal'),
            )
            .controller!
            .text,
        isEmpty,
      );
      expect(
        tester
            .widget<TextFormField>(
              find.widgetWithText(TextFormField, 'Nama petugas'),
            )
            .controller!
            .text,
        'Petugas Baru',
      );
      expect('${accounts.state.error}'.contains(fakePassword), isFalse);
      expect(find.textContaining(fakePassword), findsNothing);
      expect(find.textContaining('fixture-token'), findsNothing);
      expect(
        f.calls.where(
          (r) =>
              r.method == 'POST' && r.url.path.endsWith('/penugasan-petugas'),
        ),
        isEmpty,
      );
      expect(
        find.text(
          'Akun PETUGAS dibuat. Akun langsung tersedia di Penugasan Loket.',
        ),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'lost account response verifies existing server account without false creation claim or replay',
    (tester) async {
      await open(tester);
      final accounts = accountScope(tester);
      await startAccount(tester);
      f.failures['/akun-petugas'] = 0;
      f.commitUnknown = true;
      await submitAccount(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(accounts.state.recoveredMutation, isTrue);
      expect(
        find.text(
          'Akun PETUGAS terverifikasi di daftar. Akun tersedia di Penugasan Loket.',
        ),
        findsOneWidget,
      );
      expect(f.calls.where((r) => r.method == 'POST'), hasLength(1));
      expect(accounts.rows.last['id'], createdStaffId);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'partial provisioning preserves account and retries only rejected assignment',
    (tester) async {
      await open(tester);
      final accounts = accountScope(tester);
      await startAccount(tester);
      await submitAccount(tester);
      await assignmentsTab(tester);
      final assignments = assignmentScope(tester);
      await fillAssignment(tester);
      f.failures['/penugasan-petugas'] = 409;
      await tester.tap(find.text('Simpan'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(assignments.state.mutation, CatalogMutationStatus.failure);
      expect(accounts.rows.any((a) => a['id'] == createdStaffId), isTrue);
      expect(find.text('Data disimpan.'), findsNothing);
      f.failures.clear();
      await tester.tap(find.text('Simpan'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(assignments.rows.last['petugasId'], createdStaffId);
      expect(
        f.calls.where(
          (r) => r.method == 'POST' && r.url.path.endsWith('/akun-petugas'),
        ),
        hasLength(1),
      );
      expect(
        f.calls.where(
          (r) =>
              r.method == 'POST' && r.url.path.endsWith('/penugasan-petugas'),
        ),
        hasLength(2),
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'status confirmation preserves search and updates assignment account projection',
    (tester) async {
      await open(tester);
      final accounts = accountScope(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'Cari nama atau email petugas'),
        'lama@example',
      );
      await tester.pumpAndSettle();
      await adminAction(tester, 'Nonaktifkan akun');
      await tester.tap(find.text('Kembali'));
      await tester.pumpAndSettle();
      expect(f.calls.where((r) => r.method == 'PATCH'), isEmpty);
      await adminAction(tester, 'Nonaktifkan akun');
      await tester.tap(find.text('Lanjutkan'));
      await tester.pumpAndSettle();
      expect(accounts.rows.single['aktif'], isFalse);
      expect(
        f.calls.singleWhere((r) => r.method == 'PATCH').url.path,
        '/api/v1/akun-petugas/$existingStaffId',
      );
      await assignmentsTab(tester);
      expect(assignmentScope(tester).rows.single['petugas']['aktif'], isFalse);
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final reject in [false, true]) {
    testWidgets(
      'assignment permanent delete ${reject ? 'retains relation conflict' : 'reconciles after confirmation'}',
      (tester) async {
        await open(tester);
        await assignmentsTab(tester);
        final assignments = assignmentScope(tester);
        await adminAction(tester, 'Hapus');
        expect(find.text('Hapus Data?'), findsOneWidget);
        expect(f.calls.where((r) => r.method == 'DELETE'), isEmpty);
        if (reject) f.failures['/penugasan-petugas'] = 409;
        await tester.tap(find.text('Hapus Permanen'));
        await tester.pumpAndSettle();
        expect(
          f.calls.singleWhere((r) => r.method == 'DELETE').url.path,
          '/api/v1/penugasan-petugas/assignment-one/permanen',
        );
        expect(assignments.rows, hasLength(reject ? 1 : 0));
        expect(
          find.text('Hapus Data?'),
          reject ? findsOneWidget : findsNothing,
        );
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets(
    'room reference refresh updates open assignment form and retains room ID',
    (tester) async {
      await open(tester);
      await assignmentsTab(tester);
      final assignments = assignmentScope(tester);
      await tester.tap(find.text('Tambah'));
      await tester.pumpAndSettle();
      f.data['/loket']!.single['nama'] = 'Ruang Terbaru';
      await tester.runAsync(() => assignments.repository.refresh(['/loket']));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(DropdownButtonFormField<String>, 'Ruang / loket'),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Ruang Terbaru'), findsWidgets);
      await tester.tap(find.textContaining('Ruang Terbaru').last);
      await tester.pumpAndSettle();
      final value = tester.widget<DropdownButtonFormField<String>>(
        find.widgetWithText(DropdownButtonFormField<String>, 'Ruang / loket'),
      );
      expect(value.initialValue, 'room');
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'assignment edit preserves assignment identity and backend role rejection is shown',
    (tester) async {
      await open(tester);
      await assignmentsTab(tester);
      final assignments = assignmentScope(tester);
      await adminAction(tester, 'Ubah');
      await tester.tap(find.byType(SwitchListTile));
      f.failures['/penugasan-petugas'] = 400;
      await tester.tap(find.text('Simpan'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.textContaining('Role petugas, ruang atau periode ditolak backend'),
        findsWidgets,
      );
      expect(
        f.calls.singleWhere((r) => r.method == 'PATCH').url.path,
        '/api/v1/penugasan-petugas/assignment-one',
      );
      expect(assignments.rows.single['aktif'], isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'confirmed create with failed reload preserves success but requires verification before assignment',
    (tester) async {
      await open(tester);
      final accounts = accountScope(tester);
      await startAccount(tester);
      f.afterWrite = () => f.readError = 503;
      await submitAccount(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(accounts.state.mutation, CatalogMutationStatus.success);
      expect(accounts.state.needsReconciliation, isTrue);
      expect(
        find.text(
          'Akun PETUGAS disimpan. Muat ulang daftar sebelum membuat penugasan.',
        ),
        findsOneWidget,
      );
      f.afterWrite = null;
      f.readError = null;
      await tester.tap(find.text('Muat ulang'));
      await tester.pumpAndSettle();
      expect(accounts.rows.any((a) => a['id'] == createdStaffId), isTrue);
      expect(accounts.state.needsReconciliation, isFalse);
      expect(f.calls.where((r) => r.method == 'POST'), hasLength(1));
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'logout while directory read is pending clears both feature states',
    (tester) async {
      final gate = Completer<void>();
      f.gates[('/akun-petugas', 1)] = gate;
      await open(tester, settle: false);
      final accounts = accountScope(tester);
      final assignments = tester
          .element(find.byType(AdminStaffAccounts))
          .read<AssignmentCubit>();
      await tester.runAsync(f.api.clearSession);
      gate.complete();
      await tester.pumpAndSettle();
      expect(accounts.state.snapshot.collections, isEmpty);
      expect(assignments.state.snapshot.collections, isEmpty);
      expect(accounts.state.load, CatalogLoadStatus.sessionEnded);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
