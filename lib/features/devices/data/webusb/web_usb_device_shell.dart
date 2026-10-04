import 'package:fcm_studio/features/devices/data/adb_exception.dart';
import 'package:fcm_studio/features/devices/data/device_shell.dart';
import 'package:fcm_studio/features/devices/data/process_runner.dart';
import 'package:fcm_studio/features/devices/data/webusb/adb_connection.dart';
import 'package:fcm_studio/features/devices/data/webusb/shell_v2.dart';

/// Runs phone commands over shell v2 on the phone's WebUSB connection
/// (design §4.7). Messages name the command and the phone.
class WebUsbDeviceShell implements DeviceShell {
  WebUsbDeviceShell({required this._connectionFor, required this._nameOf});

  /// Throws [AdbException] when the phone isn't ready.
  final AdbConnection Function(String serial) _connectionFor;
  final String Function(String serial) _nameOf;

  @override
  Future<ProcessOutput> run(String serial, PhoneCommand command) async {
    try {
      return await runShellV2(_connectionFor(serial), command.shellText);
    } on AdbException catch (e) {
      throw AdbException('${describe(serial, command)} failed: ${e.message}');
    }
  }

  @override
  Future<RunningProcess> start(String serial, PhoneCommand command) async {
    try {
      return await ShellV2Process.start(
        _connectionFor(serial),
        command.shellText,
      );
    } on AdbException catch (e) {
      throw AdbException('${describe(serial, command)} failed: ${e.message}');
    }
  }

  @override
  String describe(String serial, PhoneCommand command) =>
      '`${command.shellText}` on ${_nameOf(serial)}';
}
