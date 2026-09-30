import 'package:equatable/equatable.dart';

/// The states spec §9.2 shows; anything else is [other].
enum DeviceState { device, unauthorized, offline, other }

/// One line of `adb devices -l`.
class AdbDevice extends Equatable {
  const AdbDevice({
    required this.serial,
    required this.state,
    this.rawState = '',
    this.model,
    this.product,
    this.transportId,
  });

  final String serial;
  final DeviceState state;

  /// The state as adb printed it, e.g. `recovery` for [DeviceState.other].
  final String rawState;
  final String? model;
  final String? product;
  final String? transportId;

  /// Only a device in the `device` state accepts commands.
  bool get isReady => state == DeviceState.device;

  @override
  List<Object?> get props => [
    serial,
    state,
    rawState,
    model,
    product,
    transportId,
  ];
}

/// What `getprop` says about a device (spec §9.2).
class DeviceDetails extends Equatable {
  const DeviceDetails({
    required this.name,
    this.brand = '',
    this.androidVersion = '',
  });

  /// `ro.product.marketname`, falling back to `ro.product.model`.
  final String name;
  final String brand;
  final String androidVersion;

  @override
  List<Object?> get props => [name, brand, androidVersion];
}
