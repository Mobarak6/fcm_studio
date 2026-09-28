import 'package:fcm_studio/features/presets/domain/variable_def.dart';
import 'package:flutter/material.dart';

Future<List<VariableDef>?> showVariablesDialog(
  BuildContext context,
  List<VariableDef> variables,
) => showDialog<List<VariableDef>>(
  context: context,
  builder: (_) => VariablesDialog(initial: variables),
);

/// Adds, edits and removes variable definitions (spec §6).
class VariablesDialog extends StatefulWidget {
  const VariablesDialog({required this.initial, super.key});

  final List<VariableDef> initial;

  @override
  State<VariablesDialog> createState() => _VariablesDialogState();
}

/// One editable row.
class _Draft {
  _Draft([VariableDef? variable])
    : key = TextEditingController(text: variable?.key ?? ''),
      label = TextEditingController(text: variable?.label ?? ''),
      defaultValue = TextEditingController(text: variable?.defaultValue ?? ''),
      options = TextEditingController(text: variable?.options.join(', ') ?? ''),
      type = variable?.type ?? VariableType.text,
      required = variable?.required ?? false;

  final TextEditingController key;
  final TextEditingController label;
  final TextEditingController defaultValue;
  final TextEditingController options;
  VariableType type;
  bool required;

  VariableDef toVariable() {
    final keyText = key.text.trim();
    final labelText = label.text.trim();
    return VariableDef(
      key: keyText,
      label: labelText.isEmpty ? keyText : labelText,
      type: type,
      options: type == VariableType.enumeration
          ? [
              for (final option in options.text.split(','))
                if (option.trim().isNotEmpty) option.trim(),
            ]
          : const [],
      required: required,
      defaultValue: defaultValue.text,
    );
  }

  void dispose() {
    key.dispose();
    label.dispose();
    defaultValue.dispose();
    options.dispose();
  }
}

class _VariablesDialogState extends State<VariablesDialog> {
  late final List<_Draft> _drafts = [
    for (final variable in widget.initial) _Draft(variable),
  ];
  String? _error;

  @override
  void dispose() {
    for (final draft in _drafts) {
      draft.dispose();
    }
    super.dispose();
  }

  void _remove(int index) {
    final draft = _drafts[index];
    setState(() => _drafts.removeAt(index));
    // Its text fields are still mounted until the next frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => draft.dispose());
  }

  void _save() {
    final variables = [for (final draft in _drafts) draft.toVariable()];
    final keys = <String>{};
    for (final variable in variables) {
      final problem =
          variable.problem ??
          (keys.add(variable.key)
              ? null
              : 'The key "${variable.key}" is used twice.');
      if (problem != null) {
        setState(() => _error = problem);
        return;
      }
    }
    Navigator.of(context).pop(variables);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final error = _error;
    return AlertDialog(
      title: const Text('Variables'),
      content: SizedBox(
        width: 680,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Use a variable in the message as {{key}}.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              for (final (index, draft) in _drafts.indexed)
                _DraftRow(
                  index: index,
                  draft: draft,
                  onChanged: () => setState(() {}),
                  onRemove: () => _remove(index),
                ),
              TextButton.icon(
                key: const Key('variable-add'),
                onPressed: () => setState(() => _drafts.add(_Draft())),
                icon: const Icon(Icons.add),
                label: const Text('Add variable'),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    error,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('variables-save'),
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _DraftRow extends StatelessWidget {
  const _DraftRow({
    required this.index,
    required this.draft,
    required this.onChanged,
    required this.onRemove,
  });

  final int index;
  final _Draft draft;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  static String _typeLabel(VariableType type) => switch (type) {
    VariableType.text => 'Text',
    VariableType.multiline => 'Multi-line text',
    VariableType.number => 'Number',
    VariableType.boolean => 'On/off',
    VariableType.enumeration => 'Choice list',
  };

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 140,
              child: TextField(
                key: ValueKey('variable-key-$index'),
                controller: draft.key,
                decoration: const InputDecoration(
                  labelText: 'Key',
                  isDense: true,
                ),
              ),
            ),
            SizedBox(
              width: 160,
              child: TextField(
                key: ValueKey('variable-label-$index'),
                controller: draft.label,
                decoration: const InputDecoration(
                  labelText: 'Label',
                  isDense: true,
                ),
              ),
            ),
            SizedBox(
              width: 150,
              child: DropdownButton<VariableType>(
                key: ValueKey('variable-type-$index'),
                isExpanded: true,
                value: draft.type,
                items: [
                  for (final type in VariableType.values)
                    DropdownMenuItem(
                      value: type,
                      child: Text(_typeLabel(type)),
                    ),
                ],
                onChanged: (type) {
                  if (type != null) {
                    draft.type = type;
                    onChanged();
                  }
                },
              ),
            ),
            SizedBox(
              width: 160,
              child: TextField(
                key: ValueKey('variable-default-$index'),
                controller: draft.defaultValue,
                decoration: const InputDecoration(
                  labelText: 'Default',
                  isDense: true,
                ),
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Checkbox(
                  value: draft.required,
                  onChanged: (value) {
                    draft.required = value ?? false;
                    onChanged();
                  },
                ),
                const Text('Required'),
              ],
            ),
            IconButton(
              tooltip: 'Remove',
              icon: const Icon(Icons.delete_outline),
              onPressed: onRemove,
            ),
            if (draft.type == VariableType.enumeration)
              SizedBox(
                width: 600,
                child: TextField(
                  key: ValueKey('variable-options-$index'),
                  controller: draft.options,
                  decoration: const InputDecoration(
                    labelText: 'Options, separated by commas',
                    isDense: true,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
