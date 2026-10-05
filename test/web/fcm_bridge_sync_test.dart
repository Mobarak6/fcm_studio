import 'package:fcm_studio/features/devices/data/adb_commands.dart';
import 'package:fcm_studio/features/devices/data/device_shell.dart';
import 'package:fcm_studio/features/devices/data/process_runner.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../web/fcm_bridge.dart' as bridge;
import '../helpers/device_fixtures.dart';
import '../helpers/fake_process_runner.dart';

const app = 'com.syldel.delivery';

/// Records every command; pidof finds a process, logcat ends at once.
class _RecordingShell implements DeviceShell {
  final List<PhoneCommand> commands = [];

  @override
  Future<ProcessOutput> run(String serial, PhoneCommand command) async {
    commands.add(command);
    return ProcessOutput(
      exitCode: 0,
      stdout: command.text.startsWith('pidof') ? '4321\n' : '',
    );
  }

  @override
  Future<RunningProcess> start(String serial, PhoneCommand command) async {
    commands.add(command);
    return FakeRunningProcess()..exit();
  }

  @override
  String describe(String serial, PhoneCommand command) => command.text;
}

void main() {
  test('the bridge allows every command FCM Studio runs', () async {
    final shell = _RecordingShell();
    final commands = AdbCommands(
      shell: shell,
      pollInterval: const Duration(milliseconds: 1),
      appStartTimeout: const Duration(milliseconds: 50),
      logcatTimeout: const Duration(milliseconds: 50),
    );
    await commands.deviceDetails(redmiSerial);
    await commands.listPackages(redmiSerial);
    await commands.readTokenWithRunAs(redmiSerial, app);
    await commands.launchApp(redmiSerial, app);
    await commands.readTokenFromLogcat(redmiSerial, app).drain<void>();

    expect(
      shell.commands.map((command) => command.kind).toSet(),
      PhoneCommandKind.values.toSet(),
    );
    expect(bridge.isAllowedSerial(redmiSerial), isTrue);
    for (final command in shell.commands) {
      expect(
        bridge.isAllowedCommand(command.kind.name, command.text),
        isTrue,
        reason: '${command.kind.name} `${command.text}`',
      );
    }
  });
}
