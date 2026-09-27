import 'package:fcm_studio/app/app.dart';
import 'package:fcm_studio/app/dependencies.dart';
import 'package:fcm_studio/core/storage/app_database.dart';
import 'package:fcm_studio/core/storage/secret_store.dart';
import 'package:fcm_studio/features/projects/view/project_switcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'fake_google.dart';

/// Real async work (sembast, RSA signing, MockClient) runs inside `tester.runAsync`.
Future<AppDependencies> buildTestDependencies(
  WidgetTester tester, {
  http.Client? client,
}) async {
  final database = await tester.runAsync(AppDatabase.inMemory);
  return AppDependencies(
    httpClient: client ?? fakeGoogle(),
    database: database!,
    secrets: MemorySecretStore(),
  );
}

Future<void> pumpApp(WidgetTester tester, AppDependencies dependencies) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(FcmStudioApp(dependencies: dependencies));
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// Reads a cubit from the widget tree (through the always-present ProjectSwitcher).
T readCubit<T extends Cubit<Object?>>(WidgetTester tester) =>
    BlocProvider.of<T>(tester.element(find.byType(ProjectSwitcher)));
