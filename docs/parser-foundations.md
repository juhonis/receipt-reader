# Receipt parser foundations

The first implementation is a standalone Dart package at
[`packages/receipt_parser`](../packages/receipt_parser). It has no Flutter,
native OCR or database dependency and performs no network requests. Its pinned
`timezone` 0.11.2 dependency supplies bundled IANA 2026e timezone data; the
parser imports the local database, not the package's loading APIs. The main app
now uses its financial/date rules in [reviewed manual saving](manual-saving.md),
and a draft seeds the shared [OCR review/save flow](ocr-saving.md) after offline
image recognition on Android or Windows.
All committed test inputs are invented, including prices,
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
Engine block/line order does not define financial rows. Engine lines provide
local skew evidence: endpoint word centers must span more than 10% of image
width, with slope magnitude at most 0.15. At least five estimates are required;
their median is accepted only when the median absolute deviation is at most
0.025. Otherwise the parser uses zero slope. This is a conservative global
approximation, not perspective or fold correction.

The parser groups by projected baseline height (`centerY - slope * centeredX`),
then orders each band from left to right. Original pixel boxes are untouched;
the private evaluation records `baselineSlope`. Adjustments above 0.005 magnitude
raise `skewAdjusted` for review. Grouping tolerance
is 45% of the smaller word height; overlapping words are flagged. This heuristic
is an initial single-column layout implementation, not a general layout solver.

`parseReceipt` takes an item-section top and price-column left edge in that
image's pixels. These can remain explicit layout hints or come from the optional
`proposeLayout` detector described below. Store/branch recognition is not
implemented. Header date candidates are
described below. A price
column boundary cutting through a word or a badly skewed image can produce
unclassified rows; tune neither hints nor expected outputs to hide failures.

### Conservative layout proposals

`proposeLayout` requires a unique whole-word total label before recognized footer
markers, exactly one amount to its right on the projected baseline, a unique
reconstructed header date, and at least two earlier amounts aligned with the
total's right edge (within one total-amount box height). It rejects additional
decimal columns and ambiguous baseline grouping. Nearby tokens on a projected
baseline can form one amount, including `1,` + `25`, `1` + `,25`, or
`1` + `,` + `25`. Layout and parsing share the same monetary-field joining rules:
non-currency gaps cannot exceed the smaller adjacent word height, and adjacent
digit runs cannot be fused into a new number. Printed sign tokens stay in the
amount column. A separate euro suffix does not shift the numeric alignment.
No digits are inferred, and no sum or expected financial value chooses a layout.
The detector's temporary combined boxes never replace original source words.

The proposed item section starts after the complete date baseline, rather than
at the first recognized amount. Unpriced descriptions and intervening header
material remain available for review. The price boundary is slightly left of
the leftmost aligned amount, including the total. A proposal still requires
review; unavailable proposals return explicit layout issues and null boundaries.
This does not solve multi-column receipts, strong perspective variation, or
long/incomplete captures. Explicit hints remain supported for development.

Regression cases cover split posted/total amounts, margins and skew, wrapped
names with quantity/rate continuation lines, weighed items, unpriced intervening
products and inconsistent quantity extensions. Unit rates do not become extra
purchases, and package-size text is not a purchased quantity. Wrapped or ambiguous
descriptions still require review; independent quantity/rate lines split over
multiple visual rows are not automatically joined by this layout change.

Supported candidates:

- Product name and posted amount on the same visual baseline, even when OCR
  places them in separate blocks. Duplicate product names stay separate rows.
- `PANTTI` charges/returns and explicit `ALE`/`ALENNUS` discount rows.
- An immediately following quantity/rate line such as `0,250 kg 2,00 €/kg`
  or `3 kpl × 1,00 €/kpl`, with optional `x`/`×`, Unicode minus for returns,
  and matching units (`kg`, `kpl`, `l`). Attachment
  is to the immediately preceding product only, never across another row.
