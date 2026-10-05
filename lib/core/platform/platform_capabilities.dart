import 'package:fcm_studio/core/platform/device_access.dart';

export 'package:fcm_studio/core/platform/device_access.dart';

/// What this platform can do (spec §3.1; WebUSB design §4.9; bridge design
/// §4.6). Every platform can read phones: adb on desktop, WebUSB or the
/// bridge on the web.
class PlatformFeatures {
  const PlatformFeatures({required this.deviceAccess});

  final DeviceAccess deviceAccess;

  /// Desktop: adb runs, and its path is set in Settings.
  bool get canRunAdb => deviceAccess == DeviceAccess.adb;
}
