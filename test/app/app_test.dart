import 'package:fcm_studio/app/app_error_banner.dart';
import 'package:fcm_studio/app/app_error_cubit.dart';
import 'package:fcm_studio/core/platform/platform_capabilities.dart';
import 'package:fcm_studio/features/devices/bloc/devices_bloc.dart';
import 'package:fcm_studio/features/presets/cubit/presets_cubit.dart';
import 'package:fcm_studio/features/projects/cubit/projects_cubit.dart';
import 'package:fcm_studio/features/projects/domain/project.dart';
import 'package:fcm_studio/features/settings/cubit/adb_setup_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/app_harness.dart';
import '../helpers/fake_adb_service.dart';
import '../helpers/fake_process_runner.dart';
import '../helpers/service_account_fixture.dart';

void main() {
  testWidgets('shows the empty state and opens the add-project dialog', (
    tester,
  ) async {
    await pumpApp(tester, await buildTestDependencies(tester));

    expect(
      find.text('No projects yet. Add one with a service account key.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Add project'));
    await tester.pumpAndSettle();
    expect(find.text('Choose key file…'), findsOneWidget);
  });

  testWidgets('shows an added project and its environment', (tester) async {
    await pumpApp(tester, await buildTestDependencies(tester));
    final projects = readCubit<ProjectsCubit>(tester);

    await tester.runAsync(
      () => projects.addFromServiceAccount(
        serviceAccountJson(),
        persistKey: true,
      ),
    );
    await tester.pump();
    expect(find.text('Demo Project (demo-project)'), findsOneWidget);
    expect(find.text('DEV'), findsOneWidget);

    await tester.runAsync(
      () => projects.setEnvironment(testProjectId, ProjectEnvironment.prod),
    );
    await tester.pump();
    expect(find.text('PROD'), findsOneWidget);
  });

  testWidgets('the error banner shows a reported error until dismissed', (
    tester,
  ) async {
    await pumpApp(tester, await buildTestDependencies(tester));
    readCubit<AppErrorCubit>(
      tester,
    ).report(StateError('disk full'), context: 'Could not save the preset');
    await tester.pump();
    expect(
      find.text('Could not save the preset: Bad state: disk full'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(AppErrorBanner.dismissKey));
    await tester.pump();
    expect(find.textContaining('disk full'), findsNothing);
  });

  testWidgets('the built-in presets are loaded at startup', (tester) async {
    await pumpApp(tester, await buildTestDependencies(tester));
    expect(readCubit<PresetsCubit>(tester).state.builtIns, hasLength(4));
  });

  testWidgets('adb found at startup starts tracking phones', (tester) async {
    final adb = FakeAdbService();
    await pumpApp(tester, await buildTestDependencies(tester, adb: adb));
    expect(readCubit<AdbSetupCubit>(tester).state.adbPath, fakeAdbPath);
    expect(adb.trackers, hasLength(1));
  });

  testWidgets('without adb the app works and nothing is tracked', (
    tester,
  ) async {
    await pumpApp(tester, await buildTestDependencies(tester));
    expect(readCubit<AdbSetupCubit>(tester).state.status, AdbStatus.notFound);
    expect(readCubit<DevicesBloc>(tester).state.status, TrackerStatus.noAdb);
    expect(
      find.text('No projects yet. Add one with a service account key.'),
      findsOneWidget,
    );
  });

  testWidgets('on the web adb is never looked for', (tester) async {
    final runner = FakeProcessRunner();
    await pumpApp(
      tester,
      await buildTestDependencies(
        tester,
        processRunner: runner,
        platform: const PlatformFeatures(canRunAdb: false),
      ),
    );
    expect(readCubit<AdbSetupCubit>(tester).state.status, AdbStatus.unknown);
    expect(runner.calls, isEmpty);
  });
}
