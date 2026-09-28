import 'package:fcm_studio/features/composer/cubit/composer_cubit.dart';
import 'package:fcm_studio/features/composer/view/form_fields.dart';
import 'package:fcm_studio/features/presets/domain/variable_def.dart';
import 'package:fcm_studio/features/presets/view/variables_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// The Form tab's Variables section: one input per variable, and a quick fix
/// for placeholders that have no definition (spec §5.3, §6).
class VariablesSection extends StatelessWidget {
  const VariablesSection({super.key});

  static const editKey = Key('variables-edit');
  static const addMissingKey = Key('variables-add-missing');

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ComposerCubit, ComposerState>(
      buildWhen: (previous, current) =>
          previous.variables != current.variables ||
          previous.values != current.values ||
          previous.render.undefinedPlaceholders !=
              current.render.undefinedPlaceholders,
      builder: (context, state) {
        final cubit = context.read<ComposerCubit>();
        final undefined = state.render.undefinedPlaceholders;
        return FormSection(
          title: 'Variables',
          trailing: TextButton.icon(
            key: editKey,
            onPressed: () => _edit(context),
            icon: const Icon(Icons.tune, size: 18),
            label: const Text('Edit variables…'),
          ),
          children: [
            if (undefined.isNotEmpty)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.lightbulb_outline),
                  title: Text(
                    'The message uses '
                    '${undefined.map((key) => '{{$key}}').join(', ')} '
                    'without a definition.',
                  ),
                  trailing: TextButton(
                    key: addMissingKey,
                    onPressed: cubit.addMissingVariables,
                    child: const Text('Add as variables'),
                  ),
                ),
              ),
            if (state.variables.isEmpty && undefined.isEmpty)
              Text(
                'No variables. Use {{name}} in the message to add one.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            for (final variable in state.variables)
              VariableInput(
                variable: variable,
                value: state.values[variable.key] ?? variable.defaultValue,
                onChanged: (value) =>
                    cubit.setVariableValue(variable.key, value),
              ),
          ],
        );
      },
    );
  }

  Future<void> _edit(BuildContext context) async {
    final cubit = context.read<ComposerCubit>();
    final updated = await showVariablesDialog(context, cubit.state.variables);
    if (updated != null) {
      cubit.setVariables(updated);
    }
  }
}

/// The input for one variable, by its type.
class VariableInput extends StatelessWidget {
  const VariableInput({
    required this.variable,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final VariableDef variable;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final label = variable.required ? '${variable.label} *' : variable.label;
    final fieldKey = ValueKey('variable-${variable.key}');
    switch (variable.type) {
      case VariableType.text:
        return SyncedTextField(
          key: fieldKey,
          label: label,
          value: value,
          onChanged: onChanged,
        );
      case VariableType.multiline:
        return SyncedTextField(
          key: fieldKey,
          label: label,
          value: value,
          onChanged: onChanged,
          maxLines: 4,
        );
      case VariableType.number:
        return SyncedTextField(
          key: fieldKey,
          label: label,
          value: value,
          onChanged: onChanged,
          keyboardType: TextInputType.number,
        );
      case VariableType.boolean:
        return SwitchListTile(
          key: fieldKey,
          contentPadding: EdgeInsets.zero,
          title: Text(label),
          value: value == 'true',
          onChanged: (on) => onChanged('$on'),
        );
      case VariableType.enumeration:
        return ChoiceField(
          key: fieldKey,
          label: label,
          value: value,
          options: variable.options,
          onChanged: onChanged,
        );
    }
  }
}
