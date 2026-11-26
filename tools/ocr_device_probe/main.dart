// Local-only release-mode OCR probe. Never publish this entry point.
// Anonymous private inputs must be staged in cache/receipt-private-ocr-check.
// Only statuses/counts are displayed; no receipt text or images are persisted.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:receipt_parser/receipt_parser.dart';
import 'package:receipt_reader/receipt_import.dart';
import 'package:receipt_reader/receipt_ocr.dart';

void main() => runApp(const MaterialApp(home: _Probe()));

class _Probe extends StatefulWidget {
  const _Probe();
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  final _statuses = <String>[];
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    if (!const bool.fromEnvironment('PRIVATE_OCR_CHECK')) return;
    final cache = await getTemporaryDirectory();
    for (var sample = 1; sample <= 3; sample++) {
      ReceiptEvidence? evidence;
      var status = 'sample $sample: ';
      try {
        evidence = await ReceiptEvidence.decode(
          await File(
            '${cache.path}/receipt-private-ocr-check/input-$sample.jpg',
          ).readAsBytes(),
        );
        final page = await recognizeReceipt(evidence);
        final proposal = proposeLayout(page);
        status += 'OK words=${page.words.length} layout=${proposal.available}';
      } catch (error) {
        status += error is PlatformException
            ? 'native:${error.code}'
            : error.runtimeType.toString();
      } finally {
        evidence?.dispose();
      }
      if (!mounted) return;
      setState(() => _statuses.add(status));
    }
    if (mounted) setState(() => _statuses.add('PROBE COMPLETE'));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('${kReleaseMode ? 'Release' : 'Debug'} OCR probe'),
    ),
    body: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [for (final status in _statuses) Text(status)],
      ),
    ),
  );
}
