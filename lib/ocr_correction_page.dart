import 'package:material_ui/material_ui.dart';
import 'package:receipt_parser/receipt_parser.dart' show OcrPage, formatCents;
import 'package:receipt_storage/receipt_storage.dart' show StoredReceipt;

import 'l10n/generated/app_localizations.dart';
import 'local_store.dart';
import 'receipt_format.dart';
import 'receipt_import.dart';
import 'review_page.dart';

/// Acquires fresh route-owned pixels; saved assertions never authorize a review.
class OcrCorrectionPage extends StatefulWidget {
  OcrCorrectionPage({
    super.key,
    required this.store,
    required this.receipt,
    this.imagePicker = pickReceiptImage,
    this.cameraCapture = captureReceiptImage,
    this.recognizer,
  }) {
    if (receipt.document.review.source != 'ocr') {
      throw ArgumentError.value(receipt, 'receipt', 'OCR receipt required');
    }
  }
  final LocalStore store;
  final StoredReceipt receipt;
  final Future<ReceiptEvidence?> Function() imagePicker;
  final Future<ReceiptEvidence?> Function() cameraCapture;
  final Future<OcrPage> Function(ReceiptEvidence)? recognizer;
  @override
  State<OcrCorrectionPage> createState() => _OcrCorrectionPageState();
}

class _OcrCorrectionPageState extends State<OcrCorrectionPage> {
  bool _confirmed = false, _importing = false;
  ImportFailure? _failure;

  Future<void> _import({bool camera = false}) async {
    if (!_confirmed || _importing) return;
    setState(() {
      _importing = true;
      _failure = null;
    });
    ReceiptEvidence? evidence;
    try {
      evidence = await (camera ? widget.cameraCapture : widget.imagePicker)();
      if (!mounted || evidence == null) return;
      final changed = await Navigator.push<bool>(
        context,
        MaterialPageRoute<bool>(
          builder: (_) => ReviewPage.correction(
            store: widget.store,
            receipt: widget.receipt,
            evidence: evidence!,
            recognizer: widget.recognizer,
          ),
        ),
      );
      if (mounted && changed == true) Navigator.pop(context, true);
    } on ReceiptImportException catch (error) {
      if (mounted) setState(() => _failure = error.failure);
    } catch (_) {
      if (mounted) setState(() => _failure = ImportFailure.unreadable);
    } finally {
      evidence?.dispose();
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final snapshot = widget.receipt.document.snapshot;
    return Scaffold(
      appBar: AppBar(title: Text(s.correctOcrReceipt)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(snapshot.branch.name),
                Text(receiptDateText(snapshot.date)),
                Text('${formatCents(snapshot.totalCents)} €'),
                Text(s.ocrCorrectionNotice),
                CheckboxListTile(
                  key: const Key('ocr-correction-original'),
                  title: Text(s.ocrCorrectionOriginal),
                  value: _confirmed,
                  onChanged: _importing
                      ? null
                      : (v) => setState(() => _confirmed = v ?? false),
                ),
                if (supportsReceiptCamera)
                  FilledButton.icon(
                    key: const Key('ocr-correction-camera'),
                    onPressed: _confirmed && !_importing
                        ? () => _import(camera: true)
                        : null,
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: Text(s.captureReceipt),
                  ),
                FilledButton.icon(
                  key: const Key('ocr-correction-image'),
                  onPressed: _confirmed && !_importing ? _import : null,
                  icon: const Icon(Icons.image_outlined),
                  label: Text(_importing ? s.importLoading : s.importImage),
                ),
                if (_failure != null)
                  Text(switch (_failure!) {
                    ImportFailure.tooLarge => s.importTooLarge,
                    ImportFailure.unsupported => s.importUnsupported,
                    ImportFailure.unreadable => s.importUnreadable,
                    ImportFailure.cameraDenied => s.cameraDenied,
                    ImportFailure.cameraUnavailable => s.cameraUnavailable,
                    ImportFailure.captureFailed => s.cameraFailed,
                  }),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
