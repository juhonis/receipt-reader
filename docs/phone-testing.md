# Testing on a real Android phone

Start with a permanently signed alpha APK, then use successive GitHub pre-releases
for everyday testing. This workflow is planned; there is no published signed alpha
yet. See [release preparation](releases.md) for signing and distribution work.

## First installation

1. Record phone model and Android version. A developer build can use USB debugging
   and `flutter devices`; ordinary APK installation does not require debugging.
2. If this package is already installed, record its version/signing origin and
   export an encrypted backup before changing signing or installation methods.
   Stop on a signature mismatch; do not uninstall/clear data to get past it.
3. Download the signed APK from the official repository's release, check the
   expected version/build, and approve installation through Android. Keep source
   installation permission scoped to the browser/file manager used for the APK.
4. Start offline and import the synthetic receipt before relying on the app with
   real data. A successful install alone is not an OCR/recovery test.
5. Create a password-protected backup, keep an independent copy outside app-private
   storage, and retain its password. Do not commit the backup or password.

The permanent signing key must exist before this retained installation. Do not
install emulator debug APKs, integration-test entry points or a differently signed
build over the phone's real dataset. Use the emulator for automated native tests.

## Everyday acceptance checklist

- [ ] First launch and receipt OCR work without internet or model downloads.
- [ ] Import JPEG/PNG through the actual phone picker. Until in-app camera capture
  is implemented, photograph a receipt with the phone's camera and import it.
  That original stays in the gallery/files and may follow the phone's own backups.
- [ ] Verify branch, date, product rows, quantities, discounts, deposits/returns and
  printed total; correct problems, approve, save and reopen. Totals alone do not
  prove recognition accuracy. Try a realistic long/crumpled or poorly lit receipt.
- [ ] Use the keyboard, scrolling, zoom and review controls on the physical screen.
  Check text scaling and dense dashboard layouts, including week/month/year/custom
  periods, branch filters, spending comparisons, category shares and product history.
- [ ] Correct a saved receipt/category and confirm affected graphs update. Test
  deletion only with a disposable sample; retain the real data you want to keep.
- [ ] Export through the native backup picker and rehearse reviewed recovery with
  disposable data/an isolated test installation, preserving the original dataset.
  Do not overwrite the only live copy to test restore.
- [ ] Repeat cancel/retry, background/resume and app close/reopen. Confirm receipt
  originals remain unchanged and follow the planned privacy/temporary-file audit.

Capture/layout-specific failures are expected alpha feedback, not a claim of
universal Finnish receipt support. Record what was wrong and how it was corrected.

## Next-release upgrade

1. Record the installed version and a few receipt totals/counts, catalog links and
   chart results. Export an encrypted backup and verify the independent copy exists.
2. Download the next alpha APK from the official release. Confirm it uses the same
   signing identity and a greater build number; approve the system upgrade.
3. Open existing receipts, history and graphs; import/save another receipt, then
   close/reopen. Check catalog/categories and the backup export still work.
4. Repeat once offline. Record the exact release/build and device for the result.

The release loop is ready when two successive signed builds pass this upgrade
check. An older APK is not a guaranteed rollback after database migrations; use
[the documented compatible-backup recovery path](releases.md#installation-and-recovery).

## Useful feedback

Record app version/build, phone/Android version, screen/step, expected behavior,
actual behavior and whether it repeats. Screenshots and original receipts may
contain financial, location or loyalty data: keep them private or anonymize them
before posting in a public issue. Never post a backup, signing key or password.

PC and phone data remain independent until synchronization is implemented. Do not
edit two copied datasets expecting encrypted backup restore to merge them.
