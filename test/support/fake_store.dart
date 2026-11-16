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
  final deletions = <ReviewedReceiptDeletion>[];
  final tombstones = <DurableId, ReceiptTombstone>{};
  final documents = <StoredReceipt>[];
  bool failSaveAfterCommit = false, failBranches = false, failHistory = false;
  int closeCount = 0, historyCalls = 0;
  final historyOffsets = <int>[];
  final historyFilters = <HistoryFilter?>[];
  Future<void>? historyGate;
  Future<void>? deletionGate;
  String? saveFailure;
  final _results = <DurableId, RevisionId>{};
  int _nextRevision = 2;
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
    saved.add(command);
    if (saveFailure case final failure?) throw StorageFailure(failure);
    final previous = _results[command.mutationId];
    if (previous != null) return SaveResult(previous, replayed: true);
    if (tombstones.containsKey(command.document.snapshot.id)) {
      throw const StorageFailure('receiptDeleted');
    }
    final index = documents.indexWhere(
      (r) => r.document.snapshot.id == command.document.snapshot.id,
    );
    final heads = command.document.review.expectedHeads;
    if (index < 0
        ? heads.isNotEmpty
        : heads.length != 1 || heads.single != documents[index].revision) {
      throw const StorageFailure('staleReceipt');
    }
    if (index >= 0 &&
        documents[index].document.review.source !=
            command.document.review.source) {
      throw const StorageFailure('provenanceChange');
    }
    if (index >= 0 &&
        _nextRevision <= documents[index].revision.sequence.toInt()) {
      _nextRevision = documents[index].revision.sequence.toInt() + 1;
    }
    final revision = RevisionId(
      branch.revision!.origin,
      BigInt.from(_nextRevision++),
    );
    _results[command.mutationId] = revision;
    final stored = StoredReceipt(command.document, revision);
    if (index < 0) {
      documents.add(stored);
    } else {
      documents[index] = stored;
    }
    if (failSaveAfterCommit) throw const StorageFailure('database');
    return SaveResult(revision, replayed: false);
  }

  @override
  Future<SaveResult> saveOcr(ReviewedReceipt command) => saveManual(command);
  @override
  Future<SaveResult> deleteReceipt(ReviewedReceiptDeletion command) async {
    deletions.add(command);
    await deletionGate;
    if (saveFailure case final failure?) throw StorageFailure(failure);
    final previous = _results[command.mutationId];
    if (previous != null) return SaveResult(previous, replayed: true);
    final t = command.tombstone;
    final index = documents.indexWhere(
      (r) => r.document.snapshot.id == t.receiptId,
    );
    if (index < 0 ||
        documents[index].revision != t.expectedHead ||
        documents[index].document.sha256Hex != t.documentSha256) {
      throw const StorageFailure('staleReceipt');
    }
    if (_nextRevision <= t.expectedHead.sequence.toInt()) {
      _nextRevision = t.expectedHead.sequence.toInt() + 1;
    }
    final revision = RevisionId(
      branch.revision!.origin,
      BigInt.from(_nextRevision++),
    );
    _results[command.mutationId] = revision;
    documents.removeAt(index);
    tombstones[t.receiptId] = t;
    if (failSaveAfterCommit) throw const StorageFailure('database');
    return SaveResult(revision, replayed: false);
  }

  @override
  Future<void> close() async {
    closeCount++;
  }
}
