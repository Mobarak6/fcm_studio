import 'package:fcm_studio/core/platform/platform_capabilities.dart';
import 'package:fcm_studio/features/composer/view/target_picker.dart';
import 'package:fcm_studio/features/devices/data/webusb/web_usb_adb_service.dart';
import 'package:fcm_studio/features/devices/domain/adb_device.dart';
import 'package:fcm_studio/features/devices/view/devices_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/app_harness.dart';
import '../../helpers/device_fixtures.dart';
import '../../helpers/fake_adb_service.dart';
import '../../helpers/fake_phone_access.dart';

const app = 'com.syldel.delivery';
const webUsb = PlatformFeatures(deviceAccess: DeviceAccess.webUsb);

void main() {
  late FakeAdbService adb;
  late FakePhoneAccess phones;

  setUp(() {
    adb = FakeAdbService()..packages[redmiSerial] = ['com.alpha', app];
    phones = FakePhoneAccess();
  });

  Future<void> openDevices(
    WidgetTester tester, {
    PlatformFeatures platform = webUsb,
  }) async {
    await pumpApp(
      tester,
      await buildTestDependencies(
        tester,
        adb: adb,
        platform: platform,
        phoneAccess: phones,
      ),
    );
    await addTestProject(tester);
    await tester.tap(find.byKey(const Key('nav-devices')));
    await tester.pumpAndSettle();
  }

  Future<void> phonesAre(WidgetTester tester, List<AdbDevice> devices) async {
    adb.tracker.add(devices);
    await settleAsync(tester);
  }

  AdbDevice phone(DeviceState state, {String? note}) => AdbDevice(
    serial: redmiSerial,
    state: state,
    rawState: state.name,
    model: '2409BRN2CA',
    note: note,
  );

  testWidgets('Connect a phone… opens the browser chooser', (tester) async {
    await openDevices(tester);
    await phonesAre(tester, const []);
    expect(find.text('No phones yet'), findsOneWidget);
    await tester.tap(find.byKey(DevicesScreen.connectPhoneKey));
    await settleAsync(tester);
    expect(phones.connects, 1);
  });

  testWidgets('a failing chooser is reported in the error banner', (
    tester,
  ) async {
    phones.connectError = StateError('boom');
    await openDevices(tester);
    await tester.tap(find.byKey(DevicesScreen.connectPhoneKey));
    await settleAsync(tester);
    expect(find.textContaining('Could not connect the phone'), findsOneWidget);
  });

  testWidgets('an offline phone says why; Retry and Forget reach the browser', (
    tester,
  ) async {
    await openDevices(tester);
    await phonesAre(tester, [
      phone(DeviceState.offline, note: WebUsbAdbService.inUseNote),
    ]);
    expect(find.text(WebUsbAdbService.inUseNote), findsOneWidget);

    await tester.tap(find.byKey(DevicesScreen.deviceMenuKey(redmiSerial)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retry'));
    await settleAsync(tester);
    expect(phones.retried, [redmiSerial]);

    await tester.tap(find.byKey(DevicesScreen.deviceMenuKey(redmiSerial)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Forget'));
    await settleAsync(tester);
    expect(phones.forgotten, [redmiSerial]);
  });

  testWidgets('a connecting phone shows Connecting…', (tester) async {
    await openDevices(tester);
    await phonesAre(tester, [
      phone(DeviceState.other, note: WebUsbAdbService.connectingNote),
    ]);
    expect(find.text(WebUsbAdbService.connectingNote), findsOneWidget);
  });

  testWidgets('a ready phone lists its apps like on desktop; no Retry', (
    tester,
  ) async {
    await openDevices(tester);
    await phonesAre(tester, [phone(DeviceState.device)]);
    expect(find.byKey(const ValueKey('package-$app')), findsOneWidget);
    await tester.tap(find.byKey(DevicesScreen.deviceMenuKey(redmiSerial)));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsNothing);
    expect(find.text('Forget'), findsOneWidget);
  });

  testWidgets('the screen says the browser keeps a key', (tester) async {
    await openDevices(tester);
    await phonesAre(tester, const []);
    expect(find.text(DevicesScreen.keyNotice), findsOneWidget);
  });

  testWidgets('without WebUSB, Devices explains what to do', (tester) async {
    await openDevices(
      tester,
      platform: const PlatformFeatures(deviceAccess: DeviceAccess.noWebUsb),
    );
    expect(find.text(DevicesScreen.noWebUsbMessage), findsOneWidget);
    expect(find.byKey(DevicesScreen.connectPhoneKey), findsNothing);
    await tester.tap(find.byKey(const Key('nav-composer')));
    await tester.pumpAndSettle();
    expect(find.byKey(TargetPicker.fromDeviceKey), findsNothing);
  });

  testWidgets('over plain http, Devices says to use https', (tester) async {
    await openDevices(
      tester,
      platform: const PlatformFeatures(deviceAccess: DeviceAccess.notSecure),
    );
    expect(find.text(DevicesScreen.notSecureMessage), findsOneWidget);
  });
}
