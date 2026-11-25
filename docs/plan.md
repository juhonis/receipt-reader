# Project plan

Updated November 25, 2026. The immediate goal is a dependable personal-use alpha
on a real Android phone and Windows, distributed through versioned GitHub Releases.
[Documentation index](README.md) · [Architecture](architecture.md) · [Release plan](releases.md)

## Product scope

- One native Flutter app for Android and Windows, Finnish UI and EUR receipts.
- Import, offline OCR, review, storage, history and analytics remain usable offline.
- Seuranta is the main tab: week/month/year/custom ranges, branch filter, net
  spending versus the previous period, then graph-led breakdowns. Kuitit manages data.
- Review highlights detected problems; arithmetic agreement is not an accuracy
  guarantee. Saving requires reconciled amounts and an explicit user approval.
- Products remain branch-owned. Explicit equivalent-product groups support
  cross-store price comparison; category edits regroup earlier linked purchases.
- Password-protected backups remain essential. Device synchronization is optional
  future work, not a prerequisite for phone testing or software updates.
- GitHub distributes source and binaries, never receipt data or signing secrets.
  Making source public and publishing builds are separate actions.

## Current baseline

Implemented: JPEG/PNG import and bundled OCR on both platforms; reviewed receipt
save/edit/delete; catalog and links; dashboard, categories, price histories and
cross-store comparisons; encrypted backup/recovery. See the [feature references](README.md#technical-reference).

Current persistence: SQLite schema 9, product payload 3, inner backup up to 6
(selected from retained history), encrypted envelope 1. Supported older datasets
migrate forward; older apps cannot necessarily read newer databases or backups.
The [comparison contract](cross-store-prices.md) documents the latest format change.

The Windows development ZIP has a successful reported offline laptop save/reopen/
folder-move test. Broader photograph, privacy, native-picker and clean-machine checks
remain open. Native backup/image picker checks now pass on both platforms. Android
release builds require the permanent key. Versioned APK/ZIP and CI/draft workflows
are implemented. Hosted Checks passes and the release environment is configured;
successful tagged native builds/draft upload remain pending. There is no camera capture,
sync or update button yet.

## Next milestone: repeatable phone testing and releases

### 1. Documentation and publication preparation

- [x] Replace accumulated milestone narration with this focused roadmap; index
  current guides and references, archive early prototypes and shorten setup docs.
- [x] Record a preliminary tracked-content and historical-path scan in the
  [release guide](releases.md#before-making-the-repository-public).
- [x] Choose the [MIT application license](../LICENSE), approved November 25, 2026.
- [x] Scan reachable Git history with pinned Gitleaks and review tracked fixture/
  private paths; no leaks reported. See the scope in the release guide.
- [x] Owner made the repository public.
- [x] Complete the scoped offline permission/retention/logging review and native
  import/cancel and backup save/read checks. Manufacturer transfer enforcement and
  signed first-install/phone acceptance remain outstanding. Networking needs a new review.
- [ ] Resolve applicable dependency/vendor distribution conditions and Windows
  builder entitlement; preserve the existing notice audits.

### 2. Stable Android installation and first phone test

- [x] Establish the permanent local release key and public certificate pin, stable
  package ID and a release configuration that refuses debug-key fallback.
- [x] Owner confirmed a copy of the signing folder on November 25, 2026.
  Backup location/protection and restore usability have not been independently verified.
- [x] Use one version source for displayed version, artifacts and release tags;
  remove the hand-maintained duplicate in `lib/app_version.dart`.
- [x] Build and inspect a signed alpha APK locally: permanent certificate, package/
  version, arm64, notices, SQLite provenance and offline release permissions.
- [ ] Verify signed first-launch OCR offline on a test device; static permission/
  dependency checks do not replace runtime acceptance.
- [ ] Install on the phone and exercise the [phone checklist](phone-testing.md):
  actual receipt import/review/save, chart readability, correction and backup/recovery.
- [ ] Prove a same-key APK upgrade preserves existing receipts and catalog data.
  Keep emulator/integration builds separate from this retained release installation.

### 3. GitHub Actions and versioned releases

- [x] Define CI for analysis, shared-package/app tests, workflow/history scanning
  and dependency notice checks; rehearse with the installed toolchain.
- [x] Implement signed APK and self-contained Windows ZIP candidates with version,
  tag, permission, notice, provenance and dependency validation.
- [x] Define protected builders and draft-only upload of versioned assets,
  checksums, commit/build metadata and release notes; reject existing releases.
- [x] Owner configured the protected `release` environment, `v*` deployment tags,
  self-review approval and four signing secrets; hosted Checks passes.
- [x] Confirm the Windows tagged build after disabling optional desktop JNI.
- [ ] Complete the Android tagged build/draft pipeline. Alpha.4 passes the Kotlin
  setting as a Flutter project argument, verifies the effective compiler task mode,
  and adds a signing-secret-free Android compile to Checks. Hosted compilation now
  passes; the APK certificate check fails. Local temporary-key signing matches the
  pin; refresh/compare the protected keystore secret before retrying the same tag.
- [ ] Test the exact artifacts on the phone and second Windows PC, including an
  upgrade from the previous alpha, then explicitly publish the pre-release.

### 4. Update entry point in the app

- [ ] Start with a manual GitHub release-page link if useful while networking is
  still under review; it can open the external browser without an in-app API check.
- [ ] After the permission/disclosure review, add **Tarkista päivitykset** in
  Tietoja ja lisenssit: installed/available version, notes and **Lataa päivitys**.
- [ ] Explicitly include opted-in alpha pre-releases; compare versions/builds
  correctly and select the matching platform asset. Handle offline, timeout,
  rate-limit and malformed-response cases without blocking receipt workflows.
- [ ] Keep installation user-approved: Android system APK installer, Windows
  ZIP replacement while the app is closed. Test cancellation and retained data.

Done when two successive tagged builds can be installed on the phone and Windows,
updated without data loss, and recovered from an independent encrypted backup.
Release readiness is assessed per artifact; passing local tests alone is insufficient.

## After the release loop works

1. Use real-phone feedback to fix dense layouts, keyboard/file-picker behavior,
   slow review steps and representative receipt recognition failures.
2. Add Android camera capture with private temporary storage, image-cleanup checks
   and clear handling of long/incomplete receipts. Until then, import JPEG/PNG.
3. Continue useful analytics and product-comparison improvements from observed needs.
4. Implement encrypted local two-device sync only after standalone and recovery
   workflows are dependable. Follow the [causal/conflict design](architecture.md#secure-bidirectional-local-sync)
   and storage contract; never silently merge unrelated datasets.

Deferred: silent/self-replacing updates, app-store distribution, PDF/multi-shot
import, Windows webcam, automatic product merging, more than two synchronized
devices, macOS/Linux. Assess Windows signing before broader distribution.

## Decisions requiring owner input

- Confirm vendor/runtime redistribution conditions and Windows signing approach.

The recommended first channel is alpha pre-releases in the public repository,
for personal testing. No receipt account, cloud storage or Play Store is required.
