import 'package:fcm_studio/app/app.dart';
import 'package:fcm_studio/app/dependencies.dart';
import 'package:fcm_studio/core/platform/file_access.dart';
import 'package:fcm_studio/core/platform/platform_capabilities.dart';
import 'package:fcm_studio/core/storage/app_database.dart';
import 'package:fcm_studio/core/storage/secret_store.dart';
import 'package:fcm_studio/features/composer/cubit/composer_cubit.dart';
import 'package:fcm_studio/features/devices/data/process_runner.dart';
import 'package:fcm_studio/features/projects/cubit/projects_cubit.dart';
import 'package:fcm_studio/features/projects/view/project_switcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'fake_adb_service.dart';
import 'fake_file_access.dart';
import 'fake_google.dart';
import 'fake_process_runner.dart';
import 'fcm_fixtures.dart';
import 'presets_fixture.dart';
import 'service_account_fixture.dart';

const fakeAdbPath = '/fake/sdk/platform-tools/adb';

/// Real async work (sembast, RSA signing, MockClient) runs inside
/// `tester.runAsync`. No real program ever runs: without [adb], every
/// command fails as if adb were not installed.
Future<AppDependencies> buildTestDependencies(
  WidgetTester tester, {
  http.Client? client,
  FileAccess? files,
  ProcessRunner? processRunner,
  Map<String, String>? environment,
  FakeAdbService? adb,
  PlatformFeatures platform = const PlatformFeatures(canRunAdb: true),
}) async {
  final database = await tester.runAsync(AppDatabase.inMemory);
  final runner = processRunner ?? FakeProcessRunner();
  if (adb != null && runner is FakeProcessRunner) {
    runner.on(
      '$fakeAdbPath version',
      ok('Android Debug Bridge version 1.0.41\n'),
    );
  }
  return AppDependencies(
    httpClient: client ?? fakeGoogle(),
    database: database!,
    secrets: MemorySecretStore(),
    files: files ?? FakeFileAccess(),
    loadBuiltInPresets: loadBuiltInPresetsFromFile,
    platform: platform,
    processRunner: runner,
    environment:
        environment ??
        (adb == null ? const {} : const {'ANDROID_HOME': '/fake/sdk'}),
    isWindows: false,
    adbServiceFor: adb == null ? null : (_) => adb,
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

/// Reads a cubit from the widget tree, through the always-present
/// ProjectSwitcher (also while another screen is in front).
T readCubit<T extends BlocBase<Object?>>(WidgetTester tester) =>
    BlocProvider.of<T>(
      tester.element(find.byType(ProjectSwitcher, skipOffstage: false)),
    );

/// Adds the test project through the real cubit.
Future<ProjectsCubit> addTestProject(WidgetTester tester) async {
  final projects = readCubit<ProjectsCubit>(tester);
  await tester.runAsync(
    () =>
        projects.addFromServiceAccount(serviceAccountJson(), persistKey: true),
  );
  await tester.pump();
  return projects;
}

/// Pumps the app with the test project already added, and returns both cubits.
Future<(ProjectsCubit, ComposerCubit)> pumpAppWithProject(
  WidgetTester tester, {
  int fcmStatus = 200,
  String fcmBody = successBody,
  void Function(http.Request request)? onFcmRequest,
  FileAccess? files,
  FakeAdbService? adb,
  ProcessRunner? processRunner,
}) async {
  final dependencies = await buildTestDependencies(
    tester,
    client: fakeGoogle(
      fcmStatus: fcmStatus,
      fcmBody: fcmBody,
      onFcmRequest: onFcmRequest,
    ),
    files: files,
    adb: adb,
    processRunner: processRunner,
  );
  await pumpApp(tester, dependencies);
  final projects = await addTestProject(tester);
  return (projects, readCubit<ComposerCubit>(tester));
}

/// Lets real async work finish, then settles animations.
Future<void> settleAsync(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  await tester.pumpAndSettle();
}
