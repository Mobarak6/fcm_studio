import 'dart:convert';

import 'package:fcm_studio/features/composer/cubit/composer_cubit.dart';
import 'package:fcm_studio/features/composer/domain/render_issue.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class PreviewPanel extends StatelessWidget {
  const PreviewPanel({super.key});

  static const _encoder = JsonEncoder.withIndent('  ');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BlocBuilder<ComposerCubit, ComposerState>(
      buildWhen: (previous, current) =>
          previous.render != current.render ||
          previous.jsonError != current.jsonError,
      builder: (context, state) {
        final request = state.render.request;
        final requestText = request == null ? null : _encoder.convert(request);
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Request preview',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  tooltip: 'Copy request body',
                  icon: const Icon(Icons.copy, size: 18),
                  onPressed: requestText == null
                      ? null
                      : () =>
                            Clipboard.setData(ClipboardData(text: requestText)),
                ),
              ],
            ),
            if (state.jsonError != null)
              _IssueRow(
                icon: Icons.error_outline,
                color: theme.colorScheme.error,
                text: 'Fix the JSON first.',
              ),
            for (final issue in state.render.errors)
              _IssueRow(
                icon: Icons.error_outline,
                color: theme.colorScheme.error,
                text: _format(issue),
              ),
            for (final issue in state.render.warnings)
              _IssueRow(
                icon: Icons.warning_amber,
                color: Colors.amber.shade800,
                text: _format(issue),
              ),
            for (final issue in state.render.notes)
              _IssueRow(
                icon: Icons.info_outline,
                color: theme.colorScheme.outline,
                text: _format(issue),
              ),
            const SizedBox(height: 8),
            if (requestText != null)
              SelectableText(
                requestText,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
          ],
        );
      },
    );
  }

  static String _format(RenderIssue issue) => '${issue.path}: ${issue.message}';
}

class _IssueRow extends StatelessWidget {
  const _IssueRow({
    required this.icon,
    required this.color,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
