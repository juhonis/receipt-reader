import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:receipt_reader/app.dart';
import 'package:receipt_reader/software_info_page.dart';

void main() {
  testWidgets(
    'software terms and offline license action are accessible from home',
    (t) async {
      await t.pumpWidget(const ReceiptReaderApp());
      await t.tap(find.byKey(const Key('open-software-info')));
      await t.pumpAndSettle();
      expect(find.byType(SoftwareInfoPage), findsOneWidget);
      expect(
        find.textContaining('https://developers.google.com/ml-kit/terms'),
        findsOneWidget,
      );
      expect(find.textContaining('ei pyydä verkkolupaa'), findsOneWidget);
      expect(
        t
            .widget<FilledButton>(find.byKey(const Key('open-license-page')))
            .onPressed,
        isNotNull,
      );
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('software information fits narrow screens with enlarged text', (
    t,
  ) async {
    t.view.physicalSize = const Size(320, 960);
    t.view.devicePixelRatio = 1;
    t.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    await t.pumpWidget(const ReceiptReaderApp());
    await t.tap(find.byKey(const Key('open-software-info')));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(
      find.byKey(const Key('open-license-page')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('open-license-page')), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
