import 'dart:convert';
import 'dart:io';

import 'package:fcm_studio/features/devices/data/process_runner.dart';
import 'package:fcm_studio/features/devices/data/process_runner_io.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const runner = IoProcessRunner();
  final skip = Platform.isWindows ? 'needs sh' : false;

  test('runs a command and returns its exit code and output', () async {
    final output = await runner.run('sh', [
      '-c',
      'echo out; echo err 1>&2; exit 3',
    ]);
    expect(output.exitCode, 3);
    expect(output.stdout.trim(), 'out');
    expect(output.stderr.trim(), 'err');
    expect(output.combined, contains('out'));
    expect(output.combined, contains('err'));
  }, skip: skip);

  test('decodes malformed UTF-8 instead of failing', () async {
    final output = await runner.run('sh', ['-c', r"printf 'a\377b'"]);
    expect(output.stdout, 'a�b');
  }, skip: skip);

  test('a command that does not finish in time is killed and named', () async {
    await expectLater(
      runner.run('sleep', ['5'], timeout: const Duration(milliseconds: 200)),
      throwsA(
        isA<ProcessRunException>().having(
          (e) => e.message,
          'message',
          allOf(contains('sleep 5'), contains('did not finish')),
        ),
      ),
    );
  }, skip: skip);

  test('a missing program is reported with its command', () async {
    await expectLater(
      runner.run('/no/such/adb', ['version']),
      throwsA(
        isA<ProcessRunException>().having(
          (e) => e.message,
          'message',
          contains('/no/such/adb version'),
        ),
      ),
    );
  });

  test('start streams output and can be killed', () async {
    final process = await runner.start('sh', ['-c', 'echo first; sleep 5']);
    final first = await process.stdout.transform(utf8.decoder).first;
    expect(first.trim(), 'first');
    process.kill();
    expect(await process.exitCode, isNot(0));
  }, skip: skip);
}
