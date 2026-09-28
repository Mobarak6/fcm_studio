import 'package:fcm_studio/app/app_error_cubit.dart';
import 'package:fcm_studio/features/composer/cubit/composer_cubit.dart';
import 'package:fcm_studio/features/presets/cubit/presets_cubit.dart';
import 'package:fcm_studio/features/presets/domain/preset.dart';
import 'package:fcm_studio/features/presets/view/preset_details_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Loads [preset] into the composer, asking first when the loaded preset has
/// unsaved changes. Returns false when the user keeps editing.
Future<bool> openPreset(BuildContext context, Preset preset) async {
  final composer = context.read<ComposerCubit>();
  if (composer.state.isDirty && !await confirmDiscardChanges(context)) {
    return false;
  }
  composer.loadPreset(preset);
  return true;
}

Future<bool> confirmDiscardChanges(BuildContext context) async {
  final name = context.read<ComposerCubit>().state.preset?.name;
  final discard = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Discard unsaved changes?'),
      content: Text(
        'Your changes to ${name == null ? 'this message' : '"$name"'} are not saved.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Keep editing'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Discard'),
        ),
      ],
    ),
  );
  return discard ?? false;
}

/// Cmd/Ctrl+S: updates the loaded user preset, or asks for a name.
Future<void> savePreset(BuildContext context) {
  final preset = context.read<ComposerCubit>().state.preset;
  return preset != null && !preset.builtIn
      ? updatePreset(context)
      : savePresetAs(context);
}

/// "Save as preset": a new preset from the composer's template and variables.
Future<void> savePresetAs(BuildContext context) async {
  final composer = context.read<ComposerCubit>();
  final presets = context.read<PresetsCubit>();
  final errors = context.read<AppErrorCubit>();
  final template = composer.state.template;
  if (template == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Fix the JSON before saving it as a preset.'),
      ),
    );
    return;
  }
  final details = await showPresetDetailsDialog(
    context,
    title: 'Save as preset',
    isNameTaken: presets.state.nameTaken,
  );
  if (details == null) {
    return;
  }
  try {
    final saved = await presets.saveAs(
      name: details.name,
      description: details.description,
      template: template,
      variables: composer.state.variables,
    );
    composer.presetSaved(saved);
  } catch (e) {
    errors.report(e, context: 'Could not save the preset');
  }
}

/// "Update preset": overwrites the loaded user preset.
Future<void> updatePreset(BuildContext context) async {
  final composer = context.read<ComposerCubit>();
  final presets = context.read<PresetsCubit>();
  final errors = context.read<AppErrorCubit>();
  final preset = composer.state.preset;
  final template = composer.state.template;
  if (preset == null || preset.builtIn || template == null) {
    return;
  }
  try {
    final updated = await presets.update(
      preset,
      template: template,
      variables: composer.state.variables,
    );
    composer.presetSaved(updated);
  } catch (e) {
    errors.report(e, context: 'Could not update the preset');
  }
}
