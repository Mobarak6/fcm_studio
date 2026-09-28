import 'package:flutter/material.dart';

/// Asks for one line of text. Returns null when cancelled.
Future<String?> promptForText(
  BuildContext context, {
  required String title,
  required String label,
  String initial = '',
  String confirmLabel = 'Save',
}) => showDialog<String>(
  context: context,
  builder: (_) => PromptDialog(
    title: title,
    label: label,
    initial: initial,
    confirmLabel: confirmLabel,
  ),
);

class PromptDialog extends StatefulWidget {
  const PromptDialog({
    required this.title,
    required this.label,
    required this.initial,
    required this.confirmLabel,
    super.key,
  });

  static const fieldKey = Key('prompt-field');
  static const confirmKey = Key('prompt-confirm');

  final String title;
  final String label;
  final String initial;
  final String confirmLabel;

  @override
  State<PromptDialog> createState() => _PromptDialogState();
}

class _PromptDialogState extends State<PromptDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial)
        ..selection = TextSelection(
          baseOffset: 0,
          extentOffset: widget.initial.length,
        );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 380,
        child: TextField(
          key: PromptDialog.fieldKey,
          controller: _controller,
          autofocus: true,
          decoration: InputDecoration(labelText: widget.label),
          onSubmitted: (text) => Navigator.of(context).pop(text),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: PromptDialog.confirmKey,
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
