// The browser half of the bridge (bridge design §4.4); desktop and tests
// get stand-ins.
export 'package:fcm_studio/features/devices/data/bridge/bridge_platform_stub.dart'
    if (dart.library.js_interop) 'package:fcm_studio/features/devices/data/bridge/browser/bridge_platform_web.dart';
