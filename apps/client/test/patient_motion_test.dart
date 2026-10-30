import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/testing.dart';
import 'package:queueb_client/src/api.dart';
import 'package:queueb_client/src/app.dart';
import 'package:queueb_client/src/config.dart';
import 'package:queueb_client/src/mobile_ui.dart';
import 'package:queueb_client/src/patient_motion.dart';
import 'package:queueb_client/src/patient_design.dart';
import 'package:queueb_client/src/features/patient/application/patient_booking_cubit.dart';
import 'package:timezone/data/latest.dart' as tz;

import 'patient_test_navigation.dart';
import 'patient_v2_test.dart' show PatientV2Backend;
import 'routing_portals_test.dart' show Owners;

const feedbackKey = ValueKey('motion-under-test');

void main() {
  setUpAll(tz.initializeTimeZones);

  test('minimum-opacity feedback retains WCAG text contrast', () {
    for (final canvas in [PatientDesign.paper, PatientDesign.background]) {
      final ink = Color.alphaBlend(
        PatientDesign.ink.withValues(
          alpha: PatientMicroEntrance.minimumOpacity,
        ),
        canvas,
      ).computeLuminance();
      final surface = Color.alphaBlend(
        PatientDesign.soft.withValues(
          alpha: PatientMicroEntrance.minimumOpacity,
        ),
        canvas,
      ).computeLuminance();
      expect((surface + 0.05) / (ink + 0.05), greaterThanOrEqualTo(4.5));
    }
  });

  for (final size in [
    const Size(320, 568),
    const Size(360, 800),
    const Size(390, 844),
    const Size(412, 915),
    const Size(1280, 720),
    const Size(1366, 768),
    const Size(1440, 900),
    const Size(1920, 1080),
  ]) {
    testWidgets('motion preserves input/focus and layout at $size, text 1.5', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      final input = TextEditingController();
      final focus = FocusNode();
      addTearDown(() {
        input.dispose();
        focus.dispose();
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final notice = PatientMotionOnce(), caption = PatientMotionOnce();
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
            child: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    PatientMicroEntrance(
                      once: notice,
                      child: const MobileNotice(
                        'Pendaftaran berhasil. Tiket UM-001 tersedia di Tiket Saya.',
                      ),
                    ),
                    PatientMicroEntrance(
                      once: caption,
                      child: const Text('Tanggal praktik'),
                    ),
                    TextField(controller: input, focusNode: focus),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(Duration.zero);
      focus.requestFocus();
      await tester.enterText(find.byType(TextField), 'Pilihan tetap');
      await tester.pump(const Duration(milliseconds: 100));
      expect(focus.hasFocus, isTrue);
      await tester.pump(const Duration(milliseconds: 200));
      expect(input.text, 'Pilihan tetap');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  Widget demo(
    PatientMotionOnce token, {
    bool reduced = false,
    bool active = true,
    bool visible = true,
    String text = 'Pendaftaran berhasil.',
  }) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduced),
      child: Scaffold(
        body: TickerMode(
          enabled: active,
          child: visible
              ? PatientMicroEntrance(
                  key: feedbackKey,
                  once: token,
                  child: Text(text),
                )
              : const SizedBox(),
        ),
      ),
    ),
  );

  double opacity(WidgetTester tester) => tester
      .widget<FadeTransition>(
        find.descendant(
          of: find.byKey(feedbackKey),
          matching: find.byType(FadeTransition),
        ),
      )
      .opacity
      .value;

  testWidgets('entrance is finite and same-event rebuild never restarts it', (
    tester,
  ) async {
    final token = PatientMotionOnce();
    await tester.pumpWidget(demo(token));
    // Flush the zero-delay timer, then establish the ticker's initial frame.
    await tester.pump(Duration.zero);
    await tester.pump();
    expect(opacity(tester), closeTo(0.88, 0.001));
    await tester.pump(const Duration(milliseconds: 100));
    expect(opacity(tester), greaterThan(0.88));
    await tester.pump(const Duration(milliseconds: 110));
    expect(opacity(tester), 1);
    await tester.pumpWidget(
      demo(token, text: 'Pendaftaran berhasil. Tiket siap.'),
    );
    expect(opacity(tester), 1);
    await tester.pump(const Duration(seconds: 2));
    expect(opacity(tester), 1);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('remounting a consumed event is immediately static', (
    tester,
  ) async {
    final token = PatientMotionOnce();
    await tester.pumpWidget(demo(token));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpWidget(demo(token, visible: false));
    await tester.pumpWidget(demo(token));
    expect(find.byType(Animate), findsNothing);
    expect(find.text('Pendaftaran berhasil.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion keeps semantics and never creates Animate', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final token = PatientMotionOnce();
    try {
      await tester.pumpWidget(demo(token, reduced: true));
      expect(find.byType(Animate), findsNothing);
      expect(find.bySemanticsLabel('Pendaftaran berhasil.'), findsOneWidget);
      await tester.pumpWidget(demo(token));
      expect(find.byType(Animate), findsNothing);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('offstage does not consume an event; leaving settles it', (
    tester,
  ) async {
    final token = PatientMotionOnce();
    await tester.pumpWidget(demo(token, active: false));
    expect(find.byType(Animate), findsNothing);
    await tester.pumpWidget(demo(token));
    expect(find.byType(Animate), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpWidget(demo(token, active: false));
    await tester.pumpWidget(demo(token));
    expect(find.byType(Animate), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final reduced in [false, true]) {
    testWidgets('actual notice keeps baseline semantics, reduced=$reduced', (
      tester,
    ) async {
      const text = 'Pendaftaran berhasil. Tiket tersedia di Tiket Saya.';
      final semantics = tester.ensureSemantics();
      final token = PatientMotionOnce();
      Widget page(bool animated) => MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduced),
          child: Scaffold(
            body: animated
                ? PatientMicroEntrance(
                    once: token,
                    child: const MobileNotice(text),
                  )
                : const MobileNotice(text),
          ),
        ),
      );
      List<(String, String, String)> noticeSemantics() {
        final result = <(String, String, String)>[];
        void visit(SemanticsNode node) {
          final data = node.getSemanticsData();
          if (data.label.contains(text) || data.value.contains(text)) {
            result.add((data.label, data.value, data.hint));
          }
          node.visitChildren((child) {
            visit(child);
            return true;
          });
        }

        visit(
          tester
              .binding
              .renderViews
              .single
              .owner!
              .semanticsOwner!
              .rootSemanticsNode!,
        );
        return result;
      }

      try {
        await tester.pumpWidget(page(false));
        final baseline = noticeSemantics();
        expect(baseline, isNotEmpty);
        await tester.pumpWidget(page(true));
        await tester.pump(Duration.zero);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(noticeSemantics(), baseline);
        await tester.pump(const Duration(milliseconds: 150));
        expect(noticeSemantics(), baseline);
        expect(find.byType(SelectableText), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    });
  }

  testWidgets('changing reduced motion during playback stops safely', (
    tester,
  ) async {
    final token = PatientMotionOnce();
    await tester.pumpWidget(demo(token));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpWidget(demo(token, reduced: true));
    expect(find.byType(Animate), findsNothing);
    await tester.pumpWidget(demo(token));
    expect(find.byType(Animate), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a distinct confirmed event may animate again without data keys',
    (tester) async {
      await tester.pumpWidget(demo(PatientMotionOnce()));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpWidget(demo(PatientMotionOnce()));
      expect(opacity(tester), closeTo(0.88, 0.001));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    },
  );

  Future<void> press(WidgetTester tester, Finder finder) async {
    if (finder.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        finder,
        160,
        scrollable: find.byType(Scrollable).first,
      );
    }
    await tester.ensureVisible(finder.last);
    await tester.pumpAndSettle();
    await tester.tap(finder.last);
    await tester.pumpAndSettle();
  }

  Future<(QueueApi, PatientV2Backend, Completer<void>, Owners)> pendingBooking(
    WidgetTester tester, {
    bool fail = false,
    bool timeout = false,
    bool reduced = false,
  }) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    final backend = PatientV2Backend()..walkOnly = true;
    final gate = Completer<void>();
    final owners = Owners(), previous = Bloc.observer;
    Bloc.observer = owners;
    final api =
        QueueApi(
            config: AppConfig(
              apiBaseUrl: 'http://localhost/api/v1',
              realtime: false,
            ),
            client: MockClient((request) async {
              if (request.method == 'POST' &&
                  request.url.path.endsWith('/reservasi')) {
                await gate.future;
                if (timeout) {
                  throw TimeoutException('Synthetic booking timeout');
                }
                if (fail) {
                  return backend.reply({'message': 'Reservasi ditolak'}, 409);
                }
              }
              return backend.handle(request);
            }),
          )
          ..accessToken = 'fixture-access'
          ..user = backend.user;
    addTearDown(() async {
      if (!gate.isCompleted) gate.complete();
      await tester.pumpWidget(const SizedBox());
      api.dispose();
      Bloc.observer = previous;
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(QueueBApp(api: api));
    if (reduced) {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
    }
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpAndSettle();
    await openPatientCatalog(tester, walkIn: true);
    await press(tester, find.byType(ClinicCard).first);
    await press(tester, find.widgetWithText(FilledButton, 'Reservasi walk-in'));
    await tester.tap(find.widgetWithText(FilledButton, 'Lanjutkan'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Pendaftaran berhasil.'), findsNothing);
    return (api, backend, gate, owners);
  }

  testWidgets(
    'confirmed booking alone animates; rebuild adds no POST or owner',
    (tester) async {
      final (api, backend, gate, owners) = await pendingBooking(tester);
      final count = owners.created.length;
      gate.complete();
      await tester.pumpAndSettle();
      final success = find.textContaining('Pendaftaran berhasil.');
      expect(success, findsOneWidget);
      expect(find.byType(Animate), findsOneWidget);
      final reads = backend.requests.length;
      api.notifyListeners();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(backend.requests.length, reads);
      expect(owners.created.length, count);
      expect(
        backend.requests.where((r) => r.$1 == 'POST' && r.$2 == '/reservasi'),
        hasLength(1),
      );
      await press(
        tester,
        find.widgetWithText(NavigationDestination, 'Reservasi'),
      );
      await press(
        tester,
        find.widgetWithText(NavigationDestination, 'Tiket Saya'),
      );
      expect(find.byType(Animate), findsNothing);
      expect(success, findsOneWidget);
    },
  );

  for (final timeout in [false, true]) {
    testWidgets('failed/uncertain booking never animates success: $timeout', (
      tester,
    ) async {
      final (_, _, gate, _) = await pendingBooking(
        tester,
        fail: !timeout,
        timeout: timeout,
      );
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.textContaining('Pendaftaran berhasil.'), findsNothing);
      expect(find.byType(Animate), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'reduced-motion real booking keeps feedback and navigation usable',
    (tester) async {
      final (_, backend, gate, _) = await pendingBooking(tester, reduced: true);
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.textContaining('Pendaftaran berhasil.'), findsOneWidget);
      expect(find.byType(Animate), findsNothing);
      expect(backend.tickets.single['status'], 'DIPESAN');
      await press(
        tester,
        find.widgetWithText(NavigationDestination, 'Beranda'),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'logout/disposal during success motion cannot leave controllers',
    (tester) async {
      final (api, _, gate, _) = await pendingBooking(tester);
      gate.complete();
      for (
        var frame = 0;
        frame < 15 && find.byType(Animate).evaluate().isEmpty;
        frame++
      ) {
        await tester.pump();
      }
      expect(find.byType(Animate), findsOneWidget);
      await api.logout();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byType(Animate), findsNothing);
      expect(find.widgetWithText(TextFormField, 'Email'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'tab change during success settles without replay or extra owner',
    (tester) async {
      final (_, backend, gate, owners) = await pendingBooking(tester);
      final count = owners.created.length;
      gate.complete();
      for (var i = 0; i < 15 && find.byType(Animate).evaluate().isEmpty; i++) {
        await tester.pump();
      }
      expect(find.byType(Animate), findsOneWidget);
      await tester.tap(find.widgetWithText(NavigationDestination, 'Reservasi'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await press(
        tester,
        find.widgetWithText(NavigationDestination, 'Tiket Saya'),
      );
      expect(find.byType(Animate), findsNothing);
      expect(find.textContaining('Pendaftaran berhasil.'), findsOneWidget);
      expect(owners.created.length, count);
      expect(
        backend.requests.where((r) => r.$1 == 'POST' && r.$2 == '/reservasi'),
        hasLength(1),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('session eviction while pending never animates a late result', (
    tester,
  ) async {
    final (api, _, gate, _) = await pendingBooking(tester);
    await api.logout();
    await tester.pump();
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.textContaining('Pendaftaran berhasil.'), findsNothing);
    expect(find.byType(Animate), findsNothing);
    expect(find.widgetWithText(TextFormField, 'Email'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('booking caption keeps draft and native Back guard/navigation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    final backend = PatientV2Backend();
    final api = QueueApi(
      config: AppConfig(apiBaseUrl: 'http://localhost/api/v1', realtime: false),
      client: MockClient(backend.handle),
    )..user = backend.user;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      api.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(QueueBApp(api: api));
    await tester.pumpAndSettle();
    await openPatientCatalog(tester);
    await press(tester, find.byType(ClinicCard).first);
    await press(tester, find.text('Lihat Detail Dokter'));
    await press(tester, find.text('Buat Janji Temu'));
    expect(find.text('Tanggal praktik'), findsOneWidget);
    expect(find.byType(Animate), findsOneWidget);
    final booking = tester
        .element(find.text('Tanggal praktik'))
        .read<PatientBookingCubit>();
    final draft = (
      booking.serviceId,
      booking.doctorId,
      booking.sessionId,
      booking.slotId,
      booking.state.values['date'],
    );
    final count = backend.requests.length;
    api.notifyListeners();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(backend.requests.length, count);
    expect((
      booking.serviceId,
      booking.doctorId,
      booking.sessionId,
      booking.slotId,
      booking.state.values['date'],
    ), draft);
    final router =
        tester.widget<MaterialApp>(find.byType(MaterialApp)).routerConfig!
            as GoRouter;
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(
      router.routeInformationProvider.value.uri.path,
      '/patient/reservations',
    );
    expect(backend.requests.where((r) => r.$1 == 'POST'), isEmpty);
    expect(tester.takeException(), isNull);
  });
}
