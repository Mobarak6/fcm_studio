import 'package:fcm_studio/app/navigation_cubit.dart';
import 'package:fcm_studio/features/composer/domain/target.dart';
import 'package:fcm_studio/features/composer/view/target_picker.dart';
import 'package:fcm_studio/features/devices/bloc/devices_bloc.dart';
import 'package:fcm_studio/features/devices/cubit/token_reader_cubit.dart';
import 'package:fcm_studio/features/devices/domain/adb_device.dart';
import 'package:fcm_studio/features/devices/domain/device_token.dart';
import 'package:fcm_studio/features/devices/domain/token_read_results.dart';
import 'package:fcm_studio/features/devices/view/devices_screen.dart';
import 'package:fcm_studio/features/devices/view/token_read_view.dart';
import 'package:fcm_studio/features/targets/cubit/targets_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/app_harness.dart';
import '../../helpers/device_fixtures.dart';
import '../../helpers/fake_adb_service.dart';
import '../../helpers/service_account_fixture.dart';

const app = 'com.syldel.delivery';
const redmi = AdbDevice(
  serial: redmiSerial,
  state: DeviceState.device,
  rawState: 'device',
  model: '2409BRN2CA',
);

void main() {
  late FakeAdbService adb;

  setUp(() {
    adb = FakeAdbService()
      ..details[redmiSerial] = const DeviceDetails(
        name: 'Redmi 14C',
        brand: 'Redmi',
        androidVersion: '16',
      )
      ..packages[redmiSerial] = ['com.alpha', app];
  });

  Future<void> openDevices(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('nav-devices')));
    await tester.pumpAndSettle();
  }

  Future<void> plugIn(WidgetTester tester, List<AdbDevice> devices) async {
    adb.tracker.add(devices);
    await settleAsync(tester);
  }

  testWidgets('without adb, Devices explains and links to Settings', (
    tester,
  ) async {
    await pumpAppWithProject(tester);
    await openDevices(tester);
    expect(find.textContaining('adb was not found'), findsOneWidget);
    await tester.tap(find.byKey(DevicesScreen.openSettingsKey));
    await tester.pumpAndSettle();
    expect(readCubit<NavigationCubit>(tester).state, AppSection.settings);
  });

  testWidgets("an unauthorized phone shows the hint and can't be opened", (
    tester,
  ) async {
    await pumpAppWithProject(tester, adb: adb);
    await openDevices(tester);
    await plugIn(tester, const [
      AdbDevice(
        serial: 'R58M123ABC',
        state: DeviceState.unauthorized,
        rawState: 'unauthorized',
      ),
    ]);
    expect(
      find.text('Accept the USB debugging prompt on the phone'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<ListTile>(find.byKey(const ValueKey('device-R58M123ABC')))
          .enabled,
      isFalse,
    );
    expect(adb.calls.where((c) => c.startsWith('packages')), isEmpty);
  });

  testWidgets(
    'picking an app makes its token the target, saves it, and returns to the composer',
    (tester) async {
      adb.runAs[app] = [
        RunAsTokens([
          FoundToken(token: fakeDeviceToken, senderId: testProjectNumber),
        ]),
      ];
      final (_, composer) = await pumpAppWithProject(tester, adb: adb);
      await openDevices(tester);
      await plugIn(tester, const [redmi]);
      expect(find.text('Redmi 14C'), findsWidgets);

      await tester.tap(find.byKey(const ValueKey('package-$app')));
      await settleAsync(tester);

      expect(composer.state.targetKind, TargetKind.token);
      expect(composer.state.targetValue, fakeDeviceToken);
      expect(readCubit<NavigationCubit>(tester).state, AppSection.composer);
      final saved = readCubit<TargetsCubit>(tester).state.targets.single;
      expect(saved.label, 'Redmi 14C · $app (debug)');
      expect(saved.projectId, testProjectId);
      expect(saved.senderId, testProjectNumber);
      expect(
        find.text('Using the token of Redmi 14C · $app (debug).'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    "several projects in the file: the selected project's is preselected",
    (tester) async {
      adb.runAs[app] = [
        RunAsTokens([
          FoundToken(token: fakeDeviceToken, senderId: testProjectNumber),
          FoundToken(token: otherDeviceToken, senderId: '999000999000'),
        ]),
      ];
      final (_, composer) = await pumpAppWithProject(tester, adb: adb);
      await openDevices(tester);
      await plugIn(tester, const [redmi]);
      await tester.tap(find.byKey(const ValueKey('package-$app')));
      await settleAsync(tester);

      expect(
        find.descendant(
          of: find.byKey(const ValueKey('sender-$testProjectNumber')),
          matching: find.byIcon(Icons.radio_button_checked),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(TokenReadView.useTokenKey));
      await settleAsync(tester);
      expect(composer.state.targetValue, fakeDeviceToken);
    },
  );

  testWidgets('a release build: confirm, restart the app and read its log', (
    tester,
  ) async {
    adb.runAs[app] = [const RunAsReleaseBuild()];
    adb.logcat[app] = [
      const LogcatRestartingApp(),
      const LogcatWaitingForApp(),
      const LogcatWatching(4242),
      LogcatFound(fakeDeviceToken),
    ];
    final (_, composer) = await pumpAppWithProject(tester, adb: adb);
    await openDevices(tester);
    await plugIn(tester, const [redmi]);
    await tester.tap(find.byKey(const ValueKey('package-$app')));
    await settleAsync(tester);
    expect(find.textContaining('is a release build'), findsOneWidget);
    expect(adb.calls.where((c) => c.startsWith('logcat')), isEmpty);

    await tester.tap(find.byKey(TokenReadView.readLogsKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(TokenReadView.confirmLogsKey));
    await settleAsync(tester);

    expect(composer.state.targetValue, fakeDeviceToken);
    expect(
      readCubit<TargetsCubit>(tester).state.targets.single.label,
      'Redmi 14C · $app (release)',
    );
  });

  testWidgets('an app that was never opened offers Launch app and Retry', (
    tester,
  ) async {
    adb.runAs[app] = [
      const RunAsNoTokenYet(),
      RunAsTokens([
        FoundToken(token: fakeDeviceToken, senderId: testProjectNumber),
      ]),
    ];
    final (_, composer) = await pumpAppWithProject(tester, adb: adb);
    await openDevices(tester);
    await plugIn(tester, const [redmi]);
    await tester.tap(find.byKey(const ValueKey('package-$app')));
    await settleAsync(tester);
    expect(find.text('Open the app once so it gets a token.'), findsOneWidget);

    await tester.tap(find.byKey(TokenReadView.launchKey));
    await settleAsync(tester);
    expect(adb.calls, contains('launch $redmiSerial $app'));
    await tester.tap(find.byKey(TokenReadView.retryKey));
    await settleAsync(tester);
    expect(composer.state.targetValue, fakeDeviceToken);
  });

  testWidgets('From device… opens the Devices screen', (tester) async {
    await pumpAppWithProject(tester, adb: adb);
    await tester.tap(find.byKey(TargetPicker.fromDeviceKey));
    await tester.pumpAndSettle();
    expect(readCubit<NavigationCubit>(tester).state, AppSection.devices);
  });

  testWidgets('when adb stops, the screen says it will try again', (
    tester,
  ) async {
    await pumpAppWithProject(tester, adb: adb);
    await openDevices(tester);
    await adb.tracker.close();
    await settleAsync(tester);
    expect(find.byKey(const Key('devices-restarting')), findsOneWidget);
    // Let the 1-second restart timer fire, so no timer is left pending.
    await tester.pump(const Duration(seconds: 2));
    await settleAsync(tester);
    expect(adb.trackers, hasLength(2));
  });

  testWidgets('a new adb path reopens the reader on the same phone', (
    tester,
  ) async {
    await pumpAppWithProject(tester, adb: adb);
    await openDevices(tester);
    await plugIn(tester, const [redmi]);
    expect(readCubit<TokenReaderCubit>(tester).adbPath, fakeAdbPath);
    final before = adb.calls.where((c) => c.startsWith('packages')).length;

    readCubit<DevicesBloc>(tester).add(const DevicesAdbChanged('/other/adb'));
    await settleAsync(tester);
    adb.trackers.last.add(const [redmi]);
    await settleAsync(tester);

    expect(readCubit<TokenReaderCubit>(tester).adbPath, '/other/adb');
    expect(
      adb.calls.where((c) => c.startsWith('packages')).length,
      greaterThan(before),
    );
  });

  testWidgets(
    'confirming the log read does nothing if the read moved on meanwhile',
    (tester) async {
      adb.runAs[app] = [const RunAsReleaseBuild()];
      adb.logcat[app] = [LogcatFound(fakeDeviceToken)];
      final (_, composer) = await pumpAppWithProject(tester, adb: adb);
      await openDevices(tester);
      await plugIn(tester, const [redmi]);
      await tester.tap(find.byKey(const ValueKey('package-$app')));
      await settleAsync(tester);
      await tester.tap(find.byKey(TokenReadView.readLogsKey));
      await tester.pumpAndSettle();

      readCubit<TokenReaderCubit>(tester).dismiss();
      await tester.tap(find.byKey(TokenReadView.confirmLogsKey));
      await settleAsync(tester);

      expect(adb.calls.where((c) => c.startsWith('logcat')), isEmpty);
      expect(composer.state.targetValue, isNot(fakeDeviceToken));
    },
  );
}
