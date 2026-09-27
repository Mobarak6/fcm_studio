import 'package:fcm_studio/app/dependencies.dart';
import 'package:fcm_studio/app/theme.dart';
import 'package:fcm_studio/features/composer/cubit/composer_cubit.dart';
import 'package:fcm_studio/features/composer/view/composer_screen.dart';
import 'package:fcm_studio/features/projects/cubit/projects_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class FcmStudioApp extends StatelessWidget {
  const FcmStudioApp({required this.dependencies, super.key});

  final AppDependencies dependencies;

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) => ProjectsCubit(
            repository: dependencies.projectsRepository,
            authRegistry: dependencies.authRegistry,
            firebaseApi: dependencies.firebaseProjectsApi,
          )..load(),
        ),
        BlocProvider(
          create: (_) => ComposerCubit(
            fcmClient: dependencies.fcmClient,
            auth: dependencies.authRegistry,
          ),
        ),
      ],
      child: MaterialApp(
        title: 'FCM Studio',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        home: const ComposerScreen(),
      ),
    );
  }
}
