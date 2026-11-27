/// OCR receipt notation only. Manual financial input remains strict.
String amountWithoutCurrency(String text) {
  final value = text.trim();
  return RegExp(
        r'^([-\u2212\u2013\u2014]?[0-9]+\s*[,.]\s*[0-9]+)\s*(?:€|EUR)$',
        caseSensitive: false,
      ).firstMatch(value)?.group(1)?.trim() ??
      value;
}

bool euroCurrencyMarker(String text) =>
    RegExp(r'^(?:€|EUR)$', caseSensitive: false).hasMatch(text.trim());

/// Recovery is confined to a monetary field and must be surfaced as a finding
/// by its caller. It never changes product names or strict manual parsing.
String normalizedOcrAmountLiteral(String text) =>
    amountWithoutCurrency(text)
        .replaceFirst(RegExp(r'^[\u2013\u2014](?=[0-9])'), '-')
        .replaceAll(RegExp(r'(?<=[,.])\s+(?=[0-9])'), '')
        .replaceAll(RegExp(r'(?<=[0-9])\s+(?=[,.])'), '');

/// Exact known labels with optional printed punctuation/EUR annotation. Return
/// the base spelling so OCR diacritic variants still require explicit review.
String? receiptTotalLabel(String text) =>
    RegExp(r'^(YHTEENS[ÄAĂÀÁÂÃÅ]):?(?:\s+(?:EUR|\(EUR\)|€)|\(EUR\))?$')
        .firstMatch(text.trim().toUpperCase())
        ?.group(1);

bool receiptFooterLabel(String text) => RegExp(
  r'^(ALV|VEROTON|VISA|MASTERCARD|KÄTEINEN|MAKSETTU|PANKKIKORTTI|VAIHTORAHA|BONUSTA|JÄSENNUMERO|TID)(?:\s|:|$)',
).hasMatch(text.trim().toUpperCase());

/// A complete printed boilerplate notice, not a fuzzy product-name classifier.
/// The parser additionally requires a leading position after a printed date.
bool receiptHeaderNotice(String text) =>
    RegExp(r'^ASIAKASOMISTAJAN EDUT ON HUOMIOITU\.?$')
        .hasMatch(text.trim().toUpperCase().replaceAll(RegExp(r'\s+'), ' '));
