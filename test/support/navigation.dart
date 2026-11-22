import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// Shared native/widget setup for workflows housed in the receipts tab.
Future<void> openReceiptManagement(WidgetTester tester) async {
  final tab = find.byKey(const Key('home-tab-receipts'));
  if (tab.evaluate().isNotEmpty) {
    await tester.tap(tab);
    await tester.pumpAndSettle();
  }
}
