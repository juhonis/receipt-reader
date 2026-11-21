# Windows OCR clean-machine test

Use the second Windows PC without Flutter, Python or Tesseract installed. This is
verification of a development build, not an installer or public release. Windows
x64 is the current target. Do not install OCR tools to make a failing test pass.

1. Copy receipt-reader-windows-x64-dev.zip to the PC using USB or your preferred
   transfer method. Extract the entire Receipt Reader folder to a writable local
   location. Keep the ocr and data folders beside receipt_reader.exe.
2. Disconnect the PC from the network BEFORE first launch. Run receipt_reader.exe.
   Record any missing-DLL, model-download or startup message. The ZIP includes the
   Visual C++ runtime; a separate runtime installation should not be necessary.
   An unsigned-build Windows warning may appear; this build is not signed.
3. From the home screen choose the image-import action and select the included
   synthetic_receipt.png. This image is entirely synthetic and contains no personal
   purchase information. Keep it unchanged for the second attempt.
4. Choose Tunnista kuitin teksti. Recognition should finish without a download or
   network connection. Check that text boxes align with the displayed source and
   that Ä in YHTEENSÄ is handled sensibly. Recognition errors should remain visible
   for correction, never silently accepted as reviewed information.
5. Check/adjust the proposed boundaries: product rows start below the date, and
   amounts are at the right edge. Choose Muodosta riviehdotus näillä rajoilla.
   Expected source: store SYNTHETIC TEST STORE, date 18.11.2026, MILK 2,00 €, BREAD
   3,00 €, total 5,00 €. Report any omitted, duplicated or incorrect text/amounts.
6. Set the store identity explicitly: OCR does not select a saved branch. On an
   empty installation the new-branch name field is editable immediately. Enter
   SYNTHETIC TEST STORE (test only). If branches already exist, select the correct
   one or choose Luo uusi toimipiste and enter the name/location. No separate
   branch-confirmation checkbox is required.
7. Compare the displayed date, BOTH product rows and total with the source image.
   Correct any errors and resolve remaining interpretation findings. There are
   no per-row comparison checkboxes. Matching totals do not prove OCR correctness.
8. Optionally open Tarkista vaiheittain, complete the four checks and choose
   Tarkistus valmis. No note is required. The guide does not save or bypass
   errors; editing afterwards does not force another pass through the guide.
9. With no unresolved validation problems, Hyväksy ja tallenna should be enabled.
   Use it to approve the displayed information and save directly. Reopen History
   and check both rows and 5,00 € total. If saving is disabled, report the
   highlighted problem text. Try an incorrect total first: saving must be disabled
   until it is corrected, even after completing the optional guide. Never approve
   wrong information merely to finish the test.
10. Import the same image again and verify it still opens correctly. Close a review
   while recognition is running, then retry from a new import. The app should stay
   usable, without a console window or leftover OCR process.
11. Close the app, move the ENTIRE extracted folder to another local path containing
   spaces or Finnish characters, and repeat recognition while still offline.
   Receipt databases live in Windows application-support storage and therefore do
   not move with this ZIP. Moving/deleting the extracted program is not a backup or
   deletion of saved receipt history.
12. While still offline, open the home-screen information action, Tietoja ja
   lisenssit, then Näytä ohjelmistolisenssit. The list and a selected license
   should open without downloading anything. The ZIP also includes readable
   THIRD-PARTY-NOTICES.txt and the exact THIRD-PARTY-COMPONENTS.json inventory.

Please report:

- Windows version and whether this is an x64 PC.
- Startup, missing-DLL or model-download messages, if any.
- Whether the expected date, two item amounts and total were recognized.
- Whether boxes aligned with the image and Finnish letters looked reasonable.
- Whether cancellation/retry and the moved-folder test worked.
- BUILD-INFO.json commit and the ZIP SHA-256 from windows-ocr-evidence.json.

No real receipt images are needed. Keep normal user data and independent encrypted
backups safe. This test does not certify OCR accuracy across actual store layouts,
physical camera capture, code signing, or final redistribution-license compliance.
