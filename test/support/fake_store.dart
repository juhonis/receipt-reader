import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_storage/receipt_storage.dart';
import 'package:receipt_reader/local_store.dart';

class FakeStore implements LocalStore {
  final branch = ReceiptBranch(
    id: DurableId.generate(),
    name: 'SYNTHETIC BRANCH',
    revision: RevisionId(DurableId.generate(), BigInt.one),
  );
  final saved = <ReviewedReceipt>[];
  final documents = <StoredReceipt>[];
  bool failSaveAfterCommit = false, failBranches = false, failHistory = false;
  int closeCount = 0, historyCalls = 0;
  final historyOffsets = <int>[];
  final historyFilters = <HistoryFilter?>[];
  Future<void>? historyGate;
  @override
  Future<List<ReceiptBranch>> branches() async {
    if (failBranches) throw const StorageFailure('database');
    return [branch];
  }

  @override
  Future<List<StoredReceipt>> history({
    int limit = 30,
    int offset = 0,
    HistoryFilter? filter,
  }) async {
    historyCalls++;
    historyOffsets.add(offset);
    historyFilters.add(filter);
    await historyGate;
    if (failHistory) throw const StorageFailure('database');
    int day(StoredReceiptDate d) => d.year * 10000 + d.month * 100 + d.day;
    return documents
        .where((r) {
          final s = r.document.snapshot;
          return (filter?.branchId == null ||
                  s.branch.id == filter!.branchId) &&
              (filter?.fromDate == null ||
                  day(s.date) >= day(filter!.fromDate!)) &&
              (filter?.throughDate == null ||
                  day(s.date) <= day(filter!.throughDate!)) &&
              (filter?.minTotalCents == null ||
                  s.totalCents >= filter!.minTotalCents!) &&
              (filter?.maxTotalCents == null ||
                  s.totalCents <= filter!.maxTotalCents!);
        })
        .skip(offset)
        .take(limit)
        .toList();
  }

  @override
  Future<SaveResult> saveManual(ReviewedReceipt command) async {
    final replayed = saved.any((c) => c.mutationId == command.mutationId);
    saved.add(command);
    final revision = RevisionId(branch.revision!.origin, BigInt.two);
    if (!replayed) documents.add(StoredReceipt(command.document, revision));
    if (failSaveAfterCommit) throw const StorageFailure('database');
    return SaveResult(revision, replayed: replayed);
  }

  @override
  Future<SaveResult> saveOcr(ReviewedReceipt command) => saveManual(command);
  @override
  Future<void> close() async {
    closeCount++;
  }
}
