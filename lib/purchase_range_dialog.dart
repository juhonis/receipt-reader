import 'package:material_ui/material_ui.dart';
import 'package:receipt_domain/receipt_domain.dart';

import 'l10n/generated/app_localizations.dart';
import 'receipt_format.dart';

class PurchaseRangeDialog extends StatefulWidget {
  const PurchaseRangeDialog({super.key, required this.range});
  final PurchaseDateRange range;
  @override
  State<PurchaseRangeDialog> createState() => _PurchaseRangeDialogState();
}

class _PurchaseRangeDialogState extends State<PurchaseRangeDialog> {
  final _form = GlobalKey<FormState>();
  late final _from = TextEditingController(
    text: widget.range.fromDate == null
        ? ''
        : receiptDateText(widget.range.fromDate!),
  );
  late final _through = TextEditingController(
    text: widget.range.throughDate == null
        ? ''
        : receiptDateText(widget.range.throughDate!),
  );
  String? _error;
  @override
  void dispose() {
    _from.dispose();
    _through.dispose();
    super.dispose();
  }

  String? _validate(String? text) {
    if (text == null || text.trim().isEmpty) return null;
    try {
      if (StoredReceiptDate.parse(text.trim()).hour == null) return null;
    } on ReceiptDataException {
      /* Show the localized field error. */
    }
    return AppLocalizations.of(context)!.historyDateInvalid;
  }

  void _apply() {
    if (!_form.currentState!.validate()) return;
    try {
      final range = PurchaseDateRange(
        fromDate: _from.text.trim().isEmpty
            ? null
            : StoredReceiptDate.parse(_from.text.trim()),
        throughDate: _through.text.trim().isEmpty
            ? null
            : StoredReceiptDate.parse(_through.text.trim()),
      );
      Navigator.pop(context, range);
    } on ReceiptDataException {
      setState(
        () => _error = AppLocalizations.of(context)!.historyDateRangeInvalid,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(s.purchaseDateRange),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(s.purchaseDateHint),
                TextFormField(
                  key: const Key('purchase-from'),
                  controller: _from,
                  decoration: InputDecoration(labelText: s.historyFromDate),
                  validator: _validate,
                  keyboardType: TextInputType.datetime,
                ),
                TextFormField(
                  key: const Key('purchase-through'),
                  controller: _through,
                  decoration: InputDecoration(labelText: s.historyThroughDate),
                  validator: _validate,
                  keyboardType: TextInputType.datetime,
                  onFieldSubmitted: (_) => _apply(),
                ),
                if (_error != null) Text(_error!),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(s.catalogClose),
        ),
        FilledButton(
          key: const Key('purchase-range-apply'),
          onPressed: _apply,
          child: Text(s.historyApplyFilters),
        ),
      ],
    );
  }
}
