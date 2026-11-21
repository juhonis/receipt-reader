import 'package:material_ui/material_ui.dart';

import 'l10n/generated/app_localizations.dart';
import 'manual_receipt_page.dart' show receiptAppVersion;

class SoftwareInfoPage extends StatelessWidget {
  const SoftwareInfoPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(s.softwareInfoTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(s.appTitle, style: Theme.of(context).textTheme.headlineSmall),
            const Text(receiptAppVersion),
            const SizedBox(height: 20),
            Text(s.softwareInfoEngines),
            const SizedBox(height: 12),
            Text(s.softwareInfoPrivacy),
            const SizedBox(height: 12),
            Text(s.softwareInfoTerms),
            const SelectableText(
              'https://developers.google.com/ml-kit/terms\n'
              'https://developers.google.com/terms\n'
              'https://developers.google.com/ml-kit/android-data-disclosure',
            ),
            const SizedBox(height: 20),
            FilledButton(
              key: const Key('open-license-page'),
              onPressed: () => showLicensePage(
                context: context,
                applicationName: s.appTitle,
                applicationVersion: receiptAppVersion,
              ),
              child: Text(s.softwareInfoLicenses),
            ),
            const SizedBox(height: 12),
            Text(s.softwareInfoLicenseScope),
          ],
        ),
      ),
    );
  }
}
