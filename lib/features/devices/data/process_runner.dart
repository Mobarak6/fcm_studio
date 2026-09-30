import 'package:equatable/equatable.dart';

/// What a finished command printed.
class ProcessOutput extends Equatable {
  const ProcessOutput({
    required this.exitCode,
    this.stdout = '',
    this.stderr = '',
  });

  final int exitCode;
  final String stdout;
  final String stderr;

  /// stdout and stderr together. adb prints some errors on either.
  String get combined => [stdout, stderr].where((s) => s.isNotEmpty).join('\n');

  @override
  List<Object?> get props => [exitCode, stdout, stderr];
}

/// A long-running command, e.g. `adb track-devices` or `adb logcat`.
abstract interface class RunningProcess {
  Stream<List<int>> get stdout;
  Future<int> get exitCode;
  void kill();
}

/// A command that could not start or did not finish in time. The message
/// names the command (spec §11).
class ProcessRunException implements Exception {
  const ProcessRunException(this.command, this.reason);

  final String command;
  final String reason;

  String get message => '`$command` $reason';

  @override
  String toString() => 'ProcessRunException: $message';
}

/// Runs external commands (adb). Injected, so tests never start real processes.
abstract interface class ProcessRunner {
  static const defaultTimeout = Duration(seconds: 10);

  /// Runs a command to the end. Throws [ProcessRunException] when it can't
  /// start or doesn't finish within [timeout].
  Future<ProcessOutput> run(
    String executable,
    List<String> arguments, {
    Duration timeout = defaultTimeout,
  });

  /// Starts a long-running command. Throws [ProcessRunException] when it can't start.
  Future<RunningProcess> start(String executable, List<String> arguments);
}

/// A command as one line, for messages.
String describeCommand(String executable, List<String> arguments) =>
    [executable, ...arguments].join(' ');
