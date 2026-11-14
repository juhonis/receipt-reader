import 'package:receipt_parser/receipt_parser.dart';
import 'package:test/test.dart';

void main() {
  test('date-only preserves civil precision and has no invented instant', () {
    final result = parseReceiptDate(' 29.2.2024 ');
    expect(result.state, ReceiptDateState.valid);
    expect(result.printed!.day, 29);
    expect(result.printed!.precision, DatePrecision.day);
    expect(result.printed!.hour, isNull);
    expect(result.printed!.timezone, 'Europe/Helsinki');
    expect(result.utcInstant, isNull);
    expect(result.possibleInstants, isEmpty);
  });

  test('strict calendar, year range and time validation', () {
    for (final input in [
      '29.2.2025',
      '31.4.2026',
      '0.1.2026',
      '1.0.2026',
      '1.13.2026',
      '1.1.26',
      '1.1.1969',
      '1.1.2100',
      '1.1.2026 24:00',
      '1.1.2026 12:60',
      '1.1.2026 12:00:60',
      '1.1.2026 12:3',
      'I.1.2026',
      '2026-01-01',
    ]) {
      expect(
        parseReceiptDate(input).state,
        ReceiptDateState.invalid,
        reason: input,
      );
    }
  });

  test('winter, summer and second precision use Helsinki not host time', () {
    expect(
      parseReceiptDate('15.1.2026 12:34').utcInstant,
      DateTime.utc(2026, 1, 15, 10, 34),
    );
    final summer = parseReceiptDate('15.7.2026 12:34:56');
    expect(summer.utcInstant, DateTime.utc(2026, 7, 15, 9, 34, 56));
    expect(summer.printed!.precision, DatePrecision.second);
    // Beyond explicit timezone transitions, do not freeze the final offset.
    expect(
      parseReceiptDate('15.7.2099 12:00').state,
      ReceiptDateState.unsupportedTimezone,
    );
    expect(parseReceiptDate('15.7.2099 12:00').utcInstant, isNull);
    expect(parseReceiptDate('15.7.2099').state, ReceiptDateState.valid);
  });

  test('spring clock gap is not normalized to a different printed time', () {
    final result = parseReceiptDate('29.3.2026 03:30');
    expect(result.state, ReceiptDateState.nonexistent);
    expect(result.printed!.hour, 3);
    expect(result.possibleInstants, isEmpty);
    expect(result.utcInstant, isNull);
    expect(
      parseReceiptDate('29.3.2026 02:59').utcInstant,
      DateTime.utc(2026, 3, 29, 0, 59),
    );
    expect(
      parseReceiptDate('29.3.2026 04:00').utcInstant,
      DateTime.utc(2026, 3, 29, 1),
    );
  });

  test('autumn repeated hour retains both candidates without choosing', () {
    final result = parseReceiptDate('25.10.2026 03:30');
    expect(result.state, ReceiptDateState.ambiguous);
    expect(result.possibleInstants, [
      DateTime.utc(2026, 10, 25, 0, 30),
      DateTime.utc(2026, 10, 25, 1, 30),
    ]);
    expect(result.utcInstant, isNull);
    expect(
      parseReceiptDate('25.10.2026 04:00').utcInstant,
      DateTime.utc(2026, 10, 25, 2),
    );
  });

  test('header candidate discovery preserves invalid and competing dates', () {
    expect(
      findReceiptDate(['KASSA 123 1. 2. 2026 12:34']).utcInstant,
      DateTime.utc(2026, 2, 1, 10, 34),
    );
    expect(findReceiptDate(['NO DATE']).state, ReceiptDateState.missing);
    expect(
      findReceiptDate(['1.1.2026', '2.1.2026']).state,
      ReceiptDateState.ambiguous,
    );
    for (final input in [
      'KASSA 31.2.2026 12:00',
      '1.1.26',
      '1.1.2026 12:999',
      '1.1.2026 25:00',
    ]) {
      expect(
        findReceiptDate([input]).state,
        ReceiptDateState.invalid,
        reason: input,
      );
    }
    expect(
      findReceiptDate(['1.1.2026', '12:00']).printed!.precision,
      DatePrecision.day,
    );
  });
}
