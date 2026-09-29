import 'dart:convert';

import 'package:fcm_studio/app/app_error_cubit.dart';
import 'package:fcm_studio/app/navigation_cubit.dart';
import 'package:fcm_studio/core/auth/access_token_provider.dart';
import 'package:fcm_studio/core/fcm/fcm_send_result.dart';
import 'package:fcm_studio/core/utils/shorten.dart';
import 'package:fcm_studio/core/utils/time_format.dart';
import 'package:fcm_studio/features/composer/cubit/composer_cubit.dart';
import 'package:fcm_studio/features/composer/domain/send_confirmation.dart';
import 'package:fcm_studio/features/composer/domain/target.dart';
import 'package:fcm_studio/features/composer/view/send_confirmation_dialog.dart';
import 'package:fcm_studio/features/history/cubit/history_cubit.dart';
import 'package:fcm_studio/features/history/domain/history_entry.dart';
import 'package:fcm_studio/features/history/domain/history_filter.dart';
import 'package:fcm_studio/features/presets/cubit/presets_cubit.dart';
import 'package:fcm_studio/features/presets/view/preset_actions.dart';
import 'package:fcm_studio/features/presets/view/preset_details_dialog.dart';
import 'package:fcm_studio/features/projects/cubit/projects_cubit.dart';
import 'package:fcm_studio/features/projects/domain/project.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Every send attempt, with filters and actions (spec §7.2).
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  static const clearKey = Key('history-clear');
  static const searchKey = Key('history-search');

  @override
  Widget build(BuildContext context) {
    final state = context.watch<HistoryCubit>().state;
    final visible = state.visible;
    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        actions: [
          TextButton.icon(
            key: clearKey,
            onPressed: state.entries.isEmpty ? null : () => _clear(context),
            icon: const Icon(Icons.delete_sweep_outlined),
            label: const Text('Clear history'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Filters(state: state),
          const Divider(height: 1),
          Expanded(
            child: visible.isEmpty
                ? Center(
                    child: Text(
                      state.entries.isEmpty
                          ? 'Nothing sent yet.'
                          : 'No entries match the filters.',
                    ),
                  )
                : ListView.builder(
                    itemCount: visible.length,
                    itemBuilder: (context, index) =>
                        HistoryTile(entry: visible[index]),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _clear(BuildContext context) async {
    final history = context.read<HistoryCubit>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear history?'),
        content: const Text(
          'Every history entry is deleted. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('history-clear-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await history.clear();
    }
  }
}

class _Filters extends StatefulWidget {
  const _Filters({required this.state});

  final HistoryState state;

  @override
  State<_Filters> createState() => _FiltersState();
}

class _FiltersState extends State<_Filters> {
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<HistoryCubit>();
    final filter = widget.state.filter;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          DropdownButton<String?>(
            value: filter.projectId,
            items: [
              const DropdownMenuItem<String?>(child: Text('All projects')),
              for (final id in widget.state.projectIds)
                DropdownMenuItem<String?>(value: id, child: Text(id)),
            ],
            onChanged: (id) =>
                cubit.setFilter(filter.copyWith(projectId: () => id)),
          ),
          SegmentedButton<OutcomeFilter>(
            segments: const [
              ButtonSegment(value: OutcomeFilter.all, label: Text('All')),
              ButtonSegment(
                value: OutcomeFilter.success,
                label: Text('Succeeded'),
              ),
              ButtonSegment(
                value: OutcomeFilter.failure,
                label: Text('Failed'),
              ),
            ],
            selected: {filter.outcome},
            onSelectionChanged: (selection) =>
                cubit.setFilter(filter.copyWith(outcome: selection.first)),
          ),
          SegmentedButton<ModeFilter>(
            segments: const [
              ButtonSegment(
                value: ModeFilter.all,
                label: Text('Real + dry run'),
              ),
              ButtonSegment(value: ModeFilter.real, label: Text('Real')),
              ButtonSegment(value: ModeFilter.dryRun, label: Text('Dry run')),
            ],
            selected: {filter.mode},
            onSelectionChanged: (selection) =>
                cubit.setFilter(filter.copyWith(mode: selection.first)),
          ),
          SizedBox(
            width: 260,
            child: TextField(
              key: HistoryScreen.searchKey,
              controller: _search,
              decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.search),
                hintText: 'Search target, preset, body',
                border: OutlineInputBorder(),
              ),
              onChanged: (query) =>
                  cubit.setFilter(cubit.state.filter.copyWith(query: query)),
            ),
          ),
        ],
      ),
    );
  }
}

/// One history entry, expandable to its request, response and actions.
class HistoryTile extends StatelessWidget {
  const HistoryTile({required this.entry, super.key});

  final HistoryEntry entry;

