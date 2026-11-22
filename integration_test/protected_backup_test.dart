import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart';
import 'package:receipt_storage/receipt_storage.dart';
import 'package:receipt_reader/app.dart';
import 'package:receipt_reader/backup_files.dart';
import 'package:receipt_reader/backup_service.dart';
import 'package:receipt_reader/local_store.dart';

import '../packages/receipt_domain/test/ocr_support.dart';
import '../test/support/navigation.dart';

const password = 'synthetic password 2026';

class _Observed implements LocalStore, BackupService {
  _Observed(this.delegate);
  final WorkspaceStore delegate;
  Future<Uint8List>? exported;
  Future<BackupCandidate>? prepared;
  Completer<void>? prepareStarted;
  Future<void>? activated, discarded, returned;
  @override
  bool get datasetAvailable => delegate.datasetAvailable;
  @override
  bool get canReturnToPrevious => delegate.canReturnToPrevious;
  @override
  Future<List<ReceiptBranch>> branches() => delegate.branches();
  @override
  Future<List<StoredReceipt>> history({
    int limit = 30,
    int offset = 0,
    HistoryFilter? filter,
  }) => delegate.history(limit: limit, offset: offset, filter: filter);
  @override
  Future<SaveResult> saveManual(ReviewedReceipt command) =>
      delegate.saveManual(command);
  @override
  Future<SaveResult> saveOcr(ReviewedReceipt command) =>
      delegate.saveOcr(command);
  @override
  Future<SaveResult> deleteReceipt(ReviewedReceiptDeletion command) =>
      delegate.deleteReceipt(command);
  @override
  Future<Uint8List> exportProtected(String password) =>
      exported = delegate.exportProtected(password);
  @override
  Future<BackupCandidate> prepareProtected(Uint8List file, String password) {
    final result = prepared = delegate.prepareProtected(file, password);
    prepareStarted?.complete();
    return result;
  }

  @override
  Future<void> activateBackup(BackupCandidate candidate) =>
      activated = delegate.activateBackup(candidate);
  @override
  Future<void> discardBackup(BackupCandidate candidate) =>
      discarded = delegate.discardBackup(candidate);
  @override
  Future<void> returnToPrevious() => returned = delegate.returnToPrevious();
  @override
  Future<void> close() => delegate.close();
}

class _Files implements BackupFiles {
  _Files(this.file);
  final File file;
  Future<bool>? saved;
  Future<Uint8List>? reading;
  @override
  Future<Uint8List?> read() => reading = file.readAsBytes();
  @override
  Future<bool> save(Uint8List bytes) => saved = (() async {
    await writeNewBackup(file, bytes);
    return true;
  })();
}

ReviewedReceipt manual() {
  final snapshot = ReceiptSnapshot(
    id: DurableId.generate(),
    branch: ReceiptBranch(
      id: DurableId.generate(),
      name: 'MANUAL BACKUP UI TEST',
    ),
    date: StoredReceiptDate.parse('17.11.2026'),
    totalCents: BigInt.from(250),
    items: [
      ReceiptItemSnapshot(
        id: DurableId.generate(),
        name: 'SYNTHETIC ITEM',
        kind: LineKind.product,
        cents: BigInt.from(250),
      ),
    ],
  );
  return ReviewedReceipt.manual(
    current: snapshot,
    expectedHeads: const [],
    confirmation: ManualReviewChecks(
      snapshot: snapshot,
      expectedHeads: const [],
      mutationId: DurableId.generate(),
      branchReviewed: true,
      dateReviewed: true,
      totalReviewed: true,
      reviewedRowIds: snapshot.items.map((r) => r.id),
    ).confirm(reviewedAtMs: BigInt.one, appVersion: 'protected-ui-smoke'),
  );
}

Future<void> tap(WidgetTester tester, String key, {bool settle = true}) async {
  final finder = find.byKey(Key(key));
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      240,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pump();
  if (settle) await tester.pumpAndSettle();
}

Future<void> _beginImport(
  WidgetTester tester,
  _Observed store,
  _Files files,
) async {
  store.prepared = null;
  final started = store.prepareStarted = Completer<void>();
  await tap(tester, 'backup-import', settle: false);
  await started.future.timeout(const Duration(seconds: 15));
}

