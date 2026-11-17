import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:receipt_storage/receipt_storage.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:test/test.dart';

import 'support.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  final fixture = jsonDecode(
    File('test/fixtures/protected_backup_v1.json').readAsStringSync(),
  ) as Map;
  final password = fixture['password'] as String;
  final encrypted = base64Decode(fixture['encrypted_base64'] as String);
  Matcher fails(String code) =>
      throwsA(isA<StorageFailure>().having((e) => e.code, 'code', code));
  late Directory directory;
  ReceiptWorkspace? workspace;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'receipt-workspace-test-',
    );
  });
  tearDown(() async {
    await workspace?.close();
    workspace = null;
    await directory.delete(recursive: true);
  });
  Future<ReceiptWorkspace> open({bool recovery = false}) async => workspace =
      await ReceiptWorkspace.open(directory, recoverActive: recovery);

  test('adopts the existing receipt database without changing its dataset or device', () async {
    final legacy = await ReceiptRepository.open(
      File('${directory.path}/receipts.sqlite'),
    );
    await legacy.saveManual(command(snapshot()));
    final prior = await legacy.identity();
    final before = await legacy.exportBackup();
    await legacy.close();
    final current = await open();
    expect((await current.repository.identity()).deviceId, prior.deviceId);
    expect(await current.repository.exportBackup(), before);
    await expectLater(ReceiptWorkspace.open(directory), fails('workspaceBusy'));
  });
  test('activates a closed candidate, survives reopening and can return to the old dataset', () async {
    var current = await open();
    await current.repository.saveManual(command(snapshot()));
    final prior = await current.repository.identity();
    final preview = await current.prepare(encrypted, password);
    expect(await current.repository.history(), hasLength(1));
    await current.activate(preview);
    expect(await current.repository.history(), isEmpty);
    expect(
      (await current.repository.identity()).deviceId,
      preview.restored.identity.deviceId,
    );
    expect(current.canReturnToPrevious, isTrue);
    await current.discard(preview);
    expect(await preview.restored.databaseFile.exists(), isTrue);
    await current.close();
    workspace = null;
    current = await open();
    expect(await current.repository.history(), isEmpty);
    await current.returnToPrevious();
    expect((await current.repository.identity()).deviceId, prior.deviceId);
    expect(await current.repository.history(), hasLength(1));
    await current.returnToPrevious();
    expect(await current.repository.history(), isEmpty);
  });
  test('cancel deletes only owned staging and unknown previews cannot be activated', () async {
    final current = await open();
    final preview = await current.prepare(encrypted, password);
    await current.discard(preview);
    expect(await preview.restored.directory.exists(), isFalse);
    await expectLater(current.activate(preview), fails('restoreOwnership'));
    await current.repository.verifyIntegrity();
  });
  test('a local write after preview rejects stale replacement', () async {
    final current = await open();
    final preview = await current.prepare(encrypted, password);
    await current.repository.saveManual(command(snapshot()));
    await expectLater(current.activate(preview), fails('staleRestore'));
    expect(await current.repository.history(), hasLength(1));
    await current.discard(preview);
  });
  for (final mutateIdentity in [false, true]) {
    test(
      'rejects a staged ${mutateIdentity ? "identity" : "history"} changed after preview',
      () async {
        final current = await open();
        final preview = await current.prepare(encrypted, password);
        if (mutateIdentity) {
          final raw = sqlite.sqlite3.open(preview.restored.databaseFile.path);
          raw.execute('UPDATE dataset_state SET device_id = ?', [id(70).value]);
          raw.execute('UPDATE received_cursors SET origin_device_id = ?', [
            id(70).value,
          ]);
          raw.close();
        } else {
          final candidate = await ReceiptRepository.open(
            preview.restored.databaseFile,
          );
          await candidate.saveManual(command(snapshot()));
          await candidate.close();
        }
        await expectLater(current.activate(preview), fails('staleRestore'));
        expect(await current.repository.history(), isEmpty);
        expect(current.canReturnToPrevious, isFalse);
        await current.discard(preview);
        expect(await preview.restored.directory.exists(), isFalse);
      },
    );
  }

  test('registry failure rolls back selection and permits the identical activation retry', () async {
    final current = await open();
    await current.repository.saveManual(command(snapshot()));
    final preview = await current.prepare(encrypted, password);
    final registry = sqlite.sqlite3.open('${directory.path}/workspace.sqlite');
    try {
      registry.execute(
        "CREATE TRIGGER fail_activation BEFORE UPDATE ON workspace_state BEGIN SELECT RAISE(ABORT, 'PRIVATE FAILURE'); END",
      );
      await expectLater(
        current.activate(preview),
        fails('workspaceActivation'),
      );
      expect(await current.repository.history(), hasLength(1));
      expect(registry.select('SELECT * FROM slots'), hasLength(1));
      registry.execute('DROP TRIGGER fail_activation');
      await current.activate(preview);
      expect(await current.repository.history(), isEmpty);
    } finally {
      registry.close();
    }
  });
  test('explicit recovery can replace an unreadable dataset without deleting its original files', () async {
    var current = await open();
    await current.close();
    workspace = null;
    final original = File('${directory.path}/receipts.sqlite');
    final damaged = utf8.encode('SYNTHETIC DAMAGED DATABASE');
    await original.writeAsBytes(damaged, flush: true);
    await expectLater(
      ReceiptWorkspace.open(directory),
      throwsA(isA<StorageFailure>()),
    );
    current = await open(recovery: true);
    expect(current.datasetAvailable, isFalse);
    final preview = await current.prepare(encrypted, password);
    await current.activate(preview);
    expect(current.datasetAvailable, isTrue);
    expect(await original.readAsBytes(), damaged);
    await expectLater(
      current.returnToPrevious(),
      throwsA(isA<StorageFailure>()),
    );
    expect(await current.repository.history(), isEmpty);
  });
  test(
    'missing selected files fail instead of creating an empty replacement',
    () async {
      final current = await open();
      await current.close();
      workspace = null;
      final file = File('${directory.path}/receipts.sqlite');
      await file.delete();
      await expectLater(
        ReceiptWorkspace.open(directory),
        fails('workspaceMissing'),
      );
      expect(await file.exists(), isFalse);
    },
  );
  test('future registry versions are refused without resetting data', () async {
    final current = await open();
    await current.close();
    workspace = null;
    final raw = sqlite.sqlite3.open('${directory.path}/workspace.sqlite');
    raw.userVersion = 2;
    raw.close();
    await expectLater(
      ReceiptWorkspace.open(directory),
      fails('workspaceVersion'),
    );
    final check = sqlite.sqlite3.open('${directory.path}/workspace.sqlite');
    expect(check.userVersion, 2);
    check.close();
  });
  for (final phase in ['beforeCommit', 'afterCommit']) {
    test(
      'process exit $phase preserves the correct active slot and cleans only orphan staging',
      () async {
        var current = await open();
        await current.repository.saveManual(command(snapshot()));
        final original = await current.repository.identity();
        await current.close();
        workspace = null;
        final unrelated = await Directory('${directory.path}/unrelated')
            .create();
        await File('${unrelated.path}/keep').writeAsString('SYNTHETIC');
        final result = await Process.run(Platform.resolvedExecutable, [
          'run',
          'test/helpers/workspace_exit.dart',
          directory.path,
          phase,
        ]);
        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
        current = await open();
        expect(await File('${unrelated.path}/keep').exists(), isTrue);
        final staging = await directory
            .list()
            .where((e) => e.path.contains('receipt-restore-'))
            .toList();
        if (phase == 'beforeCommit') {
          expect(
            (await current.repository.identity()).deviceId,
            original.deviceId,
          );
          expect(await current.repository.history(), hasLength(1));
          expect(staging, isEmpty);
        } else {
          expect(await current.repository.history(), isEmpty);
          expect(staging, hasLength(1));
          await current.returnToPrevious();
          expect(
            (await current.repository.identity()).deviceId,
            original.deviceId,
          );
        }
      },
    );
  }
}
