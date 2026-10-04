import 'package:fcm_studio/core/platform/device_access.dart';
import 'package:fcm_studio/features/devices/data/webusb/usb_phone.dart';

// Desktop and `flutter test` have no browser. These are only called on the
// web, where webusb_platform_web.dart replaces them.

DeviceAccess browserDeviceAccess() => DeviceAccess.noWebUsb;

UsbPhoneSource createUsbPhoneSource() =>
    throw UnsupportedError('WebUSB needs a browser.');

String adbKeyName() => 'fcm-studio';

Future<Map<String, Object?>> generateAdbKeyJwk() async =>
    throw UnsupportedError('WebCrypto needs a browser.');
