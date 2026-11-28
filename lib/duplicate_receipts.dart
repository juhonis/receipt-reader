import 'package:material_ui/material_ui.dart';
import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart' show formatCents;
import 'package:receipt_storage/receipt_storage.dart';

import 'app_version.dart';
import 'l10n/generated/app_localizations.dart';
import 'local_store.dart';
import 'receipt_format.dart';

enum DuplicateSaveAction { keepNew, discardNew, replace }

class DuplicateSaveChoice {
  const DuplicateSaveChoice.keepNew()
    : action = DuplicateSaveAction.keepNew,
      deletion = null;
  const DuplicateSaveChoice.discardNew()
    : action = DuplicateSaveAction.discardNew,
      deletion = null;
  DuplicateSaveChoice.replace(StoredReceipt old)
    : action = DuplicateSaveAction.replace,
      deletion =
          ReceiptDeletionChecks(
            document: old.document,
            expectedHead: old.revision,
            mutationId: DurableId.generate(),
            receiptReviewed: true,
          ).confirm(
            deletedAtMs: BigInt.from(
              DateTime.now().toUtc().millisecondsSinceEpoch,
            ),
            appVersion: receiptAppVersion,
          );
  final DuplicateSaveAction action;
  final ReviewedReceiptDeletion? deletion;
}

Future<List<StoredReceipt>> findDuplicateReceipts(
  LocalStore store,
  ReceiptSnapshot incoming,
) async {
  final d = incoming.date;
  final day = StoredReceiptDate.parse('${d.day}.${d.month}.${d.year}');
  final filter = HistoryFilter(fromDate: day, throughDate: day);
  final matches = <StoredReceipt>[];
  for (var offset = 0; ; offset += 200) {
    final page = await store.history(
      limit: 200,
      offset: offset,
      filter: filter,
    );
    matches.addAll(
      page.where(
        (r) => receiptDuplicateReason(incoming, r.document.snapshot) != null,
      ),
    );
    if (page.length < 200) break;
  }
  return List.unmodifiable(matches);
}

/// Normal saves with no candidate add no dialog or extra confirmation. Lookup
/// failure cannot silently bypass review. Corrections never warn about themselves.
Future<DuplicateSaveChoice?> chooseDuplicateSave(
  BuildContext context,
  LocalStore store,
  ReviewedReceipt incoming,
) async {
  if (incoming.document.review.expectedHeads.isNotEmpty) {
    return const DuplicateSaveChoice.keepNew();
  }
  List<StoredReceipt>? matches;
  try {
    matches = await findDuplicateReceipts(store, incoming.document.snapshot);
  } catch (_) {
    /* Retry in the dialog. */
  }
  if (!context.mounted || !(ModalRoute.of(context)?.isCurrent ?? false)) {
    return null;
  }
  if (matches?.isEmpty ?? false) return const DuplicateSaveChoice.keepNew();
  return showDialog<DuplicateSaveChoice>(
    context: context,
    builder: (_) => _DuplicateDialog(
      store: store,
      incoming: incoming.document.snapshot,
      initial: matches,
    ),
  );
}

class _DuplicateDialog extends StatefulWidget {
  const _DuplicateDialog({
    required this.store,
    required this.incoming,
    required this.initial,
  });
  final LocalStore store;
  final ReceiptSnapshot incoming;
  final List<StoredReceipt>? initial;
  @override
  State<_DuplicateDialog> createState() => _DuplicateDialogState();
}

class _DuplicateDialogState extends State<_DuplicateDialog> {
  late List<StoredReceipt>? _matches = widget.initial;
  bool _loading = false;
  Future<void> _retry() async {
    setState(() => _loading = true);
    try {
      final matches = await findDuplicateReceipts(
        widget.store,
        widget.incoming,
      );
      if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? false)) return;
      if (matches.isEmpty) {
        Navigator.pop(context, const DuplicateSaveChoice.keepNew());
        return;
      }
      setState(() => _matches = matches);
    } catch (_) {
      if (mounted) setState(() => _matches = null);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    Widget summary(ReceiptSnapshot r) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(r.branch.name),
        Text(receiptDateText(r.date)),
        Text('${formatCents(r.totalCents)} €'),
        ExpansionTile(
          title: Text(s.duplicateItems(r.items.length)),
          children: [
            for (final item in r.items)
              Text('${item.name} · ${formatCents(item.cents)} €'),
          ],
        ),
      ],
    );
    return AlertDialog(
      title: Text(s.duplicateTitle),
      scrollable: true,
      content: SizedBox(
        width: 560,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(s.duplicateIncoming),
            summary(widget.incoming),
            if (_loading) const LinearProgressIndicator(),
            if (_matches == null) ...[
              Text(s.duplicateLookupFailed),
              TextButton(
                key: const Key('duplicate-retry-lookup'),
                onPressed: _loading ? null : _retry,
                child: Text(s.retryAction),
              ),
            ] else ...[
              Text(s.duplicateHint),
              for (final old in _matches!)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(s.duplicateExisting),
                        summary(old.document.snapshot),
                        Text(
                          receiptDuplicateReason(
                                    widget.incoming,
                                    old.document.snapshot,
                                  ) ==
                                  ReceiptDuplicateReason.sameMinute
                              ? s.duplicateSameMinute
                              : s.duplicateSameDay,
                        ),
                        OutlinedButton(
                          key: ValueKey(
                            'duplicate-replace-${old.document.snapshot.id.value}',
                          ),
                          onPressed:
                              _loading ||
                                  widget.store is! ReceiptReplacementStore
                              ? null
                              : () => Navigator.pop(
                                  context,
                                  DuplicateSaveChoice.replace(old),
                                ),
                          child: Text(s.duplicateReplace),
                        ),
                      ],
                    ),
                  ),
                ),
              Text(s.duplicateReplacementNotice),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('duplicate-cancel'),
          onPressed: () => Navigator.pop(context),
          child: Text(s.duplicateBack),
        ),
        if (_matches != null) ...[
          FilledButton(
            key: const Key('duplicate-discard-new'),
            onPressed: _loading
                ? null
                : () => Navigator.pop(
                    context,
                    const DuplicateSaveChoice.discardNew(),
                  ),
            child: Text(s.duplicateDiscardNew),
          ),
          TextButton(
            key: const Key('duplicate-keep-both'),
            onPressed: _loading
                ? null
                : () => Navigator.pop(
                    context,
                    const DuplicateSaveChoice.keepNew(),
                  ),
            child: Text(s.duplicateKeepBoth),
          ),
        ],
      ],
    );
  }
}
