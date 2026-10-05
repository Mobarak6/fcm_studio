/// What the page and fcm_bridge.dart agree on (bridge design §4.2). A test
/// checks these against the bridge's own constants.
abstract final class BridgeProtocol {
  static const version = 1;
  static const port = 15037;
  static final url = Uri.parse('ws://127.0.0.1:$port');

  /// What the Devices screen tells people to run.
  static const startCommand = 'dart fcm_bridge.dart';
}
