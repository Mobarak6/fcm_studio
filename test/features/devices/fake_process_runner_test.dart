import 'dart:convert';

import 'package:fcm_studio/features/devices/data/process_runner.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_process_runner.dart';

void main() {
  test('answers scripted commands and records every call', () async {
    final runner = FakeProcessRunner()
      ..on('adb version', ok('Android Debug Bridge version 1.0.41\n'))
      ..on('adb -s X shell pidof app', <ProcessOutput>[ok(''), ok('42\n')]);

    expect((await runner.run('adb', ['version'])).stdout, contains('1.0.41'));
    expect(
      (await runner.run('adb', ['-s', 'X', 'shell', 'pidof', 'app'])).stdout,
      '',
    );
    expect(
      (await runner.run('adb', ['-s', 'X', 'shell', 'pidof', 'app'])).stdout,
      '42\n',
    );
    expect(
      (await runner.run('adb', ['-s', 'X', 'shell', 'pidof', 'app'])).stdout,
      '42\n',
    );
    expect(runner.commands.first, 'adb version');
  });

  test('unscripted commands fail like a missing program', () async {
    await expectLater(
      FakeProcessRunner().run('adb', ['devices']),
      throwsA(isA<ProcessRunException>()),
    );
  });

  test('long-running processes are scripted with FakeRunningProcess', () async {
    final logcat = FakeRunningProcess()..emit('hello\n');
    final runner = FakeProcessRunner()..onStart('adb logcat', () => logcat);
    final process = await runner.start('adb', ['logcat']);
    expect(await process.stdout.transform(utf8.decoder).first, 'hello\n');
    process.kill();
    expect(logcat.killed, isTrue);
    expect(await process.exitCode, -9);
  });
}
