import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:receipt_reader/app.dart';

void main() {
  for (final size in [const Size(320, 568), const Size(1280, 720)]) {
    testWidgets('Finnish app fits $size with enlarged text', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(const ReceiptReaderApp());
      await tester.pumpAndSettle();
      expect(find.text('Kuittiseuranta'), findsOneWidget);
      expect(find.text('Kuitit ja ostokset yhdessä paikassa'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
