import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fcm_studio/features/devices/data/process_runner.dart';

ProcessRunner createProcessRunner() => const IoProcessRunner();

Map<String, String> platformEnvironment() => Platform.environment;

bool platformIsWindows() => Platform.isWindows;

/// Runs commands with dart:io (desktop).
class IoProcessRunner implements ProcessRunner {
  const IoProcessRunner();

  static const _decoder = Utf8Decoder(allowMalformed: true);

  @override
  Future<ProcessOutput> run(
    String executable,
    List<String> arguments, {
    Duration timeout = ProcessRunner.defaultTimeout,
  }) async {
    final command = describeCommand(executable, arguments);
    final Process process;
    try {
      process = await Process.start(executable, arguments);
    } on ProcessException catch (e) {
      throw ProcessRunException(command, 'could not start: ${e.message}');
    }
    final stdout = process.stdout.transform(_decoder).join();
    final stderr = process.stderr.transform(_decoder).join();
    final int exitCode;
    try {
      exitCode = await process.exitCode.timeout(timeout);
    } on TimeoutException {
      process.kill();
      throw ProcessRunException(
        command,
        'did not finish within ${timeout.inSeconds} seconds',
      );
    }
    return ProcessOutput(
      exitCode: exitCode,
      stdout: await stdout,
      stderr: await stderr,
    );
  }

  @override
  Future<RunningProcess> start(
    String executable,
    List<String> arguments,
  ) async {
    try {
      return _IoRunningProcess(await Process.start(executable, arguments));
    } on ProcessException catch (e) {
      throw ProcessRunException(
        describeCommand(executable, arguments),
        'could not start: ${e.message}',
      );
    }
  }
}

class _IoRunningProcess implements RunningProcess {
  _IoRunningProcess(this._process) {
    // An unread stderr pipe can fill up and block the process.
    unawaited(_process.stderr.drain<void>());
  }

  final Process _process;

  @override
  Stream<List<int>> get stdout => _process.stdout;

  @override
  Future<int> get exitCode => _process.exitCode;

  @override
  void kill() => _process.kill();
}
