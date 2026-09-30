import 'package:equatable/equatable.dart';

/// A token found on a phone, for one sender (Firebase project number).
class FoundToken extends Equatable {
  const FoundToken({required this.token, this.senderId});

  final String token;

  /// Unknown when the token came from logcat.
  final String? senderId;

  @override
  List<Object?> get props => [token, senderId];
}

/// How a token was read (spec §9.3): `run-as` works for debug builds,
/// logcat for release builds that log their token.
enum TokenReadMethod { runAs, logcat }

/// A token read from a phone, ready to become a target (spec §9.3 "Result").
class DeviceToken extends Equatable {
  const DeviceToken({
    required this.token,
    required this.method,
    required this.readAt,
    required this.serial,
    required this.package,
    required this.deviceName,
    this.senderId,
  });

  final String token;
  final String? senderId;
  final TokenReadMethod method;
  final DateTime readAt;
  final String serial;
  final String package;

  /// The phone's market name, model or serial.
  final String deviceName;

  bool get isDebugBuild => method == TokenReadMethod.runAs;

  /// The saved-target label (spec §7.1).
  String get label =>
      '$deviceName · $package (${isDebugBuild ? 'debug' : 'release'})';

  @override
  List<Object?> get props => [
    token,
    senderId,
    method,
    readAt,
    serial,
    package,
    deviceName,
  ];
}
