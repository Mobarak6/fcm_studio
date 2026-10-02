import 'dart:async';

import 'package:fcm_studio/features/projects/cubit/projects_cubit.dart';
import 'package:fcm_studio/features/projects/domain/project.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Runs "Sign in again…" for a Google account (plan Decision 6), with a
/// Cancel while Google's page is open. Pops with the cubit's result: null on
/// success, otherwise the message to show.
class SignInAgainDialog extends StatefulWidget {
  const SignInAgainDialog({required this.account, super.key});

  final GoogleAccountRef account;

  static const cancelKey = Key('sign-in-again-cancel');

  @override
  State<SignInAgainDialog> createState() => _SignInAgainDialogState();
}

class _SignInAgainDialogState extends State<SignInAgainDialog> {
  final _cancel = Completer<void>();

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  Future<void> _run() async {
    final message = await context.read<ProjectsCubit>().signInAgain(
      widget.account,
      cancel: _cancel.future,
    );
    if (mounted) {
      Navigator.of(context).pop(message);
    }
  }

  void _stop() {
    if (!_cancel.isCompleted) {
      _cancel.complete();
    }
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final email = widget.account.email;
    return AlertDialog(
      title: const Text('Sign in again'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LinearProgressIndicator(),
          const SizedBox(height: 12),
          Text(
            kIsWeb
                ? 'Finish signing in as $email in the Google pop-up…'
                : 'Finish signing in as $email in your browser…',
          ),
        ],
      ),
      actions: [
        TextButton(
          key: SignInAgainDialog.cancelKey,
          onPressed: _stop,
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
