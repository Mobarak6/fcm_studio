import 'dart:async';

import 'package:fcm_studio/features/devices/data/adb_service.dart';
import 'package:fcm_studio/features/devices/data/bridge/bridge_client.dart';
import 'package:fcm_studio/features/devices/data/bridge/bridge_status.dart';
import 'package:fcm_studio/features/devices/domain/adb_device.dart';
import 'package:fcm_studio/features/devices/domain/token_read_results.dart';

/// The web's phones (bridge design §4.5): WebUSB's and the bridge's in one
/// list, each labelled. The bridge wins when both list a serial, so the
/// "in use" WebUSB row never shows while the bridge runs.
class WebPhones implements AdbService {
  WebPhones({
    required this._bridge,
    required this._bridgeService,
    this._usb,
    this._backoff = BridgeClient.defaultBackoff,
  });

  /// Stands in for an adb path, so `DevicesBloc` and `TokenReaderCubit`
  /// work unchanged.
  static const source = 'web';

  static const goneMessage = 'That phone is no longer connected.';

  final BridgeControl _bridge;
  final AdbService _bridgeService;
  final AdbService? _usb;
  final Duration Function(int attempt) _backoff;
  List<AdbDevice> _usbPhones = const [];
  List<AdbDevice> _bridgePhones = const [];

  /// The current phones at once, then every change. A failing bridge never
  /// ends it; a failing WebUSB side does (DevicesBloc restarts it).
  @override
  Stream<List<AdbDevice>> trackDevices() {
    late final StreamController<List<AdbDevice>> controller;
    StreamSubscription<List<AdbDevice>>? usb;
    StreamSubscription<BridgeStatus>? statuses;
    StreamSubscription<List<AdbDevice>>? bridge;
    Timer? retry;
    var attempt = 0;
    var cancelled = false;

    void emit() {
      if (!cancelled) {
        controller.add(_merged());
      }
    }

    void clearBridge() {
      if (_bridgePhones.isNotEmpty) {
        _bridgePhones = const [];
        emit();
      }
    }

    void trackBridge() {
      bridge = _bridgeService.trackDevices().listen(
        (devices) {
          attempt = 0;
          _bridgePhones = devices;
          emit();
        },
        onError: (Object _) {},
        onDone: () {
          bridge = null;
          clearBridge();
          if (!cancelled && _bridge.status is BridgeConnected) {
            retry = Timer(_backoff(++attempt), () {
              retry = null;
              if (!cancelled &&
                  bridge == null &&
                  _bridge.status is BridgeConnected) {
                trackBridge();
              }
            });
          }
        },
      );
    }

    void stopBridge() {
      retry?.cancel();
      retry = null;
      final current = bridge;
      bridge = null;
      unawaited(current?.cancel());
      clearBridge();
    }

    void onStatus(BridgeStatus status) {
      if (status is BridgeConnected) {
        if (bridge == null && retry == null) {
          trackBridge();
        }
      } else {
        stopBridge();
      }
    }

    controller = StreamController<List<AdbDevice>>(
      onListen: () {
        emit();
        usb = _usb?.trackDevices().listen((devices) {
          _usbPhones = devices;
          emit();
        }, onError: controller.addError);
        statuses = _bridge.statuses.listen(onStatus);
        onStatus(_bridge.status);
      },
      onCancel: () async {
        cancelled = true;
        retry?.cancel();
        final current = bridge;
        bridge = null;
        unawaited(current?.cancel());
        await statuses?.cancel();
        await usb?.cancel();
      },
    );
    return controller.stream;
  }

  List<AdbDevice> _merged() {
    final bridgeSerials = {for (final device in _bridgePhones) device.serial};
    return [
      for (final device in _bridgePhones) device.withLink(PhoneLink.bridge),
      for (final device in _usbPhones)
        if (!bridgeSerials.contains(device.serial))
          device.withLink(PhoneLink.usb),
    ];
  }

  /// The bridge if its latest list has [serial], else WebUSB if its has.
  AdbService _owner(String serial) {
    if (_bridgePhones.any((device) => device.serial == serial)) {
      return _bridgeService;
    }
    final usb = _usb;
    if (usb != null && _usbPhones.any((device) => device.serial == serial)) {
      return usb;
    }
    throw const AdbException(goneMessage);
  }

  @override
  Future<DeviceDetails> deviceDetails(String serial) =>
      Future.sync(() => _owner(serial).deviceDetails(serial));

  @override
  Future<List<String>> listPackages(String serial) =>
      Future.sync(() => _owner(serial).listPackages(serial));

  @override
  Future<RunAsResult> readTokenWithRunAs(String serial, String package) {
    final AdbService owner;
    try {
      owner = _owner(serial);
    } on AdbException catch (e) {
      return Future.value(RunAsFailed(e.message));
    }
    return owner.readTokenWithRunAs(serial, package);
  }

  @override
  Future<void> launchApp(String serial, String package) =>
      Future.sync(() => _owner(serial).launchApp(serial, package));

  @override
  Stream<LogcatProgress> readTokenFromLogcat(String serial, String package) {
    try {
      return _owner(serial).readTokenFromLogcat(serial, package);
    } on AdbException catch (e) {
      return Stream.value(LogcatFailed(e.message));
    }
  }
}
