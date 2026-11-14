# Receipt parser foundations

The first implementation is a standalone Dart package at
[`packages/receipt_parser`](../packages/receipt_parser). It has no Flutter,
native OCR or database dependency and performs no network requests. Its pinned
`timezone` 0.11.2 dependency supplies bundled IANA 2026e timezone data; the
parser imports the local database, not the package's loading APIs. The main app
now uses its financial/date rules in a [manual review prototype](review-prototype.md),
but OCR drafts are not yet connected to the UI. All committed test inputs are invented, including prices,
names, and geometry; no private OCR exports were copied into fixtures.

## Numeric rules

- Posted EUR amounts are signed integer cents. Parsing requires exactly two
  decimal digits, accepts comma or point and Unicode minus, and trims surrounding
  Unicode whitespace. It does not guess missing digits or replace OCR letters.
- Quantities carry an integer value, decimal scale, and explicit unit. Missing
  quantity remains null, rather than becoming one. Unit rates use millionths of
  EUR per unit. A returned product may have a negative quantity and amount.
- Arithmetic uses `BigInt` so intermediate multiplication cannot overflow.
  Serialization and SQLite range checks must be implemented at the persistence
  boundary; these values are not directly JSON/SQLite-ready.
- Quantity times rate is rounded once to cents, halfway away from zero. The
  result is a separate check; the printed amount is never overwritten.
- Every financial row contributes its signed cents once. Reconciliation is
  exact, with difference defined as row sum minus printed total. A missing or
  ambiguous total cannot reconcile. No tolerance or inferred adjustment exists.

## Geometry and supported layouts

`OcrPage.fromJson` consumes the OCR spike's version 1 word geometry contract.
Coordinates belong to the supplied upright image, including a preprocessed
variant if applicable. Pixel boxes must be finite, positive, and in bounds.
Engine block/line order is ignored. The parser sorts word centers by height,
groups nearby baselines, then orders each band from left to right. Its tolerance
is 45% of the smaller word height; overlapping words are flagged. This heuristic
is an initial single-column layout implementation, not a general layout solver.

The caller must supply an item-section top and price-column left edge in that
image's pixels. These are explicit layout hints. Automatic section detection,
and store/branch recognition are not implemented. Header date candidates are
described below. A price
column boundary cutting through a word or a badly skewed image can produce
unclassified rows; tune neither hints nor expected outputs to hide failures.

Supported candidates:

- Product name and posted amount on the same visual baseline, even when OCR
  places them in separate blocks. Duplicate product names stay separate rows.
- `PANTTI` charges/returns and explicit `ALE`/`ALENNUS` discount rows.
- An immediately following quantity/rate line such as `0,250 kg 2,00 €/kg`
  or `3 kpl 1,00 €/kpl`, with matching units (`kg`, `kpl`, `l`). Attachment
  is to the immediately preceding product only, never across another row.
- A unique `YHTEENSÄ` before recognized payment/VAT boundaries as the total.
  Later payment and VAT amounts do not become item rows. Competing totals before
  the boundary remain ambiguous, even if one would make arithmetic match.
- `NORM.`, `NORMAALIHINTA`, and `KAMPANJA` explanations retained as notes,
  excluded from the financial sum, and always flagged for discount review.
  Their semantic relationship is not automatically confirmed.

Wrapped descriptions, malformed prices, unsupported quantity syntax, and orphan
amounts are preserved in draft notes and flagged. Wrapped names are not silently
joined to the next product. Complex multi-buy offers, arbitrary footer formats,
discount-parent relationships, and automatic rounding adjustments need further
fixtures and implementation. Parent links and product identity are not inferred.

`draft.wrappedNames` proposes a combined name for a single adjacent text-only
line followed by a priced product. Lines must be left-aligned within one word
height and separated by at most 1.5 word heights. Numeric/rate-like lines,
discount explanations, intervening rows, and large gaps do not qualify. The
financial row and original note are unchanged; `wrappedNameNeedsReview` and
the unclassified-row issue remain until a later review workflow resolves them.
A missing price can look like wrapping, so these are proposals only.

Payment/VAT boundaries additionally recognize `PANKKIKORTTI`, `VAIHTORAHA`,
and `VEROTON`. Quantity/rate text can span separate description/price columns.

## Printed dates and Helsinki time

`draft.date` is independent of financial reconciliation. `parseReceiptDate`
also supports direct parsing of a printed date string. Accepted syntax is
`d.m.yyyy`, optionally followed by `HH:mm` or `HH:mm:ss`; spaces around date
dots are allowed. Calendar values and times are checked without normalization.
Two-digit years, OCR letter substitutions, and years outside 1970..2099 are
rejected rather than guessed. Dot-separated clocks and times on a separate
baseline are not joined in this iteration.

The stored candidate preserves printed year/month/day, nullable clock fields,
day/minute/second precision, and `Europe/Helsinki`. Date-only candidates have
no UTC instant. Header candidates are found only on reconstructed baselines
wholly above `itemTop`. Footer/payment timestamps never provide a fallback.
Multiple candidates remain ambiguous; malformed recognized candidates are
invalid. Missing or unrecognized syntax produces a missing date for review.

Timed candidates round-trip possible UTC offsets through the bundled IANA
rules. A spring clock gap is `nonexistent`; an autumn repeated hour is
`ambiguous`, with both possible UTC instants retained and neither selected.
Only a unique valid timed candidate exposes `utcInstant`. This does not depend
on the Windows/Android timezone setting.

Timezone lookup refuses years at or beyond the database's final explicit
Helsinki transition year, returning `unsupportedTimezone` while preserving
the printed fields. This conservative complete-year boundary avoids silently
extending the final fixed offset indefinitely. Date-only validation does not
need timezone transitions. Future rule changes require a reviewed timezone
dependency update and rerunning the transition tests.

## Validation and review

The draft exposes independent arithmetic state and parser issues. Quantity/rate
discrepancies, uncertain geometry, and unresolved discount semantics remain
visible even when the total matches. All drafts require review. The manual
prototype has independent review validation; it is not a save eligibility API.
Persistence validation and OCR issue-resolution workflows remain open.

The numeric and printed-date conventions are now defined. Broad layout coverage,
store confirmation, discount-parent relationships, date correction, and save
validation remain open; this is not a production-ready parser milestone.

## Verification

Run from `packages/receipt_parser` using Windows Dart (the SDK inside Flutter):

```powershell
dart pub get
dart analyze
dart test
```

The tests construct synthetic version 1 OCR fixtures with separate description
and price blocks and reversed reading order. They assert extracted rows and
amounts, quantity checks, reconciliation and warnings. Coverage includes signed
returns/deposits, explanatory discounts, duplicate products, strict decimal
parsing, rounding and large integers, missing/competing totals, footer exclusion,
wrapped names, invalid prices, orphan quantities, and invalid/overlapping geometry.
Date cases cover leap years, invalid calendar/time values, header-only extraction,
date-only precision, winter/summer offsets, both DST transitions, competing
candidates, and refusal to guess beyond the timezone database's usable range.

Private OCR evaluation now documents real-layout failures in the
[review prototype findings](review-prototype.md). Next, improve skew/section
handling and build explicit review corrections for OCR proposals and discount relationships. Engine
packaging and clean-machine tests remain separate
requirements before connecting OCR to the shared review workflow.
