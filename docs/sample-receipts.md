# Synthetic receipts for exploring the app

Loaded into the normal Windows and Android emulator datasets on November 24, 2026.
Both received the same **10 invented receipts, 3 DEMO branches and 22 categorized
products**, without replacing existing records. They are structured manual samples;
no real receipt images or OCR results are used.

Open **Seuranta**. With the November 24 anchor, **Viikko** contains three samples,
**Kuukausi** contains seven and **Vuosi** contains all ten. Existing receipts remain
included when all branches are selected. Choose a branch beginning **DEMO** to view
its invented purchases separately. The three branches are:

- DEMO Mallimarket Keskusta
- DEMO Mallimarket Tori
- DEMO Mallikioski Asema

The samples cover all five starter categories, repeated products with changing
prices, weighed fruit, item/receipt discounts, bottle deposits, a refund, one
unlinked bag and a small explicit adjustment. Product rankings and product price
history have explicit catalog links. These values are fictional examples, not
measured Finnish retail prices.

| Date | Branch | Receipt total |
| --- | --- | ---: |
| 24.11.2026 | Keskusta | 18.26 EUR |
| 23.11.2026 | Tori | 28.72 EUR |
| 24.11.2026 | Asema, refund | -5.39 EUR |
| 17.11.2026 | Keskusta | 22.58 EUR |
| 16.11.2026 | Tori | 26.46 EUR |
| 10.11.2026 | Keskusta | 16.11 EUR |
| 4.11.2026 | Asema | 20.14 EUR |
| 24.10.2026 | Keskusta | 32.46 EUR |
| 4.10.2026 | Tori | 15.43 EUR |
| 28.5.2026 | Keskusta | 12.67 EUR |

The demo-only totals are 41.59 EUR for the current week, 126.88 EUR for November
through the 24th, and 187.44 EUR for the year. The app's all-branch totals can be
higher or lower if other receipts are present.

## Explicit development loader

This is an additive developer tool targeting **normal application storage**.
Ordinary integration runs skip it before opening the dataset. Run it only when
intentionally adding these samples; it is not an isolated smoke test.

```powershell
flutter test integration_test/load_demo_receipts_test.dart -d windows --dart-define=RECEIPT_READER_LOAD_DEMO_DATA=true --dart-define=RECEIPT_READER_DEMO_ANCHOR=24.11.2026
flutter test integration_test/load_demo_receipts_test.dart -d emulator-5554 --dart-define=RECEIPT_READER_LOAD_DEMO_DATA=true --dart-define=RECEIPT_READER_DEMO_ANCHOR=24.11.2026
```

Reserved fixture identities make the same import repeatable without duplicate
receipts or new writes. Preflight checks refuse ID collisions, edits to existing
demo records, deleted demo receipts or a different anchor date, rather than
overwriting/resurrecting records. Interrupted creation can resume its own unfinished
samples. All saves use the existing reviewed manual/catalog/link commands; original
receipt values and user receipts are not relabelled or automatically matched.

Four isolated storage tests cover existing-data preservation, totals/categories,
idempotence, collisions, edits and deletions. Both opted-in native loads succeeded:
ten new receipts and 22 new products per platform. No database or backup format
changed. No demo-loading path is added to the normal app entry point.

After loading, rebuild normal Windows Debug/Release and Android Debug entry points,
upgrade-install Android with `adb install -r`, and launch the regular apps. Do not
uninstall or clear app data. Android loading can run offline; restore its original
airplane setting afterward. Keep the samples only as long as they are useful;
regular receipt deletion remains available.
