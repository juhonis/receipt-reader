# Releases and updates

Planned November 25, 2026. No GitHub Actions workflow, production signing or
in-app updater is implemented yet. The [roadmap](plan.md) defines the order of work.
The first distribution channel will be personal-use alpha pre-releases in the
public GitHub repository, with Android APK and Windows x64 ZIP assets.

## Before making the repository public

Public source and published binaries are separate steps. Choose an application
license before publication; none is selected yet. MIT is a possible permissive
choice, not an approval already given. Personal use does not make public binaries
private or restrict who can download them.

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

Finish a full history/content review before changing visibility. Check repository
settings, workflow permissions and published artifacts as well as source files.
Changing visibility remains an explicit owner action.

## Signing and version identity

Android keeps `fi.juhonis.receipt_reader` as its application ID. Establish a
permanent release keystore before retaining real phone data; the current Gradle
release configuration uses the local debug key. Keep the keystore and credentials
out of Git, back them up independently, and place only the required copies in
protected CI secrets. Losing the key can prevent updates to the installed app.

Every upgrade needs the same signing identity and a greater Android versionCode.
Different debug keys, CI-generated keys and a production key are not interchangeable.
Keep the emulator's debug/test installation separate from the phone's release
installation. Never solve a signature mismatch by clearing valuable application data.

Use `pubspec.yaml` as the version source; derive the displayed version rather than
manually maintaining `lib/app_version.dart`. For example, `0.2.0-alpha.1+2` could map
to tag `v0.2.0-alpha.1` and Android build 2. Increase the build number for every
distributed APK; reject tag/version mismatches and asset replacement for published
versions. Artifacts should identify platform, version and build unambiguously.

Windows initially keeps the portable ZIP. Preserve existing notice/runtime audits
and settle applicable distribution conditions. Assess Authenticode signing before
broader distribution. A release checksum detects corruption; it does not substitute
for publisher signing. See [dependency terms and notices](dependency-licenses.md).

## Proposed GitHub Actions pipeline

1. Pull requests run analysis, app/shared-package tests and relevant tooling checks
   without release credentials. Pin the Flutter SDK, dependencies and action revisions.
2. An approved version tag runs the release checks, confirms a clean source/version
   identity, prepares the pinned Windows OCR bundle, and builds Windows ZIP and
   release-signed Android APK. CI must not depend on this PC's local SDK/cache paths.
3. Validate packaged notices, native dependencies, final Android permissions and
   signing certificate. Use the [existing audit tools](dependency-licenses.md#reproduce-and-update).
   An intentional permission change must update the permission audit expectation.
4. Produce versioned assets, SHA-256 checksums, sanitized commit/build provenance,
   and brief user-facing release notes with compatibility/known-issue information.
   Upload to a **draft pre-release** with narrowly scoped release permissions.
5. Test those exact downloads on the phone and second Windows PC: offline startup,
   recognition/save/reopen, backup/recovery and a previous-alpha upgrade. Publish
   explicitly after acceptance. Ordinary commits do not automatically ship updates.

Protect signing and release jobs with trusted tags/branches and a protected
environment as appropriate. Do not expose secrets to fork PRs or run untrusted
contributor code in a privileged release context. External contributions do not
become trusted merely because the repository is public.

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
