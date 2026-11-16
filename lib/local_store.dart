import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_storage/receipt_storage.dart';

/// App-facing seam: widget tests never open the user's real database.
abstract interface class LocalStore {
  Future<List<ReceiptBranch>> branches();
  Future<List<StoredReceipt>> history({int limit = 30, int offset = 0});
  Future<SaveResult> saveManual(ReviewedReceipt command);
  Future<void> close();
}

final class RepositoryStore implements LocalStore {
  RepositoryStore(this.repository);
  final ReceiptRepository repository;

  @override
  Future<List<ReceiptBranch>> branches() => repository.branches();
  @override
  Future<List<StoredReceipt>> history({int limit = 30, int offset = 0}) =>
      repository.history(limit: limit, offset: offset);
  @override
  Future<SaveResult> saveManual(ReviewedReceipt command) =>
      repository.saveManual(command);
  @override
  Future<void> close() => repository.close();
}

/// A single connection owned by the app, outside the checkout/import folders.
Future<LocalStore> openApplicationStore() async {
  final directory = await getApplicationSupportDirectory();
  await directory.create(recursive: true);
  return RepositoryStore(
    await ReceiptRepository.open(
      File('${directory.path}${Platform.pathSeparator}receipts.sqlite'),
    ),
  );
}
