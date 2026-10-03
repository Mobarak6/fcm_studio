import 'package:fcm_studio/features/devices/data/adb_exception.dart';
import 'package:fcm_studio/features/devices/data/process_runner.dart';

/// How desktop adb runs a phone command (WebUSB design §4.7).
enum PhoneCommandKind { shell, execOut, logcat }

/// A command run on the phone.
class PhoneCommand {
  const PhoneCommand.shell(this.text) : kind = PhoneCommandKind.shell;

  /// Byte-for-byte output, e.g. `run-as <package> cat <file>`.
  const PhoneCommand.execOut(this.text) : kind = PhoneCommandKind.execOut;

  /// `logcat` with [text] as its arguments.
  const PhoneCommand.logcat(this.text) : kind = PhoneCommandKind.logcat;

  final PhoneCommandKind kind;
  final String text;

  /// The command line in the phone's shell.
  String get shellText =>
      kind == PhoneCommandKind.logcat ? 'logcat $text' : text;
}

/// Runs commands on a phone: adb on desktop, WebUSB on the web.
abstract interface class DeviceShell {
  /// Runs [command] to the end. A non-zero exit code is not an error;
  /// throws [AdbException] when the command can't run at all.
  Future<ProcessOutput> run(String serial, PhoneCommand command);

  /// Starts a long-running [command]. Throws [AdbException] when it can't
  /// start.
  Future<RunningProcess> start(String serial, PhoneCommand command);

  /// How messages name [command], already in backticks.
  String describe(String serial, PhoneCommand command);
}

/// Desktop: `adb -s <serial> shell|exec-out|logcat …`, exactly as M3 ran it.
class ProcessDeviceShell implements DeviceShell {
  ProcessDeviceShell({required this._runner, required this._adbPath});

  final ProcessRunner _runner;
  final String _adbPath;

  List<String> _arguments(String serial, PhoneCommand command) => [
    '-s',
    serial,
    ...switch (command.kind) {
      PhoneCommandKind.shell => ['shell', command.text],
      PhoneCommandKind.execOut => ['exec-out', ...command.text.split(' ')],
      PhoneCommandKind.logcat => ['logcat', ...command.text.split(' ')],
    },
  ];

  @override
  Future<ProcessOutput> run(String serial, PhoneCommand command) async {
    try {
      return await _runner.run(_adbPath, _arguments(serial, command));
    } on ProcessRunException catch (e) {
      throw AdbException(e.message);
    }
  }

  @override
  Future<RunningProcess> start(String serial, PhoneCommand command) async {
    try {
      return await _runner.start(_adbPath, _arguments(serial, command));
    } on ProcessRunException catch (e) {
      throw AdbException(e.message);
    }
  }

  @override
  String describe(String serial, PhoneCommand command) =>
      '`${describeCommand(_adbPath, _arguments(serial, command))}`';
}
