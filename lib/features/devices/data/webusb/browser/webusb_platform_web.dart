import 'dart:js_interop';
import 'dart:typed_data';

import 'package:fcm_studio/core/platform/device_access.dart';
import 'package:fcm_studio/features/devices/data/webusb/browser/usb_interop.dart';
import 'package:fcm_studio/features/devices/data/webusb/browser/web_usb_phone.dart';
import 'package:fcm_studio/features/devices/data/webusb/usb_phone.dart';
import 'package:web/web.dart' as web;

/// What this browser can do with phones (design §4.9).
DeviceAccess browserDeviceAccess() {
  // Browsers only expose navigator.usb on https (or localhost) pages.
  if (!web.window.isSecureContext) {
    return DeviceAccess.notSecure;
  }
  return navigatorUsb == null ? DeviceAccess.noWebUsb : DeviceAccess.webUsb;
}

UsbPhoneSource createUsbPhoneSource() => WebUsbPhoneSource(navigatorUsb!);

/// The name the phone shows next to the browser's key.
String adbKeyName() => 'fcm-studio@${web.window.location.host}';

/// A new 2048-bit RSA key from WebCrypto, exported as a JWK (design §4.5).
Future<Map<String, Object?>> generateAdbKeyJwk() async {
  final subtle = web.window.crypto.subtle;
  final pair =
      await subtle
              .generateKey(
                _RsaKeyGenParams(
                  name: 'RSASSA-PKCS1-v1_5',
                  modulusLength: 2048,
                  publicExponent: Uint8List.fromList([1, 0, 1]).toJS,
                  hash: 'SHA-1',
                ),
                true,
                ['sign'.toJS].toJS,
              )
              .toDart
          as _KeyPair;
  final jwk = await subtle.exportKey('jwk', pair.privateKey).toDart;
  final map = jwk.dartify()! as Map<Object?, Object?>;
  return {for (final entry in map.entries) '${entry.key}': entry.value};
}

extension type _RsaKeyGenParams._(JSObject _) implements JSObject {
  external factory _RsaKeyGenParams({
    required String name,
    required int modulusLength,
    required JSUint8Array publicExponent,
    required String hash,
  });
}

extension type _KeyPair._(JSObject _) implements JSObject {
  external web.CryptoKey get privateKey;
}
