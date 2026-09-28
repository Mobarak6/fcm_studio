import 'package:fcm_studio/features/composer/domain/send_confirmation.dart';
import 'package:flutter/material.dart';

/// Asks before a production send (spec §4.3). True means send.
Future<bool> confirmSend(
  BuildContext context,
  SendConfirmation confirmation,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (_) => SendConfirmationDialog(confirmation: confirmation),
    ) ??
    false;

class SendConfirmationDialog extends StatefulWidget {
  const SendConfirmationDialog({required this.confirmation, super.key});

  static const typedKey = Key('confirm-project-id');
  static const confirmKey = Key('confirm-send');

  final SendConfirmation confirmation;

  @override
  State<SendConfirmationDialog> createState() => _SendConfirmationDialogState();
}

class _SendConfirmationDialogState extends State<SendConfirmationDialog> {
  final TextEditingController _typed = TextEditingController();

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final confirmation = widget.confirmation;
    final scheme = Theme.of(context).colorScheme;
    final ready =
        !confirmation.requiresTypedProjectId ||
        _typed.text.trim() == confirmation.projectId;
    return AlertDialog(
      icon: Icon(Icons.warning_amber, color: scheme.error),
      title: const Text('Send to production?'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Project: ${confirmation.projectId} (PROD)'),
            const SizedBox(height: 8),
            Text('Audience: ${confirmation.audience}'),
            if (confirmation.requiresTypedProjectId) ...[
              const SizedBox(height: 16),
              TextField(
                key: SendConfirmationDialog.typedKey,
                controller: _typed,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Type ${confirmation.projectId} to confirm',
                ),
                onChanged: (_) => setState(() {}),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: SendConfirmationDialog.confirmKey,
          style: FilledButton.styleFrom(
            backgroundColor: scheme.error,
            foregroundColor: scheme.onError,
          ),
          onPressed: ready ? () => Navigator.of(context).pop(true) : null,
          child: const Text('Send'),
        ),
      ],
    );
  }
}
