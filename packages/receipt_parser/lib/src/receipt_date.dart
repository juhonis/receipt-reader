import 'package:timezone/data/latest_all.dart' as database;
import 'package:timezone/timezone.dart' as tz;

enum ReceiptDateState {
  valid,
  missing,
  invalid,
  ambiguous,
  nonexistent,
  unsupportedTimezone,
}

enum DatePrecision { day, minute, second }

/// Printed civil fields, never the host computer's timezone.
class PrintedDate {
  const PrintedDate(
    this.year,
    this.month,
    this.day,
    this.hour,
    this.minute,
    this.second,
    this.precision,
  );
  final int year, month, day;
  final int? hour, minute, second;
  final DatePrecision precision;
  String get timezone => 'Europe/Helsinki';
}

class ReceiptDateResult {
  ReceiptDateResult(
    this.state,
    this.printed,
    Iterable<DateTime> instants,
    Iterable<String> sourceText,
  ) : possibleInstants = List.unmodifiable(instants),
      sourceText = List.unmodifiable(sourceText);
  final ReceiptDateState state;
  final PrintedDate? printed;
  final List<DateTime> possibleInstants;
  final List<String> sourceText;
  DateTime? get utcInstant =>
      state == ReceiptDateState.valid && possibleInstants.length == 1
      ? possibleInstants.single
      : null;
}

bool _initialized = false;

/// Civil day at an actual instant in Helsinki, independent of the host timezone.
PrintedDate helsinkiCalendarDate(DateTime instant) {
  if (!_initialized) {
    database.initializeTimeZones();
    _initialized = true;
  }
  final local = tz.TZDateTime.from(instant, tz.getLocation('Europe/Helsinki'));
  return PrintedDate(
    local.year,
    local.month,
    local.day,
    null,
    null,
    null,
    DatePrecision.day,
  );
}

/// Strict Finnish date syntax. Two-digit years and impossible calendar dates
/// are invalid. The initial supported receipt-year range is 1970..2099.
ReceiptDateResult parseReceiptDate(String text) {
  ReceiptDateResult failure(ReceiptDateState state) =>
      ReceiptDateResult(state, null, [], [text]);
  final match = RegExp(
    r'^(\d{1,2})\s*\.\s*(\d{1,2})\s*\.\s*(\d{4})(?:\s+(\d{1,2}):(\d{2})(?::(\d{2}))?)?$',
  ).firstMatch(text.trim());
  if (match == null) return failure(ReceiptDateState.invalid);
  final day = int.parse(match[1]!);
  final month = int.parse(match[2]!);
  final year = int.parse(match[3]!);
  final hour = match[4] == null ? null : int.parse(match[4]!);
  final minute = match[5] == null ? null : int.parse(match[5]!);
  final second = match[6] == null ? null : int.parse(match[6]!);
  final civil = DateTime.utc(
    year,
    month,
    day,
    hour ?? 0,
    minute ?? 0,
    second ?? 0,
  );
  if (year < 1970 ||
      year > 2099 ||
      civil.year != year ||
      civil.month != month ||
      civil.day != day ||
      civil.hour != (hour ?? 0) ||
      civil.minute != (minute ?? 0) ||
      civil.second != (second ?? 0))
    return failure(ReceiptDateState.invalid);
  final printed = PrintedDate(
    year,
    month,
    day,
    hour,
    minute,
    second,
    hour == null
        ? DatePrecision.day
        : second == null
        ? DatePrecision.minute
        : DatePrecision.second,
  );
  if (hour == null)
    return ReceiptDateResult(ReceiptDateState.valid, printed, [], [text]);
  if (!_initialized) {
    database.initializeTimeZones();
    _initialized = true;
  }
  final location = tz.getLocation('Europe/Helsinki');
  // The package does not extrapolate recurring DST rules indefinitely. Keep
  // only complete years before its last explicit transition; never silently
  // accept a frozen final offset as evidence for a future receipt.
  final lastTransitionYear = DateTime.fromMillisecondsSinceEpoch(
    location.transitionAt.last,
    isUtc: true,
  ).year;
  if (year >= lastTransitionYear) {
    return ReceiptDateResult(
      ReceiptDateState.unsupportedTimezone,
      printed,
      [],
      [text],
    );
  }
  // Enumerate offsets, then round-trip through IANA rules. Unlike a civil-time
  // constructor this neither normalizes spring gaps nor chooses an autumn fold.
  final instants = <DateTime>[];
  for (final offset in location.zones.map((z) => z.offset).toSet()) {
    final instant = civil.subtract(offset);
    final local = tz.TZDateTime.from(instant, location);
    if (local.year == year &&
        local.month == month &&
        local.day == day &&
        local.hour == hour &&
        local.minute == minute &&
        local.second == (second ?? 0)) {
      instants.add(instant);
    }
  }
  instants.sort();
  return ReceiptDateResult(
    instants.isEmpty
        ? ReceiptDateState.nonexistent
        : instants.length > 1
        ? ReceiptDateState.ambiguous
        : ReceiptDateState.valid,
    printed,
    instants,
    [text],
  );
}

/// Finds candidates in separately reconstructed header baselines. Never joins
/// dates and times across lines, or uses footer/payment timestamps as fallback.
ReceiptDateResult findReceiptDate(Iterable<String> headerLines) {
  final pattern = RegExp(
    r'(?<![\d.])(\d{1,2}\s*\.\s*\d{1,2}\s*\.\s*\d{2,4})(?:\s+\d+:\S+)?(?![\d.:]|\s+\d+:)',
  );
  final candidates = [
    for (final line in headerLines)
      for (final match in pattern.allMatches(line)) match[0]!,
  ];
  if (candidates.isEmpty)
    return ReceiptDateResult(ReceiptDateState.missing, null, [], []);
  if (candidates.length != 1)
    return ReceiptDateResult(ReceiptDateState.ambiguous, null, [], candidates);
  return parseReceiptDate(candidates.single);
}
