# Documentation

## Start here

| Document | Purpose |
| --- | --- |
| [Plan](plan.md) | Current scope, priorities and remaining decisions |
| [Windows setup](windows-development.md) | Toolchain, emulator and everyday build loop |
| [Phone testing](phone-testing.md) | Safe installation, real receipts and update checks |
| [Releases and updates](releases.md) | Public-repo preparation, signing, CI and planned update UX |
| [Release notes](release-notes.md) | User-facing notes for the current alpha candidate |
| [Testing](testing.md) | Shared checks, native workflows and application-data protection |
| [Synthetic samples](sample-receipts.md) | Optional invented data for exploring charts |

## Technical reference

These documents describe behavior, invariants and evidence for particular features.
Their dated verification sections describe the build tested at that time; they are
not the current release checklist or a place to append every later test run.

- Design and storage: [architecture](architecture.md), [storage contract](local-storage-contract.md),
  [local repository](local-storage.md), [migration/recovery](migration-recovery.md).
- Import and OCR: [image import](image-import.md), [parser](parser-foundations.md),
  [Windows engine and bundle](windows-ocr.md), [Finnish corpus](finnish-ocr-corpus.md),
  [Windows clean-machine test](windows-ocr-clean-machine.md).
- Receipt workflows: [manual save](manual-saving.md), [OCR save](ocr-saving.md),
  [review](receipt-review.md), [manual correction](manual-corrections.md),
  [OCR correction](ocr-corrections.md), [deletion](receipt-deletion.md),
  [filtered history](history-filters.md).
- Products: [catalog](product-catalog.md), [saved links](saved-product-links.md),
  [inline editing](inline-product-editing.md), [purchase history](purchase-history.md),
  [trends](product-trends.md), [rankings](product-rankings.md),
  [categories](product-categories.md), [cross-store prices](cross-store-prices.md).
- Charts: [dashboard](spending-dashboard.md), [spending summaries](spending-summary.md),
  [store comparisons](store-comparisons.md).
- Recovery and distribution: [backup format](backup-recovery.md),
  [password-protected backups](password-backups.md), [dependency notices](dependency-licenses.md).
- [Historical experiments](archive/README.md): superseded prototypes and engine evaluations.

## Keeping this small

Keep the README as an entry point and the plan focused on unfinished work. Put
setup commands in the setup/testing guides, release policy in the release guide,
and feature rules in the relevant reference. Update existing documents instead of
adding a report for every increment. Keep routine verification in commit messages
or release notes; retain detailed reports only when they explain a lasting decision.
Use Git history for old roadmap and environment snapshots.
