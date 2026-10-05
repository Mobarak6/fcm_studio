import 'dart:async';
import 'dart:convert';

import 'package:fcm_studio/features/devices/data/bridge/bridge_channel.dart';
import 'package:fcm_studio/features/devices/data/bridge/bridge_client.dart';
import 'package:fcm_studio/features/devices/data/bridge/bridge_status.dart';
import 'package:flutter_test/flutter_test.dart';

import 'eventually.dart';

/// The bridge's side of one connection, played by the test.
class FakeBridgeChannel implements BridgeChannel {
  final StreamController<String> _fromBridge = StreamController<String>();
  final List<Map<String, Object?>> sent = [];
  bool closed = false;

  void fromBridge(Map<String, Object?> message) =>
      _fromBridge.add(jsonEncode(message));

  void fromBridgeText(String text) => _fromBridge.add(text);

  void hello({int protocol = 1, String? adb = '/sdk/adb', String? problem}) =>
      fromBridge({
        'type': 'hello',
        'protocol': protocol,
        'adb': adb,
        'problem': ?problem,
      });

  /// The bridge going away.
  Future<void> drop() => _fromBridge.close();

  /// Every `run` request the page sent, in order.
  Iterable<Map<String, Object?>> get runs =>
      sent.where((message) => message['type'] == 'run');

  @override
  Stream<String> get messages => _fromBridge.stream;

  @override
  void send(String message) =>
      sent.add(jsonDecode(message) as Map<String, Object?>);

  @override
  Future<void> close() async {
    closed = true;
    if (!_fromBridge.isClosed) {
      unawaited(_fromBridge.close());
    }
  }
}

/// Connects to new [FakeBridgeChannel]s, or fails while [running] is false.
class FakeBridgeConnector {
  final List<FakeBridgeChannel> channels = [];
  bool running = true;
  int attempts = 0;

  Future<BridgeChannel> connect(Uri url) async {
    attempts++;
    if (!running) {
      throw const BridgeUnreachableException();
    }
    final channel = FakeBridgeChannel();
    channels.add(channel);
    return channel;
  }
}

/// A [BridgeClient] already connected to a [FakeBridgeChannel].
Future<(BridgeClient, FakeBridgeChannel)> connectedBridgeClient() async {
  final connector = FakeBridgeConnector();
  final client = BridgeClient(
    connector: connector.connect,
    readAutoConnect: () async => false,
    writeAutoConnect: (_) async {},
  )..connect();
  addTearDown(client.dispose);
  await eventually(() => connector.channels.isNotEmpty);
  final channel = connector.channels.single..hello();
  await eventually(() => client.status is BridgeConnected);
  return (client, channel);
}
