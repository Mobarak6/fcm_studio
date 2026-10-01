import 'package:flutter/foundation.dart';

/// What this platform can do (spec §3.1). The device features need a
/// desktop: browsers can't run adb.
class PlatformFeatures {
  const PlatformFeatures({required this.canRunAdb});

  static const PlatformFeatures current = PlatformFeatures(canRunAdb: !kIsWeb);

  final bool canRunAdb;
}
