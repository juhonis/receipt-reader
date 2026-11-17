import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:receipt_storage/receipt_storage.dart';

import 'backup_files.dart';
import 'backup_service.dart';
import 'l10n/generated/app_localizations.dart';

class BackupPage extends StatefulWidget {
  const BackupPage({super.key, required this.service, required this.files});
  final BackupService service;
  final BackupFiles files;
  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  final _password = TextEditingController(), _again = TextEditingController();
  BackupCandidate? _candidate;
  bool _busy = false, _reviewed = false, _stale = false;
  String? _error, _notice;
  AppLocalizations get s => AppLocalizations.of(context)!;

  String? _takePassword({bool exporting = false}) {
    final password = _password.text;
    try {
      ProtectedBackup.checkPassword(password);
    } catch (_) {
      setState(() => _error = s.backupPasswordRule);
      return null;
    }
    if (exporting && password != _again.text) {
      setState(() => _error = s.backupPasswordsDiffer);
      return null;
    }
    _password.clear();
    _again.clear();
    FocusManager.instance.primaryFocus?.unfocus();
    return password;
  }

  Future<void> _work(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await action();
    } on StorageFailure catch (error) {
      if (mounted) {
        setState(() {
          _stale = error.code == 'staleRestore';
          _error = switch (error.code) {
            'backupAuthentication' => s.backupAuthentication,
            'backupFileExists' => s.backupFileExists,
            'backupFile' => s.backupFileError,
            'backupPassword' => s.backupPasswordRule,
            'staleRestore' => s.backupStale,
            'invalidEncryptedBackup' ||
            'invalidBackup' ||
            'unsupportedBackup' ||
            'backupTooLarge' ||
            'backupChecksum' ||
            'backupManifest' ||
            'invalidData' => s.backupInvalid,
            _ => s.backupFailed,
          };
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = s.backupFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export() async {
    final password = _takePassword(exporting: true);
    if (password == null) return;
    await _work(() async {
      final bytes = await widget.service.exportProtected(password);
      try {
        if (!mounted) return;
        final saved = await widget.files.save(bytes);
        if (mounted) {
          setState(() => _notice = saved ? s.backupSaved : s.backupCancelled);
        }
      } finally {
        bytes.fillRange(0, bytes.length, 0);
      }
    });
  }

  Future<void> _import() async {
    final password = _takePassword();
    if (password == null) return;
    await _work(() async {
      final bytes = await widget.files.read();
      if (bytes == null) {
        if (mounted) setState(() => _notice = s.backupCancelled);
        return;
      }
      final candidate = await widget.service.prepareProtected(bytes, password);
      if (!mounted) {
        await widget.service.discardBackup(candidate);
        return;
      }
      setState(() {
        _candidate = candidate;
        _reviewed = false;
        _stale = false;
      });
    });
  }

  Future<void> _discard() => _work(() async {
    await widget.service.discardBackup(_candidate!);
    if (mounted) {
      setState(() {
        _candidate = null;
        _reviewed = false;
        _stale = false;
      });
    }
  });

  Future<void> _activate() => _work(() async {
    await widget.service.activateBackup(_candidate!);
    _candidate = null;
    if (mounted) Navigator.pop(context, true);
  });

  Future<void> _previous() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(s.backupPrevious),
        content: Text(s.backupPreviousNotice),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(s.cancelAction),
          ),
          FilledButton(
            key: const Key('backup-confirm-previous'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.backupConfirmPrevious),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _work(() async {
        await widget.service.returnToPrevious();
        if (mounted) Navigator.pop(context, true);
      });
    }
  }

  @override
  void dispose() {
    _password.dispose();
    _again.dispose();
    final candidate = _candidate;
    if (candidate != null) {
      unawaited(
        widget.service.discardBackup(candidate).catchError((Object _) {}),
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final candidate = _candidate;
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(title: Text(s.backupTitle)),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(s.backupNotice),
              const SizedBox(height: 16),
              if (candidate == null) ...[
                TextField(
                  key: const Key('backup-password'),
                  controller: _password,
                  obscureText: true,
                  enabled: !_busy,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(labelText: s.backupPassword),
                ),
                Text(s.backupPasswordRule),
                TextField(
                  key: const Key('backup-password-again'),
                  controller: _again,
                  obscureText: true,
                  enabled: !_busy,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(labelText: s.backupPasswordAgain),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  key: const Key('backup-export'),
                  onPressed: _busy || !widget.service.datasetAvailable
                      ? null
                      : _export,
                  child: Text(s.backupExport),
                ),
                OutlinedButton(
                  key: const Key('backup-import'),
                  onPressed: _busy ? null : _import,
                  child: Text(s.backupImport),
                ),
                if (widget.service.canReturnToPrevious)
                  TextButton(
                    key: const Key('backup-previous'),
                    onPressed: _busy ? null : _previous,
                    child: Text(s.backupPrevious),
                  ),
              ] else ...[
                Text(
                  s.backupPreview,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text(
                  s.backupCounts(
                    candidate.receipts,
                    candidate.deleted,
                    candidate.events,
                  ),
                ),
                Text(s.backupReplaceNotice),
                CheckboxListTile(
                  key: const Key('backup-reviewed'),
                  value: _reviewed,
                  onChanged: _busy
                      ? null
                      : (v) => setState(() => _reviewed = v ?? false),
                  title: Text(s.backupReviewed),
                ),
                FilledButton(
                  key: const Key('backup-activate'),
                  onPressed: !_busy && _reviewed && !_stale ? _activate : null,
                  child: Text(s.backupActivate),
                ),
                TextButton(
                  key: const Key('backup-discard'),
                  onPressed: _busy ? null : _discard,
                  child: Text(s.backupDiscard),
                ),
              ],
              if (_busy) ...[
                const LinearProgressIndicator(),
                Text(s.backupBusy),
              ],
              if (_error != null) Text(_error!, key: const Key('backup-error')),
              if (_notice != null)
                Text(_notice!, key: const Key('backup-notice')),
            ],
          ),
        ),
      ),
    );
  }
}
