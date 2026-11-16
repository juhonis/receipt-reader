import 'package:material_ui/material_ui.dart';
import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart' show formatCents;
import 'package:receipt_storage/receipt_storage.dart';

import 'l10n/generated/app_localizations.dart';
import 'local_store.dart';
import 'manual_receipt_page.dart' show receiptAppVersion;
import 'receipt_format.dart';

/// One explicit confirmation; an uncertain write retains the immutable command.
class ReceiptDeletionDialog extends StatefulWidget {
  const ReceiptDeletionDialog({
    super.key,
    required this.receipt,
    required this.store,
  });
  final StoredReceipt receipt;
  final LocalStore store;
  @override
  State<ReceiptDeletionDialog> createState() => _ReceiptDeletionDialogState();
}

class _ReceiptDeletionDialogState extends State<ReceiptDeletionDialog> {
  bool _reviewed = false, _saving = false, _failed = false, _stale = false;
  ReviewedReceiptDeletion? _pending;

  Future<void> _delete() async {
    if (_saving || (!_reviewed && _pending == null)) return;
    _pending ??=
        ReceiptDeletionChecks(
          document: widget.receipt.document,
          expectedHead: widget.receipt.revision,
          mutationId: DurableId.generate(),
          receiptReviewed: _reviewed,
        ).confirm(
          deletedAtMs: BigInt.from(
            DateTime.now().toUtc().millisecondsSinceEpoch,
          ),
          appVersion: receiptAppVersion,
        );
    setState(() {
      _saving = true;
      _failed = false;
    });
    try {
      await widget.store.deleteReceipt(_pending!);
      if (mounted) Navigator.pop(context, true);
    } on StorageFailure catch (error) {
      if (mounted) {
        setState(() {
          _failed = true;
          _stale =
              error.code == 'staleReceipt' || error.code == 'receiptDeleted';
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
    final snapshot = widget.receipt.document.snapshot;
    final locked = _pending != null;
    return PopScope(
      canPop: !locked,
      child: AlertDialog(
        title: Text(s.deleteReceiptTitle),
        scrollable: true,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(snapshot.branch.name),
            Text(receiptDateText(snapshot.date)),
            Text('${formatCents(snapshot.totalCents)} €'),
            Text(s.deleteReceiptNotice),
            if (!locked)
              CheckboxListTile(
                key: const Key('delete-receipt-reviewed'),
                title: Text(s.deleteReceiptReviewed),
                value: _reviewed,
                onChanged: (v) => setState(() => _reviewed = v ?? false),
              ),
            if (_saving) const LinearProgressIndicator(),
            if (_failed)
              Text(_stale ? s.deleteReceiptStale : s.deleteReceiptFailed),
            if (locked && !_stale) Text(s.deleteReceiptPending),
          ],
        ),
        actions: [
          if (!locked)
            TextButton(
              key: const Key('delete-receipt-cancel'),
              onPressed: () => Navigator.pop(context, false),
              child: Text(s.cancelAction),
            ),
          if (_failed)
            TextButton(
              key: const Key('delete-receipt-close'),
              onPressed: () => Navigator.pop(context, true),
              child: Text(s.closeToHistory),
            ),
          if (!_stale)
            FilledButton(
              key: const Key('delete-receipt-confirm'),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              onPressed: !_saving && (_reviewed || locked) ? _delete : null,
              child: Text(_failed ? s.retrySave : s.deleteReceiptAction),
            ),
        ],
      ),
    );
  }
}
