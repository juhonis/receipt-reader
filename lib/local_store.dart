import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_storage/receipt_storage.dart';

import 'backup_service.dart';

/// App-facing seam: widget tests never open the user's real database.
abstract interface class LocalStore {
  Future<List<ReceiptBranch>> branches();
  Future<List<StoredReceipt>> history({
    int limit = 30,
    int offset = 0,
    HistoryFilter? filter,
  });
  Future<SaveResult> saveManual(ReviewedReceipt command);
  Future<SaveResult> saveOcr(ReviewedReceipt command);
  Future<SaveResult> deleteReceipt(ReviewedReceiptDeletion command);
  Future<void> close();
}

final class RepositoryStore implements LocalStore {
  RepositoryStore(this.repository);
  final ReceiptRepository repository;

  @override
  Future<List<ReceiptBranch>> branches() => repository.branches();
  @override
  Future<List<StoredReceipt>> history({
    int limit = 30,
    int offset = 0,
    HistoryFilter? filter,
  }) => repository.history(limit: limit, offset: offset, filter: filter);
  @override
  Future<SaveResult> saveManual(ReviewedReceipt command) =>
      repository.saveManual(command);
  @override
  Future<SaveResult> saveOcr(ReviewedReceipt command) =>
      repository.saveOcr(command);
  @override
  Future<SaveResult> deleteReceipt(ReviewedReceiptDeletion command) =>
      repository.deleteReceipt(command);
  @override
  Future<void> close() => repository.close();
}

/// Serializes all app reads/writes with backup preparation and activation.
final class WorkspaceStore implements LocalStore, BackupService {
  WorkspaceStore(this.workspace);
  final ReceiptWorkspace workspace;
  Future<void> _tail = Future.value();
  bool _closed = false;
  Future<T> _run<T>(Future<T> Function() action) {
    if (_closed) return Future.error(const StorageFailure('workspaceClosed'));
    final result = _tail.then((_) {
      if (!workspace.usable) throw const StorageFailure('workspaceRestart');
      return action();
    });
    _tail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  @override
  bool get canReturnToPrevious => workspace.canReturnToPrevious;
  @override
  bool get datasetAvailable => workspace.datasetAvailable;
  @override
  Future<List<ReceiptBranch>> branches() =>
      _run(() => workspace.repository.branches());
  @override
  Future<List<StoredReceipt>> history({
    int limit = 30,
    int offset = 0,
    HistoryFilter? filter,
  }) => _run(
    () => workspace.repository.history(
      limit: limit,
      offset: offset,
      filter: filter,
    ),
  );
  @override
  Future<SaveResult> saveManual(ReviewedReceipt command) =>
      _run(() => workspace.repository.saveManual(command));
  @override
  Future<SaveResult> saveOcr(ReviewedReceipt command) =>
      _run(() => workspace.repository.saveOcr(command));
  @override
  Future<SaveResult> deleteReceipt(ReviewedReceiptDeletion command) =>
      _run(() => workspace.repository.deleteReceipt(command));
  @override
  Future<Uint8List> exportProtected(String password) =>
      _run(() => workspace.exportProtected(password));
  @override
  Future<BackupCandidate> prepareProtected(Uint8List file, String password) =>
      _run(() async {
        final preview = await workspace.prepare(file, password);
        return BackupCandidate(
          receipts: preview.receipts,
          deleted: preview.deleted,
          events: preview.events,
          token: preview,
        );
      });
  @override
  Future<void> activateBackup(BackupCandidate candidate) =>
      _run(() => workspace.activate(candidate.token as RestorePreview));
  @override
  Future<void> discardBackup(BackupCandidate candidate) =>
      _run(() => workspace.discard(candidate.token as RestorePreview));
  @override
  Future<void> returnToPrevious() => _run(workspace.returnToPrevious);
  @override
  Future<void> close() {
    if (_closed) return _tail;
    _closed = true;
    return _tail = _tail.then((_) => workspace.close());
  }
}

Future<LocalStore> openApplicationStore() async => WorkspaceStore(
  await ReceiptWorkspace.open(await getApplicationSupportDirectory()),
);

Future<LocalStore> openApplicationRecoveryStore() async => WorkspaceStore(
  await ReceiptWorkspace.open(
    await getApplicationSupportDirectory(),
    recoverActive: true,
  ),
);
