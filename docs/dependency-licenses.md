# Dependency notices and redistribution audit

Reviewed November 21, 2026 against the pinned development builds. This milestone
changes notice collection, artifact checks and the information screen. It does
not change OCR engines, dependency versions, receipt data or database schemas.

## Findings and changes

| Area | Evidence and handling |
| --- | --- |
| Dart/Flutter | 69 package identities in the production dependency closure, including first-party packages, platform alternatives and build-hook dependencies. Notice families and source hashes are recorded. Flutter's engine has an aggregate notice with its own component terms. |
| Android native dependencies | 73 distinct resolved release artifacts, including bundled ML Kit 16.0.1, its Google/AndroidX dependencies, Flutter's embedding and target ABI artifacts. POM license declarations and embedded AAR/JAR notices are retained. |
| Supplemental notices | 172 deduplicated text blocks retain complete copyright, conditions, disclaimers, source references and exceptions. Identical text can have several component labels. Only line endings and indentation of literal Flutter separator lines are normalized. The engine aggregate keeps its separate readable entries from Flutter. |
| Windows OCR | Tesseract 5.5.1 and the pinned Finnish/English tessdata_fast models use Apache-2.0; Leptonica 1.85.0 uses its BSD-2-Clause-style license. Source/model hashes and the original notice files remain pinned in the OCR bundle. No NOTICE file was present in the pinned Tesseract archive. |
| SQLite | The native binary comes from sqlite3.dart 3.9.1; the observed Windows SQLite engine is 3.54.1. The Windows DLL matches the package's asset hash. Android's stripped binaries match after reproducing AGP's strip transformation on all three verified input assets. SQLite's public-domain status is separate from its MIT-licensed Dart wrapper. |
| Android native bridge/toolchain | JNI's generated Android header copyright, Dart native API copyright/full SDK license, and NDK 28.2.13676358 sysroot notices are explicitly retained. The JNI library builds as C rather than introducing a separate C++ shared runtime. |
| Microsoft runtime | The ZIP copies unmodified x64 Microsoft.VC143.CRT redistributable files, never debug_nonredist. BUILD-INFO records their version and individual hashes. Microsoft's redistribution rights depend on its terms and builder entitlement. |

Two concrete gaps were fixed. Flutter's generated notices did not automatically
cover the native Google SDK's embedded notices. A generated Flutter entry also
contained a copyright stub referring to a LICENSE file rather than the complete
license text. Supplemental copies now retain the full simple-package/SDK texts
alongside Flutter's complete engine aggregate. Artifact checks reject either
omission instead of merely checking that NOTICES.Z exists.

The app's home-screen information action opens **Tietoja ja lisenssit**. Its
license screen reads the packaged notices offline. Vendor terms and SDK metrics
information are explained separately; reading licenses never opens a browser or
downloads notice text. The Windows ZIP additionally contains readable
THIRD-PARTY-NOTICES.txt and THIRD-PARTY-COMPONENTS.json.

## Scope of the recorded inventory

[third_party/dependencies.json](../third_party/dependencies.json) records public
coordinates/versions, declared license families, POM/artifact/notice hashes,
Flutter/Dart revisions, OCR source/model pins and native SQLite asset hashes.
It contains no local usernames, cache paths, receipt images or application data.
[third_party/NOTICES.txt](../third_party/NOTICES.txt) is generated from those public
dependency files and included through Flutter's additional-license mechanism.

This is deliberately a conservative inventory. Alternative-platform packages,
build hooks and publishers' broader aggregate notices can appear even when their
code is not included in a particular executable. The aggregate notices include
MPL-covered entries such as Eigen and GPL text accompanied by the GCC Runtime
Library Exception. Those texts, exceptions and upstream source references are
preserved; neither a GPL keyword nor a top-level Apache declaration alone decides
the license of the application. Do not remove exceptions or source references
when updating the generated files.

The one explicit inherited-POM case is listenablefuture 1.0, whose Apache-2.0
declaration comes from guava-parent 26.0-android. The namespace-free javax.inject
POM is parsed normally. Flutter's native Maven artifacts are tied to the exact
engine revision and covered by the SDK aggregate rather than an invented Maven
license declaration. Platform-plugin project code is covered by its pub-package
source notices; the Maven inventory excludes Gradle project artifacts.

Unfamiliar license declarations fail inventory generation for review.
Changing build inputs, SDK revisions, source license texts or supplemental notices
invalidates the recorded review. Generation is an explicit maintainer action;
it is not an automatic legal approval of a new dependency.

## Vendor terms and release decisions