  static const _monospace = TextStyle(fontFamily: 'monospace', fontSize: 12);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final project = context.select(
      (ProjectsCubit c) =>
          c.state.projects.where((p) => p.id == entry.projectId).firstOrNull,
    );
    final target = entry.target;
    final targetText =
        target.label ??
        (target.kind == TargetKind.token
            ? shortenMiddle(target.value)
            : target.value);
    final outcome = switch (entry.outcome) {
      HistorySuccess() => entry.validateOnly ? 'Valid (dry run)' : 'Sent',
      HistoryFailure(:final code, :final explanation) => '$code · $explanation',
    };
    final id = entry.id;
    return ExpansionTile(
      key: ValueKey('history-$id'),
      leading: Icon(
        entry.succeeded ? Icons.check_circle : Icons.error,
        color: entry.succeeded ? Colors.green : theme.colorScheme.error,
      ),
      title: Text(targetText),
      subtitle: Text(
        [
          formatLocalTime(entry.sentAt),
          entry.projectId,
          ?entry.presetName,
          outcome,
        ].join(' · '),
      ),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Tooltip(
              message: project == null
                  ? 'The project ${entry.projectId} was removed.'
                  : 'Send again with a current access token',
              child: FilledButton.tonalIcon(
                key: ValueKey('history-resend-$id'),
                onPressed: project == null
                    ? null
                    : () => _resend(context, project),
                icon: const Icon(Icons.replay),
                label: const Text('Resend'),
              ),
            ),
            OutlinedButton(
              key: ValueKey('history-open-$id'),
              onPressed: () => _open(context),
              child: const Text('Open in composer'),
            ),
            OutlinedButton(
              key: ValueKey('history-save-$id'),
              onPressed: () => _saveAsPreset(context),
              child: const Text('Save as preset…'),
            ),
            PopupMenuButton<bool>(
              key: ValueKey('history-curl-$id'),
              enabled: project != null,
              tooltip: 'Copy as cURL',
              onSelected: (withToken) {
                if (project != null) {
                  _copyCurl(context, project, includeAccessToken: withToken);
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: true,
                  child: Text('Copy as cURL with access token'),
                ),
                PopupMenuItem(
                  value: false,
                  child: Text(r'Copy as cURL with $FCM_ACCESS_TOKEN'),
                ),
              ],
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Text('Copy as cURL'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text('Request', style: theme.textTheme.titleSmall),
        SelectableText(
          const JsonEncoder.withIndent('  ').convert(entry.request),
          style: _monospace,
        ),
        if (entry.responseBody case final body?) ...[
          const SizedBox(height: 8),
          Text(
            'Response${entry.httpStatus == null ? '' : ' (HTTP ${entry.httpStatus})'}'
            ' · ${entry.duration.inMilliseconds} ms',
            style: theme.textTheme.titleSmall,
          ),
          SelectableText(body, style: _monospace),
        ],
      ],
    );
  }

  /// Resend asks first for a production project, like every send (spec §4.3).
  Future<void> _resend(BuildContext context, Project project) async {
    final history = context.read<HistoryCubit>();
    final messenger = ScaffoldMessenger.of(context);
    final confirmation = SendConfirmation.forSend(
      project: project,
      target: entry.target.toTarget(),
      validateOnly: entry.validateOnly,
    );
    if (confirmation != null && !await confirmSend(context, confirmation)) {
      return;
    }
    final outcome = await history.resend(entry, project);
    messenger.showSnackBar(
      SnackBar(
        content: Text(switch (outcome.result) {
          FcmSendSuccess(:final messageName) => 'Resent: $messageName',
          FcmSendFailure() =>
            'Resend failed: ${outcome.explanation?.title ?? 'see History'}',
        }),
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    final composer = context.read<ComposerCubit>();
    final navigation = context.read<NavigationCubit>();
    if (composer.state.isDirty && !await confirmDiscardChanges(context)) {
      return;
    }
    composer.openMessage(
      template: entry.template,
      target: entry.target.toTarget(),
    );
    navigation.show(AppSection.composer);
  }

  Future<void> _saveAsPreset(BuildContext context) async {
    final presets = context.read<PresetsCubit>();
    final errors = context.read<AppErrorCubit>();
    final messenger = ScaffoldMessenger.of(context);
    final details = await showPresetDetailsDialog(
      context,
      title: 'Save as preset',
      isNameTaken: presets.state.nameTaken,
    );
    if (details == null) {
      return;
    }
    try {
      await presets.saveAs(
        name: details.name,
        description: details.description,
        template: entry.template,
        variables: const [],
      );
      messenger.showSnackBar(
        SnackBar(content: Text('Saved "${details.name}".')),
      );
    } catch (e) {
      errors.report(e, context: 'Could not save the preset');
    }
  }

  Future<void> _copyCurl(
    BuildContext context,
    Project project, {
    required bool includeAccessToken,
  }) async {
    final history = context.read<HistoryCubit>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final command = await history.curl(
        entry,
        project,
        includeAccessToken: includeAccessToken,
      );
      await Clipboard.setData(ClipboardData(text: command));
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            includeAccessToken
                ? "Copied. The access token in it is valid for up to 1 hour; don't paste it into chats."
                : r'Copied. Set $FCM_ACCESS_TOKEN before running it.',
          ),
        ),
      );
    } on AuthException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}
