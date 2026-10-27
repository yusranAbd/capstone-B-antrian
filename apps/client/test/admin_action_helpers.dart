import 'package:flutter_test/flutter_test.dart';
import 'package:queueb_client/src/admin_ui.dart';

/// Navigate the new menu without weakening the existing mutation assertions.
Future<void> adminAction(
  WidgetTester tester,
  String action, {
  Finder? row,
}) async {
  final menu = row ?? find.byType(AdminRowActions).first;
  await tester.ensureVisible(menu);
  await tester.pumpAndSettle();
  await tester.tap(menu);
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text(action).last);
  await tester.tap(find.text(action).last);
  await tester.pumpAndSettle();
}
