# License evidence tooling

See [the audit and update procedure](../../docs/dependency-licenses.md). These
tools read only public dependency/toolchain artifacts, never private receipts or
application databases. They add no runtime dependency or network request.

`android-inventory.init.gradle` resolves the app's external release artifacts and
POMs without the variant ambiguity of project/plugin artifacts. It runs only in
the root Android application build, not Flutter's included Gradle build.

`audit.py --generate` writes the reviewed `third_party` inventory and supplemental
notices. With no arguments it regenerates in memory and refuses drift. `--windows`
and `--apk` verify actual built notice assets; the Windows check is also mandatory
inside the ZIP packager. `test_audit.py` exercises UTF-8 byte ranges, malformed
offsets, nested JAR notices and rejection of missing/truncated notice text.

The audit intentionally retains upstream aggregate notices and full Dart source
license texts even when they duplicate generated Flutter entries. Grouping and
whitespace do not discard attribution, license conditions or runtime exceptions.
Use the recorded source/display hashes to review updates; do not hand-edit the
generated files or treat collection as approval of unfamiliar terms.
