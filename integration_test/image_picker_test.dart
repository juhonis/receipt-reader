import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:receipt_reader/receipt_import.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const interactive = bool.fromEnvironment('INTERACTIVE_IMAGE_PICKER');
  if (interactive) {
    setUpAll(() => binding.platformDispatcher.semanticsEnabledTestValue = true);
    tearDownAll(binding.platformDispatcher.clearSemanticsEnabledTestValue);
  }
  testWidgets(
    'native image picker imports the synthetic receipt and cancels without data',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(child: Text('Synthetic image picker check')),
          ),
        ),
      );
      // Select test/fixtures/synthetic_receipt.png, then cancel the second dialog.
      final evidence = await pickReceiptImage();
      expect(evidence, isNotNull);
      try {
        expect(evidence!.image.width, 1000);
        expect(evidence.image.height, 1000);
      } finally {
        evidence?.dispose();
      }
      expect(await pickReceiptImage(), isNull);
    },
    skip: !interactive,
  );
}
