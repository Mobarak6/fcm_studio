import 'dart:async';
import 'dart:convert';

import 'package:fcm_studio/features/devices/data/adb_exception.dart';
import 'package:fcm_studio/features/devices/data/bridge/bridge_adb_service.dart';
import 'package:fcm_studio/features/devices/domain/adb_device.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/device_fixtures.dart';
import '../../../helpers/eventually.dart';
import '../../../helpers/fake_bridge_channel.dart';

const app = 'com.syldel.delivery';

Map<String, Object?> out(int id, String text) => {
  'type': 'stdout',
  'id': id,
  'data': base64Encode(utf8.encode(text)),
};

void main() {
  test('trackDevices decodes adb track-devices; cancel kills it', () async {
    final (client, channel) = await connectedBridgeClient();
    final lists = <List<AdbDevice>>[];
    final subscription = BridgeAdbService(
      bridge: client,
    ).trackDevices().listen(lists.add);
    expect(channel.sent.single, {'type': 'track', 'id': 1});
    channel.fromBridge(out(1, trackFrame(redmiTrackLine)));
    await eventually(() => lists.isNotEmpty);
    expect(lists.single.single.serial, redmiSerial);
    await subscription.cancel();
    expect(channel.sent.last, {'type': 'kill', 'id': 1});
  });

  test('when adb track-devices ends, the stream fails and ends', () async {
    final (client, channel) = await connectedBridgeClient();
    final errors = <Object>[];
    final done = Completer<void>();
    BridgeAdbService(
      bridge: client,
    ).trackDevices().listen((_) {}, onError: errors.add, onDone: done.complete);
    channel.fromBridge({'type': 'exit', 'id': 1, 'code': 1});
    await done.future;
    expect(
      errors.single,
      isA<AdbException>().having(
        (e) => e.message,
        'message',
        BridgeAdbService.trackStoppedMessage,
      ),
    );
  });

  test('phone commands go through the bridge', () async {
    final (client, channel) = await connectedBridgeClient();
    final packages = BridgeAdbService(bridge: client).listPackages(redmiSerial);
    await eventually(() => channel.runs.isNotEmpty);
    expect(channel.runs.single['text'], 'pm list packages -3');
    channel
      ..fromBridge(out(1, 'package:$app\n'))
      ..fromBridge({'type': 'exit', 'id': 1, 'code': 0});
    expect(await packages, [app]);
  });
}
