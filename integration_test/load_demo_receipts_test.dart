import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_storage/receipt_storage.dart';

import '../tools/demo_receipts/demo_data.dart';

/// Explicitly opted-in provisioning of the normal app dataset, NOT a smoke test.
/// Ordinary integration-suite runs skip it before opening application storage.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const enabled = bool.fromEnvironment('RECEIPT_READER_LOAD_DEMO_DATA');
  const date = String.fromEnvironment('RECEIPT_READER_DEMO_ANCHOR');
  testWidgets('explicitly load ten synthetic receipts into normal app storage', (
    t,
  ) async {
    if (date.isEmpty) throw StateError('explicit_demo_anchor_required');
    final anchor = StoredReceiptDate.parse(date);
    final workspace = await ReceiptWorkspace.open(
      await getApplicationSupportDirectory(),
    );
    try {
      final result = await loadDemoReceipts(workspace.repository, anchor);
      expect(result.receipts, 10);
      // Only invented fixture counts/totals are printed, never existing user data.
      // ignore: avoid_print
      print(
        'DEMO DATA: receipts=10 new=${result.createdReceipts} products=${result.createdProducts} '
        'linked=${result.linkedReceipts}; fixture-only cents week=${result.weekCents} '
        'month=${result.monthCents} year=${result.yearCents}; anchor=$date',
      );
    } finally {
      await workspace.close();
    }
  }, skip: !enabled);
}
