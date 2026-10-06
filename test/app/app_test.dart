import 'dart:ui' as ui;

import 'package:fcm_studio/app/app_error_banner.dart';
import 'package:fcm_studio/app/app_error_cubit.dart';
import 'package:fcm_studio/app/shell.dart';
import 'package:fcm_studio/core/platform/platform_capabilities.dart';
import 'package:fcm_studio/features/composer/view/target_picker.dart';
import 'package:fcm_studio/features/devices/bloc/devices_bloc.dart';
import 'package:fcm_studio/features/devices/data/web_phones.dart';
import 'package:fcm_studio/features/presets/cubit/presets_cubit.dart';
import 'package:fcm_studio/features/projects/cubit/projects_cubit.dart';
import 'package:fcm_studio/features/projects/domain/project.dart';
import 'package:fcm_studio/features/settings/cubit/adb_setup_cubit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/app_harness.dart';
import '../helpers/fake_adb_service.dart';
import '../helpers/fake_bridge_control.dart';
import '../helpers/fake_phone_access.dart';
import '../helpers/fake_process_runner.dart';
import '../helpers/service_account_fixture.dart';

void main() {
  testWidgets('shows the empty state and opens the add-project dialog', (
    tester,
  ) async {
    await pumpApp(tester, await buildTestDependencies(tester));

    expect(
      find.text(
        'No projects yet. Add one with a service account key or Google sign-in.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Add project'));
    await tester.pumpAndSettle();
    expect(find.text('Choose key file…'), findsOneWidget);
  });

  testWidgets('the rail shows the FCM Studio logo', (tester) async {
    await pumpApp(tester, await buildTestDependencies(tester));
    final logo = tester.widget<Image>(find.byKey(AppShell.logoKey));
    expect(logo.image, const AssetImage(AppShell.logoAsset));
    expect(find.byTooltip('FCM Studio'), findsOneWidget);
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
    expect(readCubit<PresetsCubit>(tester).state.builtIns, hasLength(55));
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
      find.text(
        'No projects yet. Add one with a service account key or Google sign-in.',
      ),
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
        platform: const PlatformFeatures(deviceAccess: DeviceAccess.noWebUsb),
      ),
    );
    expect(readCubit<AdbSetupCubit>(tester).state.status, AdbStatus.unknown);
    expect(runner.calls, isEmpty);
  });

  testWidgets('quitting the app stops adb track-devices', (tester) async {
    final adb = FakeAdbService();
    await pumpApp(tester, await buildTestDependencies(tester, adb: adb));
    expect(adb.trackers.last.hasListener, isTrue);

    final response = await tester.runAsync(tester.binding.handleRequestAppExit);

    expect(response, ui.AppExitResponse.exit);
    expect(adb.trackers.last.hasListener, isFalse);
  });

  testWidgets(
    'without WebUSB, Devices and From device stay: the bridge reads phones',
    (tester) async {
      await pumpApp(
        tester,
        await buildTestDependencies(
          tester,
          platform: const PlatformFeatures(deviceAccess: DeviceAccess.noWebUsb),
          bridge: FakeBridgeControl(),
        ),
      );
      await addTestProject(tester);
      expect(find.text('Target'), findsOneWidget);
      expect(find.byKey(const Key('nav-devices')), findsOneWidget);
      expect(find.byKey(const Key('nav-settings')), findsNothing);
      expect(find.byKey(TargetPicker.fromDeviceKey), findsOneWidget);
    },
  );

  testWidgets(
    'with WebUSB, phones are tracked at once and Settings is hidden',
    (tester) async {
      final adb = FakeAdbService();
      await pumpApp(
        tester,
        await buildTestDependencies(
          tester,
          adb: adb,
          platform: const PlatformFeatures(deviceAccess: DeviceAccess.webUsb),
          phoneAccess: FakePhoneAccess(),
        ),
      );
      expect(adb.trackers, hasLength(1));
      expect(readCubit<DevicesBloc>(tester).state.adbPath, WebPhones.source);
      expect(readCubit<AdbSetupCubit>(tester).state.status, AdbStatus.unknown);
      expect(find.byKey(const Key('nav-devices')), findsOneWidget);
      expect(find.byKey(const Key('nav-settings')), findsNothing);
      await addTestProject(tester);
      expect(find.byKey(TargetPicker.fromDeviceKey), findsOneWidget);
    },
  );

  testWidgets(
    'on the web the bridge starts with the app and phones are tracked',
    (tester) async {
      final bridge = FakeBridgeControl();
      await pumpApp(
        tester,
        await buildTestDependencies(
          tester,
          adb: FakeAdbService(),
          platform: const PlatformFeatures(deviceAccess: DeviceAccess.noWebUsb),
          bridge: bridge,
        ),
      );
      expect(bridge.starts, 1);
      expect(readCubit<DevicesBloc>(tester).state.adbPath, WebPhones.source);
    },
  );

  testWidgets('on the web WebPhones serves the phones; desktop has no bridge', (
    tester,
  ) async {
    final bridge = FakeBridgeControl();
    final web = await buildTestDependencies(
      tester,
      platform: const PlatformFeatures(deviceAccess: DeviceAccess.noWebUsb),
      bridge: bridge,
    );
    expect(web.adbServiceFor(WebPhones.source), isA<WebPhones>());
    expect(web.bridge, same(bridge));
    final desktop = await buildTestDependencies(tester);
    expect(desktop.bridge, isNull);
  });
}
