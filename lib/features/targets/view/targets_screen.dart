import 'package:fcm_studio/app/app_error_cubit.dart';
import 'package:fcm_studio/app/navigation_cubit.dart';
import 'package:fcm_studio/app/widgets/prompt_dialog.dart';
import 'package:fcm_studio/core/utils/time_format.dart';
import 'package:fcm_studio/features/composer/cubit/composer_cubit.dart';
import 'package:fcm_studio/features/composer/domain/target.dart';
import 'package:fcm_studio/features/targets/cubit/targets_cubit.dart';
import 'package:fcm_studio/features/targets/domain/saved_target.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Saved tokens, topics and conditions (spec §7.1).
class TargetsScreen extends StatelessWidget {
  const TargetsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final targets = context.watch<TargetsCubit>().state.targets;
    return Scaffold(
      appBar: AppBar(title: const Text('Saved targets')),
      body: targets.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No saved targets yet. Use the star next to the target '
                  'field in the composer.',
                ),
              ),
            )
          : ListView(
              children: [
                for (final target in targets) _TargetTile(target: target),
              ],
            ),
    );
  }
}

enum _TargetAction { use, rename, delete }

class _TargetTile extends StatelessWidget {
  const _TargetTile({required this.target});

  final SavedTarget target;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: ValueKey('target-${target.id}'),
      leading: Icon(switch (target.kind) {
        TargetKind.token => Icons.smartphone,
        TargetKind.topic => Icons.tag,
        TargetKind.condition => Icons.rule,
      }),
      title: Text(target.label),
      subtitle: Text(
        [
          target.kind.name,
          target.displayValue,
          ?target.projectId,
          'last used ${formatLocalTime(target.lastUsedAt)}',
        ].join(' · '),
      ),
      // Lists show tokens shortened; a tap copies the full value.
      onTap: () => _copy(context),
      trailing: PopupMenuButton<_TargetAction>(
        key: ValueKey('target-menu-${target.id}'),
        tooltip: 'Target actions',
        onSelected: (action) => _onAction(context, action),
        itemBuilder: (context) => const [
          PopupMenuItem(
            value: _TargetAction.use,
            child: Text('Use in composer'),
          ),
          PopupMenuItem(value: _TargetAction.rename, child: Text('Rename…')),
          PopupMenuItem(value: _TargetAction.delete, child: Text('Delete')),
        ],
      ),
    );
  }

  Future<void> _copy(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final errors = context.read<AppErrorCubit>();
    try {
      await Clipboard.setData(ClipboardData(text: target.value));
      messenger.showSnackBar(
        const SnackBar(content: Text('Copied the full value.')),
      );
    } catch (e) {
      errors.report(e, context: 'Could not copy the value');
    }
  }

  Future<void> _onAction(BuildContext context, _TargetAction action) async {
    final targets = context.read<TargetsCubit>();
    final composer = context.read<ComposerCubit>();
    final navigation = context.read<NavigationCubit>();
    final errors = context.read<AppErrorCubit>();
    try {
      switch (action) {
        case _TargetAction.use:
          composer.setTarget(target.kind, target.value);
          navigation.show(AppSection.composer);
        case _TargetAction.rename:
          final label = await promptForText(
            context,
            title: 'Rename target',
            label: 'Label',
            initial: target.label,
          );
          if (label != null && label.trim().isNotEmpty) {
            await targets.rename(target, label);
          }
        case _TargetAction.delete:
          await targets.remove(target);
      }
    } catch (e) {
      errors.report(e, context: 'Could not update the saved target');
    }
  }
}
