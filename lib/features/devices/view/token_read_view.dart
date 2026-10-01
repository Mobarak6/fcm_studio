import 'package:fcm_studio/core/utils/shorten.dart';
import 'package:fcm_studio/features/devices/cubit/token_reader_cubit.dart';
import 'package:fcm_studio/features/devices/domain/token_read_results.dart';
import 'package:fcm_studio/features/devices/view/device_actions.dart';
import 'package:fcm_studio/features/projects/cubit/projects_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Where reading a token stands, and what the user can do next (spec §9.3).
class TokenReadView extends StatefulWidget {
  const TokenReadView({required this.read, super.key});

  static const useTokenKey = Key('token-use');
  static const readLogsKey = Key('token-read-logs');
  static const confirmLogsKey = Key('token-confirm-logs');
  static const launchKey = Key('token-launch');
  static const retryKey = Key('token-retry');

  final TokenRead read;

  @override
  State<TokenReadView> createState() => _TokenReadViewState();
}

class _TokenReadViewState extends State<TokenReadView> {
  String? _sender;

  @override
  void initState() {
    super.initState();
    _sender = _preselected(widget.read);
  }

  @override
  void didUpdateWidget(TokenReadView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.read != oldWidget.read) {
      _sender = _preselected(widget.read);
    }
  }

  static String? _preselected(TokenRead read) =>
      read is TokenReadFound ? read.preselectedSenderId : null;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<TokenReaderCubit>();
    String? projectNumber() =>
        context.read<ProjectsCubit>().state.selected?.projectNumber;
    final dismiss = TextButton(
      onPressed: cubit.dismiss,
      child: const Text('OK'),
    );
    return switch (widget.read) {
      TokenReadIdle() => const SizedBox.shrink(),
      TokenReading(:final package) => _Note(
        busy: true,
        text: 'Reading the token of $package…',
      ),
      TokenReadFound(:final package, :final tokens, :final method)
          when tokens.length > 1 =>
        _Card(
          children: [
            Text(
              '$package has tokens for several Firebase projects. Pick one:',
            ),
            for (final token in tokens)
              ListTile(
                key: ValueKey('sender-${token.senderId}'),
                dense: true,
                leading: Icon(
                  token.senderId == _sender
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                ),
                title: Text('Project number ${token.senderId ?? 'unknown'}'),
                subtitle: Text(shortenMiddle(token.token)),
                onTap: () => setState(() => _sender = token.senderId),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                key: TokenReadView.useTokenKey,
                onPressed: tokens.any((t) => t.senderId == _sender)
                    ? () => useDeviceToken(
                        context,
                        package: package,
                        found: tokens.firstWhere((t) => t.senderId == _sender),
                        method: method,
                      )
                    : null,
                child: const Text('Use this token'),
              ),
            ),
          ],
        ),
      TokenReadFound(:final package) => _Note(
        text: 'Using the token of $package.',
      ),
      TokenReadReleaseBuild(:final package) => _Card(
        children: [
          Text("$package is a release build, so its files can't be read."),
          const SizedBox(height: 4),
          const Text(
            'FCM Studio can restart the app and look for its token in the log. '
            'This works only if the app logs its token.',
          ),
          Wrap(
            spacing: 8,
            children: [
              FilledButton(
                key: TokenReadView.readLogsKey,
                onPressed: () => _confirmLogcat(context, package),
                child: const Text('Restart the app and read its log…'),
              ),
              dismiss,
            ],
          ),
        ],
      ),
      TokenReadNoTokenYet(:final package) => _Card(
        children: [
          const Text('Open the app once so it gets a token.'),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton(
                key: TokenReadView.launchKey,
                onPressed: () => cubit.launchApp(package),
                child: const Text('Launch app'),
              ),
              FilledButton(
                key: TokenReadView.retryKey,
                onPressed: () =>
                    cubit.readToken(package, projectNumber: projectNumber()),
                child: const Text('Retry'),
              ),
            ],
          ),
        ],
      ),
      TokenReadNotInstalled(:final package) => _Card(
        error: true,
        children: [Text('$package is not installed on this phone.'), dismiss],
      ),
      TokenReadWatchingLogcat(:final progress) => _Note(
        busy: true,
        text: switch (progress) {
          LogcatRestartingApp() => 'Restarting the app…',
          LogcatWaitingForApp() => 'Waiting for the app to start…',
          _ => "Watching the app's log for its token…",
        },
      ),
      TokenReadLogcatNoToken(:final package) => _Card(
        error: true,
        children: [
          Text(
            "$package didn't print its token within 20 seconds. Use a debug "
            'build, or add a debug-only log line that prints the token.',
          ),
          dismiss,
        ],
      ),
      TokenReadAppDidNotStart(:final package) => _Card(
        error: true,
        children: [
          Text("$package didn't start within 10 seconds."),
          Wrap(
            spacing: 8,
            children: [
              FilledButton(
                key: TokenReadView.retryKey,
                onPressed: () => cubit.readTokenFromLogcat(package),
                child: const Text('Retry'),
              ),
              dismiss,
            ],
          ),
        ],
      ),
      TokenReadFailed(:final message) => _Card(
        error: true,
        children: [SelectableText(message), dismiss],
      ),
    };
  }

  /// Logcat restarts the app, so it runs only after the user agrees (spec §9.3).
  Future<void> _confirmLogcat(BuildContext context, String package) async {
    final cubit = context.read<TokenReaderCubit>();
    final serial = cubit.state.serial;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restart the app?'),
        content: Text(
          '$package will be closed and opened again on the phone, and its log '
          'watched for up to 20 seconds. Nothing is cleared from the log.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: TokenReadView.confirmLogsKey,
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Restart and read'),
          ),
        ],
      ),
    );
    // The phone may have changed while the dialog was open.
    final read = cubit.state.read;
    final sameAsk =
        cubit.state.serial == serial &&
        read is TokenReadReleaseBuild &&
        read.package == package;
    if ((confirmed ?? false) && sameAsk) {
      await cubit.readTokenFromLogcat(package);
    }
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text, this.busy = false});

  final String text;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: busy
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.check_circle, color: Colors.green),
      title: Text(text),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.children, this.error = false});

  final bool error;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: error ? scheme.errorContainer : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }
}
