import 'dart:async';
import 'dart:js_interop';

import 'package:fcm_studio/features/devices/data/bridge/bridge_channel.dart';
import 'package:web/web.dart' as web;

/// Opens the browser's WebSocket to the bridge (bridge design §4.4).
Future<BridgeChannel> connectBridgeChannel(Uri url) =>
    WebBridgeChannel.connect(url);

/// Whether the browser denied this site access to apps on this computer
/// (Chrome's Local Network Access). Unknown counts as no.
Future<bool> bridgeBlockedByBrowser() async {
  for (final name in const ['loopback-network', 'local-network-access']) {
    try {
      final status = await web.window.navigator.permissions
          .query(_PermissionDescriptor(name: name))
          .toDart;
      if (status.state == 'denied') {
        return true;
      }
    } on Object {
      // This browser doesn't know that permission.
    }
  }
  return false;
}

/// A page served from this computer connects to the bridge by itself.
bool pageIsLocal() {
  final host = web.window.location.hostname;
  return host == 'localhost' || host == '127.0.0.1';
}

/// Saves fcm_bridge.dart, which every web build serves next to index.html.
void downloadBridgeFile() {
  web.HTMLAnchorElement()
    ..href = 'fcm_bridge.dart'
    ..download = 'fcm_bridge.dart'
    ..click();
}

/// The browser's WebSocket as a [BridgeChannel].
class WebBridgeChannel implements BridgeChannel {
  WebBridgeChannel._(this._socket);

  final web.WebSocket _socket;
  final StreamController<String> _messages = StreamController<String>();

  /// Completes once the socket opens; fails if it closes first.
  static Future<BridgeChannel> connect(Uri url) {
    final web.WebSocket socket;
    try {
      socket = web.WebSocket(url.toString());
    } on Object {
      return Future.error(const BridgeUnreachableException());
    }
    final channel = WebBridgeChannel._(socket);
    final opened = Completer<BridgeChannel>();
    socket
      ..onopen = ((web.Event _) {
        if (!opened.isCompleted) {
          opened.complete(channel);
        }
      }).toJS
      ..onmessage = ((web.MessageEvent event) {
        final data = event.data;
        if (data.isA<JSString>()) {
          channel._messages.add((data as JSString).toDart);
        }
      }).toJS
      ..onclose = ((web.CloseEvent _) {
        if (!opened.isCompleted) {
          opened.completeError(const BridgeUnreachableException());
        }
        unawaited(channel._messages.close());
      }).toJS;
    return opened.future;
  }

  @override
  Stream<String> get messages => _messages.stream;

  @override
  void send(String message) => _socket.send(message.toJS);

  @override
  Future<void> close() async => _socket.close();
}

extension type _PermissionDescriptor._(JSObject _) implements JSObject {
  external factory _PermissionDescriptor({required String name});
}
