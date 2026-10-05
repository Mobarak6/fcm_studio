import 'dart:ui' show AppExitResponse;

import 'package:fcm_studio/app/app_error_banner.dart';
import 'package:fcm_studio/app/app_error_cubit.dart';
import 'package:fcm_studio/app/dependencies.dart';
import 'package:fcm_studio/app/navigation_cubit.dart';
import 'package:fcm_studio/app/shell.dart';
import 'package:fcm_studio/app/theme.dart';
import 'package:fcm_studio/core/platform/file_access.dart';
import 'package:fcm_studio/core/platform/platform_capabilities.dart';
import 'package:fcm_studio/features/composer/cubit/composer_cubit.dart';
import 'package:fcm_studio/features/devices/bloc/devices_bloc.dart';
import 'package:fcm_studio/features/devices/cubit/bridge_cubit.dart';
import 'package:fcm_studio/features/devices/cubit/token_reader_cubit.dart';
import 'package:fcm_studio/features/devices/data/phone_access.dart';
import 'package:fcm_studio/features/devices/data/web_phones.dart';
import 'package:fcm_studio/features/history/cubit/history_cubit.dart';
import 'package:fcm_studio/features/presets/cubit/presets_cubit.dart';
import 'package:fcm_studio/features/projects/cubit/projects_cubit.dart';
import 'package:fcm_studio/features/settings/cubit/adb_setup_cubit.dart';
import 'package:fcm_studio/features/targets/cubit/targets_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class FcmStudioApp extends StatelessWidget {
  const FcmStudioApp({required this.dependencies, this.errors, super.key});

  final AppDependencies dependencies;

  /// The error banner's cubit. `main()` passes one that also receives
  /// uncaught errors; otherwise the app makes its own.
  final AppErrorCubit? errors;

  @override
  Widget build(BuildContext context) {
    final errors = this.errors;
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<FileAccess>.value(value: dependencies.files),
        RepositoryProvider<PlatformFeatures>.value(
          value: dependencies.platform,
        ),
        if (dependencies.phoneAccess case final phoneAccess?)
          RepositoryProvider<PhoneAccess>.value(value: phoneAccess),
      ],
      child: MultiBlocProvider(
        providers: [
          if (errors != null)
            BlocProvider.value(value: errors)
          else
            BlocProvider(create: (_) => AppErrorCubit()),
          BlocProvider(
            create: (_) => ProjectsCubit(
              repository: dependencies.projectsRepository,
              authRegistry: dependencies.authRegistry,
              firebaseApi: dependencies.firebaseProjectsApi,
            )..load(),
          ),
          BlocProvider(
            lazy: false,
            create: (_) => PresetsCubit(
              repository: dependencies.presetsRepository,
              clock: dependencies.clock,
            )..load(),
          ),
          BlocProvider(
            lazy: false,
            create: (_) => TargetsCubit(
              repository: dependencies.targetsRepository,
              clock: dependencies.clock,
            )..load(),
          ),
          BlocProvider(
            lazy: false,
            create: (_) => HistoryCubit(
              repository: dependencies.historyRepository,
              sender: dependencies.messageSender,
            )..load(),
          ),
          BlocProvider(create: (_) => NavigationCubit()),
          BlocProvider(
            create: (_) => ComposerCubit(sender: dependencies.messageSender),
          ),
          BlocProvider(
            lazy: false,
            create: (_) {
              final cubit = AdbSetupCubit(
                locator: dependencies.adbLocator,
                settings: dependencies.settingsRepository,
              );
              // Browsers can't run adb (spec §3.1).
              if (dependencies.platform.canRunAdb) {
                cubit.locate();
              }
              return cubit;
            },
          ),
          if (dependencies.bridge case final bridge?)
            BlocProvider(
              lazy: false,
              create: (_) => BridgeCubit(control: bridge)..start(),
            ),
          BlocProvider(
            lazy: false,
            create: (_) {
              final bloc = DevicesBloc(serviceFor: dependencies.adbServiceFor);
              // There is no adb to find on the web: its phones (WebUSB and
              // the bridge) are tracked at once (bridge design §4.6).
              if (!dependencies.platform.canRunAdb) {
                bloc.add(const DevicesAdbChanged(WebPhones.source));
              }
              return bloc;
            },
          ),
          BlocProvider(
            create: (_) => TokenReaderCubit(
              serviceFor: dependencies.adbServiceFor,
              recent: dependencies.recentPackagesRepository,
            ),
          ),
        ],
        child: _AdbExitGuard(
          enabled: dependencies.platform.canRunAdb,
          child: BlocListener<AdbSetupCubit, AdbSetupState>(
            // Phones are tracked with whichever adb was found, or not at all.
            listenWhen: (previous, current) =>
                previous.adbPath != current.adbPath,
            listener: (context, state) => context.read<DevicesBloc>().add(
              DevicesAdbChanged(state.adbPath),
            ),
            child: MaterialApp(
              title: 'FCM Studio',
              debugShowCheckedModeBanner: false,
              theme: AppTheme.light,
              darkTheme: AppTheme.dark,
              // The error banner stays above every screen and dialog.
              builder: (context, child) => Column(
                children: [
                  const AppErrorBanner(),
                  Expanded(child: child ?? const SizedBox.shrink()),
                ],
              ),
              home: const AppShell(),
            ),
          ),
        ),
      ),
    );
  }
}

/// Closes the adb owners when the app quits. On macOS and Windows quitting
/// doesn't dispose the widget tree, which would leave `adb track-devices`
/// (and `adb logcat` during a read) running.
class _AdbExitGuard extends StatefulWidget {
  const _AdbExitGuard({required this.enabled, required this.child});

  final bool enabled;
  final Widget child;

  @override
  State<_AdbExitGuard> createState() => _AdbExitGuardState();
}

class _AdbExitGuardState extends State<_AdbExitGuard> {
  AppLifecycleListener? _listener;

  @override
  void initState() {
    super.initState();
    if (widget.enabled) {
      _listener = AppLifecycleListener(onExitRequested: _closeAdb);
    }
  }

  Future<AppExitResponse> _closeAdb() async {
    // Read first: nothing may touch the context after an await.
    final devices = context.read<DevicesBloc>();
    final reader = context.read<TokenReaderCubit>();
    await Future.wait([devices.close(), reader.close()]);
    return AppExitResponse.exit;
  }

  @override
  void dispose() {
    _listener?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
