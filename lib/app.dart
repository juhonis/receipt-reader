import 'package:cupertino_ui/cupertino_ui.dart'
    show GlobalCupertinoLocalizations;
import 'package:flutter_localizations/flutter_localizations.dart'
    show GlobalWidgetsLocalizations;
import 'package:material_ui/material_ui.dart';

import 'l10n/generated/app_localizations.dart';
import 'review_page.dart';
import 'receipt_import.dart';

class ReceiptReaderApp extends StatelessWidget {
  const ReceiptReaderApp({super.key, this.imagePicker = pickReceiptImage});
  final Future<ReceiptEvidence?> Function() imagePicker;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('fi'),
      // Flutter's generated delegate list still uses the legacy UI shims.
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
      ),
      home: _HomePage(imagePicker: imagePicker),
    );
  }
}

class _HomePage extends StatefulWidget {
  const _HomePage({required this.imagePicker});
  final Future<ReceiptEvidence?> Function() imagePicker;
  @override
  State<_HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<_HomePage> {
  bool _importing = false;
  ImportFailure? _failure;

  Future<void> _import() async {
    if (_importing) return;
    setState(() {
      _importing = true;
      _failure = null;
    });
    try {
      final evidence = await widget.imagePicker();
      if (!mounted) {
        evidence?.dispose();
        return;
      }
      if (evidence != null) {
        try {
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ReviewPage(evidence: evidence),
            ),
          );
        } finally {
          evidence.dispose();
        }
      }
    } on ReceiptImportException catch (error) {
      if (mounted) {
        setState(() {
          _failure = error.failure;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _failure = ImportFailure.unreadable;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _importing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(strings.appTitle)),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.receipt_long_outlined, size: 64),
                  const SizedBox(height: 24),
                  Text(
                    strings.welcomeTitle,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  Text(strings.developmentNotice, textAlign: TextAlign.center),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _importing ? null : _import,
                    icon: const Icon(Icons.image_outlined),
                    label: Text(
                      _importing ? strings.importLoading : strings.importImage,
                    ),
                  ),
                  if (_failure != null)
                    Text(switch (_failure!) {
                      ImportFailure.tooLarge => strings.importTooLarge,
                      ImportFailure.unsupported => strings.importUnsupported,
                      ImportFailure.unreadable => strings.importUnreadable,
                    }),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const ReviewPage(),
                      ),
                    ),
                    child: Text(strings.startReview),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
