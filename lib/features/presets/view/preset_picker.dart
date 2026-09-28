import 'package:fcm_studio/features/composer/cubit/composer_cubit.dart';
import 'package:fcm_studio/features/presets/cubit/presets_cubit.dart';
import 'package:fcm_studio/features/presets/domain/preset.dart';
import 'package:fcm_studio/features/presets/view/preset_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// The composer's preset picker, with Save as and Update (spec §5.5, §6).
class PresetPicker extends StatelessWidget {
  const PresetPicker({super.key});

  static const dropdownKey = Key('preset-dropdown');
  static const saveAsKey = Key('preset-save-as');
  static const updateKey = Key('preset-update');

  static String _label(Preset preset) =>
      preset.builtIn ? '${preset.name} (built-in)' : preset.name;

  @override
  Widget build(BuildContext context) {
    final presets = context.watch<PresetsCubit>().state;
    return BlocBuilder<ComposerCubit, ComposerState>(
      buildWhen: (previous, current) =>
          previous.preset != current.preset ||
          previous.isDirty != current.isDirty,
      builder: (context, composer) {
        final current = composer.preset;
        final selectedId = current != null && presets.byId(current.id) != null
            ? current.id
            : null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Preset', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            DropdownButton<String>(
              key: dropdownKey,
              isExpanded: true,
              hint: const Text('No preset'),
              value: selectedId,
              items: [
                for (final preset in presets.all)
                  DropdownMenuItem(
                    value: preset.id,
                    child: Text(
                      _label(preset),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              // The dot marks unsaved changes (spec §6).
              selectedItemBuilder: (context) => [
                for (final preset in presets.all)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      preset.id == selectedId && composer.isDirty
                          ? '• ${_label(preset)}'
                          : _label(preset),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (id) {
                final preset = id == null ? null : presets.byId(id);
                if (preset != null) {
                  openPreset(context, preset);
                }
              },
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  key: saveAsKey,
                  onPressed: () => savePresetAs(context),
                  child: const Text('Save as preset…'),
                ),
                OutlinedButton(
                  key: updateKey,
                  onPressed:
                      current != null && !current.builtIn && composer.isDirty
                      ? () => updatePreset(context)
                      : null,
                  child: const Text('Update preset'),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
