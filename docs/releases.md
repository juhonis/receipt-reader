# Releases and updates

Updated November 25, 2026. Permanent Android signing and local APK verification
and GitHub workflow definitions are implemented. Hosted Checks passes and owner
setup is complete; successful tagged native builds, published phone alphas and
the in-app updater remain pending. The [roadmap](plan.md) defines the order of work.
The first distribution channel will be personal-use alpha pre-releases in the
public GitHub repository, with Android APK and Windows x64 ZIP assets.

## Before making the repository public

Public source and published binaries are separate steps. The application uses the
[MIT license](../LICENSE), approved November 25, 2026. Third-party components retain
their own licenses and distribution terms. Personal use does not make public
binaries private or restrict who can download them.

Review tracked content and reachable Git history, not just the current checkout.
Keep private receipts/OCR exports, databases/backups, passwords and signing material
out of commits, workflow logs, caches, artifacts and release assets. Ignoring a path
does not remove files already committed. Revoke an exposed credential before any
necessary history cleanup; do not rewrite published history casually.

Preliminary check on November 25, 2026, before this docs change:

- Scanned 400 tracked files for private-key headers and known GitHub/AWS/Slack
  credential patterns; no matches. This was not a comprehensive secret scanner.
- Inspected paths reported by `git rev-list --objects --all` over 134 reachable
  commits; no sensitive-looking receipt, database, environment or signing paths
  were reported. This was a path check, not a scan of every historical blob.
- Reported historical image paths were launcher icons and the three expected
  synthetic import/receipt fixtures. No private receipt directory was inspected.

The subsequent checksum-pinned Gitleaks 8.30.1 scan (`git --log-opts=--all`, full
redaction) reported no leaks. Tracked fixture images/OCR exports are synthetic;
private receipt paths and signing material remain ignored. This is scoped review
evidence, not a guarantee that every kind of sensitive content can be detected.
Check repository settings and published artifacts as well as source files.
Changing visibility remains an explicit owner action.

Native checks now cover backup save/read and image import/cancel on Windows and
the emulator; synthetic image hashes stayed unchanged. Android uses bounded
in-memory URI reads without persistent grants/cache images. Windows imports are
read-only. The release permission audit now permits only the generated signature
receiver permission, rejecting any unreviewed network/storage/other permission.
OS cloud-backup/device-transfer exclusions are explicit; manufacturer enforcement
and source-provider/cloud-storage behavior still require device-specific checks.
SQLite is unencrypted locally, and receipt deletion retains historical events.

## Signing and version identity

Android keeps `fi.juhonis.receipt_reader` as its application ID. Its release build
requires the permanent signing configuration and never falls back to a debug key.
The public certificate fingerprint is pinned in
[`android/release-certificate.sha256`](../android/release-certificate.sha256).
The existing private key lives in `%LOCALAPPDATA%/ReceiptReader/signing/`, outside
the checkout. Keep that entire folder in an independent protected backup, including
its credential configuration; the companion local copy is not an independent backup.
Only the public fingerprint belongs in Git. Losing the key can prevent updates to
the installed app.

`android/key.properties` is ignored and access-restricted. CI can supply all four
`RECEIPT_READER_STORE_FILE`, `RECEIPT_READER_STORE_PASSWORD`, `RECEIPT_READER_KEY_ALIAS`
and `RECEIPT_READER_KEY_PASSWORD` environment variables from protected secrets.
Partial environment credentials never mix with the local configuration.
The private keystore, passwords and full configuration must not enter logs or assets.

[`setup_signing.py`](../tools/releases/setup_signing.py) is a one-time Windows
bootstrap for an installation with no existing identity. It refuses to replace an
existing key/configuration/fingerprint. Do not rerun it for this repository's existing
identity or on a CI runner: restore the original key and configure its path instead.

Every upgrade needs the same signing identity and a greater Android versionCode.
Different debug keys, CI-generated keys and a production key are not interchangeable.
Keep the emulator's debug/test installation separate from the phone's release
installation. Never solve a signature mismatch by clearing valuable application data.

`pubspec.yaml` is the version source. `tools/releases/version.py` generates the
displayed `lib/app_version.dart`; its check rejects stale metadata or a wrong tag.
The current candidate is `0.2.0-alpha.4+5`, with expected tag `v0.2.0-alpha.4` and
Android build 5. Earlier candidates/tags are retained separately. Version checks
reject tag mismatches and build numbers not greater than previous tagged builds.
Local builders create no tag/release. Reject asset replacement for published
versions. Artifacts should identify platform, version and build unambiguously.

