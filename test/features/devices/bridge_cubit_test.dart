import 'package:fcm_studio/features/devices/cubit/bridge_cubit.dart';
import 'package:fcm_studio/features/devices/data/bridge/bridge_status.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_bridge_control.dart';

void main() {
  test('follows the bridge and forwards the buttons', () async {
    final bridge = FakeBridgeControl(const BridgeNotRunning());
    final cubit = BridgeCubit(control: bridge);
    addTearDown(cubit.close);
    expect(cubit.state, const BridgeNotRunning());
    bridge.emit(const BridgeConnected('/sdk/adb'));
    expect(cubit.state, const BridgeConnected('/sdk/adb'));

    await cubit.start();
    cubit.connect();
    await cubit.disconnect();
    cubit.download();
    expect(
      [bridge.starts, bridge.connects, bridge.disconnects, bridge.downloads],
      [1, 1, 1, 1],
    );
  });
}
