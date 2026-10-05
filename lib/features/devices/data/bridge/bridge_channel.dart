/// A WebSocket to the bridge (bridge design §4.4). The browser's is in
/// browser/bridge_platform_web.dart; tests use fakes.
abstract interface class BridgeChannel {
  /// Text frames from the bridge. Ends when the connection closes.
  Stream<String> get messages;

  void send(String message);

  Future<void> close();
}

/// Opens a channel to [url]. Throws [BridgeUnreachableException] when
/// nothing accepts the connection.
typedef BridgeConnector = Future<BridgeChannel> Function(Uri url);

/// No bridge answered (not running, refused, or blocked by the browser).
class BridgeUnreachableException implements Exception {
  const BridgeUnreachableException();

  @override
  String toString() => 'BridgeUnreachableException';
}
