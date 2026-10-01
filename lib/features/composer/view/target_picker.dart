import 'package:fcm_studio/app/app_error_cubit.dart';
import 'package:fcm_studio/app/navigation_cubit.dart';
import 'package:fcm_studio/app/widgets/prompt_dialog.dart';
import 'package:fcm_studio/core/platform/platform_capabilities.dart';
import 'package:fcm_studio/features/composer/cubit/composer_cubit.dart';
import 'package:fcm_studio/features/composer/domain/target.dart';
import 'package:fcm_studio/features/projects/cubit/projects_cubit.dart';
import 'package:fcm_studio/features/targets/cubit/targets_cubit.dart';
import 'package:fcm_studio/features/targets/domain/saved_target.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Token / Topic / Condition, an autocomplete from saved targets, and the
/// star that saves the current target (spec §5.5, §7.1).
class TargetPicker extends StatefulWidget {
  const TargetPicker({super.key});

  static const fieldKey = Key('target-field');
  static const starKey = Key('save-target');
  static const fromDeviceKey = Key('target-from-device');

  @override
  State<TargetPicker> createState() => _TargetPickerState();
}

class _TargetPickerState extends State<TargetPicker> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: context.read<ComposerCubit>().state.targetValue,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Iterable<SavedTarget> _suggestions(String text) {
    final query = text.trim().toLowerCase();
    final projectId = context.read<ProjectsCubit>().state.selectedId;
    final targets = context.read<TargetsCubit>().state.targets;
    return SavedTarget.orderFor(targets, projectId)
        .where(
          (t) =>
              query.isEmpty ||
              t.label.toLowerCase().contains(query) ||
              t.value.toLowerCase().contains(query),
        )
        .take(8);
  }

  Future<void> _toggleSaved(Target target, SavedTarget? saved) async {
    final targets = context.read<TargetsCubit>();
    final errors = context.read<AppErrorCubit>();
    final projectId = context.read<ProjectsCubit>().state.selectedId;
    final label = saved == null
        ? await promptForText(
            context,
            title: 'Save target',
            label: 'Label',
            initial: SavedTarget.defaultLabel(target),
          )
        : null;
    if (saved == null && label == null) {
      return;
    }
    try {
      if (saved != null) {
        await targets.remove(saved);
      } else {
        await targets.save(target, label: label!, projectId: projectId);
      }
    } catch (e) {
      errors.report(e, context: 'Could not update saved targets');
    }
  }

  @override
  Widget build(BuildContext context) {
    final kind = context.select((ComposerCubit c) => c.state.targetKind);
    final target = context.select((ComposerCubit c) => c.state.target);
    final saved = context.select((TargetsCubit c) => c.state.matching(target));
    final cubit = context.read<ComposerCubit>();
    return BlocListener<ComposerCubit, ComposerState>(
      // History and the Targets screen set the target from outside the field.
      listenWhen: (previous, current) =>
          previous.targetValue != current.targetValue,
      listener: (context, state) {
        // Events arrive a microtask late; read the latest value, not `state`.
        final latest = context.read<ComposerCubit>().state.targetValue;
        if (latest != _controller.text) {
          _controller.text = latest;
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Target',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              if (context.read<PlatformFeatures>().canRunAdb)
                TextButton.icon(
                  key: TargetPicker.fromDeviceKey,
                  onPressed: () =>
                      context.read<NavigationCubit>().show(AppSection.devices),
                  icon: const Icon(Icons.phone_android, size: 18),
                  label: const Text('From device…'),
                ),
              IconButton(
                key: TargetPicker.starKey,
                tooltip: saved == null
                    ? 'Save this target'
                    : 'Remove from saved targets',
                icon: Icon(saved == null ? Icons.star_border : Icons.star),
                onPressed: target.validate().isNotEmpty
                    ? null
                    : () => _toggleSaved(target, saved),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SegmentedButton<TargetKind>(
            segments: const [
              ButtonSegment(value: TargetKind.token, label: Text('Token')),
              ButtonSegment(value: TargetKind.topic, label: Text('Topic')),
              ButtonSegment(
                value: TargetKind.condition,
                label: Text('Condition'),
              ),
            ],
            selected: {kind},
            onSelectionChanged: (selection) =>
                cubit.setTargetKind(selection.first),
          ),
          const SizedBox(height: 8),
          RawAutocomplete<SavedTarget>(
            textEditingController: _controller,
            focusNode: _focusNode,
            displayStringForOption: (option) => option.value,
            optionsBuilder: (value) => _suggestions(value.text),
            onSelected: (option) => cubit.setTarget(option.kind, option.value),
            fieldViewBuilder: (context, controller, focusNode, onSubmitted) =>
                TextField(
                  key: TargetPicker.fieldKey,
                  controller: controller,
                  focusNode: focusNode,
                  minLines: 1,
                  maxLines: kind == TargetKind.token ? 4 : 2,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: switch (kind) {
                      TargetKind.token => 'Device token',
                      TargetKind.topic => 'Topic name',
                      TargetKind.condition => 'Condition',
                    },
                    hintText: switch (kind) {
                      TargetKind.token => 'Paste the FCM registration token',
                      TargetKind.topic => 'e.g. news (without /topics/)',
                      TargetKind.condition =>
                        "e.g. 'news' in topics && 'sports' in topics",
                    },
                  ),
                  onChanged: cubit.setTargetValue,
                ),
            optionsViewBuilder: (context, onSelected, options) =>
                _Suggestions(options: options.toList(), onSelected: onSelected),
          ),
        ],
      ),
    );
  }
}

class _Suggestions extends StatelessWidget {
  const _Suggestions({required this.options, required this.onSelected});

  final List<SavedTarget> options;
  final AutocompleteOnSelected<SavedTarget> onSelected;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: Material(
        elevation: 4,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 280, maxWidth: 360),
          child: ListView(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            children: [
              for (final option in options)
                ListTile(
                  key: ValueKey('target-suggestion-${option.id}'),
                  dense: true,
                  title: Text(option.label),
                  subtitle: Text(
                    [
                      option.kind.name,
                      option.displayValue,
                      ?option.projectId,
                    ].join(' · '),
                  ),
                  onTap: () => onSelected(option),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