Future<void> enterPassword(
  WidgetTester tester, {
  bool confirm = false,
  String value = password,
}) async {
  final field = find.byKey(const Key('backup-password'));
  if (field.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      field,
      240,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.ensureVisible(field);
  await tester.pumpAndSettle();
  expect(tester.widget<TextField>(field).enabled, isTrue);
  await tester.tap(field);
  await tester.pumpAndSettle();
  await tester.enterText(field, value);
  await tester.pump();
  expect(tester.widget<TextField>(field).controller!.text, value);
  if (confirm) {
    await tester.enterText(
      find.byKey(const Key('backup-password-again')),
      value,
    );
  }
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  expect(tester.widget<TextField>(field).controller!.text, value);
}

Future<void> review(WidgetTester tester) async {
  final target = find.byKey(const Key('backup-reviewed'));
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      target,
      240,
      scrollable: find.byType(Scrollable).first,
    );
  }
  final box = find.descendant(of: target, matching: find.byType(Checkbox));
  await tester.ensureVisible(box);
  await tester.pumpAndSettle();
  await tester.tap(box);
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native password backup, reviewed activation, previous dataset and startup recovery',
    (tester) async {
      final support = await getApplicationSupportDirectory();
      final directory = await support.createTemp('protected-backup-ui-smoke-');
      _Observed? store;
      try {
        var workspace = await ReceiptWorkspace.open(directory);
        store = _Observed(WorkspaceStore(workspace));
        final initial = manual();
        await store.saveManual(initial);
        final prior = (await workspace.repository.read(
          initial.document.snapshot.id,
        ))!;
        await store.deleteReceipt(
          ReceiptDeletionChecks(
            document: prior.document,
            expectedHead: prior.revision,
            mutationId: DurableId.generate(),
            receiptReviewed: true,
          ).confirm(deletedAtMs: BigInt.two, appVersion: 'protected-ui-smoke'),
        );
        await store.saveOcr(OcrFixture().save());
        final original = await workspace.repository.identity();
        final files = _Files(File('${directory.path}/synthetic.rrbackup'));
        final current = store;
        await tester.pumpWidget(
          ReceiptReaderApp(
            storageOpener: () async => current,
            backupFiles: files,
          ),
        );
        await tester.pumpAndSettle();
        await openReceiptManagement(tester);
        await tap(tester, 'open-backups');
        await enterPassword(tester, confirm: true);
        await tap(tester, 'backup-export', settle: false);
        await store.exported;
        await tester.pump();
        await files.saved;
        await tester.pumpAndSettle();
        expect(await files.file.exists(), isTrue);
        expect((await files.file.readAsBytes()).take(8), 'RRBACKUP'.codeUnits);
        await store.saveManual(manual());
        expect(await store.history(), hasLength(2));
        await enterPassword(tester, value: 'wrong synthetic password');
        await _beginImport(tester, store, files);
        await expectLater(
          store.prepared,
          throwsA(
            isA<StorageFailure>().having(
              (e) => e.code,
              'code',
              'backupAuthentication',
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('backup-error')), findsOneWidget);
        expect(
          (await workspace.repository.identity()).deviceId,
          original.deviceId,
        );
        await enterPassword(tester);
        await _beginImport(tester, store, files);
        final cancelled = (await store.prepared)!;
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('backup-activate')))
              .onPressed,
          isNull,
        );
        await tap(tester, 'backup-discard', settle: false);
        await store.discarded;
        await tester.pumpAndSettle();
        expect(
          await (cancelled.token as RestorePreview).restored.directory.exists(),
          isFalse,
        );
        await enterPassword(tester);
        await _beginImport(tester, store, files);
        await store.prepared;
        await tester.pumpAndSettle();
        await review(tester);
        await tap(tester, 'backup-activate', settle: false);
        await store.activated;
        await tester.pumpAndSettle();
        expect(await store.history(), hasLength(1));
        expect(
          (await workspace.repository.identity()).deviceId,
          isNot(original.deviceId),
        );
        expect(
          await workspace.repository.readDeleted(initial.document.snapshot.id),
          isNotNull,
        );
        await tap(tester, 'open-backups');
        await tap(tester, 'backup-previous');
        await tap(tester, 'backup-confirm-previous', settle: false);
        await store.returned;
        await tester.pumpAndSettle();
        expect(
          (await workspace.repository.identity()).deviceId,
          original.deviceId,
        );
        expect(await store.history(), hasLength(2));
        await tester.pumpWidget(const SizedBox());
        await store.close();
        store = null;
        final damaged = 'SYNTHETIC UNREADABLE DATABASE'.codeUnits;
        final legacy = File('${directory.path}/receipts.sqlite');
        await legacy.writeAsBytes(damaged, flush: true);
        Future<LocalStore>? normalOpen;
        await tester.pumpWidget(
          ReceiptReaderApp(
            storageOpener: () => normalOpen = (() async => _Observed(
              WorkspaceStore(await ReceiptWorkspace.open(directory)),
            ))(),
            recoveryOpener: () async {
              workspace = await ReceiptWorkspace.open(
                directory,
                recoverActive: true,
              );
              return store = _Observed(WorkspaceStore(workspace));
            },
            backupFiles: files,
          ),
        );
        await expectLater(normalOpen, throwsA(isA<StorageFailure>()));
        await tester.pumpAndSettle();
        await openReceiptManagement(tester);
        await tap(tester, 'open-backup-recovery');
        // The asynchronous opener is awaited by the gate; wait for its home state.
        for (var i = 0; i < 100 && store == null; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('open-history')), findsNothing);
        await tap(tester, 'open-backups');
        await enterPassword(tester);
        final recovered = store!;
        await _beginImport(tester, recovered, files);
        await recovered.prepared;
        await tester.pumpAndSettle();
        await review(tester);
        await tap(tester, 'backup-activate', settle: false);
        await recovered.activated;
        await tester.pumpAndSettle();
        expect(await legacy.readAsBytes(), damaged);
        expect(await recovered.history(), hasLength(1));
        await workspace.repository.verifyIntegrity();
        expect(find.byKey(const Key('open-history')), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await store?.close();
        if (directory.parent.absolute.path != support.absolute.path ||
            !directory.uri.pathSegments
                .where((s) => s.isNotEmpty)
                .last
                .startsWith('protected-backup-ui-smoke-')) {
          throw StateError('unexpected_smoke_directory');
        }
        await directory.delete(recursive: true);
      }
    },
  );
}
