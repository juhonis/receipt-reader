import 'package:receipt_domain/receipt_domain.dart';

import 'l10n/generated/app_localizations.dart';

String categoryLabel(AppLocalizations s, ReceiptCategory category) =>
    switch (category.kind) {
      CategorySpendingKind.product => category.name!,
      CategorySpendingKind.uncategorized => s.categoryUncategorized,
      CategorySpendingKind.deposit => s.categoryDeposits,
      CategorySpendingKind.receiptDiscount => s.categoryReceiptDiscounts,
      CategorySpendingKind.adjustment => s.categoryAdjustments,
    };