ML Kit's SDK/model terms are not the Apache license printed below its web code
samples. Its POMs identify the [ML Kit terms](https://developers.google.com/ml-kit/terms),
which incorporate the [Google APIs terms](https://developers.google.com/terms).
Other Google components identify the [Android SDK terms](https://developer.android.com/studio/terms.html).
The embedded open-source notices supplement those vendor terms.

Google documents on-device receipt-content processing and SDK diagnostics/usage
metrics, and requires appropriate user disclosure. The information screen now
mentions this distinction. The current Android release manifest removes INTERNET
and ACCESS_NETWORK_STATE; debug builds retain debugger networking. This is not a
claim that a network-enabled ML Kit build disables telemetry. Enabling networking
for future sync requires another permission/disclosure review. The disclosure
page describes current SDKs, so retain the pinned version evidence as well.

Microsoft's [VS 2022 redistribution list](https://learn.microsoft.com/visualstudio/releases/2022/redistribution)
permits the specified unmodified runtime files subject to its license terms.
This machine has VS 2022 Build Tools installed. Installation and copied files do
not prove the owner's licensing entitlement. Before public distribution, confirm
that entitlement under the [Microsoft licensing guidance](https://www.microsoft.com/licensing/guidance/Visual-Studio).
The repository currently has no chosen application LICENSE. No MIT, Apache or
proprietary application license has been selected on the owner's behalf.

Before publishing, the owner still needs to decide the application's licensing
and end-user terms, confirm applicable Google/Microsoft conditions and retained
source-availability references, and choose signing/distribution credentials.
These are separate from the verified notice coverage. Public-release readiness
remains false; a development ZIP is not a signed public release.
The Android release artifact currently uses the development debug signing
configuration; no production signing credentials were added or used.

## Reproduce and update

Use the Windows toolchain described in [development setup](windows-development.md).
After dependency/build-input changes, refresh the resolved inventory first:

```powershell
$env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr'
./android/gradlew.bat -p android -I ../tools/licenses/android-inventory.init.gradle :app:receiptLicenseInventory --console=plain
python tools/licenses/audit.py --generate
python tools/licenses/audit.py
python -m unittest discover -s tools/licenses -p 'test_*.py'
flutter analyze
flutter test
flutter build windows --release
python tools/licenses/audit.py --windows build/windows/x64/runner/Release
flutter build apk --release
python tools/licenses/audit.py --apk build/app/outputs/flutter-apk/app-release.apk
python tools/windows_ocr/package.py
```

Review new components/terms and update the explicit review date when changing
pins. Commit the generated inventory and notices together with dependency changes.
The build-local inventory contains cache paths and is intentionally not committed.
After flutter clean, rerun Windows OCR setup before regenerating its evidence.

The packager requires the reviewed inputs, validates every retained Dart notice
body and the complete supplemental text inside the actual compressed asset,
checks Windows SQLite provenance, then copies the readable notices and inventory.
The APK check validates its actual packaged notice asset, reproduces SQLite
stripping with the pinned NDK, and inspects final permissions with aapt2. It writes
build/licenses/android-release-evidence.json with the APK/native-library hashes,
inventory hash and observed permissions. Neither substitutes for the separate
Windows native-import audit or end-user acceptance.

## Primary references

- [Flutter LicenseRegistry and generated notices](https://api.flutter.dev/flutter/foundation/LicenseRegistry-class.html)
- [Google's native notice-display guidance](https://developers.google.com/android/guides/opensource)
- [ML Kit Android data disclosure](https://developers.google.com/ml-kit/android-data-disclosure)
- [Guava's exact inherited parent POM](https://repo.maven.apache.org/maven2/com/google/guava/guava-parent/26.0-android/guava-parent-26.0-android.pom)
- [Pinned Tesseract license](https://github.com/tesseract-ocr/tesseract/blob/5.5.1/LICENSE)
- [Pinned Leptonica license](https://github.com/DanBloomberg/leptonica/blob/1.85.0/leptonica-license.txt)
- [Pinned model license](https://github.com/tesseract-ocr/tessdata_fast/blob/87416418657359cb625c412a48b6e1d6d41c29bd/LICENSE)
- [SQLite copyright and redistribution statement](https://sqlite.org/copyright.html)

## Verification for this milestone

- All 150 app tests and app analysis pass; the four Python audit tests pass.
- The native license screen opens a retained Google SDK notice and its license
  text on Windows and on the Android emulator in airplane mode. The test binding
  disables Flutter's automatic registry, so the integration test registers the
  actual packaged asset explicitly; ordinary startup uses ServicesBinding.
- Windows Release notices retain all 1,661 source engine notice bodies, full
  package/SDK license text and the supplemental notices. The Windows SQLite DLL
  matches the published package asset hash.
- The release APK carries 15 native libraries across three ABIs. Its packaged
  notices pass validation, all three SQLite binaries match their verified inputs
  after reproducing stripping, and aapt2 reports neither INTERNET nor
  ACCESS_NETWORK_STATE. The sole requested permission is the app's generated
  DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION.
- The supplemental notice format resolves all 338 recorded component labels;
  no expected label is lost or extra label introduced by separator parsing.
- Audit tools and license-page smoke tests do not open receipts or application databases.
  The normal Windows Debug/Release and Android Debug entry points are restored
  after the native tests, and the prior emulator airplane setting is restored.
