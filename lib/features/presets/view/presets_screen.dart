import 'package:fcm_studio/app/app_error_cubit.dart';
import 'package:fcm_studio/app/navigation_cubit.dart';
import 'package:fcm_studio/core/platform/file_access.dart';
import 'package:fcm_studio/features/composer/cubit/composer_cubit.dart';
import 'package:fcm_studio/features/presets/cubit/presets_cubit.dart';
import 'package:fcm_studio/features/presets/domain/preset.dart';
import 'package:fcm_studio/features/presets/domain/preset_codec.dart';
import 'package:fcm_studio/features/presets/domain/preset_groups.dart';
import 'package:fcm_studio/features/presets/view/preset_actions.dart';
import 'package:fcm_studio/features/presets/view/preset_details_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

enum PresetAction { open, duplicate, edit, export, delete }

/// Built-in and user presets, with export and import (spec §6).
class PresetsScreen extends StatefulWidget {
  const PresetsScreen({super.key});

  static const importKey = Key('presets-import');
  static const exportKey = Key('presets-export');

  @override
  State<PresetsScreen> createState() => _PresetsScreenState();
}

class _PresetsScreenState extends State<PresetsScreen> {
  /// Presets ticked for export, built-in ones included.
  final Set<String> _selected = {};

  /// The keys of the groups whose sections are closed.
  final Set<String> _closed = {};

  /// True when every preset in [group] is ticked, false when none is, and
  /// null (a dash) when some are.
  bool? _ticked(PresetGroup group) {
    final count = group.presets.where((p) => _selected.contains(p.id)).length;
    if (count == 0) {
      return false;
    }
    return count == group.presets.length ? true : null;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PresetsCubit>().state;
    final groups = state.groups;
    final shown = [for (final group in groups) ...group.presets];
    final selected = [
      for (final p in shown)
        if (_selected.contains(p.id)) p,
    ];
    Widget tile(Preset preset) => _PresetTile(
      preset: preset,
      selected: _selected.contains(preset.id),
      onSelected: (on) => setState(() {
        if (on) {
          _selected.add(preset.id);
        } else {
          _selected.remove(preset.id);
        }
      }),
      onAction: _onAction,
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Presets'),
        actions: [
          TextButton.icon(
            key: PresetsScreen.importKey,
            onPressed: () => _run('import presets', _import),
            icon: const Icon(Icons.file_open_outlined),
            label: const Text('Import…'),
          ),
          TextButton.icon(
            key: PresetsScreen.exportKey,
            // Nothing ticked exports every preset, built-in ones included.
            onPressed: () => _run(
              'export presets',
              () => _export(selected.isEmpty ? shown : selected),
            ),
            icon: const Icon(Icons.save_alt),
            label: Text(
              selected.isEmpty ? 'Export all' : 'Export ${selected.length}',
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          if (state.userPresets.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'No presets yet. Save one from the composer, or import a file.',
              ),
            ),
          for (final group in groups) ...[
            _GroupHeader(
              group: group,
              open: !_closed.contains(group.key),
              ticked: _ticked(group),
              onToggle: () => setState(() {
                if (!_closed.remove(group.key)) {
                  _closed.add(group.key);
                }
              }),
              onTick: (on) => setState(() {
                for (final preset in group.presets) {
                  if (on) {
                    _selected.add(preset.id);
                  } else {
                    _selected.remove(preset.id);
                  }
                }
              }),
            ),
            if (!_closed.contains(group.key))
              for (final preset in group.presets) tile(preset),
          ],
        ],
      ),
    );
  }

  /// Runs [action]; an unexpected failure goes to the error banner.
  Future<void> _run(String what, Future<void> Function() action) async {
    final errors = context.read<AppErrorCubit>();
    try {
      await action();
    } catch (e) {
      errors.report(e, context: 'Could not $what');
    }
  }

  Future<void> _onAction(Preset preset, PresetAction action) =>
      _run('${action.name} the preset', () async {
        final presets = context.read<PresetsCubit>();
        final composer = context.read<ComposerCubit>();
        final navigation = context.read<NavigationCubit>();
        final messenger = ScaffoldMessenger.of(context);
        switch (action) {
          case PresetAction.open:
            if (await openPreset(context, preset)) {
              navigation.show(AppSection.composer);
            }
          case PresetAction.duplicate:
            final copy = await presets.duplicate(preset);
            messenger.showSnackBar(
              SnackBar(content: Text('Created "${copy.name}".')),
            );
          case PresetAction.edit:
            final details = await showPresetDetailsDialog(
              context,
              title: 'Edit details',
              name: preset.name,
              description: preset.description,
              group: preset.group,
              groups: presets.state.groupNames,
              isNameTaken: (name, group) => presets.state.nameTaken(
                name,
                group: group,
                exceptId: preset.id,
              ),
            );
            if (details != null) {
              final renamed = await presets.rename(
                preset,
                name: details.name,
                description: details.description,
                group: details.group,
              );
              composer.presetUpdated(renamed);
            }
          case PresetAction.export:
            await _export([preset]);
          case PresetAction.delete:
            if (await _confirmDelete(preset)) {
              await presets.delete(preset);
              composer.detachPreset(preset.id);
            }
        }
      });

