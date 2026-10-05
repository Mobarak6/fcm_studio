import 'package:fcm_studio/features/devices/data/adb_exception.dart';
import 'package:fcm_studio/features/devices/data/bridge/bridge_status.dart';
import 'package:fcm_studio/features/devices/data/web_phones.dart';
import 'package:fcm_studio/features/devices/domain/adb_device.dart';
import 'package:fcm_studio/features/devices/domain/token_read_results.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/eventually.dart';
import '../../helpers/fake_adb_service.dart';
import '../../helpers/fake_bridge_control.dart';

const app = 'com.syldel.delivery';
const connected = BridgeConnected('/sdk/adb');

AdbDevice phone(String serial) =>
    AdbDevice(serial: serial, state: DeviceState.device, rawState: 'device');

void main() {
  late FakeAdbService usb;
  late FakeAdbService viaBridge;
  late FakeBridgeControl bridge;

  setUp(() {
    usb = FakeAdbService();
    viaBridge = FakeAdbService();
    bridge = FakeBridgeControl();
  });

  WebPhones phones({bool withUsb = true}) => WebPhones(
    bridge: bridge,
    bridgeService: viaBridge,
    usb: withUsb ? usb : null,
    backoff: (_) => const Duration(milliseconds: 10),
  );

  Future<List<List<AdbDevice>>> track(
    WebPhones web, {
    void Function()? onDone,
  }) async {
    final lists = <List<AdbDevice>>[];
    final subscription = web.trackDevices().listen(
      lists.add,
      onError: (Object _) {},
      onDone: onDone,
    );
    addTearDown(subscription.cancel);
    await pumpEventQueue();
    return lists;
  }

  test(
    'USB phones are listed at once, labelled USB; the bridge waits',
    () async {
      final lists = await track(phones());
      expect(lists.last, isEmpty);
      expect(viaBridge.trackers, isEmpty);
      usb.tracker.add([phone('USB1')]);
      await pumpEventQueue();
      expect(lists.last, [phone('USB1').withLink(PhoneLink.usb)]);
    },
  );

  test(
    'bridge phones join once it connects; the bridge wins a shared serial',
    () async {
      final lists = await track(phones());
      usb.tracker.add([phone('SAME'), phone('USB1')]);
      bridge.emit(connected);
      await pumpEventQueue();
      expect(viaBridge.trackers, hasLength(1));
      viaBridge.tracker.add([phone('SAME')]);
      await pumpEventQueue();
      expect(lists.last, [
        phone('SAME').withLink(PhoneLink.bridge),
        phone('USB1').withLink(PhoneLink.usb),
      ]);
    },
  );

  test('when the bridge goes away its phones go, and tracking stops', () async {
    final lists = await track(phones());
    bridge.emit(connected);
    await pumpEventQueue();
    viaBridge.tracker.add([phone('BR1')]);
    await pumpEventQueue();
    expect(lists.last, [phone('BR1').withLink(PhoneLink.bridge)]);
    bridge.emit(const BridgeNotRunning());
    await pumpEventQueue();
    expect(lists.last, isEmpty);
    expect(viaBridge.tracker.hasListener, isFalse);
  });

  test('a bridge tracker that ends is started again while connected', () async {
    var ended = false;
    final lists = await track(phones(), onDone: () => ended = true);
    bridge.emit(connected);
    await pumpEventQueue();
    viaBridge.tracker.add([phone('BR1')]);
    await pumpEventQueue();
    viaBridge.tracker.addError(const AdbException('adb server restarted'));
    await viaBridge.tracker.close();
    await pumpEventQueue();
    expect(lists.last, isEmpty);
    await eventually(() => viaBridge.trackers.length == 2);
    viaBridge.tracker.add([phone('BR1')]);
    await pumpEventQueue();
    expect(lists.last, [phone('BR1').withLink(PhoneLink.bridge)]);
    usb.tracker.add([phone('USB1')]);
    await pumpEventQueue();
    expect(lists.last, hasLength(2));
    expect(ended, isFalse);
  });

  test('calls go to the side that lists the phone', () async {
    final web = phones();
    await track(web);
    usb.tracker.add([phone('USB1')]);
    bridge.emit(connected);
    await pumpEventQueue();
    viaBridge.tracker.add([phone('BR1')]);
    await pumpEventQueue();

    await web.deviceDetails('USB1');
    await web.listPackages('BR1');
    await web.readTokenWithRunAs('BR1', app);
    await web.launchApp('USB1', app);
    await web.readTokenFromLogcat('BR1', app).drain<void>();
    expect(usb.calls, containsAll(['details USB1', 'launch USB1 $app']));
    expect(
      viaBridge.calls,
      containsAll(['packages BR1', 'run-as BR1 $app', 'logcat BR1 $app']),
    );
  });

  test('a phone that is gone gets a clear message', () async {
    final web = phones();
    await expectLater(
      web.deviceDetails('GONE'),
      throwsA(
        isA<AdbException>().having(
          (e) => e.message,
          'message',
          WebPhones.goneMessage,
        ),
      ),
    );
    expect(
      await web.readTokenWithRunAs('GONE', app),
      const RunAsFailed(WebPhones.goneMessage),
    );
    expect(await web.readTokenFromLogcat('GONE', app).toList(), [
      const LogcatFailed(WebPhones.goneMessage),
    ]);
  });

  test('without WebUSB, only the bridge phones are listed', () async {
    final lists = await track(phones(withUsb: false));
    bridge.emit(connected);
    await pumpEventQueue();
    viaBridge.tracker.add([phone('BR1')]);
    await pumpEventQueue();
    expect(lists.last, [phone('BR1').withLink(PhoneLink.bridge)]);
    expect(usb.trackers, isEmpty);
  });

  test('cancelling stops both sides', () async {
    final subscription = phones().trackDevices().listen((_) {});
    bridge.emit(connected);
    await pumpEventQueue();
    await subscription.cancel();
    expect(usb.tracker.hasListener, isFalse);
    expect(viaBridge.tracker.hasListener, isFalse);
  });
}
