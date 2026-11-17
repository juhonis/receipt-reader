import 'dart:io';
import 'dart:typed_data';

import 'package:receipt_domain/receipt_domain.dart';
import 'package:crypto/crypto.dart' show sha256;
import 'package:sqlite3/sqlite3.dart' as sqlite;

import 'protected_backup.dart';
import 'repository.dart';

/// A validated, closed restore candidate, bound to the dataset state reviewed
/// before preparation. It is owned by exactly one workspace and one activation.
final class RestorePreview {
  RestorePreview._(this.restored, this._stamp, this._digest);
  final String _digest;
  final RestoredReceiptBackup restored;
  final (String, int, DurableId?, BigInt?) _stamp;
  int get receipts => restored.receiptCount;
  int get deleted => restored.deletedReceiptCount;
  int get events => restored.eventCount;
}

/// One exclusive application workspace. Receipt DBs are never renamed or replaced.
/// A separate FULL/WAL SQLite registry atomically selects the active closed slot;
/// the previous slot and all earlier activated slots remain intact.
final class ReceiptWorkspace {
  ReceiptWorkspace._(this.directory, this._lease, this._registry);
  final Directory directory;
  final RandomAccessFile _lease;
  final sqlite.Database _registry;
  static final _openRoots = <String>{};
  final _previews = <RestorePreview>{};
  ReceiptRepository? _repository;
  bool _poisoned = false;
  bool get datasetAvailable => _repository != null && !_poisoned;
  bool get usable => !_poisoned && !_closed;
  ReceiptRepository get repository =>
      _repository ??
      (throw const StorageFailure('workspaceDatasetUnavailable'));
  late String _active;
  late int _generation;
  String? _previous;
  bool _closed = false;
  bool get canReturnToPrevious => _previous != null;
  String get _rootKey =>
      Platform.isWindows ? directory.path.toLowerCase() : directory.path;

  static Future<ReceiptWorkspace> open(
    Directory requested, {
    bool recoverActive = false,
  }) async {
    await requested.create(recursive: true);
    final root = Directory(await requested.resolveSymbolicLinks());
    final rootKey = Platform.isWindows ? root.path.toLowerCase() : root.path;
    if (!_openRoots.add(rootKey)) throw const StorageFailure('workspaceBusy');
    RandomAccessFile? lease;
    sqlite.Database? registry;
    ReceiptWorkspace? workspace;
    try {
      lease = await File('${root.path}/workspace.lock')
          .open(mode: FileMode.append);
      await lease.lock(FileLock.exclusive);
      registry = sqlite.sqlite3.open('${root.path}/workspace.sqlite');
      registry.execute('PRAGMA foreign_keys = ON');
      registry.execute('PRAGMA journal_mode = WAL');
      registry.execute('PRAGMA synchronous = FULL');
      if (registry.userVersion == 0) {
        if (registry
            .select("SELECT name FROM sqlite_schema WHERE type = 'table'")
            .isNotEmpty) {
          throw const StorageFailure('workspaceVersion');
        }
        registry.execute('BEGIN IMMEDIATE');
        try {
          registry.execute(
            'CREATE TABLE slots (path TEXT PRIMARY KEY NOT NULL) STRICT',
          );
          registry.execute(
            'CREATE TABLE workspace_state (singleton INTEGER PRIMARY KEY CHECK (singleton = 1), active TEXT REFERENCES slots(path), previous TEXT REFERENCES slots(path), generation INTEGER NOT NULL CHECK (generation >= 0)) STRICT',
          );
          registry.execute(
            'INSERT INTO workspace_state VALUES (1, NULL, NULL, 0)',
          );
          registry.execute('PRAGMA user_version = 1');
          registry.execute('COMMIT');
        } catch (_) {
          try {
            registry.execute('ROLLBACK');
          } catch (_) {}
          rethrow;
        }
      }
      if (registry.userVersion != 1) {
        throw const StorageFailure('workspaceVersion');
      }
      if (registry.select('PRAGMA integrity_check').single.values.single !=
              'ok' ||
          registry.select('PRAGMA foreign_key_check').isNotEmpty ||
          registry.select('PRAGMA foreign_keys').single.values.single != 1 ||
          registry.select('PRAGMA synchronous').single.values.single != 2) {
        throw const StorageFailure('workspaceIntegrity');
      }
      workspace = ReceiptWorkspace._(root, lease, registry);
      final state = workspace._state;
      workspace._generation = state['generation']! as int;
      if (state['active'] == null) {
        if (state['previous'] != null || workspace._generation != 0) {
          throw const StorageFailure('workspaceIntegrity');
        }
        try {
          workspace._repository = await ReceiptRepository.open(
            File('${root.path}/receipts.sqlite'),
          );
        } on StorageFailure {
          if (!recoverActive) rethrow;
        }
        workspace._active = 'receipts.sqlite';
        workspace._commit('receipts.sqlite', null, initial: true);
      } else {
        workspace._active = workspace._slot(state['active']);
        workspace._previous = state['previous'] == null
            ? null
            : workspace._slot(state['previous']);
        try {
          workspace._repository = await workspace._openSlot(workspace._active);
        } on StorageFailure {
          if (!recoverActive) rethrow;
        }
      }
      await workspace._cleanupOrphans();
      return workspace;
    } catch (error) {
      // A repository may have opened before registry initialization failed.
      if (workspace != null) {
        try {
          await workspace._repository?.close();
        } catch (_) {}
      }
      registry?.close();
      if (lease != null) {
        try {
          await lease.unlock();
        } catch (_) {}
        await lease.close();
      }
      _openRoots.remove(rootKey);
      if (error is StorageFailure) rethrow;
      throw const StorageFailure('workspaceOpen');
    }
  }

