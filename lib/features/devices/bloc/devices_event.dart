abstract class DevicesEvent {
  const DevicesEvent();
}

/// adb was found at [adbPath], moved, or lost (null).
class DevicesAdbChanged extends DevicesEvent {
  const DevicesAdbChanged(this.adbPath);

  final String? adbPath;
}

class DeviceSelected extends DevicesEvent {
  const DeviceSelected(this.serial);

  final String serial;
}
