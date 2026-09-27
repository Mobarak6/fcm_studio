import 'package:fcm_studio/core/fcm/fcm_error_explainer.dart';
import 'package:fcm_studio/core/fcm/fcm_send_result.dart';
import 'package:fcm_studio/features/composer/cubit/composer_cubit.dart';
import 'package:fcm_studio/features/projects/cubit/projects_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

/// Sends the composer's message to the selected project, if there is one.
void sendSelected(BuildContext context) {
  final project = context.read<ProjectsCubit>().state.selected;
  if (project == null) {
    return;
  }
  context.read<ComposerCubit>().send(project);
}

class SendPanel extends StatelessWidget {
  const SendPanel({super.key});

  static const sendButtonKey = Key('send-button');

  @override
  Widget build(BuildContext context) {
    final hasProject = context.select(
      (ProjectsCubit cubit) => cubit.state.selected != null,
    );
    return BlocBuilder<ComposerCubit, ComposerState>(
      builder: (context, state) {
        final sending = state.sendStatus == SendStatus.sending;
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Tooltip(
                message: hasProject
                    ? 'Cmd/Ctrl + Enter'
                    : 'Add a project first',
                child: FilledButton.icon(
                  key: sendButtonKey,
                  onPressed: hasProject && state.canSend
                      ? () => sendSelected(context)
                      : null,
                  icon: sending
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                  label: Text(sending ? 'Sending…' : 'Send'),
                ),
              ),
              if (state.lastResult case final result?) ...[
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 320),
                  child: SingleChildScrollView(
                    child: ResultView(
                      result: result,
                      explanation: state.lastExplanation,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class ResultView extends StatelessWidget {
  const ResultView({required this.result, this.explanation, super.key});

  final FcmSendResult result;
  final ErrorExplanation? explanation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final milliseconds = result.duration.inMilliseconds;
    switch (result) {
      case FcmSendSuccess(:final messageName):
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.check_circle, color: Colors.green),
          title: const Text('Sent'),
          subtitle: SelectableText('$messageName · $milliseconds ms'),
        );
      case FcmSendFailure(:final error):
        final e = explanation;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.error, color: theme.colorScheme.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    e?.title ?? 'Send failed',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            if (e != null) ...[
              const SizedBox(height: 8),
              SelectableText(e.explanation),
              const SizedBox(height: 8),
              Text(
                e.action,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
            if (e?.link case final link?)
              TextButton.icon(
                onPressed: () => launchUrl(link),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('Open in console'),
              ),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(
                'Raw response${result.httpStatus == null ? '' : ' (HTTP ${result.httpStatus})'}',
              ),
              children: [
                SelectableText(
                  result.responseBody ?? error.message ?? 'No response body.',
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ],
            ),
          ],
        );
    }
  }
}