  Map<String, Object?> get _state {
    final rows = _registry.select('SELECT * FROM workspace_state');
    if (rows.length != 1) throw const StorageFailure('workspaceIntegrity');
    return Map<String, Object?>.from(rows.single);
  }

  String _slot(Object? value) {
    if (value is! String ||
        (value != 'receipts.sqlite' &&
            !RegExp(r'^receipt-restore-[A-Za-z0-9_-]+/receipts\.sqlite$')
                .hasMatch(value))) {
      throw const StorageFailure('workspacePath');
    }
    return value;
  }

  Future<ReceiptRepository> _openSlot(String slot) async {
    final file = File('${directory.path}/${_slot(slot)}');
    if (!await file.exists()) throw const StorageFailure('workspaceMissing');
    return ReceiptRepository.open(file);
  }

  Future<(String, int, DurableId?, BigInt?)> _stamp() async {
    final identity = await _repository?.identity();
    return (
      _active,
      _generation,
      identity?.deviceId,
      identity?.nextLocalSequence,
    );
  }

  Future<Uint8List> exportProtected(String password) async {
    ProtectedBackup.checkPassword(password);
    final bytes = await repository.exportBackup();
    try {
      return await ProtectedBackup.encrypt(bytes, password);
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  Future<RestorePreview> prepare(Uint8List file, String password) async {
    final stamp = await _stamp();
    final bytes = await ProtectedBackup.decrypt(file, password);
    try {
      final result = await ReceiptRepository.restoreBackup(
        bytes,
        stagingParent: directory,
      );
      final preview = RestorePreview._(
        result,
        stamp,
        sha256.convert(bytes).toString(),
      );
      _previews.add(preview);
      return preview;
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  Future<void> activate(RestorePreview preview) async {
    if (!_previews.contains(preview)) {
      throw const StorageFailure('restoreOwnership');
    }
    if (preview._stamp != await _stamp()) {
      throw const StorageFailure('staleRestore');
    }
    final parentName = preview.restored.directory.uri.pathSegments
        .where((s) => s.isNotEmpty)
        .last;
    final slot = _slot('$parentName/receipts.sqlite');
    await _switch(slot, reviewed: preview);
    _previews.remove(preview);
  }

  Future<void> returnToPrevious() async {
    final previous = _previous;
    if (previous == null) throw const StorageFailure('noPreviousDataset');
    await _switch(previous);
  }

  Future<void> _switch(String slot, {RestorePreview? reviewed}) async {
    final candidate = await _openSlot(slot);
    final prior = _repository;
    try {
      if (reviewed != null) {
        final identity = await candidate.identity();
        final expected = reviewed.restored.identity;
        if (identity.deviceId != expected.deviceId ||
            identity.datasetId != expected.datasetId ||
            identity.nextLocalSequence != expected.nextLocalSequence ||
            sha256.convert(await candidate.exportBackup()).toString() !=
                reviewed._digest) {
          throw const StorageFailure('staleRestore');
        }
      }
      _commit(slot, _active);
    } catch (_) {
      await candidate.close();
      rethrow;
    }
    _repository = candidate;
    // Selection has committed. Failure closing an old read connection cannot
    // turn that durable success into a retry of a different activation.
    try {
      await prior?.close();
    } catch (_) {}
  }

  void _commit(String slot, String? previous, {bool initial = false}) {
    if (_generation >= 9223372036854775807) {
      throw const StorageFailure('workspaceExhausted');
    }
    final next = _generation + 1;
    try {
      _registry.execute('BEGIN IMMEDIATE');
      final state = _state;
      if (state['generation'] != _generation ||
          (!initial && state['active'] != _active)) {
        throw const StorageFailure('staleRestore');
      }
      _registry.execute('INSERT OR IGNORE INTO slots VALUES (?)', [slot]);
      _registry.execute(
        'UPDATE workspace_state SET active = ?, previous = ?, generation = ? WHERE singleton = 1',
        [slot, previous, next],
      );
      _registry.execute('COMMIT');
    } catch (error) {
      try {
        _registry.execute('ROLLBACK');
      } catch (_) {}
      // Resolve a response lost after COMMIT by its exact persisted selection.
      Map<String, Object?> state;
      try {
        state = _state;
      } catch (_) {
        _poisoned = true;
        throw const StorageFailure('workspaceRestart');
      }
      if (state['active'] != slot ||
          state['generation'] != next ||
          state['previous'] != previous) {
        if (error is StorageFailure) rethrow;
        throw const StorageFailure('workspaceActivation');
      }
    }
    _active = slot;
    _previous = previous;
    _generation = next;
  }

  Future<void> discard(RestorePreview preview) async {
    if (!_previews.remove(preview)) return;
    await _removeStaging(preview.restored.directory);
  }

  Future<void> _removeStaging(Directory target) async {
    final slot = target.uri.pathSegments.where((s) => s.isNotEmpty).last;
    _slot('$slot/receipts.sqlite');
    if (target.parent.absolute.path != directory.absolute.path ||
        await FileSystemEntity.isLink(target.path)) {
      throw const StorageFailure('workspacePath');
    }
    if (_registry.select('SELECT path FROM slots WHERE path = ?', [
      '$slot/receipts.sqlite',
    ]).isNotEmpty) {
      return;
    }
    if (await target.exists()) await target.delete(recursive: true);
  }

  Future<void> _cleanupOrphans() async {
    final retained = _registry
        .select('SELECT path FROM slots')
        .map((r) => _slot(r['path']))
        .toSet();
    await for (final entry in directory.list(followLinks: false)) {
      if (entry is! Directory) continue;
      final name = entry.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (!RegExp(r'^receipt-restore-[A-Za-z0-9_-]+$').hasMatch(name)) continue;
      if (!retained.contains('$name/receipts.sqlite')) {
        await _removeStaging(entry);
      }
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _repository?.close();
      for (final preview in _previews.toList()) {
        await discard(preview);
      }
    } finally {
      _registry.close();
      try {
        await _lease.unlock();
      } finally {
        await _lease.close();
        _openRoots.remove(_rootKey);
      }
    }
  }
}
