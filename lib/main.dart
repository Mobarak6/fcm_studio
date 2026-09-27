import 'package:fcm_studio/app/app.dart';
import 'package:fcm_studio/app/dependencies.dart';
import 'package:flutter/widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dependencies = await AppDependencies.create();
  runApp(FcmStudioApp(dependencies: dependencies));
}
