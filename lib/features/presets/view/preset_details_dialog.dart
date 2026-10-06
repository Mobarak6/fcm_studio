import 'package:flutter/material.dart';

typedef PresetDetails = ({String name, String description, String group});

Future<PresetDetails?> showPresetDetailsDialog(
  BuildContext context, {
  required String title,
  required bool Function(String name, String group) isNameTaken,
  String name = '',
  String description = '',
  String group = '',
  List<String> groups = const [],
}) => showDialog<PresetDetails>(
  context: context,
  builder: (_) => PresetDetailsDialog(
    title: title,
    isNameTaken: isNameTaken,
    name: name,
    description: description,
    group: group,
    groups: groups,
  ),
);

/// Asks for a preset's name, description and group. Names must be unique
/// within the group.
class PresetDetailsDialog extends StatefulWidget {
  const PresetDetailsDialog({
    required this.title,
    required this.isNameTaken,
    this.name = '',
    this.description = '',
    this.group = '',
    this.groups = const [],
    super.key,
  });

  static const nameKey = Key('preset-name');
  static const descriptionKey = Key('preset-description');
  static const groupKey = Key('preset-group');
  static const saveKey = Key('preset-details-save');

  final String title;
  final bool Function(String name, String group) isNameTaken;
  final String name;
  final String description;
  final String group;

  /// The existing groups, suggested while typing a group.
  final List<String> groups;

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
  late final TextEditingController _group = TextEditingController(
    text: widget.group,
  );
  final FocusNode _groupFocus = FocusNode();
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _group.dispose();
    _groupFocus.dispose();
    super.dispose();
  }

  /// The groups that hold the typed text, ignoring case. The group typed
  /// exactly isn't suggested, so a chosen suggestion closes the list.
  Iterable<String> _suggestions(TextEditingValue value) {
    final typed = value.text.trim().toLowerCase();
    return widget.groups.where((group) {
      final candidate = group.toLowerCase();
      return candidate != typed && candidate.contains(typed);
    });
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a name.');
      return;
    }
    final group = _group.text.trim();
    if (widget.isNameTaken(name, group)) {
      setState(
        () => _error = group.isEmpty
            ? 'A preset named "$name" already exists.'
            : 'A preset named "$name" already exists in $group.',
      );
      return;
    }
    Navigator.of(
      context,
    ).pop((name: name, description: _description.text.trim(), group: group));
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
            const SizedBox(height: 12),
            Autocomplete<String>(
              textEditingController: _group,
              focusNode: _groupFocus,
              optionsBuilder: _suggestions,
              // Below the field, the list would cover Save and Cancel.
              optionsViewOpenDirection: OptionsViewOpenDirection.up,
              fieldViewBuilder:
                  (context, controller, focusNode, onFieldSubmitted) =>
                      TextField(
                        key: PresetDetailsDialog.groupKey,
                        controller: controller,
                        focusNode: focusNode,
                        decoration: const InputDecoration(
                          labelText: 'Group (optional)',
                        ),
                        // Enter saves what was typed, like the Name field;
                        // a suggestion is picked by clicking it.
                        onSubmitted: (_) => _save(),
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
