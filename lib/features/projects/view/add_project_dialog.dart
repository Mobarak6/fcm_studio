import 'package:fcm_studio/features/projects/cubit/projects_cubit.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

Future<void> showAddProjectDialog(BuildContext context) {
  final cubit = context.read<ProjectsCubit>();
  return showDialog<void>(
    context: context,
    builder: (_) =>
        BlocProvider.value(value: cubit, child: const AddProjectDialog()),
  );
}

class AddProjectDialog extends StatefulWidget {
  const AddProjectDialog({super.key});

  @override
  State<AddProjectDialog> createState() => _AddProjectDialogState();
}

class _AddProjectDialogState extends State<AddProjectDialog> {
  bool _remember = false;
  bool _busy = false;
  String? _error;
  String? _info;

  Future<void> _chooseFile() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Service account key',
          extensions: ['json'],
          mimeTypes: ['application/json'],
          uniformTypeIdentifiers: ['public.json'],
        ),
      ],
    );
    if (file == null || !mounted) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    final text = await file.readAsString();
    if (!mounted) {
      return;
    }
    final result = await context.read<ProjectsCubit>().addFromServiceAccount(
      text,
      persistKey: !kIsWeb || _remember,
    );
    if (!mounted) {
      return;
    }
    switch (result) {
      case AddProjectSuccess(:final project, needsProjectNumber: true):
        setState(() {
          _busy = false;
          _info =
              'Added ${project.id}. This key cannot read the project number, so set it '
              'later from the project menu (optional; used to check device tokens).';
        });
      case AddProjectSuccess():
        Navigator.of(context).pop();
      case AddProjectFailure(:final message):
        setState(() {
          _busy = false;
          _error = message;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final error = _error;
    final info = _info;
    return AlertDialog(
      title: const Text('Add project'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Choose a service account key file (.json). Get one in Firebase console → '
              'Project settings → Service accounts → Generate new private key.',
            ),
            const SizedBox(height: 12),
            Text(
              'Tip: create a separate service account that only has the '
              '"Firebase Cloud Messaging API Admin" role, and use its key here.',
              style: theme.textTheme.bodySmall,
            ),
            if (kIsWeb) ...[
              const SizedBox(height: 12),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _remember,
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _remember = value ?? false),
                title: const Text('Remember on this browser'),
                subtitle: const Text(
                  'Otherwise the key is kept only until this tab is closed or reloaded. '
                  'Browser storage can be read by scripts on this site.',
                ),
              ),
            ],
            if (_busy) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
            ],
            if (error != null) ...[
              const SizedBox(height: 16),
              Text(error, style: TextStyle(color: theme.colorScheme.error)),
            ],
            if (info != null) ...[const SizedBox(height: 16), Text(info)],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(info == null ? 'Cancel' : 'Done'),
        ),
        FilledButton(
          onPressed: _busy ? null : _chooseFile,
          child: const Text('Choose key file…'),
        ),
      ],
    );
  }
}
