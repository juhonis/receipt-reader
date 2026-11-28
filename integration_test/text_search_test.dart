import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart';
import 'package:receipt_storage/receipt_storage.dart';
import 'package:receipt_reader/app.dart';
import 'package:receipt_reader/history_page.dart';
import 'package:receipt_reader/local_store.dart';
import 'package:receipt_reader/product_picker.dart';

import '../test/text_search_test.dart' show runTextSearchTests, searchText;
import '../test/history_page_test.dart' show tapKey;

ReviewedReceipt _receipt(ReceiptBranch branch, String name, String date) {
  final snapshot = ReceiptSnapshot(
    id: DurableId.generate(),
    branch: branch,
    date: StoredReceiptDate.parse(date),
    totalCents: BigInt.from(200),
    items: [
      ReceiptItemSnapshot(
        id: DurableId.generate(),
        name: name,
        kind: LineKind.product,
        cents: BigInt.from(200),
      ),
    ],
  );
  return ReviewedReceipt.manual(
    current: snapshot,
    expectedHeads: [],
    confirmation: ManualReviewChecks(
      snapshot: snapshot,
      expectedHeads: [],
      mutationId: DurableId.generate(),
      branchReviewed: true,
      dateReviewed: true,
      totalReviewed: true,
      reviewedRowIds: snapshot.items.map((i) => i.id),
    ).confirm(reviewedAtMs: BigInt.one, appVersion: 'search-smoke'),
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  runTextSearchTests();
  testWidgets(
    'native SQLite search reaches unloaded receipts and aliases after reopen without writes',
    (t) async {
      final support = await getApplicationSupportDirectory();
      final directoryName = 'text-search-smoke-${DurableId.generate().value}';
      final directory = Directory('${support.path}/$directoryName');
      await directory.create();
      ReceiptRepository? repository;
      try {
        final file = File('${directory.path}/receipts.sqlite');
        final original = repository = await ReceiptRepository.open(file);
        await original.saveManual(
          _receipt(
            ReceiptBranch(id: DurableId.generate(), name: 'ÄITI MARKET'),
            'ORDINARY',
            '16.11.2026',
          ),
        );
        final branch = (await original.branches()).single;
        for (var i = 0; i < 30; i++) {
          await original.saveManual(_receipt(branch, 'ORDINARY', '16.11.2026'));
        }
        final target = _receipt(branch, 'Ruisleipä 100%_', '1.11.2026');
        await original.saveManual(target);
        DurableId? productId;
        for (var i = 0; i < 32; i++) {
          final id = DurableId.generate();
          final document = ProductDocument(
            product: ProductSnapshot(
              id: id,
              storeId: branch.id,
              canonicalName: i == 31 ? 'Ruisleipä' : 'AAA $i',
            ),
            storeRevision: branch.revision!,
            expectedHead: null,
            reviewedAtMs: BigInt.one,
            appVersion: 'search-smoke',
          );
          final saved = await original.saveProduct(
            document,
            mutationId: DurableId.generate(),
          );
          if (i == 31) {
            productId = id;
            await original.saveAlias(
              ProductAliasDocument(
                alias: ProductAliasSnapshot(
                  id: DurableId.generate(),
                  storeId: branch.id,
                  normalizedName: 'ruis 100%_',
                  productId: id,
                  isActive: true,
                ),
                storeRevision: branch.revision!,
                productRevision: saved.revision,
                expectedHead: null,
                reviewedAtMs: BigInt.one,
                appVersion: 'search-smoke',
              ),
              mutationId: DurableId.generate(),
            );
          }
        }
        final before = await original.identity();
        await original.close();
        repository = null;
        final reopened = repository = await ReceiptRepository.open(file);
        final store = RepositoryStore(reopened);
        await t.pumpWidget(const ReceiptReaderApp());
        await t.pumpAndSettle();
        Navigator.of(t.element(find.byType(Scaffold).first)).push(
          MaterialPageRoute<void>(builder: (_) => HistoryPage(store: store)),
        );
        await t.pumpAndSettle();
        await searchText(t, 'history-search', 'äiti LEIPÄ %_');
        expect(
          find.byKey(ValueKey('history-${target.document.snapshot.id.value}')),
          findsOneWidget,
        );
        final picked = chooseProduct(
          t.element(find.byType(HistoryPage)),
          store,
          branch.id,
        );
        await t.pumpAndSettle();
        await searchText(t, 'picker-search', 'LEIPÄ RUIS %_');
        FocusManager.instance.primaryFocus?.unfocus();
        await t.pumpAndSettle();
        await tapKey(t, 'pick-product-${productId!.value}');
        expect((await picked)!.product!.document.product.id, productId);
        final after = await reopened.identity();
        expect(after.nextLocalSequence, before.nextLocalSequence);
        expect((await reopened.history(limit: 200)).length, 32);
        await reopened.verifyIntegrity();
      } finally {
        await t.pumpWidget(const SizedBox());
        await repository?.close();
        if (directory.absolute.parent.path != support.absolute.path ||
            directory.uri.pathSegments.where((s) => s.isNotEmpty).last !=
                directoryName) {
          throw StateError('Unexpected text-search test directory');
        }
        await directory.delete(recursive: true);
      }
    },
  );
}
