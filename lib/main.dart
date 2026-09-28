import 'package:fcm_studio/app/app.dart';
import 'package:fcm_studio/app/app_error_cubit.dart';
import 'package:fcm_studio/app/dependencies.dart';
import 'package:flutter/widgets.dart';

Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  final errors = AppErrorCubit();
  // Errors that nothing else caught show as a dismissible banner (spec §11).
  binding.platformDispatcher.onError = (error, stack) {
    errors.report(error);
    return true;
  };
  final dependencies = await AppDependencies.create();
  runApp(FcmStudioApp(dependencies: dependencies, errors: errors));
}
