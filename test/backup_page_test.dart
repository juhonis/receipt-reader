import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:receipt_reader/app.dart';
import 'package:receipt_reader/backup_files.dart';
import 'package:receipt_reader/backup_page.dart';
import 'package:receipt_reader/backup_service.dart';
import 'package:receipt_storage/receipt_storage.dart';

import 'support/fake_store.dart';

class _Store extends FakeStore implements BackupService {
  @override
  bool datasetAvailable = true;
  @override
  bool canReturnToPrevious = false;
  int exports = 0, prepares = 0, activations = 0, discarded = 0, previous = 0;
  String? failure;
  Future<void>? gate;
  final candidate = BackupCandidate(
    receipts: 3,
    deleted: 1,
    events: 8,
    token: Object(),
  );
  final tokens = <BackupCandidate>[];
  @override
  Future<Uint8List> exportProtected(String password) async {
    exports++;
    await gate;
    if (failure != null) throw StorageFailure(failure!);
    return Uint8List.fromList([1, 2, 3]);
  }

  @override
  Future<BackupCandidate> prepareProtected(
    Uint8List bytes,
    String password,
  ) async {
    prepares++;
    await gate;
    if (failure != null) throw StorageFailure(failure!);
    return candidate;
  }

  @override
  Future<void> activateBackup(BackupCandidate candidate) async {
    activations++;
    tokens.add(candidate);
    await gate;
    if (failure != null) throw StorageFailure(failure!);
    datasetAvailable = true;
  }

  @override
  Future<void> discardBackup(BackupCandidate candidate) async {
    discarded++;
  }

  @override
  Future<void> returnToPrevious() async {
    previous++;
  }
}

class _Files implements BackupFiles {
  Uint8List? incoming = Uint8List.fromList([9]);
  Uint8List? written;
  bool saveResult = true;
  @override
  Future<Uint8List?> read() async => incoming;
  @override
  Future<bool> save(Uint8List bytes) async {
    written = Uint8List.fromList(bytes);
    return saveResult;
  }
}

Future<void> visible(WidgetTester tester, Finder target) async {
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      target,
      220,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, String key) async {
  final target = find.byKey(Key(key));
  await visible(tester, target);
  await tester.tap(target);
  await tester.pump();
  if (find.byType(LinearProgressIndicator).evaluate().isEmpty) {
    await tester.pumpAndSettle();
  }
}

Future<void> password(
  WidgetTester tester, {
  String value = 'synthetic password 2026',
  bool again = false,
}) async {
  await visible(tester, find.byKey(const Key('backup-password')));
  await tester.enterText(find.byKey(const Key('backup-password')), value);
  if (again) {
    await tester.enterText(
      find.byKey(const Key('backup-password-again')),
      value,
    );
  }
}

Future<void> _open(WidgetTester tester, _Store store, _Files files) async {
  await tester.pumpWidget(
    ReceiptReaderApp(storageOpener: () async => store, backupFiles: files),
  );
  await tester.pumpAndSettle();
  await tap(tester, 'open-backups');
}