  Future<bool> _confirmDelete(Preset preset) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "${preset.name}"?'),
        content: const Text(
          'This cannot be undone. Export it first to keep a copy.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _export(List<Preset> presets) async {
    final cubit = context.read<PresetsCubit>();
    final files = context.read<FileAccess>();
    final messenger = ScaffoldMessenger.of(context);
    final name = presets.length == 1
        ? '${_fileName(presets.single.name)}${PresetCodec.fileExtension}'
        : 'fcm-studio-presets${PresetCodec.fileExtension}';
    final saved = await files.saveText(
      suggestedName: name,
      text: cubit.exportText(presets),
    );
    if (saved) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Exported ${presets.length} preset${presets.length == 1 ? '' : 's'}.',
          ),
        ),
      );
    }
  }

  Future<void> _import() async {
    final cubit = context.read<PresetsCubit>();
    final composer = context.read<ComposerCubit>();
    final files = context.read<FileAccess>();
    final messenger = ScaffoldMessenger.of(context);
    final text = await files.openText(
      label: 'FCM Studio presets',
      extensions: const ['json'],
    );
    if (text == null || !mounted) {
      return;
    }
    final ImportPreview preview;
    try {
      preview = cubit.previewImport(text);
    } on PresetFormatException catch (e) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("Can't import this file"),
          content: Text(e.message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }
    var choice = ImportConflictChoice.keepBoth;
    if (preview.conflicts.isNotEmpty) {
      if (!mounted) {
        return;
      }
      final picked = await showDialog<ImportConflictChoice>(
        context: context,
        builder: (_) => ImportConflictDialog(conflicts: preview.conflicts),
      );
      if (picked == null) {
        return;
      }
      choice = picked;
    }
    final count = await cubit.applyImport(preview, choice);
    // Replace keeps the id, so the composer may hold an old copy.
    final loadedId = composer.state.preset?.id;
    final reloaded = loadedId == null ? null : cubit.state.byId(loadedId);
    if (reloaded != null) {
      composer.presetUpdated(reloaded);
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text('Imported $count preset${count == 1 ? '' : 's'}.'),
      ),
    );
  }

  static String _fileName(String name) {
    final safe = name
        .toLowerCase()
        .replaceAll(RegExp('[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return safe.isEmpty ? 'preset' : safe;
  }
}

/// A group's section header. Its checkbox ticks every preset in the group;
/// a tap elsewhere opens or closes the section.
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.group,
    required this.open,
    required this.ticked,
    required this.onToggle,
    required this.onTick,
  });

  final PresetGroup group;
  final bool open;

  /// Null when some of the group's presets are ticked.
  final bool? ticked;
  final VoidCallback onToggle;
  final ValueChanged<bool> onTick;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: ValueKey('preset-group-${group.key}'),
      leading: Checkbox(
        key: ValueKey('preset-group-check-${group.key}'),
        tristate: true,
        value: ticked,
        // All ticked: untick them all. Otherwise tick them all.
        onChanged: (_) => onTick(ticked != true),
      ),
      title: Text(group.name, style: Theme.of(context).textTheme.titleSmall),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${group.presets.length}'),
          const SizedBox(width: 8),
          Icon(open ? Icons.expand_less : Icons.expand_more),
        ],
      ),
      onTap: onToggle,
    );
  }
}

class _PresetTile extends StatelessWidget {
  const _PresetTile({
    required this.preset,
    required this.selected,
    required this.onSelected,
    required this.onAction,
  });

  final Preset preset;
  final bool selected;
  final ValueChanged<bool> onSelected;
  final Future<void> Function(Preset preset, PresetAction action) onAction;

  @override
  Widget build(BuildContext context) {
    final count = preset.variables.length;
    final details = [
      if (preset.description.isNotEmpty) preset.description,
      '$count variable${count == 1 ? '' : 's'}',
    ].join(' · ');
    return ListTile(
      key: ValueKey('preset-${preset.id}'),
      leading: Checkbox(
        value: selected,
        onChanged: (value) => onSelected(value ?? false),
      ),
      title: Row(
        children: [
          Flexible(child: Text(preset.name)),
          if (preset.builtIn) ...[
            const SizedBox(width: 6),
            const Tooltip(
              message: 'Built-in: read-only. Duplicate it to edit a copy.',
              child: Icon(Icons.lock_outline, size: 16),
            ),
          ],
        ],
      ),
      subtitle: Text(details),
      onTap: () => onAction(preset, PresetAction.open),
      trailing: PopupMenuButton<PresetAction>(
        key: ValueKey('preset-menu-${preset.id}'),
        tooltip: 'Preset actions',
        onSelected: (action) => onAction(preset, action),
        itemBuilder: (context) => [
          const PopupMenuItem(
            value: PresetAction.open,
            child: Text('Open in composer'),
          ),
          const PopupMenuItem(
            value: PresetAction.duplicate,
            child: Text('Duplicate'),
          ),
          if (!preset.builtIn)
            const PopupMenuItem(
              value: PresetAction.edit,
              child: Text('Edit details…'),
            ),
          const PopupMenuItem(
            value: PresetAction.export,
            child: Text('Export…'),
          ),
          if (!preset.builtIn)
            const PopupMenuItem(
              value: PresetAction.delete,
              child: Text('Delete…'),
            ),
        ],
      ),
    );
  }
}

/// Asks what to do with imported presets whose names already exist.
class ImportConflictDialog extends StatelessWidget {
  const ImportConflictDialog({required this.conflicts, super.key});

  final List<String> conflicts;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Some presets already exist'),
      content: Text(
        'These names are already used: ${conflicts.join(', ')}.\n\n'
        'Your choice applies to all of them. Built-in presets are never '
        'replaced; a clash with one is kept as a copy.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(ImportConflictChoice.skip),
          child: const Text('Skip'),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(ImportConflictChoice.replace),
          child: const Text('Replace'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop(ImportConflictChoice.keepBoth),
          child: const Text('Keep both'),
        ),
      ],
    );
  }
}
