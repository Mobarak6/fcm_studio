import 'package:fcm_studio/core/platform/device_access.dart';

export 'package:fcm_studio/core/platform/device_access.dart';

/// What this platform can do (spec §3.1; WebUSB design §4.9).
class PlatformFeatures {
  const PlatformFeatures({required this.deviceAccess});

  final DeviceAccess deviceAccess;

  /// Desktop: adb runs, and its path is set in Settings.
  bool get canRunAdb => deviceAccess == DeviceAccess.adb;

  /// Phones can be read: adb on desktop, WebUSB in Chromium browsers.
  bool get canReadPhones =>
      deviceAccess == DeviceAccess.adb || deviceAccess == DeviceAccess.webUsb;
}
