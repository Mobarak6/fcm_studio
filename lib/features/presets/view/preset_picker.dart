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
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Preset', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            _PresetSearchField(
              // Your own presets first: the built-in list is long.
              presets: [...presets.userPresets, ...presets.builtIns],
              selected: current == null ? null : presets.byId(current.id),
              isDirty: composer.isDirty,
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

/// A search field over [presets]. While it is not being typed in, it shows
/// the loaded preset.
class _PresetSearchField extends StatefulWidget {
  const _PresetSearchField({
    required this.presets,
    required this.selected,
    required this.isDirty,
  });

  final List<Preset> presets;
  final Preset? selected;
  final bool isDirty;

  @override
  State<_PresetSearchField> createState() => _PresetSearchFieldState();
}

class _PresetSearchFieldState extends State<_PresetSearchField> {
  late final TextEditingController _controller = TextEditingController(
    text: _selectedText,
  );
  final FocusNode _focus = FocusNode();

  /// The dot marks unsaved changes (spec §6).
  String get _selectedText {
    final selected = widget.selected;
    if (selected == null) {
      return '';
    }
    final label = PresetPicker._label(selected);
    return widget.isDirty ? '• $label' : label;
  }

  /// Keeps the entries whose label holds every typed word, in any order.
  static List<DropdownMenuEntry<String>> _matching(
    List<DropdownMenuEntry<String>> entries,
    String filter,
  ) {
    final words = filter
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
    return [
      for (final entry in entries)
        if (words.every(entry.label.toLowerCase().contains)) entry,
    ];
  }

  @override
  void initState() {
    super.initState();
    _focus.addListener(_showSelectedWhenLeft);
  }

  @override
  void didUpdateWidget(_PresetSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // e.g. a preset was loaded, edited or renamed elsewhere.
    if (!_focus.hasFocus) {
      _showSelected();
    }
  }

  void _showSelectedWhenLeft() {
    if (!_focus.hasFocus) {
      _showSelected();
    }
  }

  void _showSelected() {
    final text = _selectedText;
    if (_controller.text != text) {
      _controller.text = text;
    }
  }

  Future<void> _open(String? id) async {
    final preset = id == null
        ? null
        : context.read<PresetsCubit>().state.byId(id);
    if (preset == null) {
      return;
    }
    if (!await openPreset(context, preset) && mounted) {
      // "Keep editing": the loaded preset stays, so show it again.
      _showSelected();
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // No initialSelection: it would replace the text, dropping the dot.
    return DropdownMenu<String>(
      key: PresetPicker.dropdownKey,
      controller: _controller,
      focusNode: _focus,
      expandedInsets: EdgeInsets.zero,
      enableFilter: true,
      filterCallback: _matching,
      requestFocusOnTap: true,
      menuHeight: 360,
      leadingIcon: const Icon(Icons.search),
      hintText: 'Search presets',
      dropdownMenuEntries: [
        for (final preset in widget.presets)
          DropdownMenuEntry(
            value: preset.id,
            label: PresetPicker._label(preset),
          ),
      ],
      onSelected: _open,
    );
  }
}
