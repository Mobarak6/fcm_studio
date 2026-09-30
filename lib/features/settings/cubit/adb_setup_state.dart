import 'package:equatable/equatable.dart';
import 'package:fcm_studio/features/devices/data/adb_locator.dart';

enum AdbStatus { unknown, locating, found, notFound }

class AdbSetupState extends Equatable {
  const AdbSetupState({
    this.status = AdbStatus.unknown,
    this.location,
    this.userPath,
    this.tried = const [],
  });

  final AdbStatus status;
  final AdbLocation? location;

  /// The path set in Settings, if any.
  final String? userPath;

  /// Every path tried, for the "not found" message.
  final List<String> tried;

  String? get adbPath => location?.path;

  /// True when a path is set in Settings but adb was found elsewhere, or not at all.
  bool get userPathFailed =>
      userPath != null && location?.source != AdbSource.settings;

  AdbSetupState copyWith({AdbStatus? status}) => AdbSetupState(
    status: status ?? this.status,
    location: location,
    userPath: userPath,
    tried: tried,
  );

  @override
  List<Object?> get props => [status, location, userPath, tried];
}