Future<void> review(WidgetTester tester) async {
  await visible(tester, find.byKey(const Key('backup-reviewed')));
  final box = find.descendant(
    of: find.byKey(const Key('backup-reviewed')),
    matching: find.byType(Checkbox),
  );
  await tester.ensureVisible(box);
  await tester.pumpAndSettle();
  await tester.tap(box);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'export validates password confirmation, clears fields and saves only service output',
    (tester) async {
      final store = _Store(), files = _Files();
      await _open(tester, store, files);
      await password(tester, value: 'short');
      await tap(tester, 'backup-export');
      expect(store.exports, 0);
      expect(find.byKey(const Key('backup-error')), findsOneWidget);
      await password(tester);
      await tap(tester, 'backup-export');
      expect(store.exports, 0);
      await password(tester, again: true);
      await tap(tester, 'backup-export');
      expect(store.exports, 1);
      expect(files.written, [1, 2, 3]);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('backup-password')))
            .controller!
            .text,
        isEmpty,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('backup-password')))
            .obscureText,
        isTrue,
      );
      expect(find.byKey(const Key('backup-notice')), findsOneWidget);
    },
  );
  testWidgets('cancelled open/save leaves the active dataset unchanged', (
    tester,
  ) async {
    final store = _Store(),
        files = _Files()
          ..incoming = null
          ..saveResult = false;
    await _open(tester, store, files);
    await password(tester);
    await tap(tester, 'backup-import');
    expect(store.prepares, 0);
    expect(store.activations, 0);
    await password(tester, again: true);
    await tap(tester, 'backup-export');
    expect(store.activations, 0);
    expect(find.textContaining('valinta peruttiin'), findsOneWidget);
  });
  for (final code in [
    'backupAuthentication',
    'invalidEncryptedBackup',
    'backupTooLarge',
  ]) {
    testWidgets('$code never exposes an activation or keeps the password', (
      tester,
    ) async {
      final store = _Store()..failure = code;
      await _open(tester, store, _Files());
      await password(tester);
      await tap(tester, 'backup-import');
      expect(find.byKey(const Key('backup-activate')), findsNothing);
      expect(store.activations, 0);
      expect(find.byKey(const Key('backup-error')), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('backup-password')))
            .controller!
            .text,
        isEmpty,
      );
    });
  }
  testWidgets(
    'validated preview requires explicit review before replacing the dataset',
    (tester) async {
      final store = _Store();
      await _open(tester, store, _Files());
      await password(tester);
      await tap(tester, 'backup-import');
      expect(find.textContaining('Kuitteja: 3'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('backup-activate')))
            .onPressed,
        isNull,
      );
      await review(tester);
      await tap(tester, 'backup-activate');
      expect(store.activations, 1);
      expect(store.tokens.single, same(store.candidate));
      expect(find.byType(BackupPage), findsNothing);
      expect(store.discarded, 0);
    },
  );
  for (final back in [false, true]) {
    testWidgets(
      'preview ${back ? 'back navigation' : 'cancellation'} removes staging without replacement',
      (tester) async {
        final store = _Store();
        await _open(tester, store, _Files());
        await password(tester);
        await tap(tester, 'backup-import');
        if (back) {
          await Navigator.of(tester.element(find.byType(BackupPage)))
              .maybePop();
          await tester.pumpAndSettle();
        } else {
          await tap(tester, 'backup-discard');
        }
        expect(store.discarded, 1);
        expect(store.activations, 0);
      },
    );
  }
  testWidgets('preparation in flight blocks back and double submit', (
    tester,
  ) async {
    final store = _Store();
    final gate = Completer<void>();
    store.gate = gate.future;
    await _open(tester, store, _Files());
    await password(tester);
    await tap(tester, 'backup-import');
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const Key('backup-import')))
          .onPressed,
      isNull,
    );
    await Navigator.of(tester.element(find.byType(BackupPage))).maybePop();
    await tester.pump();
    expect(find.byType(BackupPage), findsOneWidget);
    expect(store.prepares, 1);
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('backup-activate')), findsOneWidget);
  });
  testWidgets('late preparation after route disposal removes its candidate', (
    tester,
  ) async {
    final store = _Store();
    final gate = Completer<void>();
    store.gate = gate.future;
    await _open(tester, store, _Files());
    await password(tester);
    await tap(tester, 'backup-import');
    await tester.pumpWidget(const SizedBox());
    gate.complete();
    await tester.pumpAndSettle();
    expect(store.discarded, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'stale replacement disables retry and retains the current dataset',
    (tester) async {
      final store = _Store();
      await _open(tester, store, _Files());
      await password(tester);
      await tap(tester, 'backup-import');
      await review(tester);
      store.failure = 'staleRestore';
      await tap(tester, 'backup-activate');
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('backup-activate')))
            .onPressed,
        isNull,
      );
      await tap(tester, 'backup-discard');
      expect(store.discarded, 1);
    },
  );
  testWidgets(
    'failed activation retries the same candidate and blocks dismissal during retry',
    (tester) async {
      final store = _Store();
      await _open(tester, store, _Files());
      await password(tester);
      await tap(tester, 'backup-import');
      await review(tester);
      store.failure = 'workspaceActivation';
      await tap(tester, 'backup-activate');
      store.failure = null;
      final gate = Completer<void>();
      store.gate = gate.future;
      await tap(tester, 'backup-activate');
      await Navigator.of(tester.element(find.byType(BackupPage))).maybePop();
      await tester.pump();
      expect(find.byType(BackupPage), findsOneWidget);
      gate.complete();
      await tester.pumpAndSettle();
      expect(store.tokens, everyElement(same(store.candidate)));
      expect(find.byType(BackupPage), findsNothing);
    },
  );
  testWidgets(
    'returning to the previous local dataset requires a separate confirmation',
    (tester) async {
      final store = _Store()..canReturnToPrevious = true;
      await _open(tester, store, _Files());
      await tap(tester, 'backup-previous');
      await tap(tester, 'backup-confirm-previous');
      expect(store.previous, 1);
      expect(find.byType(BackupPage), findsNothing);
    },
  );
  testWidgets(
    'startup recovery is explicit and restores normal home actions after activation',
    (tester) async {
      final store = _Store()..datasetAvailable = false;
      await tester.pumpWidget(
        ReceiptReaderApp(
          storageOpener: () async =>
              throw const StorageFailure('corruptDatabase'),
          recoveryOpener: () async => store,
          backupFiles: _Files(),
        ),
      );
      await tester.pumpAndSettle();
      await tap(tester, 'open-backup-recovery');
      expect(find.byKey(const Key('open-history')), findsNothing);
      await tap(tester, 'open-backups');
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('backup-export')))
            .onPressed,
        isNull,
      );
      await password(tester);
      await tap(tester, 'backup-import');
      await review(tester);
      await tap(tester, 'backup-activate');
      expect(find.byKey(const Key('open-history')), findsOneWidget);
    },
  );
  testWidgets('backup preview fits 320 pixels with doubled text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final store = _Store();
    await _open(tester, store, _Files());
    await password(tester);
    await tap(tester, 'backup-import');
    await review(tester);
    await tap(tester, 'backup-activate');
    expect(tester.takeException(), isNull);
  });
}