## Local APK build

After changing the pubspec version, regenerate and commit the Dart metadata:

```powershell
python tools/releases/version.py
python tools/releases/version.py --check --tag v0.2.0-alpha.4 --check-history
python -m unittest discover -s tools/releases -p 'test_*.py'
```

Refresh the [notice inventory](dependency-licenses.md#reproduce-and-update) whenever
its recorded build inputs change. From a clean, reviewed commit, build with:

```powershell
python tools/releases/android.py --tag v0.2.0-alpha.4
```

The wrapper checks current notice evidence, builds the signed universal APK and
verifies its certificate, v2 signature, package/version, arm64 support, native
SQLite provenance, packaged MIT/third-party notices and absence of network permissions.
It rejects a changed commit or dirty source appearing during a distributable build.
Outputs under `build/distribution/releases/` are a versioned APK, SHA-256 sidecar
and sanitized JSON build evidence. Existing artifact names are never overwritten.
The first local alpha includes arm64 and has minimum API 24, which supports the
planned Android 14/API 34 phone. Actual phone acceptance remains outstanding.

`--allow-dirty` is only a local rehearsal: output goes to `build/distribution/rehearsal/`
and is marked development even if the source happens to be clean. Neither mode
publishes, installs on a device, grants public-release approval or proves phone
acceptance. Finish privacy/native-picker and offline/upgrade tests separately.

Windows keeps the portable ZIP. Build it with `flutter build windows --release`,
then `python tools/windows_ocr/package.py --tag v0.2.0-alpha.4`. Versioned mode
produces immutable ZIP/checksum/evidence files alongside the APK. The no-tag mode
remains the legacy development ZIP. Preserve existing notice/runtime audits
and settle applicable distribution conditions. Assess Authenticode signing before
broader distribution. A release checksum detects corruption; it does not substitute
for publisher signing. See [dependency terms and notices](dependency-licenses.md).

## GitHub Actions pipeline

1. [Checks](../.github/workflows/ci.yml) runs on main pushes, pull requests and release
   calls: workflow lint, history scan, analysis, app/shared-package tests, tooling
   checks and an Android debug compile without release credentials. Actions and tools use checksum/commit pins;
   Flutter/Dart/engine revisions must match the reviewed dependency inventory.
2. An approved version tag runs the release checks, confirms a clean source/version
   identity, prepares the pinned Windows OCR bundle, and builds Windows ZIP and
   release-signed Android APK. Both builders use the protected `release` environment.
   The [setup helper](../tools/ci/prepare.py) prepares clean-runner dependencies;
   `--existing` rehearses the same checks with installed SDKs. CI verifies existing
   notice evidence; it never automatically approves regenerated dependency notices.
   Android compilation uses Flutter's explicit `--android-project-arg=kotlin.incremental=false`.
   A hosted Gradle init check verifies the effective Debug/Release Kotlin task mode
   before compilation, avoiding cross-drive cache paths. Dotted environment-variable
   names cannot carry this setting: Windows/Python/Dart uppercase their names.
   Normal local debug builds keep their default incremental behavior.
   Windows explicitly disables optional desktop JNI discovery, so installing the
   Android build JDK cannot add a `jvm.dll` dependency to the ZIP.
3. Validate packaged notices, native dependencies, final Android permissions and
   signing certificate. Use the [existing audit tools](dependency-licenses.md#reproduce-and-update).
   An intentional permission change must update the permission audit expectation.
4. Produce versioned assets, SHA-256 checksums, sanitized commit/build provenance,
   and brief user-facing release notes with compatibility/known-issue information.
   [Draft release](../.github/workflows/release.yml) validates the exact six APK/ZIP,
   checksum and metadata assets against the tag's version, commit and certificate.
   Only its final job gets `contents: write`; it creates a **draft pre-release**.
   Signing material is temporary, outside checkout/output paths, and removed after
   the APK build. There are no signing caches. Existing releases/drafts are refused.
   The current signing wrapper checks the restored keystore certificate before
   compilation. Failure diagnostics include public fingerprints, never credentials.
5. Test those exact downloads on the phone and second Windows PC: offline startup,
   recognition/save/reopen, backup/recovery and a previous-alpha upgrade. Publish
   explicitly after acceptance. Ordinary commits do not automatically ship updates.

Protect signing and release jobs with trusted tags/branches and a protected
environment as appropriate. Do not expose secrets to fork PRs or run untrusted
contributor code in a privileged release context. External contributions do not
become trusted merely because the repository is public.

## One-time GitHub activation

The owner has completed this setup and made the repository public. Hosted Checks
and Windows builds pass. Alpha.4 also compiles Android successfully, but its APK
certificate check fails. Local signing through the temporary-key CI path matches
the permanent certificate. Refresh/compare the protected keystore secret and retry
alpha.4 before creating another candidate; the hosted signer fingerprint is unknown.
The procedure below remains the reference for another repository/installation.

1. Review source/terms, then change repository visibility separately if desired.
   Keep default workflow token permissions read-only; the draft job requests its
   limited write permission explicitly.
2. Create the `release` environment under repository Settings → Environments.
   Restrict deployment tags to `v*`, require owner review before either builder,
   and protect those tags against modification/deletion. For solo maintenance,
   permit the owner to approve their own run.
3. Configure these **environment secrets**, using the existing private signing
   files and authenticated tooling. Do not generate another keystore on the runner.

| Secret | Existing source |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | Base64 encoding of the permanent `.p12` file |
| `ANDROID_STORE_PASSWORD` | `storePassword` from the private configuration |
| `ANDROID_KEY_ALIAS` | `keyAlias` from the private configuration |
| `ANDROID_KEY_PASSWORD` | `keyPassword` from the private configuration |

4. Push the reviewed main commit and let Checks pass. Then create/push its exact
   version tag, for example `v0.2.0-alpha.4`. Tags whose commits are not on main,
   stale generated metadata and reused/lower Android build numbers are rejected.
5. Approve the builders, inspect the draft/assets, and perform the phone/laptop
   checks before explicitly publishing. A failed upload can leave an incomplete
   draft; inspect it before manually removing/replacing any unpublished candidate.
   Rerunning the publisher never silently replaces an existing release or draft.

Draft downloads require repository write access; sign in as the owner on the phone
for draft acceptance. Published pre-releases in a public repo are publicly downloadable.
The workflow does not change repo visibility or publish the draft itself.

## Planned app update flow

Location: **Tietoja ja lisenssit**, showing the installed version.

- First optional increment: an external GitHub releases-page link. Users download
  in their browser; this does not require an in-app API request.
- After the networking review: **Tarkista päivitykset** makes an explicit HTTPS
  request for release metadata. No startup polling, receipt upload or bundled
  GitHub access token. Release checks expose ordinary request metadata to GitHub.
- Alpha users must see approved pre-releases: do not rely solely on GitHub's
  `latest release` endpoint, which excludes pre-releases. Filter draft releases,
  compare supported version/build values, and pick the matching platform asset.
- Show available version and release notes, then **Lataa päivitys** opens the
  official release download in the external browser. Validate repository/HTTPS
  destinations; arbitrary response URLs must not become trusted update sources.
- Offline, cancellation, timeout, rate limits and malformed/missing assets leave
  receipt workflows available and give a short actionable status.

The Android release manifest currently removes INTERNET and ACCESS_NETWORK_STATE.
An in-app API check requires changing that offline permission posture. Review SDK
network behavior/disclosures, including bundled ML Kit diagnostics, before enabling
it; the permission cannot be assumed to limit networking to the updater. Update
[privacy evidence](dependency-licenses.md#vendor-terms-and-release-decisions) and
artifact checks together. A browser-only link can precede that change.

## Installation and recovery

Android downloads an APK through the browser; the user permits that source if
required and approves the system installer. The app does not silently install
itself or initially request its own package-install permission. Verify same-key,
increasing-build upgrades preserve receipts, products and preferences.

On Windows, close the app and extract the complete new ZIP into a fresh folder.
The normal database is in application-support storage outside that folder, so keep
its identity/path stable between releases. Verify OCR dependencies and data after
launch; replacing just the EXE is insufficient.

Before migration tests, keep an independent password-protected backup. Older
executables may not read an upgraded database or newer backup format. A rollback
must use an app compatible with the backup it restores; document the exact recovery
path and warn that restoring an older backup loses later edits. Never test recovery
by overwriting the only dataset. See [phone testing](phone-testing.md).

Software updates do not transfer receipts between PC and phone. Until sync exists,
treat the installations as separate datasets. Backup transfer is a reviewed dataset
replacement, not an automatic merge.
