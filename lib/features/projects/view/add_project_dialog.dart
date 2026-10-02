import 'dart:async';

import 'package:fcm_studio/features/projects/cubit/projects_cubit.dart';
import 'package:fcm_studio/features/projects/view/google_projects_dialog.dart';
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

  static const googleKey = Key('add-project-google');
  static const cancelGoogleKey = Key('add-project-google-cancel');

  @override
  State<AddProjectDialog> createState() => _AddProjectDialogState();
}

class _AddProjectDialogState extends State<AddProjectDialog> {
  bool _remember = false;
  bool _busy = false;
  String? _error;
  String? _info;

  /// Set while Google's sign-in is open; completing it stops waiting.
  Completer<void>? _cancelGoogle;
  GoogleProjectsFound? _found;

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

  Future<void> _signInWithGoogle() async {
    final cubit = context.read<ProjectsCubit>();
    final cancel = Completer<void>();
    setState(() {
      _cancelGoogle = cancel;
      _busy = true;
      _error = null;
      _info = null;
    });
    final result = await cubit.signInWithGoogle(cancel: cancel.future);
    if (!mounted) {
      return;
    }
    setState(() {
      _cancelGoogle = null;
      _busy = false;
      switch (result) {
        case GoogleProjectsFound():
          _found = result;
        case GoogleSignInFailed(:final message):
          _error = message;
        case GoogleSignInStopped():
          break;
      }
    });
  }

  void _stopGoogle() {
    final cancel = _cancelGoogle;
    if (cancel != null && !cancel.isCompleted) {
      cancel.complete();
    }
  }

  @override
  void dispose() {
    // Closing the dialog while Google's page is open stops the sign-in, so
    // the loopback server closes too.
    _stopGoogle();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final found = _found;
    if (found != null) {
      return GoogleProjectsDialog(found: found);
    }
    final theme = Theme.of(context);
    final error = _error;
    final info = _info;
    final googleAvailable = context.read<ProjectsCubit>().canSignInWithGoogle;
    final waitingForGoogle = _cancelGoogle != null;
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
            const Divider(height: 32),
            const Text(
              'Or sign in with Google to add the Firebase projects your account '
              'can see.',
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: AddProjectDialog.googleKey,
              onPressed: googleAvailable && !_busy ? _signInWithGoogle : null,
              icon: const Icon(Icons.login),
              label: const Text('Sign in with Google…'),
            ),
            if (!googleAvailable) ...[
              const SizedBox(height: 4),
              Text(
                "Google sign-in isn't set up in this copy of FCM Studio. "
                'See docs/oauth-setup.md.',
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (waitingForGoogle) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              const Text(
                kIsWeb
                    ? 'Finish signing in in the Google pop-up…'
                    : 'Finish signing in in your browser…',
              ),
            ] else if (_busy) ...[
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
        if (waitingForGoogle)
          TextButton(
            key: AddProjectDialog.cancelGoogleKey,
            onPressed: _stopGoogle,
            child: const Text('Cancel sign-in'),
          )
        else
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
