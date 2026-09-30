import 'package:fcm_studio/features/devices/data/process_runner.dart';

/// What `run-as <package> cat <token file>` reported (spec §9.3; messages
/// confirmed on the Redmi 14C, Android 16).
enum RunAsOutcome { file, notDebuggable, noSuchFile, unknownPackage, error }

final RegExp _olderUnknownPackage = RegExp(r"Package '[^']*' is unknown");

RunAsOutcome classifyRunAs(ProcessOutput output) {
  if (output.exitCode == 0 && output.stdout.contains('<map')) {
    return RunAsOutcome.file;
  }
  final text = output.combined;
  if (text.contains('package not debuggable')) {
    return RunAsOutcome.notDebuggable;
  }
  if (text.contains('unknown package') || _olderUnknownPackage.hasMatch(text)) {
    return RunAsOutcome.unknownPackage;
  }
  if (text.contains('No such file or directory')) {
    return RunAsOutcome.noSuchFile;
  }
  return RunAsOutcome.error;
}
