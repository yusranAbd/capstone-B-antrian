import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Exercise the retained ticket deep link, which is no longer a bottom item.
/// Use the router rather than manipulating the feature's state or controllers.
Future<void> openPatientTickets(WidgetTester tester) async {
  GoRouter.of(tester.element(find.byType(NavigationBar)))
      .go('/patient/tickets');
  await tester.pumpAndSettle();
}

Future<void> openPatientAgenda(WidgetTester tester) async {
  GoRouter.of(tester.element(find.byType(NavigationBar)))
      .go('/patient/appointments');
  await tester.pumpAndSettle();
}

/// Reach the retained catalog via the public reservation sheet rather than
/// obsolete home shortcuts. Every action uses the actual widget callback.
Future<void> openPatientCatalog(
  WidgetTester tester, {
  bool walkIn = false,
}) async {
  for (final target in [
    find.widgetWithText(NavigationDestination, 'Riwayat'),
    find.widgetWithText(FloatingActionButton, 'Buat Reservasi'),
    find.text('Pilih Poliklinik'),
  ]) {
    await tester.ensureVisible(target.last);
    await tester.pumpAndSettle();
    await tester.tap(target.last);
    await tester.pumpAndSettle();
  }
  if (walkIn) {
    await tester.tap(find.widgetWithText(FilterChip, 'Walk-in'));
    await tester.pumpAndSettle();
  }
}
