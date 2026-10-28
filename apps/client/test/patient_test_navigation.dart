import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reach the retained catalog via the public reservation sheet rather than
/// obsolete home shortcuts. Every action uses the actual widget callback.
Future<void> openPatientCatalog(
  WidgetTester tester, {
  bool walkIn = false,
}) async {
  for (final target in [
    find.widgetWithText(NavigationDestination, 'Reservasi'),
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
