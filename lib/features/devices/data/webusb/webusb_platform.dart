// The browser half of WebUSB (design §4.1); desktop and tests get stand-ins.
export 'package:fcm_studio/features/devices/data/webusb/webusb_platform_stub.dart'
    if (dart.library.js_interop) 'package:fcm_studio/features/devices/data/webusb/browser/webusb_platform_web.dart';
