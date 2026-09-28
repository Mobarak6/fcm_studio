import 'package:fcm_studio/core/fcm/fcm_error_explainer.dart';
import 'package:fcm_studio/core/fcm/fcm_send_result.dart';
import 'package:fcm_studio/features/composer/cubit/composer_cubit.dart';
import 'package:fcm_studio/features/composer/domain/send_confirmation.dart';
import 'package:fcm_studio/features/composer/view/send_confirmation_dialog.dart';
import 'package:fcm_studio/features/projects/cubit/projects_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

/// Sends the composer's message to the selected project. Send,
/// Cmd/Ctrl+Enter and Retry all come here, so a production project always
/// asks first (spec §4.3).
Future<void> sendSelected(BuildContext context) async {
  final project = context.read<ProjectsCubit>().state.selected;
  final composer = context.read<ComposerCubit>();
  if (project == null || !composer.state.canSend) {
    return;
  }
  final confirmation = SendConfirmation.forSend(
    project: project,
    target: composer.state.target,
    validateOnly: composer.state.validateOnly,
  );
  if (confirmation != null && !await confirmSend(context, confirmation)) {
    return;
  }
  await composer.send(project);
}

class SendPanel extends StatelessWidget {
  const SendPanel({super.key});

  static const sendButtonKey = Key('send-button');
  static const dryRunKey = Key('dry-run');

  @override
  Widget build(BuildContext context) {
    final hasProject = context.select(
      (ProjectsCubit cubit) => cubit.state.selected != null,
    );
    return BlocBuilder<ComposerCubit, ComposerState>(
      builder: (context, state) {
        final cubit = context.read<ComposerCubit>();
        final sending = state.sendStatus == SendStatus.sending;
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CheckboxListTile(
                key: dryRunKey,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: state.validateOnly,
                onChanged: (value) => cubit.setValidateOnly(value ?? false),
                title: const Text('Dry run (validate only)'),
                subtitle: const Text(
                  'FCM checks the message but delivers nothing.',
                ),
              ),
              const SizedBox(height: 8),
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
                  label: Text(
                    sending
                        ? 'Sending…'
                        : state.validateOnly
                        ? 'Send (dry run)'
                        : 'Send',
                  ),
                ),
              ),
              if (state.lastResult case final result?) ...[
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 360),
                  child: SingleChildScrollView(
                    child: ResultView(
                      result: result,
                      explanation: state.lastExplanation,
                      dryRun: state.lastSentDryRun,
                      historyError: state.lastHistoryError,
                      onRetry: hasProject && state.canSend
                          ? () => sendSelected(context)
                          : null,
                      onShowField: cubit.showField,
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
  const ResultView({
    required this.result,
    this.explanation,
    this.dryRun = false,
    this.historyError,
    this.onRetry,
    this.onShowField,
    super.key,
  });

  static const retryKey = Key('retry-button');

  final FcmSendResult result;
  final ErrorExplanation? explanation;

  /// The result of a dry run: FCM validated the message and delivered nothing.
  final bool dryRun;

  /// Shown when the send could not be saved to history.
  final String? historyError;

  /// Sends again. Null while sending again isn't possible.
  final VoidCallback? onRetry;

  /// Shows a rejected field (e.g. `message.data[0].value`) in the JSON tab.
  final ValueChanged<String>? onShowField;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final milliseconds = result.duration.inMilliseconds;
    final historyNote = historyError;
    switch (result) {
      case FcmSendSuccess(:final messageName):
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.check_circle, color: Colors.green),
              title: Text(dryRun ? 'Valid (dry run, not delivered)' : 'Sent'),
              subtitle: SelectableText('$messageName · $milliseconds ms'),
            ),
            if (historyNote != null)
              Text(historyNote, style: theme.textTheme.bodySmall),
          ],
        );
      case FcmSendFailure(:final error):
        final e = explanation;
        final showField = onShowField;
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
            if (showField != null)
              for (final violation in error.fieldViolations)
                TextButton.icon(
                  key: ValueKey('show-field-${violation.field}'),
                  onPressed: () => showField(violation.field),
                  icon: const Icon(Icons.my_location, size: 16),
                  label: Text('Show ${violation.field} in JSON'),
                ),
            Wrap(
              spacing: 8,
              children: [
                if (e?.link case final link?)
                  TextButton.icon(
                    onPressed: () => launchUrl(link),
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('Open in console'),
                  ),
                TextButton.icon(
                  key: retryKey,
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Retry'),
                ),
              ],
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
            if (historyNote != null)
              Text(historyNote, style: theme.textTheme.bodySmall),
          ],
        );
    }
  }
}
