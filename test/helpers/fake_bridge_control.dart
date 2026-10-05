import 'dart:async';

import 'package:fcm_studio/features/devices/data/adb_exception.dart';
import 'package:fcm_studio/features/devices/data/bridge/bridge_client.dart';
import 'package:fcm_studio/features/devices/data/bridge/bridge_status.dart';

/// A bridge whose status the test sets. Records what the app asked.
class FakeBridgeControl implements BridgeControl {
  FakeBridgeControl([this._status = const BridgeOff()]);

  BridgeStatus _status;
  final StreamController<BridgeStatus> _statuses =
      StreamController<BridgeStatus>.broadcast(sync: true);
  int starts = 0;
  int connects = 0;
  int disconnects = 0;
  int downloads = 0;

  /// Moves the bridge to [status], as the real client would.
  void emit(BridgeStatus status) {
    _status = status;
    _statuses.add(status);
  }

  @override
  BridgeStatus get status => _status;

  @override
  Stream<BridgeStatus> get statuses => _statuses.stream;

  @override
  Future<void> start() async {
    starts++;
  }

  @override
  void connect() => connects++;

  @override
  Future<void> disconnect() async {
    disconnects++;
  }

  @override
  void download() => downloads++;

  @override
  BridgeCall request(Map<String, Object?> message) =>
      throw const AdbException(BridgeClient.notConnectedMessage);
}
