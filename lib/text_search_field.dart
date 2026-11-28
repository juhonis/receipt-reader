import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'l10n/generated/app_localizations.dart';

/// Keep typing responsive while avoiding a database scan for every keystroke.
class TextSearchField extends StatefulWidget {
  const TextSearchField({
    super.key,
    required this.fieldKey,
    required this.value,
    required this.label,
    required this.hint,
    required this.onChanged,
    this.enabled = true,
  });
  final String fieldKey, value, label, hint;
  final ValueChanged<String> onChanged;
  final bool enabled;

  @override
  State<TextSearchField> createState() => _TextSearchFieldState();
}

class _TextSearchFieldState extends State<TextSearchField> {
  late final _controller = TextEditingController(text: widget.value);
  late String _submittedValue = widget.value;
  Timer? _debounce;

  void _submit(String value) {
    _debounce?.cancel();
    _submittedValue = value;
    widget.onChanged(value);
  }

  @override
  void didUpdateWidget(TextSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) _debounce?.cancel();
    // A delayed parent rebuild may acknowledge an earlier submitted query after
    // the user has already continued typing. Only external resets replace text.
    if (oldWidget.value != widget.value && widget.value != _submittedValue) {
      _debounce?.cancel();
      if (_controller.text != widget.value) _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    key: Key(widget.fieldKey),
    controller: _controller,
    enabled: widget.enabled,
    maxLength: 200,
    textInputAction: TextInputAction.search,
    decoration: InputDecoration(
      labelText: widget.label,
      hintText: widget.hint,
      counterText: '',
      prefixIcon: const Icon(Icons.search),
      suffixIcon: _controller.text.isEmpty
          ? null
          : IconButton(
              key: Key('${widget.fieldKey}-clear'),
              tooltip: AppLocalizations.of(context)!.clearSearch,
              onPressed: widget.enabled
                  ? () {
                      setState(_controller.clear);
                      _submit('');
                    }
                  : null,
              icon: const Icon(Icons.clear),
            ),
    ),
    onChanged: (value) {
      setState(() {});
      _debounce?.cancel();
      _debounce = Timer(
        const Duration(milliseconds: 250),
        () => _submit(value),
      );
    },
    onSubmitted: _submit,
  );
}
