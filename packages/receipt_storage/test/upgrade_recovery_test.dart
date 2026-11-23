import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:test/test.dart';

import 'support/upgrade_rehearsal.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'migration-recovery-test-',
    );
  });
  tearDown(() async {
    if (directory.parent.absolute.path != Directory.systemTemp.absolute.path ||
        !directory.path.contains('migration-recovery-test-')) {
      throw StateError('unexpected_test_directory');
    }
    await directory.delete(recursive: true);
  });
  for (final version in [1, 2, 3, 4, 5, 6]) {
    test(
      'v$version upgrade, exact analytics, encrypted recovery and retained history',
      () => rehearseUpgrade(directory, version),
    );
  }
  test(
    'future schemas and corrupt projections are refused without resetting data',
    () => rehearseRefusal(directory),
  );
}
