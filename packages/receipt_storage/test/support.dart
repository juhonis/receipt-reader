import 'dart:io';

import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart';
import 'package:receipt_storage/receipt_storage.dart';
import 'package:receipt_storage/src/database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

DurableId id(int number) => DurableId.parse(
  '00000000-0000-4000-8000-${number.toString().padLeft(12, '0')}',
);
ReceiptItemSnapshot row({
  int number = 3,
  String name = 'Maito 1 l',
  BigInt? cents,
  LineKind kind = LineKind.product,
  DurableId? parent,
  DiscountScope? scope,
}) => ReceiptItemSnapshot(
  id: id(number),
  name: name,
  kind: kind,
  cents: cents ?? BigInt.from(200),
  parentItemId: parent,
  discountScope: scope,
);
ReceiptSnapshot snapshot({
  int number = 1,
  ReceiptBranch? branch,
  List<ReceiptItemSnapshot>? items,
  BigInt? total,
  String date = '16.11.2026',
}) => ReceiptSnapshot(
  id: id(number),
  branch: branch ?? ReceiptBranch(id: id(2), name: 'TEST BRANCH'),
  date: StoredReceiptDate.parse(date),
  totalCents: total ?? BigInt.from(200),
  items: items ?? [row()],
);
ReviewedReceipt command(
  ReceiptSnapshot current, {
  int mutation = 4,
  List<RevisionId> heads = const [],
  int at = 123,
}) {
  final checks = ManualReviewChecks(
    snapshot: current,
    expectedHeads: heads,
    mutationId: id(mutation),
    branchReviewed: true,
    dateReviewed: true,
    totalReviewed: true,
    reviewedRowIds: current.items.map((row) => row.id),
  );
  return ReviewedReceipt.manual(
    current: current,
    expectedHeads: heads,
    confirmation: checks.confirm(
      reviewedAtMs: BigInt.from(at),
      appVersion: 'storage-test',
    ),
  );
}

class Harness {
  Harness._(this.directory, this.file);
  final Directory directory;
  final File file;
  late ReceiptDatabase database;
  late ReceiptRepository repository;
  late sqlite.Database raw;
  bool _open = false;

  static Future<Harness> create() async {
    final directory = await Directory.systemTemp.createTemp(
      'receipt-storage-test-',
    );
    final harness = Harness._(
      directory,
      File('${directory.path}/receipts.sqlite'),
    );
    await harness.open();
    return harness;
  }

  Future<void> open() async {
    database = ReceiptDatabase.file(file);
    repository = await ReceiptRepository.connect(database);
    raw = sqlite.sqlite3.open(file.path);
    raw.execute('PRAGMA foreign_keys = ON');
    _open = true;
  }

  Future<void> closeConnection() async {
    if (!_open) return;
    raw.close();
    await repository.close();
    _open = false;
  }

  Future<void> reopen() async {
    await closeConnection();
    await open();
  }

  int count(String table) =>
      raw.select('SELECT COUNT(*) AS count FROM $table').single['count'] as int;
  Future<void> dispose() async {
    await closeConnection();
    // Only remove the exact temporary directory this harness created.
    final tempRoot = Directory.systemTemp.absolute.path;
    if (directory.parent.absolute.path != tempRoot ||
        !directory.path.contains('receipt-storage-test-')) {
      throw StateError('unexpected_test_directory');
    }
    await directory.delete(recursive: true);
  }
}
