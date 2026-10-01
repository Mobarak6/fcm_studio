import 'package:fcm_studio/app/widgets/prompt_dialog.dart';
import 'package:fcm_studio/features/devices/data/adb_locator.dart';
import 'package:fcm_studio/features/settings/cubit/adb_setup_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Where adb is, with Change… and Find automatically (spec §9.1).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static const changeKey = Key('adb-change');
  static const automaticKey = Key('adb-automatic');

  static String sourceLabel(AdbSource source) => switch (source) {
    AdbSource.settings => 'set in Settings',
    AdbSource.androidHome => 'from ANDROID_HOME',
    AdbSource.androidSdkRoot => 'from ANDROID_SDK_ROOT',
    AdbSource.sdkDefault => 'Android SDK default location',
    AdbSource.homebrew => 'Homebrew',
    AdbSource.usrLocal => '/usr/local/bin',
    AdbSource.path => 'found on PATH',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: BlocBuilder<AdbSetupCubit, AdbSetupState>(
        builder: (context, state) {
          final location = state.location;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Android Debug Bridge (adb)',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                'FCM Studio uses adb to read device tokens from phones over USB.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              switch (state.status) {
                AdbStatus.unknown || AdbStatus.locating => const ListTile(
                  leading: SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  title: Text('Looking for adb…'),
                ),
                AdbStatus.found when location != null => ListTile(
                  leading: const Icon(Icons.check_circle, color: Colors.green),
                  title: SelectableText(location.path),
                  subtitle: Text(
                    '${location.version} · ${sourceLabel(location.source)}',
                  ),
                ),
                _ => ListTile(
                  leading: Icon(Icons.error, color: theme.colorScheme.error),
                  title: const Text('adb was not found'),
                  subtitle: Text(
                    'Install Android SDK Platform-Tools, or set the path to adb. '
                    'Looked in: ${state.tried.join(', ')}',
                  ),
                ),
              },
              if (state.userPathFailed)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    "${state.userPath} doesn't run adb.",
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton(
                    key: changeKey,
                    onPressed: () => _change(context),
                    child: const Text('Change…'),
                  ),
                  // Always there: the adb found earlier may be gone.
                  TextButton(
                    key: automaticKey,
                    onPressed: () => state.userPath != null
                        ? context.read<AdbSetupCubit>().setUserPath(null)
                        : context.read<AdbSetupCubit>().locate(),
                    child: Text(
                      state.userPath != null
                          ? 'Find automatically'
                          : 'Find again',
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _change(BuildContext context) async {
    final cubit = context.read<AdbSetupCubit>();
    final path = await promptForText(
      context,
      title: 'Path to adb',
      label: 'Full path to the adb program',
      initial: cubit.state.userPath ?? cubit.state.adbPath ?? '',
      confirmLabel: 'Use',
    );
    if (path != null && path.trim().isNotEmpty) {
      await cubit.setUserPath(path);
    }
  }
}
