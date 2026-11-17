import 'dart:convert';
import 'dart:io';

import 'package:receipt_storage/receipt_storage.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

Future<void> main(List<String> arguments) async {
  final workspace = await ReceiptWorkspace.open(Directory(arguments[0]));
  final fixture = jsonDecode(
    File('test/fixtures/protected_backup_v1.json').readAsStringSync(),
  ) as Map;
  final preview = await workspace.prepare(
    base64Decode(fixture['encrypted_base64'] as String),
    fixture['password'] as String,
  );
  if (arguments[1] == 'afterCommit') {
    await workspace.activate(preview);
  } else {
    final registry = sqlite.sqlite3.open('${arguments[0]}/workspace.sqlite');
    final name = preview.restored.directory.uri.pathSegments
        .where((s) => s.isNotEmpty)
        .last;
    final path = '$name/receipts.sqlite';
    registry.execute('BEGIN IMMEDIATE');
    registry.execute('INSERT INTO slots VALUES (?)', [path]);
    registry.execute(
      'UPDATE workspace_state SET previous = active, active = ?, generation = generation + 1',
      [path],
    );
  }
  exit(0); // Deliberately bypass connection close and all cleanup.
}
