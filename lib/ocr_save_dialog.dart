import 'package:material_ui/material_ui.dart';
import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_storage/receipt_storage.dart' show StorageFailure;

import 'l10n/generated/app_localizations.dart';
import 'local_store.dart';

/// Holds one immutable confirmed command until success or explicit exit to history.
/// No edit/re-approval or image disposal occurs during an uncertain retry.
class OcrSaveDialog extends StatefulWidget {
  const OcrSaveDialog({super.key, required this.store, required this.command});
  final LocalStore store;
  final ReviewedReceipt command;
  @override
  State<OcrSaveDialog> createState() => _OcrSaveDialogState();
}

class _OcrSaveDialogState extends State<OcrSaveDialog> {
  bool _saving = false, _failed = false, _stale = false;
  @override
  void initState() {
    super.initState();
    _save();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _failed = false;
    });
    try {
      await widget.store.saveOcr(widget.command);
      if (mounted) Navigator.pop(context);
    } on StorageFailure catch (error) {
      if (mounted) {
        setState(() {
          _failed = true;
          _stale =
              {
                'staleProduct',
                'missingProduct',
                'crossStoreProduct',
              }.contains(error.code) ||
              error.code == 'staleReceipt' ||
              error.code == 'staleBranch' ||
              error.code == 'receiptDeleted';
        });
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text(s.saveReceipt),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_saving) const LinearProgressIndicator(),
              Text(
                _stale
                    ? s.manualCorrectionStale
                    : _failed
                    ? s.manualSaveFailed
                    : s.savingReceipt,
              ),
              if (!_stale) Text(s.pendingSaveNotice),
            ],
          ),
        ),
        actions: [
          if (_failed)
            TextButton(
              key: const Key('ocr-close-pending'),
              onPressed: () => Navigator.pop(context),
              child: Text(s.closeToHistory),
            ),
          if (_failed && !_stale)
            FilledButton(
              key: const Key('ocr-retry-save'),
              onPressed: _saving ? null : _save,
              child: Text(s.retrySave),
            ),
        ],
      ),
    );
  }
}
