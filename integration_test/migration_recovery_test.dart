import 'package:cupertino_ui/cupertino_ui.dart'
    show GlobalCupertinoLocalizations;
import 'package:flutter_localizations/flutter_localizations.dart'
    show GlobalWidgetsLocalizations;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:receipt_parser/receipt_parser.dart';
import 'package:receipt_reader/l10n/generated/app_localizations.dart';
import 'package:receipt_reader/local_store.dart';
import 'package:receipt_reader/purchase_history_page.dart';
import 'package:receipt_reader/purchase_summary_view.dart';
import 'package:receipt_reader/spending_page.dart';

import '../packages/receipt_storage/test/support/upgrade_rehearsal.dart';

Widget shell(Widget page) => MaterialApp(
  key: UniqueKey(),
  locale: const Locale('fi'),
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: page,
);

Future<void> waitFor(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 300 && finder.evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(finder, findsOneWidget);
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  for (final version in [1, 2, 3, 4]) {
    testWidgets(
      'native v$version migration, rollback, analytics and encrypted recovery',
      (tester) async {
        final support = await getApplicationSupportDirectory();
        final directory = await support.createTemp(
          'migration-recovery-smoke-v$version-',
        );
        try {
          await rehearseUpgrade(
            directory,
            version,
            inspectRestored: (workspace, product, total) async {
              final store = RepositoryStore(workspace.repository);
              await tester.pumpWidget(
                shell(SpendingPage(store: store, service: store)),
              );
              await waitFor(
                tester,
                find.text(
                  'Kuittien loppusummat yhteensä: ${formatCents(total)} €',
                ),
              );
              await tester.pumpWidget(
                shell(
                  PurchaseHistoryPage(
                    store: store,
                    service: store,
                    product: product,
                    branchName: 'SYNTHETIC UPGRADE BRANCH',
                  ),
                ),
              );
              await waitFor(tester, find.text('Ostorivejä yhteensä: 2'));
              final summary = tester
                  .widget<PurchaseSummaryView>(find.byType(PurchaseSummaryView))
                  .summary;
              expect(summary.groups, hasLength(2));
              expect(summary.effectiveCents, BigInt.from(500));
              expect(tester.takeException(), isNull);
              await tester.pumpWidget(const SizedBox());
            },
          );
        } finally {
          await tester.pumpWidget(const SizedBox());
          if (directory.parent.absolute.path != support.absolute.path ||
              !directory.path.contains('migration-recovery-smoke-v$version-')) {
            throw StateError('unexpected_test_directory');
          }
          await directory.delete(recursive: true);
        }
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );
  }
  testWidgets('native refuses future schemas and corrupt data without reset', (
    tester,
  ) async {
    final support = await getApplicationSupportDirectory();
    final directory = await support.createTemp('migration-recovery-refusal-');
    try {
      await rehearseRefusal(directory);
    } finally {
      if (directory.parent.absolute.path != support.absolute.path ||
          !directory.path.contains('migration-recovery-refusal-')) {
        throw StateError('unexpected_test_directory');
      }
      await directory.delete(recursive: true);
    }
  });
}
