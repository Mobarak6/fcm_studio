import 'package:fcm_studio/app/app_error_banner.dart';
import 'package:fcm_studio/app/app_error_cubit.dart';
import 'package:fcm_studio/app/dependencies.dart';
import 'package:fcm_studio/app/navigation_cubit.dart';
import 'package:fcm_studio/app/shell.dart';
import 'package:fcm_studio/app/theme.dart';
import 'package:fcm_studio/core/platform/file_access.dart';
import 'package:fcm_studio/features/composer/cubit/composer_cubit.dart';
import 'package:fcm_studio/features/history/cubit/history_cubit.dart';
import 'package:fcm_studio/features/presets/cubit/presets_cubit.dart';
import 'package:fcm_studio/features/projects/cubit/projects_cubit.dart';
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
    return RepositoryProvider<FileAccess>.value(
      value: dependencies.files,
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
        ],
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
    );
  }
}
