import 'package:fcm_studio/features/projects/cubit/projects_cubit.dart';
import 'package:fcm_studio/features/projects/domain/project.dart';
import 'package:fcm_studio/features/projects/view/add_project_dialog.dart';
import 'package:fcm_studio/features/projects/view/sign_in_again_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class ProjectSwitcher extends StatelessWidget {
  const ProjectSwitcher({super.key});

  static const dropdownKey = Key('project-dropdown');

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return BlocBuilder<ProjectsCubit, ProjectsState>(
      builder: (context, state) {
        final selected = state.selected;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Project', style: textTheme.titleSmall),
            const SizedBox(height: 8),
            if (state.status != ProjectsStatus.ready)
              const Text('Loading projects…')
            else if (selected == null)
              const Text(
                'No projects yet. Add one with a service account key or Google sign-in.',
              )
            else
              Row(
                children: [
                  Expanded(
                    child: _ProjectPicker(
                      projects: state.projects,
                      selected: selected,
                    ),
                  ),
                  const SizedBox(width: 8),
                  EnvironmentChip(environment: selected.environment),
                  _ProjectMenu(project: selected),
                ],
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => showAddProjectDialog(context),
              icon: const Icon(Icons.add),
              label: const Text('Add project'),
            ),
          ],
        );
      },
    );
  }
}

/// The project dropdown. Typing filters it by name or project ID (the label
/// is "Name (id)"); leaving it without choosing shows the selected project
/// again.
class _ProjectPicker extends StatefulWidget {
  const _ProjectPicker({required this.projects, required this.selected});

  final List<Project> projects;
  final Project selected;

  @override
  State<_ProjectPicker> createState() => _ProjectPickerState();
}

class _ProjectPickerState extends State<_ProjectPicker> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.selected.label,
  );
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_showSelectedWhenLeft);
  }

  @override
  void didUpdateWidget(_ProjectPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    // e.g. the project was switched elsewhere, or renamed.
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
    final label = widget.selected.label;
    if (_controller.text != label) {
      _controller.text = label;
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
    return DropdownMenu<String>(
      key: ProjectSwitcher.dropdownKey,
      controller: _controller,
      focusNode: _focus,
      initialSelection: widget.selected.id,
      expandedInsets: EdgeInsets.zero,
      enableFilter: true,
      requestFocusOnTap: true,
      menuHeight: 360,
      leadingIcon: const Icon(Icons.search),
      hintText: 'Search projects',
      dropdownMenuEntries: [
        for (final project in widget.projects)
          DropdownMenuEntry(value: project.id, label: project.label),
      ],
      onSelected: (id) {
        if (id != null) {
          context.read<ProjectsCubit>().select(id);
        }
      },
    );
  }
}

class EnvironmentChip extends StatelessWidget {
  const EnvironmentChip({required this.environment, super.key});

  final ProjectEnvironment environment;

  static Color colorOf(ProjectEnvironment environment) => switch (environment) {
    ProjectEnvironment.dev => Colors.green,
    ProjectEnvironment.staging => Colors.amber,
    ProjectEnvironment.prod => Colors.red,
  };

  @override
  Widget build(BuildContext context) {
    final color = colorOf(environment);
    return Chip(
      label: Text(environment.name.toUpperCase()),
      visualDensity: VisualDensity.compact,
      side: BorderSide(color: color),
      backgroundColor: color.withValues(alpha: 0.12),
    );
  }
}

enum _MenuAction { dev, staging, prod, projectNumber, signInAgain, remove }

class _ProjectMenu extends StatelessWidget {
  const _ProjectMenu({required this.project});

  final Project project;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_MenuAction>(
      key: const Key('project-menu'),
      tooltip: 'Project options',
      onSelected: (action) => _onSelected(context, action),
      itemBuilder: (context) => [
        for (final environment in ProjectEnvironment.values)
          CheckedPopupMenuItem(
            value: _MenuAction.values.byName(environment.name),
            checked: project.environment == environment,
            child: Text('Environment: ${environment.name}'),
          ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: _MenuAction.projectNumber,
          child: Text(
            project.projectNumber == null
                ? 'Set project number…'
                : 'Project number: ${project.projectNumber}',
          ),
        ),
        if (project.credential case GoogleAccountRef(:final email)) ...[
          PopupMenuItem<_MenuAction>(
            enabled: false,
            child: Text('Signed in as $email'),
          ),
          const PopupMenuItem(
            value: _MenuAction.signInAgain,
            child: Text('Sign in again…'),
          ),
        ],
        const PopupMenuItem(
          value: _MenuAction.remove,
          child: Text('Remove project…'),
        ),
      ],
    );
  }

  Future<void> _onSelected(BuildContext context, _MenuAction action) async {
    final cubit = context.read<ProjectsCubit>();
    switch (action) {
      case _MenuAction.dev || _MenuAction.staging || _MenuAction.prod:
        await cubit.setEnvironment(
          project.id,
          ProjectEnvironment.values.byName(action.name),
        );
      case _MenuAction.projectNumber:
        final number = await showDialog<String>(
          context: context,
          builder: (_) =>
              _ProjectNumberDialog(initial: project.projectNumber ?? ''),
        );
        if (number != null) {
          await cubit.setProjectNumber(project.id, number);
        }
      case _MenuAction.signInAgain:
        final credential = project.credential;
        if (credential is! GoogleAccountRef) {
          return;
        }
        final messenger = ScaffoldMessenger.of(context);
        final message = await showDialog<String>(
          context: context,
          barrierDismissible: false,
          builder: (_) => BlocProvider.value(
            value: cubit,
            child: SignInAgainDialog(account: credential),
          ),
        );
        messenger.showSnackBar(
          SnackBar(
            content: Text(message ?? 'Signed in again as ${credential.email}.'),
          ),
        );
      case _MenuAction.remove:
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Remove ${project.id}?'),
            content: Text(switch (project.credential) {
              ServiceAccountRef() =>
                'The project and its stored key are removed from FCM Studio. '
                    'Nothing changes in Firebase.',
              GoogleAccountRef(:final email) =>
                'The project is removed from FCM Studio. The sign-in for $email '
                    'is forgotten once no other project uses it. Nothing changes '
                    'in Firebase.',
            }),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Remove'),
              ),
            ],
          ),
        );
        if (confirmed ?? false) {
          await cubit.remove(project.id);
        }
    }
  }
}

class _ProjectNumberDialog extends StatefulWidget {
  const _ProjectNumberDialog({required this.initial});

  final String initial;

  @override
  State<_ProjectNumberDialog> createState() => _ProjectNumberDialogState();
}

class _ProjectNumberDialogState extends State<_ProjectNumberDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Project number'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: const InputDecoration(
          helperText:
              'Firebase console → Project settings → General → Project number. '
              'Leave empty to clear.',
          helperMaxLines: 2,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
