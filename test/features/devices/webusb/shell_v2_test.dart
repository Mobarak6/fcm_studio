import 'dart:async';
import 'dart:convert';

import 'package:fcm_studio/features/devices/data/adb_exception.dart';
import 'package:fcm_studio/features/devices/data/process_runner.dart';
import 'package:fcm_studio/features/devices/data/webusb/adb_connection.dart';
import 'package:fcm_studio/features/devices/data/webusb/shell_v2.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/adb_key_fixture.dart';
import '../../../helpers/fake_adbd.dart';

void main() {
  late FakeAdbd adbd;
  late AdbConnection connection;

  setUp(() async {
    adbd = FakeAdbd()..start();
    connection = AdbConnection(
      transport: adbd.transport,
      loadKey: () async => testAdbKey(),
      keyName: 'fcm-studio@example.com',
    );
    await connection.connect();
  });

  test(
    'the decoder handles packets split across chunks, or several in one',
    () {
      final bytes = [
        ...ShellV2.packet(ShellV2.stdout, utf8.encode('hello')),
        ...ShellV2.packet(ShellV2.stderr, utf8.encode('oops')),
        ...ShellV2.packet(ShellV2.exit, [3]),
      ];
      final decoder = ShellV2Decoder();
      final packets = [
        ...decoder.add(bytes.sublist(0, 3)),
        ...decoder.add(bytes.sublist(3, 12)),
        ...decoder.add(bytes.sublist(12)),
      ];
      expect(packets.map((p) => p.id), [
        ShellV2.stdout,
        ShellV2.stderr,
        ShellV2.exit,
      ]);
      expect(utf8.decode(packets[0].data), 'hello');
      expect(utf8.decode(packets[1].data), 'oops');
      expect(packets[2].data, [3]);
    },
  );

  test('run collects stdout, stderr and the exit code', () async {
    adbd.commands['run-as app cat x'] = const ProcessOutput(
      exitCode: 1,
      stderr: 'run-as: package not debuggable: app\n',
    );
    final output = await runShellV2(connection, 'run-as app cat x');
    expect(output.exitCode, 1);
    expect(output.stdout, isEmpty);
    expect(output.stderr, 'run-as: package not debuggable: app\n');
    expect(adbd.opened, ['run-as app cat x']);
  });

  test('an empty output with exit 0', () async {
    adbd.commands['true'] = const ProcessOutput(exitCode: 0);
    final output = await runShellV2(connection, 'true');
    expect((output.exitCode, output.stdout, output.stderr), (0, '', ''));
  });

  test('a command the phone refuses is an AdbException', () async {
    await expectLater(
      runShellV2(connection, 'unknown'),
      throwsA(isA<AdbException>()),
    );
  });

  test(
    'a running process streams stdout; kill closes it on the phone',
    () async {
      final logcat = adbd.running['logcat --pid=42'] =
          StreamController<String>();
      final process = await ShellV2Process.start(connection, 'logcat --pid=42');
      final lines = <String>[];
      final subscription = process.stdout
          .transform(utf8.decoder)
          .listen(lines.add);
      logcat.add('line one\n');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(lines, ['line one\n']);
      process.kill();
      expect(await process.exitCode, -9);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(adbd.closedByHost, ['logcat --pid=42']);
      await subscription.cancel();
    },
  );

  test('unplugging during a running process is an error on stdout', () async {
    adbd.running['logcat --pid=42'] = StreamController<String>();
    final process = await ShellV2Process.start(connection, 'logcat --pid=42');
    final errors = <Object>[];
    process.stdout.listen((_) {}, onError: errors.add);
    adbd.transport.unplug();
    expect(await process.exitCode, -1);
    expect(errors.single, isA<AdbException>());
  });
}
