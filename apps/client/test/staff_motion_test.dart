import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:queueb_client/src/api.dart';
import 'package:queueb_client/src/features/staff/application/staff_queue_bloc.dart';
import 'package:queueb_client/src/features/staff/data/staff_queue_repository.dart';
import 'package:queueb_client/src/features/staff/models/staff_queue_models.dart';
import 'package:queueb_client/src/queue.dart';
import 'package:timezone/data/latest.dart' as tz;

import 'staff_bloc_fixture.dart';
import 'staff_command_bloc_test.dart' show initialStatuses, commandPath;
import 'routing_portals_test.dart' show Owners;

void main() {
  setUpAll(tz.initializeTimeZones);
  late StaffFixtureApi api;
  late StaffQueueRepository repository;
  late StaffQueueBloc bloc;
  late Owners owners;
  late BlocObserver previous;
  late List<StaffFakeFeed> feeds;
  setUp(() {
    api = StaffFixtureApi();
    feeds = [];
    previous = Bloc.observer;
    owners = Owners();
    Bloc.observer = owners;
    repository = StaffQueueRepository(
      api,
      feedFactory: (service, refresh, status) {
        final feed = StaffFakeFeed(refresh, status, () {});
        feeds.add(feed);
        return feed.dispose;
      },
    );
  });
  tearDown(() {
    repository.dispose();
    api.dispose();
    Bloc.observer = previous;
  });
  final feedback = find.byKey(const ValueKey('staff-command-feedback'));
  double opacity(WidgetTester tester) => tester
      .widget<FadeTransition>(
        find.descendant(of: feedback, matching: find.byType(FadeTransition)),
      )
      .opacity
      .value;
  Future<void> open(
    WidgetTester tester,
    StaffOperation operation, {
    bool reduced = false,
  }) async {
    api.status = initialStatuses[operation]!;
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduced),
          child: QueuePage(api: api, repository: repository),
        ),
      ),
    );
    await tester.pumpAndSettle();
    bloc = tester.element(feedback).read<StaffQueueBloc>();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
    expect(owners.created.whereType<StaffQueueBloc>(), hasLength(1));
    expect(feeds, hasLength(1));
  }

  Future<dynamic> execute(StaffOperation op) => bloc.execute(
    op,
    ticketId: op == StaffOperation.call ? null : staffTicket,
  );
  const operations = [
    StaffOperation.call,
    StaffOperation.recall,
    StaffOperation.skip,
    StaffOperation.requeue,
    StaffOperation.start,
    StaffOperation.complete,
  ];
  for (final op in operations) {
    for (final reduced in [false, true]) {
      testWidgets(
        '${op.name} only confirmed feedback; one POST, reduced=$reduced',
        (tester) async {
          await open(tester, op, reduced: reduced);
          final post = api.block(commandPath(op), 'POST');
          final command = execute(op);
          await post.entered.future;
          await tester.pump();
          expect(find.byType(Animate), findsNothing);
          final reconcile = api.block('/queue/snapshot');
          post.release.complete();
          await reconcile.entered.future;
          await tester.pump();
          expect(find.byType(Animate), findsNothing);
          reconcile.release.complete();
          await command;
          await tester.pump();
          await tester.pump(Duration.zero);
          await tester.pump();
          expect(
            find.descendant(of: feedback, matching: find.byType(Animate)),
            reduced ? findsNothing : findsOneWidget,
          );
          expect(api.status, op.expectedStatus);
          expect(api.count(commandPath(op), 'POST'), 1);
          await tester.pump(const Duration(milliseconds: 210));
          if (!reduced) expect(opacity(tester), 1);
          final ownerCount = owners.created.length,
              readCount = api.calls.length;
          api.notifyListeners();
          await tester.pump();
          expect(api.calls.length, readCount);
          // Keep a real refresh pending across a frame: synchronized changes must
          // not be mistaken for a new command confirmation.
          final readGate = api.block('/queue/snapshot');
          final refresh = bloc.refresh();
          await readGate.entered.future;
          await tester.pump();
          readGate.release.complete();
          await refresh;
          await tester.pump();
          // Existing refresh clears transient feedback; it must stay cleared.
          expect(bloc.state.message, isNull);
          expect(
            find.descendant(of: feedback, matching: find.byType(Animate)),
            findsNothing,
          );
          feeds.single.status('Realtime terhubung');
          await tester.pump();
          expect(owners.created.length, ownerCount);
          expect(feeds.where((f) => !f.disposed), hasLength(1));
          expect(api.count(commandPath(op), 'POST'), 1);
          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(milliseconds: 250));
          expect(bloc.isClosed, isTrue);
          expect(feeds.single.disposed, isTrue);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  for (final outcome in ['conflict', 'uncertain-call', 'reconciled-start']) {
    testWidgets('$outcome never produces a confirmed-success animation', (
      tester,
    ) async {
      final op = outcome == 'reconciled-start'
          ? StaffOperation.start
          : StaffOperation.call;
      await open(tester, op);
      if (outcome == 'conflict') {
        api.failures['POST ${commandPath(op)}'] = const ApiException(
          409,
          'Synthetic conflict',
        );
      }
      if (outcome == 'uncertain-call') api.loseWithoutCommit = true;
      if (outcome == 'reconciled-start') api.loseMutation = true;
      await expectLater(execute(op), throwsA(isA<ApiException>()));
      await tester.pumpAndSettle();
      expect(find.byType(Animate), findsNothing);
      expect(api.count(commandPath(op), 'POST'), 1);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'account switch while POST is pending rejects late feedback and closes feed',
    (tester) async {
      await open(tester, StaffOperation.call);
      final post = api.block(commandPath(StaffOperation.call), 'POST');
      final rejected = expectLater(
        execute(StaffOperation.call),
        throwsA(isA<ApiException>()),
      );
      await post.entered.future;
      api.changeIdentity('different-staff');
      await tester.pump();
      post.release.complete();
      await rejected;
      await tester.pumpAndSettle();
      expect(find.byType(Animate), findsNothing);
      expect(feeds.single.disposed, isTrue);
      expect(api.count(commandPath(StaffOperation.call), 'POST'), 1);
      expect(tester.takeException(), isNull);
    },
  );
}
