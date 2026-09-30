import 'package:equatable/equatable.dart';
import 'package:fcm_studio/features/devices/domain/device_token.dart';

/// The result of reading the token file with `run-as` (spec §9.3 step 1).
sealed class RunAsResult extends Equatable {
  const RunAsResult();

  @override
  List<Object?> get props => [];
}

final class RunAsTokens extends RunAsResult {
  const RunAsTokens(this.tokens);

  final List<FoundToken> tokens;

  @override
  List<Object?> get props => [tokens];
}

/// `run-as` refuses release builds; logcat (step 2) may work.
final class RunAsReleaseBuild extends RunAsResult {
  const RunAsReleaseBuild();
}

/// The app has no token yet: it was never opened, or hasn't registered.
final class RunAsNoTokenYet extends RunAsResult {
  const RunAsNoTokenYet();
}

final class RunAsNotInstalled extends RunAsResult {
  const RunAsNotInstalled();
}

final class RunAsFailed extends RunAsResult {
  const RunAsFailed(this.message);

  /// Names the command that failed (spec §11).
  final String message;

  @override
  List<Object?> get props => [message];
}

/// Progress of reading the token from logcat (spec §9.3 step 2).
sealed class LogcatProgress extends Equatable {
  const LogcatProgress();

  @override
  List<Object?> get props => [];
}

final class LogcatRestartingApp extends LogcatProgress {
  const LogcatRestartingApp();
}

final class LogcatWaitingForApp extends LogcatProgress {
  const LogcatWaitingForApp();
}

final class LogcatWatching extends LogcatProgress {
  const LogcatWatching(this.pid);

  final int pid;

  @override
  List<Object?> get props => [pid];
}

final class LogcatFound extends LogcatProgress {
  const LogcatFound(this.token);

  final String token;

  @override
  List<Object?> get props => [token];
}

final class LogcatAppDidNotStart extends LogcatProgress {
  const LogcatAppDidNotStart();
}

/// The app ran but printed no token within the time limit.
final class LogcatNoToken extends LogcatProgress {
  const LogcatNoToken();
}

final class LogcatFailed extends LogcatProgress {
  const LogcatFailed(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}
