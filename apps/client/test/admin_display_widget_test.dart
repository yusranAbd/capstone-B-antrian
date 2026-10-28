import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:queueb_client/src/admin.dart';
import 'package:queueb_client/src/admin_display.dart';
import 'package:queueb_client/src/admin_ui.dart';
import 'package:queueb_client/src/features/admin/application/display_management_cubit.dart';
import 'package:queueb_client/src/features/admin/models/admin_display_models.dart';
import 'package:timezone/data/latest.dart' as tz;

import 'admin_action_helpers.dart';
import 'admin_display_cubit_test.dart'
    show DisplayFixture, fixtureActivationCode, stateText;

void main() {
  setUpAll(tz.initializeTimeZones);
  late DisplayFixture f;
  setUp(() => f = DisplayFixture());
  tearDown(() => f.dispose());
  Future<void> open(WidgetTester tester, {bool settle = true}) async {
    tester.view.physicalSize = const Size(1440, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AdminStyle.theme,
        home: Scaffold(body: AdminPage(api: f.api, initialSection: 7)),
      ),
    );
    if (settle) await tester.pumpAndSettle();
  }

  DisplayManagementCubit scope(WidgetTester tester) => tester
      .element(find.byType(AdminDisplayPage))
      .read<DisplayManagementCubit>();
  Future<void> rotate(WidgetTester tester) async {
    await adminAction(tester, 'Kode aktivasi / rotasi');
    await tester.tap(find.text('Lanjutkan'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets(
    'one shared list, compact search and rebuild do not fetch twice or imply online status',
    (tester) async {
      await open(tester);
      final c = scope(tester);
      expect(f.reads, {adminDisplayPath: 1, '/layanan': 1});
      expect(find.text('TV a'), findsOneWidget);
      expect(find.text('TV b'), findsOneWidget);
      expect(
        find.text(
          'Status aktif adalah izin perangkat, bukan indikator online.',
        ),
        findsOneWidget,
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Cari perangkat atau poliklinik'),
        'TV a',
      );
      await tester.pumpAndSettle();
      expect(find.text('TV b'), findsNothing);
      await tester.tap(find.byTooltip('Ciutkan sidebar'));
      await tester.pumpAndSettle();
      expect(f.reads[adminDisplayPath], 1);
      expect(stateText(c.state).contains(fixtureActivationCode), isFalse);
      await tester.pumpWidget(const SizedBox());
      expect(c.isClosed, isTrue);
    },
  );
  testWidgets(
    'loading and failed refresh do not claim an empty verified list',
    (tester) async {
      final gate = Completer<void>();
      f.gates[(adminDisplayPath, 1)] = gate;
      f.readError = 503;
      await open(tester, settle: false);
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsWidgets);
      gate.complete();
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Hasil tindakan perangkat belum dapat dipastikan'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Belum ada perangkat yang sesuai'),
        findsNothing,
      );
      f.readError = null;
      f.data[adminDisplayPath] = [];
      await tester.tap(find.text('Muat ulang'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Belum ada perangkat yang sesuai'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'create and edit preserve clinic binding and do not claim pairing success',
    (tester) async {
      await open(tester);
      final c = scope(tester);
      await tester.tap(find.text('Tambah perangkat'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nama perangkat'),
        'TV Baru',
      );
      final dropdown = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(DropdownButtonFormField<String>),
      );
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Poli Awal').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Simpan perangkat'));
      await tester.pumpAndSettle();
      final create = f.calls.singleWhere((r) => r.method == 'POST');
      expect(jsonDecode(create.body), {
        'nama': 'TV Baru',
        'layananId': 'clinic',
      });
      expect(c.devices, hasLength(3));
      expect(find.text('Kode aktivasi sekali pakai'), findsNothing);
      await adminAction(tester, 'Ubah');
      expect(
        find.widgetWithText(DropdownButtonFormField<String>, 'Poliklinik'),
        findsNothing,
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nama perangkat'),
        'TV Rename',
      );
      await tester.tap(find.text('Simpan perangkat'));
      await tester.pumpAndSettle();
      final patch = f.calls.singleWhere((r) => r.method == 'PATCH');
      expect(jsonDecode(patch.body), {'nama': 'TV Rename'});
      expect(patch.url.path, '/api/v1/perangkat-display/a');
      expect(c.devices.first['layananId'], 'clinic');
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'backend rejection leaves form and metadata intact with a safe error',
    (tester) async {
      await open(tester);
      await adminAction(tester, 'Ubah');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nama perangkat'),
        'Rejected',
      );
      f.failures['update'] = 409;
      await tester.tap(find.text('Simpan perangkat'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(scope(tester).devices.first['nama'], 'TV a');
      expect(find.textContaining(fixtureActivationCode), findsNothing);
      expect(find.textContaining('fixture-secret'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'clinic changes update create form choices from the shared catalog',
    (tester) async {
      await open(tester);
      final c = scope(tester);
      await tester.tap(find.text('Tambah perangkat'));
      await tester.pumpAndSettle();
      f.data['/layanan']!.first['nama'] = 'Poli Terbaru';
      await tester.runAsync(() => c.repository.catalog.refresh(['/layanan']));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(DropdownButtonFormField<String>),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Poli Terbaru'), findsWidgets);
      await tester.tap(find.text('Poli Terbaru').last);
      await tester.pumpAndSettle();
      f.data['/layanan']!.first['aktif'] = false;
      await tester.runAsync(() => c.repository.catalog.refresh(['/layanan']));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nama perangkat'),
        'TV baru',
      );
      await tester.tap(find.text('Simpan perangkat'));
      await tester.pumpAndSettle();
      expect(find.text('Pilih poliklinik aktif.'), findsOneWidget);
      expect(f.calls.where((r) => r.method == 'POST'), isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'one-time code is local to dialog and disappears after close without another fetch',
    (tester) async {
      await open(tester);
      final c = scope(tester);
      await rotate(tester);
      expect(find.text('Kode aktivasi sekali pakai'), findsOneWidget);
      expect(find.text(fixtureActivationCode), findsOneWidget);
      expect(stateText(c.state).contains(fixtureActivationCode), isFalse);
      expect(c.state.awaitingDisclosure, isTrue);
      await tester.tap(find.text('Selesai'));
      await tester.pumpAndSettle();
      expect(find.text(fixtureActivationCode), findsNothing);
      expect(c.state.awaitingDisclosure, isFalse);
      expect(f.reads[adminDisplayPath], 2);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
  for (final ending in ['expiry', 'logout', 'role']) {
    testWidgets(
      '$ending removes old activation information and cleans up its scope',
      (tester) async {
        f.activationLifetime = const Duration(seconds: 10);
        await open(tester);
        final c = scope(tester);
        await rotate(tester);
        expect(find.text(fixtureActivationCode), findsOneWidget);
        if (ending == 'expiry') {
          await tester.pump(const Duration(seconds: 11));
        } else if (ending == 'logout') {
          await tester.runAsync(f.api.clearSession);
        } else {
          f.identity = {'id': 'admin', 'peran': 'USER'};
          await tester.runAsync(f.api.reloadOwnProfile);
        }
        await tester.pumpAndSettle();
        expect(find.text(fixtureActivationCode), findsNothing);
        expect(c.state.awaitingDisclosure, isFalse);
        expect(
          f.calls.where((r) => r.url.path.endsWith('/aktivasi')),
          hasLength(1),
        );
        await tester.pumpWidget(const SizedBox());
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'lost rotation is not replayed and new rotation requires an explicit warning confirmation',
    (tester) async {
      await open(tester);
      final c = scope(tester);
      f.failures['activate'] = 0;
      f.commitUnknown = true;
      await rotate(tester);
      await tester.pumpAndSettle();
      expect(find.text('Kode aktivasi sekali pakai'), findsNothing);
      expect(c.state.uncertainActivations, {'a'});
      await tester.tap(find.text('Muat ulang'));
      await tester.pumpAndSettle();
      await adminAction(tester, 'Kode aktivasi / rotasi');
      expect(
        find.textContaining('Penerbitan ini adalah rotasi baru.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Kembali'));
      await tester.pumpAndSettle();
      expect(
        f.calls.where((r) => r.url.path.endsWith('/aktivasi')),
        hasLength(1),
      );
      f.failures.clear();
      await rotate(tester);
      expect(find.text(fixtureActivationCode), findsOneWidget);
      await tester.tap(find.text('Selesai'));
      await tester.pumpAndSettle();
      expect(
        f.calls.where((r) => r.url.path.endsWith('/aktivasi')),
        hasLength(2),
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('revocation is confirmed and targets A while B remains active', (
    tester,
  ) async {
    await open(tester);
    final c = scope(tester);
    await adminAction(tester, 'Nonaktifkan');
    await tester.tap(find.text('Kembali'));
    await tester.pumpAndSettle();
    expect(f.calls.where((r) => r.method == 'POST'), isEmpty);
    await adminAction(tester, 'Nonaktifkan');
    await tester.tap(find.text('Lanjutkan'));
    await tester.pumpAndSettle();
    expect(
      f.calls.singleWhere((r) => r.method == 'POST').url.path,
      '/api/v1/perangkat-display/a/nonaktifkan',
    );
    expect(c.devices.firstWhere((d) => d['id'] == 'a')['aktif'], isFalse);
    expect(c.devices.firstWhere((d) => d['id'] == 'b')['aktif'], isTrue);
    await tester.pumpWidget(const SizedBox());
  });
  for (final reject in [false, true]) {
    testWidgets(
      'permanent delete ${reject ? 'shows rejection without removing data' : 'waits for confirmation and reconciles'}',
      (tester) async {
        await open(tester);
        final c = scope(tester);
        await adminAction(tester, 'Hapus');
        expect(find.text('Hapus Data?'), findsOneWidget);
        expect(f.calls.where((r) => r.method == 'DELETE'), isEmpty);
        if (reject) f.failures['delete'] = 409;
        await tester.tap(find.text('Hapus Permanen'));
        await tester.pumpAndSettle();
        expect(
          f.calls.singleWhere((r) => r.method == 'DELETE').url.path,
          '/api/v1/perangkat-display/a/permanen',
        );
        expect(c.devices, hasLength(reject ? 2 : 1));
        expect(
          find.text('Hapus Data?'),
          reject ? findsOneWidget : findsNothing,
        );
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
