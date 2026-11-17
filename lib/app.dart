import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart'
    show GlobalCupertinoLocalizations;
import 'package:flutter_localizations/flutter_localizations.dart'
    show GlobalWidgetsLocalizations;
import 'package:material_ui/material_ui.dart';

import 'l10n/generated/app_localizations.dart';
import 'review_page.dart';
import 'receipt_import.dart';
import 'local_store.dart';
import 'manual_receipt_page.dart';
import 'history_page.dart';
import 'backup_files.dart';
import 'backup_page.dart';
import 'backup_service.dart';

class ReceiptReaderApp extends StatelessWidget {
  const ReceiptReaderApp({
    super.key,
    this.imagePicker = pickReceiptImage,
    this.storageOpener,
    this.recoveryOpener,
    this.backupFiles = const NativeBackupFiles(),
  });
  final Future<LocalStore> Function()? storageOpener, recoveryOpener;
  final BackupFiles backupFiles;
  final Future<ReceiptEvidence?> Function() imagePicker;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('fi'),
      // Flutter's generated delegate list still uses the legacy UI shims.
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
      ),
      home: storageOpener == null
          ? _HomePage(imagePicker: imagePicker, backupFiles: backupFiles)
          : _StorageGate(
              opener: storageOpener!,
              recoveryOpener: recoveryOpener,
              imagePicker: imagePicker,
              backupFiles: backupFiles,
            ),
    );
  }
}

class _HomePage extends StatefulWidget {
  const _HomePage({
    required this.imagePicker,
    required this.backupFiles,
    this.store,
  });
  final BackupFiles backupFiles;
  final LocalStore? store;
  final Future<ReceiptEvidence?> Function() imagePicker;
  @override
  State<_HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<_HomePage> {
  bool _importing = false;
  ImportFailure? _failure;

  Future<void> _manual() async {
    final store = widget.store;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => store == null
            ? const ReviewPage()
            : ManualReceiptPage(store: store),
      ),
    );
    if (saved == true && mounted && store != null) await _history();
  }

  Future<void> _history() => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) =>
          HistoryPage(store: widget.store!, imagePicker: widget.imagePicker),
    ),
  );

  Future<void> _backup() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => BackupPage(
          service: widget.store! as BackupService,
          files: widget.backupFiles,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _import() async {
    if (_importing) return;
    setState(() {
      _importing = true;
      _failure = null;
    });
    try {
      final evidence = await widget.imagePicker();
      if (!mounted) {
        evidence?.dispose();
        return;
      }
      if (evidence != null) {
        bool? saved;
        try {
          saved = await Navigator.of(context).push<bool>(
            MaterialPageRoute<bool>(
              builder: (_) =>
                  ReviewPage(evidence: evidence, store: widget.store),
            ),
          );
        } finally {
          evidence.dispose();
        }
        if (saved == true && mounted && widget.store != null) await _history();
      }
    } on ReceiptImportException catch (error) {
      if (mounted) {
        setState(() {
          _failure = error.failure;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _failure = ImportFailure.unreadable;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _importing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context)!;
    final recovery =
        widget.store is BackupService &&
        !(widget.store! as BackupService).datasetAvailable;
    return Scaffold(
      appBar: AppBar(title: Text(strings.appTitle)),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.receipt_long_outlined, size: 64),
                  const SizedBox(height: 24),
                  Text(
                    strings.welcomeTitle,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.store == null
                        ? strings.developmentNotice
                        : strings.localStorageNotice,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  if (!recovery)
                    FilledButton.icon(
                      onPressed: _importing ? null : _import,
                      icon: const Icon(Icons.image_outlined),
                      label: Text(
                        _importing
                            ? strings.importLoading
                            : strings.importImage,
                      ),
                    ),
                  if (_failure != null)
                    Text(switch (_failure!) {
                      ImportFailure.tooLarge => strings.importTooLarge,
                      ImportFailure.unsupported => strings.importUnsupported,
                      ImportFailure.unreadable => strings.importUnreadable,
                    }),
                  const SizedBox(height: 12),
                  if (!recovery)
                    FilledButton(
                      onPressed: _manual,
                      child: Text(
                        widget.store == null
                            ? strings.startReview
                            : strings.manualEntryTitle,
                      ),
                    ),
                  if (widget.store != null && !recovery)
                    TextButton.icon(
                      key: const Key('open-history'),
                      onPressed: _history,
                      icon: const Icon(Icons.history),
                      label: Text(strings.historyTitle),
                    ),
                  if (recovery) Text(strings.backupRecoveryMode),
                  if (widget.store is BackupService)
                    TextButton.icon(
                      key: const Key("open-backups"),
                      onPressed: _backup,
                      icon: const Icon(Icons.backup_outlined),
                      label: Text(strings.backupTitle),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Opens once, retains the connection across routes, and closes even when the
/// widget is disposed before the asynchronous open completes. No reset fallback.
class _StorageGate extends StatefulWidget {
  const _StorageGate({
    required this.opener,
    required this.recoveryOpener,
    required this.imagePicker,
    required this.backupFiles,
  });
  final Future<LocalStore> Function()? recoveryOpener;
  final BackupFiles backupFiles;
  final Future<LocalStore> Function() opener;
  final Future<ReceiptEvidence?> Function() imagePicker;
  @override
  State<_StorageGate> createState() => _StorageGateState();
}

class _StorageGateState extends State<_StorageGate> {
  LocalStore? _store;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open({bool recovering = false}) async {
    setState(() => _failed = false);
    try {
      final store = await (recovering
          ? widget.recoveryOpener!
          : widget.opener)();
      if (!mounted) {
        await store.close();
        return;
      }
      setState(() => _store = store);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    final store = _store;
    if (store != null) unawaited(store.close().catchError((Object _) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_store case final store?) {
      return _HomePage(
        imagePicker: widget.imagePicker,
        store: store,
        backupFiles: widget.backupFiles,
      );
    }
    final s = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(s.appTitle)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!_failed) const CircularProgressIndicator(),
              Text(_failed ? s.storageOpenFailed : s.storageOpening),
              if (_failed)
                TextButton(
                  key: const Key('retry-storage'),
                  onPressed: _open,
                  child: Text(s.retryAction),
                ),
              if (_failed && widget.recoveryOpener != null)
                TextButton(
                  key: const Key("open-backup-recovery"),
                  onPressed: () => _open(recovering: true),
                  child: Text(s.backupRecovery),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
