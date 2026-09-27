import 'package:fcm_studio/features/composer/cubit/composer_cubit.dart';
import 'package:fcm_studio/features/composer/domain/target.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class TargetPicker extends StatefulWidget {
  const TargetPicker({super.key});

  @override
  State<TargetPicker> createState() => _TargetPickerState();
}

class _TargetPickerState extends State<TargetPicker> {
  late final TextEditingController _controller;

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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final kind = context.select(
      (ComposerCubit cubit) => cubit.state.targetKind,
    );
    final cubit = context.read<ComposerCubit>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Target', style: Theme.of(context).textTheme.titleSmall),
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
        TextField(
          key: const Key('target-field'),
          controller: _controller,
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
      ],
    );
  }
}
