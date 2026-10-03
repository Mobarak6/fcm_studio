import 'package:fcm_studio/features/devices/data/adb_commands.dart';
import 'package:fcm_studio/features/devices/data/adb_exception.dart';
import 'package:fcm_studio/features/devices/data/device_shell.dart';
import 'package:fcm_studio/features/devices/data/process_runner.dart';
import 'package:fcm_studio/features/devices/domain/token_read_results.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/device_fixtures.dart';
import '../../helpers/fake_process_runner.dart';

const app = 'com.syldel.delivery';

/// A phone shell that isn't adb, as the web's will be: commands are keyed
/// by their shell text, and messages name the phone.
class FakeDeviceShell implements DeviceShell {
  final Map<String, ProcessOutput> outputs = {};
  final Map<String, FakeRunningProcess> processes = {};
  final List<String> ran = [];

  @override
  Future<ProcessOutput> run(String serial, PhoneCommand command) async {
    ran.add(command.shellText);
    final output = outputs[command.shellText];
    if (output == null) {
      throw AdbException('${describe(serial, command)} failed: not scripted');
    }
    return output;
  }

  @override
  Future<RunningProcess> start(String serial, PhoneCommand command) async {
    ran.add(command.shellText);
    final process = processes[command.shellText];
    if (process == null) {
      throw AdbException('${describe(serial, command)} failed: not scripted');
    }
    return process;
  }

  @override
  String describe(String serial, PhoneCommand command) =>
      '`${command.shellText}` on Redmi 14C';
}

void main() {
  late FakeDeviceShell shell;

  setUp(() => shell = FakeDeviceShell());

  AdbCommands commands() => AdbCommands(
    shell: shell,
    pollInterval: const Duration(milliseconds: 1),
    appStartTimeout: const Duration(milliseconds: 50),
    logcatTimeout: const Duration(milliseconds: 100),
  );

  test('failures name the command the way the shell describes it', () async {
    shell.outputs['pm list packages -3'] = const ProcessOutput(
      exitCode: 1,
      stderr: 'boom',
    );
    await expectLater(
      commands().listPackages(redmiSerial),
      throwsA(
        isA<AdbException>().having(
          (e) => e.message,
          'message',
          '`pm list packages -3` on Redmi 14C failed: boom',
        ),
      ),
    );
  });

  test('a release build reported on stderr is still a release build', () async {
    shell.outputs['run-as $app cat ${AdbCommands.tokenFile}'] =
        const ProcessOutput(
          exitCode: 1,
          stderr: 'run-as: package not debuggable: $app',
        );
    expect(
      await commands().readTokenWithRunAs(redmiSerial, app),
      const RunAsReleaseBuild(),
    );
  });

  test('logcat runs in the phone shell and finds the token', () async {
    shell.outputs
      ..['am force-stop $app'] = ok('')
      ..['monkey -p $app -c android.intent.category.LAUNCHER 1'] = ok(
        'Events injected: 1\n',
      )
      ..['pidof $app'] = ok('4242\n');
    final logcat = FakeRunningProcess()
      ..emit('10-04 12:00:01.000 I/flutter: FCM token: $fakeDeviceToken\n');
    shell.processes['logcat --pid=4242'] = logcat;

    final progress = await commands()
        .readTokenFromLogcat(redmiSerial, app)
        .toList();

    expect(progress.last, LogcatFound(fakeDeviceToken));
    expect(shell.ran, contains('logcat --pid=4242'));
    expect(logcat.killed, isTrue);
  });

  group('ProcessDeviceShell keeps the desktop adb commands', () {
    final desktop = ProcessDeviceShell(
      runner: FakeProcessRunner(),
      adbPath: '/sdk/adb',
    );

    test('shell, exec-out and logcat', () {
      expect(
        desktop.describe('S', const PhoneCommand.shell('pm list packages -3')),
        '`/sdk/adb -s S shell pm list packages -3`',
      );
      expect(
        desktop.describe('S', const PhoneCommand.execOut('run-as a cat f')),
        '`/sdk/adb -s S exec-out run-as a cat f`',
      );
      expect(
        desktop.describe('S', const PhoneCommand.logcat('--pid=1')),
        '`/sdk/adb -s S logcat --pid=1`',
      );
    });

    test('a command adb cannot run is an AdbException naming it', () async {
      await expectLater(
        desktop.run('S', const PhoneCommand.shell('getprop')),
        throwsA(
          isA<AdbException>().having(
            (e) => e.message,
            'message',
            contains('/sdk/adb -s S shell getprop'),
          ),
        ),
      );
    });
  });
}
