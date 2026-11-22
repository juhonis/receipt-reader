import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:receipt_reader/app.dart';

import '../test/support/navigation.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native license page exposes retained Google SDK terms offline', (
    t,
  ) async {
    // Flutter's test binding deliberately disables ServicesBinding.initLicenses.
    // Register the actual packaged file through the same public registry and
    // documented notice format; no synthetic license text is substituted.
    LicenseRegistry.addLicense(() async* {
      final bytes = await rootBundle.load('NOTICES.Z');
      final text = utf8.decode(gzip.decode(bytes.buffer.asUint8List()));
      for (final block in text.split('\n${'-' * 80}\n')) {
        final split = block.indexOf('\n\n');
        if (split >= 0) {
          yield LicenseEntryWithLineBreaks(
            block.substring(0, split).split('\n'),
            block.substring(split + 2),
          );
        }
      }
    });
    // No storage opener, receipt image, or application database is used.
    await t.pumpWidget(const ReceiptReaderApp());
    await t.tap(find.byKey(const Key('open-software-info')));
    await t.pumpAndSettle();
    await openReceiptManagement(t);
    await t.scrollUntilVisible(
      find.byKey(const Key('open-license-page')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await t.tap(find.byKey(const Key('open-license-page')));
    for (var i = 0; i < 600; i++) {
      await t.pump(const Duration(milliseconds: 50));
      if (find.text('Android Google SDK: Abseil').evaluate().isNotEmpty) break;
    }
    expect(find.byType(LicensePage), findsOneWidget);
    final entry = find.text('Android Google SDK: Abseil');
    expect(entry, findsOneWidget);
    await t.ensureVisible(entry);
    await t.tap(entry);
    await t.pumpAndSettle();
    expect(find.textContaining('Apache License'), findsWidgets);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });
}
