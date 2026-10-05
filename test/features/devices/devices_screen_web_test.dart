import 'package:fcm_studio/core/platform/platform_capabilities.dart';
import 'package:fcm_studio/features/composer/view/target_picker.dart';
import 'package:fcm_studio/features/devices/data/bridge/bridge_status.dart';
import 'package:fcm_studio/features/devices/data/webusb/web_usb_adb_service.dart';
import 'package:fcm_studio/features/devices/domain/adb_device.dart';
import 'package:fcm_studio/features/devices/view/devices_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/app_harness.dart';
import '../../helpers/clipboard.dart';
import '../../helpers/device_fixtures.dart';
import '../../helpers/fake_adb_service.dart';
import '../../helpers/fake_bridge_control.dart';
import '../../helpers/fake_phone_access.dart';

const app = 'com.syldel.delivery';
const webUsb = PlatformFeatures(deviceAccess: DeviceAccess.webUsb);
const noWebUsb = PlatformFeatures(deviceAccess: DeviceAccess.noWebUsb);

void main() {
  late FakeAdbService adb;
  late FakePhoneAccess phones;
  late FakeBridgeControl bridge;

  setUp(() {
    adb = FakeAdbService()..packages[redmiSerial] = ['com.alpha', app];
    phones = FakePhoneAccess();
    bridge = FakeBridgeControl();
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
        bridge: bridge,
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

  /// The cubit hears the change in a microtask; a zero-length pump runs it
  /// before deciding whether a frame is due.
  Future<void> bridgeIs(WidgetTester tester, BridgeStatus status) async {
    bridge.emit(status);
    await tester.pump(Duration.zero);
  }

  AdbDevice phone(
    DeviceState state, {
    String? note,
    PhoneLink link = PhoneLink.usb,
  }) => AdbDevice(
    serial: redmiSerial,
    state: state,
    rawState: state.name,
    model: '2409BRN2CA',
    note: note,
    link: link,
  );

  String? linkText(WidgetTester tester) => tester
      .widget<Text>(find.byKey(DevicesScreen.deviceLinkKey(redmiSerial)))
      .data;

  testWidgets('Connect a phone (USB) opens the browser chooser', (
    tester,
  ) async {
    await openDevices(tester);
    await phonesAre(tester, const []);
    expect(find.text('No phones yet'), findsOneWidget);
    expect(find.text(DevicesScreen.emptyWebText), findsOneWidget);
    expect(find.text('Connect a phone (USB)'), findsOneWidget);
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

  testWidgets(
    'an offline USB phone says why; Retry and Forget reach the browser',
    (tester) async {
      await openDevices(tester);
      await phonesAre(tester, [
        phone(DeviceState.offline, note: WebUsbAdbService.inUseNote),
      ]);
      expect(find.text(WebUsbAdbService.inUseNote), findsOneWidget);
      expect(linkText(tester), 'USB');

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
    },
  );

  testWidgets('a connecting phone shows Connecting…', (tester) async {
    await openDevices(tester);
    await phonesAre(tester, [
      phone(DeviceState.other, note: WebUsbAdbService.connectingNote),
    ]);
    expect(find.text(WebUsbAdbService.connectingNote), findsOneWidget);
  });

  testWidgets('a ready USB phone lists its apps like on desktop; no Retry', (
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

  testWidgets('a bridge phone is labelled Bridge and has no menu', (
    tester,
  ) async {
    await openDevices(tester);
    await phonesAre(tester, [
      phone(DeviceState.device, link: PhoneLink.bridge),
    ]);
    expect(linkText(tester), 'Bridge');
    expect(find.byKey(DevicesScreen.deviceMenuKey(redmiSerial)), findsNothing);
    expect(find.byKey(const ValueKey('package-$app')), findsOneWidget);
  });

  testWidgets('the screen says the browser keeps a key', (tester) async {
    await openDevices(tester);
    await phonesAre(tester, const []);
    expect(find.text(DevicesScreen.keyNotice), findsOneWidget);
  });

  testWidgets(
    'the bridge starts with the app, and its line follows its status',
    (tester) async {
      await openDevices(tester);
      expect(bridge.starts, 1);
      expect(find.text(DevicesScreen.bridgeOffText), findsOneWidget);
      await bridgeIs(tester, const BridgeConnecting());
      expect(find.text(DevicesScreen.bridgeConnectingText), findsOneWidget);
      await bridgeIs(tester, const BridgeConnected('/sdk/adb'));
      expect(
        find.text(DevicesScreen.bridgeConnectedText('/sdk/adb')),
        findsOneWidget,
      );
      await bridgeIs(tester, const BridgeWrongVersion(2));
      expect(
        find.text(DevicesScreen.bridgeWrongVersionText(2)),
        findsOneWidget,
      );
      await bridgeIs(tester, const BridgeNoAdb('adb is missing'));
      expect(find.text('adb is missing'), findsOneWidget);
      await bridgeIs(tester, const BridgeBlocked());
      expect(find.text(DevicesScreen.bridgeBlockedText), findsOneWidget);
    },
  );

  testWidgets(
    'Connect through bridge, Try again and Disconnect reach the bridge',
    (tester) async {
      await openDevices(tester);
      await tester.tap(find.byKey(DevicesScreen.bridgeConnectKey));
      await tester.pump();
      expect(bridge.connects, 1);
      await bridgeIs(tester, const BridgeNotRunning());
      expect(find.text(DevicesScreen.bridgeNotRunningText), findsOneWidget);
      await tester.tap(find.byKey(DevicesScreen.bridgeRetryKey));
      await tester.pump();
      expect(bridge.connects, 2);
      await bridgeIs(tester, const BridgeConnected('/sdk/adb'));
      await tester.tap(find.byKey(DevicesScreen.bridgeDisconnectKey));
      await settleAsync(tester);
      expect(bridge.disconnects, 1);
    },
  );

  testWidgets('Copy and Download help start the bridge', (tester) async {
    final copied = mockClipboard(tester);
    await openDevices(tester);
    await bridgeIs(tester, const BridgeNotRunning());
    await tester.tap(find.byKey(DevicesScreen.bridgeCopyKey));
    await settleAsync(tester);
    expect(copied(), 'dart fcm_bridge.dart');
    await tester.tap(find.byKey(DevicesScreen.bridgeDownloadKey));
    await tester.pump();
    expect(bridge.downloads, 1);
  });

  testWidgets('the Bridge menu connects and downloads', (tester) async {
    await openDevices(tester);
    await tester.tap(find.byKey(DevicesScreen.bridgeMenuKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Connect through bridge').last);
    await tester.pumpAndSettle();
    expect(bridge.connects, 1);
    await tester.tap(find.byKey(DevicesScreen.bridgeMenuKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Download fcm_bridge.dart').last);
    await tester.pumpAndSettle();
    expect(bridge.downloads, 1);
  });

  testWidgets(
    'without WebUSB, USB is off and says why; the bridge still reads phones',
    (tester) async {
      await openDevices(tester, platform: noWebUsb);
      final button = tester.widget<FilledButton>(
        find.byKey(DevicesScreen.connectPhoneKey),
      );
      expect(button.onPressed, isNull);
      expect(find.text(DevicesScreen.noWebUsbMessage), findsOneWidget);
      expect(find.text(DevicesScreen.bridgeOffText), findsOneWidget);
      await phonesAre(tester, const []);
      expect(find.text(DevicesScreen.emptyBridgeText), findsOneWidget);
      await phonesAre(tester, [
        phone(DeviceState.device, link: PhoneLink.bridge),
      ]);
      expect(find.byKey(const ValueKey('package-$app')), findsOneWidget);
      await tester.tap(find.byKey(const Key('nav-composer')));
      await tester.pumpAndSettle();
      expect(find.byKey(TargetPicker.fromDeviceKey), findsOneWidget);
    },
  );

  testWidgets('over plain http, USB says to use https', (tester) async {
    await openDevices(
      tester,
      platform: const PlatformFeatures(deviceAccess: DeviceAccess.notSecure),
    );
    expect(find.text(DevicesScreen.notSecureMessage), findsOneWidget);
    expect(find.text(DevicesScreen.bridgeOffText), findsOneWidget);
  });
}
