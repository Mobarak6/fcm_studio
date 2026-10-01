import 'package:fcm_studio/features/composer/cubit/composer_cubit.dart';
import 'package:fcm_studio/features/composer/domain/sender_check.dart';
import 'package:fcm_studio/features/composer/domain/target.dart';
import 'package:fcm_studio/features/projects/cubit/projects_cubit.dart';
import 'package:fcm_studio/features/targets/cubit/targets_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Warns when the target token belongs to another Firebase project, and
/// offers to switch to it (spec §7.1). The token's sender ID is known when
/// it was read from a phone.
class SenderWarning extends StatelessWidget {
  const SenderWarning({super.key});

  static const switchKey = Key('sender-switch-project');

  @override
  Widget build(BuildContext context) {
    final target = context.select((ComposerCubit c) => c.state.target);
    final senderId = context.select(
      (TargetsCubit c) =>
          target is TokenTarget ? c.state.matching(target)?.senderId : null,
    );
    final projects = context.watch<ProjectsCubit>().state;
    final mismatch = SenderCheck.check(
      senderId: senderId,
      project: projects.selected,
      projects: projects.projects,
    );
    if (mismatch == null) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    return Card(
      key: const Key('sender-warning'),
      margin: const EdgeInsets.only(top: 12),
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber, color: scheme.onErrorContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    mismatch.message,
                    style: TextStyle(color: scheme.onErrorContainer),
                  ),
                ),
              ],
            ),
            if (mismatch.switchTo case final project?)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  key: switchKey,
                  onPressed: () =>
                      context.read<ProjectsCubit>().select(project.id),
                  child: Text('Switch to ${project.label}'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
