import 'dart:convert';

import 'package:fcm_studio/features/devices/domain/adb_device.dart';

/// Parses a device list as `adb devices -l` and `adb track-devices -l` print
/// it: one device per line, `<serial> <state> key:value…`.
List<AdbDevice> parseDeviceList(String text) {
  final devices = <AdbDevice>[];
  for (final line in const LineSplitter().convert(text)) {
    final trimmed = line.trim();
    if (trimmed.startsWith('*') || trimmed.startsWith('List of devices')) {
      continue;
    }
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length < 2) {
      continue;
    }
    final fields = <String, String>{
      for (final part in parts.skip(2))
        if (part.contains(':'))
          part.substring(0, part.indexOf(':')): part.substring(
            part.indexOf(':') + 1,
          ),
    };
    devices.add(
      AdbDevice(
        serial: parts[0],
        state: _state(parts[1]),
        rawState: parts[1],
        model: fields['model'],
        product: fields['product'],
        transportId: fields['transport_id'],
      ),
    );
  }
  return devices;
}

DeviceState _state(String raw) => switch (raw) {
  'device' => DeviceState.device,
  'unauthorized' => DeviceState.unauthorized,
  'offline' => DeviceState.offline,
  _ => DeviceState.other,
};
