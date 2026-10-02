import 'package:fcm_studio/core/firebase/firebase_projects_api.dart';
import 'package:fcm_studio/features/projects/cubit/projects_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// The checklist of an account's Firebase projects (spec §4.2).
class GoogleProjectsDialog extends StatefulWidget {
  const GoogleProjectsDialog({required this.found, super.key});

  final GoogleProjectsFound found;

  static const addKey = Key('google-projects-add');
  static const searchKey = Key('google-projects-search');

  static Key projectKey(String projectId) =>
      ValueKey('google-project-$projectId');

  @override
  State<GoogleProjectsDialog> createState() => _GoogleProjectsDialogState();
}

class _GoogleProjectsDialogState extends State<GoogleProjectsDialog> {
  final Set<String> _picked = {};
  String _query = '';
  bool _saving = false;
  String? _error;

  /// Matches the display name or the project ID, ignoring case.
  bool _matches(FirebaseProjectInfo project) {
    final query = _query.trim().toLowerCase();
    return query.isEmpty ||
        project.displayName.toLowerCase().contains(query) ||
        project.projectId.toLowerCase().contains(query);
  }

  Future<void> _add() async {
    final cubit = context.read<ProjectsCubit>();
    final picked = [
      for (final project in widget.found.projects)
        if (_picked.contains(project.projectId)) project,
    ];
    setState(() {
      _saving = true;
      _error = null;
    });
    final error = await cubit.addGoogleProjects(widget.found.session, picked);
    if (!mounted) {
      return;
    }
    if (error == null) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _saving = false;
        _error = error;
      });
    }
  }

  void _toggle(String projectId, bool? picked) {
    setState(() {
      if (picked ?? false) {
        _picked.add(projectId);
      } else {
        _picked.remove(projectId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final found = widget.found;
    final existing = {
      for (final project in context.read<ProjectsCubit>().state.projects)
        project.id,
    };
    final error = _error;
    final count = _picked.length;
    final shown = found.projects.where(_matches).toList();
    return AlertDialog(
      title: Text('Projects for ${found.email}'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (found.projects.isEmpty)
              Text(
                '${found.email} has no Firebase projects. Sign in with another '
                'account, or ask to be added to a project.',
              )
            else ...[
              TextField(
                key: GoogleProjectsDialog.searchKey,
                autofocus: true,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search by name or project ID',
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
              const SizedBox(height: 8),
              if (shown.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text('No projects match "${_query.trim()}".'),
                ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 360),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final project in shown)
                      CheckboxListTile(
                        key: GoogleProjectsDialog.projectKey(project.projectId),
                        value: _picked.contains(project.projectId),
                        onChanged: _saving
                            ? null
                            : (picked) => _toggle(project.projectId, picked),
                        title: Text(project.displayName),
                        subtitle: Text(
                          existing.contains(project.projectId)
                              ? '${project.projectId} · already added; it will '
                                    'use this account'
                              : project.projectId,
                        ),
                      ),
                  ],
                ),
              ),
            ],
            if (_saving) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
            ],
            if (error != null) ...[
              const SizedBox(height: 16),
              Text(error, style: TextStyle(color: theme.colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: GoogleProjectsDialog.addKey,
          onPressed: count == 0 || _saving ? null : _add,
          child: Text(switch (count) {
            0 => 'Add projects',
            1 => 'Add 1 project',
            _ => 'Add $count projects',
          }),
        ),
      ],
    );
  }
}
