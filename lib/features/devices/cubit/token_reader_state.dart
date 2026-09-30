import 'package:equatable/equatable.dart';
import 'package:fcm_studio/features/devices/domain/device_token.dart';
import 'package:fcm_studio/features/devices/domain/package_order.dart';
import 'package:fcm_studio/features/devices/domain/token_read_results.dart';

enum PackagesStatus { idle, loading, ready, failed }

/// Where reading a package's token stands (spec §9.3).
sealed class TokenRead extends Equatable {
  const TokenRead();

  @override
  List<Object?> get props => [];
}

final class TokenReadIdle extends TokenRead {
  const TokenReadIdle();
}

/// Every step after idle is about one package.
sealed class TokenReadStep extends TokenRead {
  const TokenReadStep(this.package);

  final String package;

  @override
  List<Object?> get props => [package];
}

final class TokenReading extends TokenReadStep {
  const TokenReading(super.package);
}

final class TokenReadFound extends TokenReadStep {
  const TokenReadFound(
    super.package, {
    required this.tokens,
    required this.method,
    this.preselectedSenderId,
  });

  final List<FoundToken> tokens;
  final TokenReadMethod method;

  /// The sender matching the selected project, or the only one.
  final String? preselectedSenderId;

  @override
  List<Object?> get props => [package, tokens, method, preselectedSenderId];
}

final class TokenReadReleaseBuild extends TokenReadStep {
  const TokenReadReleaseBuild(super.package);
}

final class TokenReadNoTokenYet extends TokenReadStep {
  const TokenReadNoTokenYet(super.package);
}

final class TokenReadNotInstalled extends TokenReadStep {
  const TokenReadNotInstalled(super.package);
}

final class TokenReadWatchingLogcat extends TokenReadStep {
  const TokenReadWatchingLogcat(super.package, this.progress);

  final LogcatProgress progress;

  @override
  List<Object?> get props => [package, progress];
}

final class TokenReadLogcatNoToken extends TokenReadStep {
  const TokenReadLogcatNoToken(super.package);
}

final class TokenReadAppDidNotStart extends TokenReadStep {
  const TokenReadAppDidNotStart(super.package);
}

final class TokenReadFailed extends TokenReadStep {
  const TokenReadFailed(super.package, this.message);

  /// Names the failed command (spec §11).
  final String message;

  @override
  List<Object?> get props => [package, message];
}

class TokenReaderState extends Equatable {
  const TokenReaderState({
    this.serial,
    this.packagesStatus = PackagesStatus.idle,
    this.installed = const [],
    this.recent = const [],
    this.query = '',
    this.packagesError,
    this.read = const TokenReadIdle(),
  });

  final String? serial;
  final PackagesStatus packagesStatus;
  final List<String> installed;

  /// Newest first.
  final List<String> recent;
  final String query;
  final String? packagesError;
  final TokenRead read;

  List<String> get packages => orderPackages(installed, recent, query);

  bool get isBusy => read is TokenReading || read is TokenReadWatchingLogcat;

  TokenReaderState copyWith({
    PackagesStatus? packagesStatus,
    List<String>? installed,
    List<String>? recent,
    String? query,
    String? Function()? packagesError,
    TokenRead? read,
  }) => TokenReaderState(
    serial: serial,
    packagesStatus: packagesStatus ?? this.packagesStatus,
    installed: installed ?? this.installed,
    recent: recent ?? this.recent,
    query: query ?? this.query,
    packagesError: packagesError != null ? packagesError() : this.packagesError,
    read: read ?? this.read,
  );

  @override
  List<Object?> get props => [
    serial,
    packagesStatus,
    installed,
    recent,
    query,
    packagesError,
    read,
  ];
}
