# Receipt parser foundations

The first implementation is a standalone Dart package at
[`packages/receipt_parser`](../packages/receipt_parser). It has no Flutter,
native OCR, database, network, or runtime package dependencies. The main app
does not use it yet. All committed test inputs are invented, including prices,
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
store/branch recognition, and date recognition are not implemented. A price
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

## Validation and review

The draft exposes independent arithmetic state and parser issues. Quantity/rate
discrepancies, uncertain geometry, and unresolved discount semantics remain
visible even when the total matches. All drafts require review. There is no save
eligibility API yet: branch/date review, row correction, and persistence validation
must be implemented before any save workflow can use these results.

Printed dates, date-only precision, Europe/Helsinki DST ambiguity, and UTC
conversion are still open work. The roadmap's full financial/date and parser
milestones remain unchecked until that work and broader fixture coverage exist.

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

Next, expand representative synthetic layout fixtures, implement conservative
wrapped-name/discount relationships and date candidates, then exercise private
OCR outputs locally. Engine packaging and clean-machine tests remain separate
requirements before connecting OCR to the shared review workflow.
