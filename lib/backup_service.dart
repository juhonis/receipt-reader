import 'dart:typed_data';

final class BackupCandidate {
  const BackupCandidate({
    required this.receipts,
    required this.deleted,
    required this.events,
    required this.token,
  });
  final int receipts, deleted, events;
  final Object token;
}

abstract interface class BackupService {
  bool get canReturnToPrevious;
  bool get datasetAvailable;
  Future<Uint8List> exportProtected(String password);
  Future<BackupCandidate> prepareProtected(Uint8List file, String password);
  Future<void> activateBackup(BackupCandidate candidate);
  Future<void> discardBackup(BackupCandidate candidate);
  Future<void> returnToPrevious();
}
