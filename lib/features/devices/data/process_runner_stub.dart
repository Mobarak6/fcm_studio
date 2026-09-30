import 'package:fcm_studio/features/devices/data/process_runner.dart';

ProcessRunner createProcessRunner() => const UnsupportedProcessRunner();

Map<String, String> platformEnvironment() => const {};

bool platformIsWindows() => false;

/// Web: browsers can't start programs, so the device features are hidden there (spec §3.1).
class UnsupportedProcessRunner implements ProcessRunner {
  const UnsupportedProcessRunner();

  @override
  Future<ProcessOutput> run(
    String executable,
    List<String> arguments, {
    Duration timeout = ProcessRunner.defaultTimeout,
  }) async {
    throw UnsupportedError('Running programs is not available on the web.');
  }

  @override
  Future<RunningProcess> start(
    String executable,
    List<String> arguments,
  ) async {
    throw UnsupportedError('Running programs is not available on the web.');
  }
}
