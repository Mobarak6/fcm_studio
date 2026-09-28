import 'package:flutter/material.dart';

typedef PresetDetails = ({String name, String description});

Future<PresetDetails?> showPresetDetailsDialog(
  BuildContext context, {
  required String title,
  required bool Function(String name) isNameTaken,
  String name = '',
  String description = '',
}) => showDialog<PresetDetails>(
  context: context,
  builder: (_) => PresetDetailsDialog(
    title: title,
    isNameTaken: isNameTaken,
    name: name,
    description: description,
  ),
);

/// Asks for a preset's name and description. Names must be unique.
class PresetDetailsDialog extends StatefulWidget {
  const PresetDetailsDialog({
    required this.title,
    required this.isNameTaken,
    this.name = '',
    this.description = '',
    super.key,
  });

  static const nameKey = Key('preset-name');
  static const descriptionKey = Key('preset-description');
  static const saveKey = Key('preset-details-save');

  final String title;
  final bool Function(String name) isNameTaken;
  final String name;
  final String description;

  @override
  State<PresetDetailsDialog> createState() => _PresetDetailsDialogState();
}

class _PresetDetailsDialogState extends State<PresetDetailsDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.name,
  );
  late final TextEditingController _description = TextEditingController(
    text: widget.description,
  );
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a name.');
      return;
    }
    if (widget.isNameTaken(name)) {
      setState(() => _error = 'A preset named "$name" already exists.');
      return;
    }
    Navigator.of(
      context,
    ).pop((name: name, description: _description.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: PresetDetailsDialog.nameKey,
              controller: _name,
              autofocus: true,
              decoration: InputDecoration(labelText: 'Name', errorText: _error),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 12),
            TextField(
              key: PresetDetailsDialog.descriptionKey,
              controller: _description,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: PresetDetailsDialog.saveKey,
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
