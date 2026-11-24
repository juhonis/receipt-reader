import 'package:material_ui/material_ui.dart';

import 'l10n/generated/app_localizations.dart';

class DashboardInfoButton extends StatelessWidget {
  const DashboardInfoButton({
    super.key,
    required this.title,
    required this.paragraphs,
    this.actions = const [],
  });
  final String title;
  final List<String> paragraphs;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: title,
    icon: const Icon(Icons.info_outline, size: 20),
    onPressed: () => showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        scrollable: true,
        content: SizedBox(
          width: 520,
          child: Text(paragraphs.where((p) => p.isNotEmpty).join('\n\n')),
        ),
        actions: [
          ...actions,
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(AppLocalizations.of(context)!.catalogClose),
          ),
        ],
      ),
    ),
  );
}
