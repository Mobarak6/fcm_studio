import 'dart:async';

import 'package:fcm_studio/features/devices/data/adb_commands.dart';
import 'package:fcm_studio/features/devices/data/adb_service.dart';
import 'package:fcm_studio/features/devices/data/bridge/bridge_client.dart';
import 'package:fcm_studio/features/devices/data/bridge/bridge_device_shell.dart';
import 'package:fcm_studio/features/devices/data/parsers/track_devices_decoder.dart';
import 'package:fcm_studio/features/devices/domain/adb_device.dart';
import 'package:fcm_studio/features/devices/domain/token_read_results.dart';

/// The bridge's phones as an [AdbService] (bridge design §4.4): adb's
/// device list, and the same phone commands as desktop.
class BridgeAdbService implements AdbService {
  BridgeAdbService({required this._bridge});

  static const trackStoppedMessage =
      '`adb track-devices -l` stopped (through the bridge)';

  final BridgeControl _bridge;

  late final AdbCommands _commands = AdbCommands(
    shell: BridgeDeviceShell(bridge: _bridge),
  );

  @override
  Stream<List<AdbDevice>> trackDevices() {
    late final StreamController<List<AdbDevice>> controller;
    BridgeCall? call;
    StreamSubscription<List<AdbDevice>>? subscription;
    var failed = false;

    controller = StreamController<List<AdbDevice>>(
      onListen: () {
        try {
          final started = _bridge.request(const {'type': 'track'});
          call = started;
          subscription = started.output
              .where((chunk) => !chunk.isError)
              .map((chunk) => chunk.bytes)
              .transform(const TrackDevicesDecoder())
              .listen(
                controller.add,
                onError: (Object error, StackTrace stackTrace) {
                  failed = true;
                  controller.addError(error, stackTrace);
                },
                onDone: () {
                  if (!failed) {
                    controller.addError(
                      const AdbException(trackStoppedMessage),
                    );
                  }
                  unawaited(controller.close());
                },
              );
        } on AdbException catch (e, stackTrace) {
          controller.addError(e, stackTrace);
          unawaited(controller.close());
        }
      },
      // Like ProcessAdbService: the decoder only ends once the process does,
      // so kill first and don't wait for the cancel. The cancel ends with the
      // call's error if the bridge stops first; nobody is listening by then.
      onCancel: () {
        call?.kill();
        subscription?.cancel().ignore();
      },
    );
    return controller.stream;
  }

  @override
  Future<DeviceDetails> deviceDetails(String serial) =>
      _commands.deviceDetails(serial);

  @override
  Future<List<String>> listPackages(String serial) =>
      _commands.listPackages(serial);

  @override
  Future<RunAsResult> readTokenWithRunAs(String serial, String package) =>
      _commands.readTokenWithRunAs(serial, package);

  @override
  Future<void> launchApp(String serial, String package) =>
      _commands.launchApp(serial, package);

  @override
  Stream<LogcatProgress> readTokenFromLogcat(String serial, String package) =>
      _commands.readTokenFromLogcat(serial, package);
}
