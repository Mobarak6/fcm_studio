import 'dart:convert';

import 'package:fcm_studio/features/devices/data/adb_commands.dart';
import 'package:fcm_studio/features/devices/data/adb_exception.dart';
import 'package:fcm_studio/features/devices/data/bridge/bridge_client.dart';
import 'package:fcm_studio/features/devices/data/bridge/bridge_device_shell.dart';
import 'package:fcm_studio/features/devices/data/device_shell.dart';
import 'package:fcm_studio/features/devices/data/process_runner.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fake_bridge_channel.dart';

const app = 'com.syldel.delivery';

Map<String, Object?> chunk(int id, List<int> bytes, {String type = 'stdout'}) =>
    {'type': type, 'id': id, 'data': base64Encode(bytes)};

Map<String, Object?> exited(int id, int code) => {
  'type': 'exit',
  'id': id,
  'code': code,
};

void main() {
  test('run sends the command and collects its output', () async {
    final (client, channel) = await connectedBridgeClient();
    final shell = BridgeDeviceShell(bridge: client);
    const command = PhoneCommand.execOut(
      'run-as $app cat ${AdbCommands.tokenFile}',
    );
    final output = shell.run('S1', command);
    expect(channel.runs.single, {
      'type': 'run',
      'serial': 'S1',
      'kind': 'execOut',
      'text': 'run-as $app cat ${AdbCommands.tokenFile}',
      'id': 1,
    });
    channel
      ..fromBridge(chunk(1, utf8.encode('<map/>')))
      ..fromBridge(chunk(1, utf8.encode('note'), type: 'stderr'))
      ..fromBridge(exited(1, 0));
    expect(
      await output,
      const ProcessOutput(exitCode: 0, stdout: '<map/>', stderr: 'note'),
    );
  });

  test('a character split across chunks decodes whole', () async {
    final (client, channel) = await connectedBridgeClient();
    final output = BridgeDeviceShell(
      bridge: client,
    ).run('S1', const PhoneCommand.shell('pm list packages -3'));
    final bytes = utf8.encode('Rédmi');
    channel
      ..fromBridge(chunk(1, bytes.sublist(0, 2)))
      ..fromBridge(chunk(1, bytes.sublist(2)))
      ..fromBridge(exited(1, 0));
    expect((await output).stdout, 'Rédmi');
  });

  test('an error reply names the command', () async {
    final (client, channel) = await connectedBridgeClient();
    final run = BridgeDeviceShell(
      bridge: client,
    ).run('S1', const PhoneCommand.shell('pm list packages -3'));
    channel.fromBridge({
      'type': 'error',
      'id': 1,
      'message': 'fcm_bridge refused this command.',
    });
    await expectLater(
      run,
      throwsA(
        isA<AdbException>().having(
          (e) => e.message,
          'message',
          '`adb -s S1 shell pm list packages -3` (through the bridge) '
              'failed: fcm_bridge refused this command.',
        ),
      ),
    );
  });

  test('start streams stdout only; kill asks the bridge', () async {
    final (client, channel) = await connectedBridgeClient();
    final process = await BridgeDeviceShell(
      bridge: client,
    ).start('S1', const PhoneCommand.logcat('--pid=42'));
    final text = <String>[];
    final done = process.stdout.map(utf8.decode).forEach(text.add);
    channel
      ..fromBridge(chunk(1, utf8.encode('line 1\n')))
      ..fromBridge(chunk(1, utf8.encode('ignored'), type: 'stderr'))
      ..fromBridge(chunk(1, utf8.encode('line 2\n')));
    process.kill();
    expect(channel.sent.last, {'type': 'kill', 'id': 1});
    channel.fromBridge(exited(1, -15));
    await done;
    expect(text.join(), 'line 1\nline 2\n');
    expect(await process.exitCode, -15);
  });

  test(
    'a command that never finishes times out, like on desktop, and is stopped',
    () async {
      final (client, channel) = await connectedBridgeClient();
      final run = BridgeDeviceShell(
        bridge: client,
        timeout: const Duration(seconds: 1),
      ).run('S1', const PhoneCommand.shell('pidof $app'));
      channel.fromBridge(chunk(1, utf8.encode('partial')));
      await expectLater(
        run,
        throwsA(
          isA<AdbException>().having(
            (e) => e.message,
            'message',
            '`adb -s S1 shell pidof $app` (through the bridge) did not finish '
                'within 1 seconds',
          ),
        ),
      );
      expect(channel.sent.last, {'type': 'kill', 'id': 1});
    },
  );

  test('describe names adb and the bridge', () async {
    final (client, _) = await connectedBridgeClient();
    final shell = BridgeDeviceShell(bridge: client);
    expect(
      shell.describe('S1', const PhoneCommand.shell('pidof $app')),
      '`adb -s S1 shell pidof $app` (through the bridge)',
    );
    expect(
      shell.describe('S1', const PhoneCommand.execOut('run-as $app cat f')),
      '`adb -s S1 exec-out run-as $app cat f` (through the bridge)',
    );
    expect(
      shell.describe('S1', const PhoneCommand.logcat('--pid=1')),
      '`adb -s S1 logcat --pid=1` (through the bridge)',
    );
  });

  test('when not connected, the command fails with its name', () async {
    final client = BridgeClient(
      connector: FakeBridgeConnector().connect,
      readAutoConnect: () async => false,
      writeAutoConnect: (_) async {},
    );
    addTearDown(client.dispose);
    await expectLater(
      BridgeDeviceShell(
        bridge: client,
      ).run('S1', const PhoneCommand.shell('pidof $app')),
      throwsA(
        isA<AdbException>().having(
          (e) => e.message,
          'message',
          '`adb -s S1 shell pidof $app` (through the bridge) failed: '
              '${BridgeClient.notConnectedMessage}',
        ),
      ),
    );
  });
}