- A unique `YHTEENSÄ` before recognized payment/VAT boundaries as the total.
  Exact colon and euro annotations such as `YHTEENSÄ (EUR)` are supported.
  Posted amounts may end in `€`/`EUR`; a final standalone currency token may
  have a wider gap without allowing separate numeric tokens to fuse.
  Later payment and VAT amounts do not become item rows. Competing totals before
  the boundary remain ambiguous, even if one would make arithmetic match.
- Exact whole-label variants `YHTEENSA` and `YHTEENS` followed by an A with
  breve/acute/grave/circumflex/tilde/ring are candidates with
  `totalLabelNeedsReview`. No general fuzzy matching or product-name rewriting
  is applied. Footer boundaries also recognize bonus/member/payment identifiers
  (`BONUSTA`, `JÄSENNUMERO`, `TID`) so their amounts cannot become purchases.
- OCR-only whitespace directly beside a decimal comma/point can be removed,
  with `normalizedOcrAmount` recorded. This also applies inside a complete
  quantity/rate line when split decimal fragments are within the smaller word
  height. A leading OCR en/em dash in a posted amount is proposed as negative
  only with the same review finding. Manual input remains strict. Adjacent
  digit runs in separate tokens and price tokens separated by more than a word
  height are not fused into a fabricated amount. Letters are never replaced.
- `NORM.`, `NORMAALIHINTA`, and `KAMPANJA` explanations retained as notes,
  excluded from the financial sum, and always flagged for discount review.
  Their semantic relationship is not automatically confirmed.

Wrapped descriptions, malformed prices, unsupported quantity syntax, and orphan
amounts are preserved in draft notes and flagged. Wrapped names are not silently
joined to the next product. Complex multi-buy offers, arbitrary footer formats,
discount-parent relationships, and automatic rounding adjustments need further
fixtures and implementation. Parent links and product identity are not inferred.

The [Finnish corpus](finnish-ocr-corpus.md) records the expanded hand-annotated
synthetic cases, actual Tesseract/ML Kit captures, review gates and limitations.

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
[review prototype findings](archive/review-prototype.md). Next, improve skew/section
handling and remaining review corrections. The shared temporary review now
supports [individual findings and quantity/discount relationships](archive/android-ocr-review.md).
Orphan findings preserve a typed quantity/rate candidate when the strict parser
can produce one; mismatched units or excessive precision do not create a candidate.
All recognized financial discount rows require an explicit relationship review,
including negative discounts. Explanatory price text remains excluded from sums.
Engine packaging and clean-machine tests remain separate release requirements.

Findings now carry `FindingScope` (receipt, item, or total). The temporary review
supports scoped unparsed-item classification and invalid/normalized-total
correction; see [review behavior](archive/android-ocr-review.md). A structural
`ReceiptEvidenceCoverage` inventory also retains original source words and any
words outside header/row/finding/total/footer evidence. This detects omissions,
including bands crossing the item boundary and text between competing totals;
it does not claim correct classification or completed human review.

Parsed drafts retain `ReceiptParseContext` (the immutable source page and chosen
boundaries). Geometry/skew findings retain relevant original words for inspection,
but those words do not count as structurally assigned merely because they appear
in geometry evidence. `reviewFindingsForDraft` adds independent review-only
`unassignedSource` findings for omissions without mutating the parser result.
`unreviewedOmissions` tracks their explicit review separately from the immutable
structural inventory; resolving an unrelated geometry warning cannot clear them.

`OcrEvidenceAudit` validates supported OCR evidence independently of financial
reconciliation. Whole-page and geometry approvals retain immutable field/row/
evidence snapshots, which must match current data. Geometry types distinguish
boundary errors (re-parse required) from individually reviewed overlap/band/skew
cases. Unsupported decisions, stale targets, unaccounted deleted rows, silently
dropped quantities, and incomplete context cannot approve a receipt. A ready
audit is combined with exact `ReviewValidation` and final confirmation to complete
only the temporary no-save prototype; persistence remains a separate contract.
