import 'package:fcm_studio/features/devices/data/bridge/bridge_channel.dart';

// Desktop and `flutter test` have no browser. These are only called on the
// web, where bridge_platform_web.dart replaces them.

Future<BridgeChannel> connectBridgeChannel(Uri url) async =>
    throw const BridgeUnreachableException();

Future<bool> bridgeBlockedByBrowser() async => false;

bool pageIsLocal() => false;

void downloadBridgeFile() =>
    throw UnsupportedError('Downloading fcm_bridge.dart needs a browser.');
