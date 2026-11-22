import 'package:material_ui/material_ui.dart';
import 'package:receipt_domain/receipt_domain.dart';

import 'l10n/generated/app_localizations.dart';
import 'receipt_format.dart';

class DashboardRangeDialog extends StatefulWidget {
  const DashboardRangeDialog({
    super.key,
    required this.first,
    required this.last,
    required this.today,
  });
  final StoredReceiptDate first, last, today;
  @override
  State<DashboardRangeDialog> createState() => _DashboardRangeDialogState();
}

class _DashboardRangeDialogState extends State<DashboardRangeDialog> {
  final _form = GlobalKey<FormState>();
  late final _first = TextEditingController(
    text: receiptDateText(widget.first),
  );
  late final _last = TextEditingController(text: receiptDateText(widget.last));
  String? _error;
  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    super.dispose();
  }

  String? _validate(String? value) {
    try {
      final date = StoredReceiptDate.parse(value?.trim() ?? '');
      if (date.hour == null &&
          purchaseCalendarDay(date) <= purchaseCalendarDay(widget.today)) {
        return null;
      }
    } on ReceiptDataException {
      /* Show the localized field error. */
    }
    return AppLocalizations.of(context)!.dashboardRangeInvalid;
  }

  void _apply() {
    if (!_form.currentState!.validate()) return;
    final first = StoredReceiptDate.parse(_first.text.trim());
    final last = StoredReceiptDate.parse(_last.text.trim());
    if (purchaseCalendarDay(first) > purchaseCalendarDay(last)) {
      setState(
        () => _error = AppLocalizations.of(context)!.historyDateRangeInvalid,
      );
      return;
    }
    Navigator.pop(
      context,
      PurchaseDateRange(fromDate: first, throughDate: last),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(s.dashboardCustom),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(s.dashboardCustomNotice),
                TextFormField(
                  key: const Key('dashboard-custom-from'),
                  controller: _first,
                  decoration: InputDecoration(labelText: s.historyFromDate),
                  validator: _validate,
                  keyboardType: TextInputType.datetime,
                ),
                TextFormField(
                  key: const Key('dashboard-custom-through'),
                  controller: _last,
                  decoration: InputDecoration(labelText: s.historyThroughDate),
                  validator: _validate,
                  keyboardType: TextInputType.datetime,
                  onFieldSubmitted: (_) => _apply(),
                ),
                if (_error != null)
                  Text(_error!, key: const Key('dashboard-custom-error')),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('dashboard-custom-cancel'),
          onPressed: () => Navigator.pop(context),
          child: Text(s.cancelAction),
        ),
        FilledButton(
          key: const Key('dashboard-custom-apply'),
          onPressed: _apply,
          child: Text(s.historyApplyFilters),
        ),
      ],
    );
  }
}
