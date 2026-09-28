import 'package:fcm_studio/app/app.dart';
import 'package:fcm_studio/app/app_error_cubit.dart';
import 'package:fcm_studio/app/dependencies.dart';
import 'package:fcm_studio/app/startup_error_app.dart';
import 'package:flutter/widgets.dart';

Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  final errors = AppErrorCubit();
  // Errors that nothing else caught show as a dismissible banner (spec §11).
  routeUncaughtErrors(binding, errors);
  final AppDependencies dependencies;
  try {
    dependencies = await AppDependencies.create();
  } on Object catch (e) {
    runApp(StartupErrorApp(error: e));
    return;
  }
  runApp(FcmStudioApp(dependencies: dependencies, errors: errors));
}
