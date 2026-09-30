import 'package:equatable/equatable.dart';
import 'package:fcm_studio/features/devices/domain/adb_device.dart';

enum TrackerStatus { noAdb, starting, running, restarting }

class DevicesState extends Equatable {
  const DevicesState({
    this.status = TrackerStatus.noAdb,
    this.adbPath,
    this.devices = const [],
    this.selectedSerial,
    this.details = const {},
    this.retryIn,
    this.lastError,
  });

  final TrackerStatus status;
  final String? adbPath;
  final List<AdbDevice> devices;

  /// Kept while the phone is unplugged. If it is not in the next list and
  /// exactly one other phone is ready, that phone is selected instead.
  final String? selectedSerial;
  final Map<String, DeviceDetails> details;

  /// While restarting: how long until the next try.
  final Duration? retryIn;

  /// Why adb stopped, naming the command when known.
  final String? lastError;

  AdbDevice? get selected {
    for (final device in devices) {
      if (device.serial == selectedSerial) {
        return device;
      }
    }
    return null;
  }

  /// The market name from getprop, else adb's model, else the serial.
  String nameOf(AdbDevice device) =>
      details[device.serial]?.name ?? device.model ?? device.serial;

  DevicesState copyWith({
    TrackerStatus? status,
    String? Function()? adbPath,
    List<AdbDevice>? devices,
    String? Function()? selectedSerial,
    Map<String, DeviceDetails>? details,
    Duration? Function()? retryIn,
    String? Function()? lastError,
  }) => DevicesState(
    status: status ?? this.status,
    adbPath: adbPath != null ? adbPath() : this.adbPath,
    devices: devices ?? this.devices,
    selectedSerial: selectedSerial != null
        ? selectedSerial()
        : this.selectedSerial,
    details: details ?? this.details,
    retryIn: retryIn != null ? retryIn() : this.retryIn,
    lastError: lastError != null ? lastError() : this.lastError,
  );

  @override
  List<Object?> get props => [
    status,
    adbPath,
    devices,
    selectedSerial,
    details,
    retryIn,
    lastError,
  ];
}
