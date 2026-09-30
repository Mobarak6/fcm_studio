import 'package:fcm_studio/features/devices/data/adb_locator.dart';
import 'package:fcm_studio/features/devices/data/process_runner.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_process_runner.dart';

const adbVersion =
    'Android Debug Bridge version 1.0.41\nVersion 33.0.3-8952118\n'
    'Installed as /opt/homebrew/bin/adb\n';

void main() {
  late FakeProcessRunner runner;

  setUp(() => runner = FakeProcessRunner());

  AdbLocator locator({
    Map<String, String> environment = const {'HOME': '/Users/me'},
    bool windows = false,
  }) =>
      AdbLocator(runner: runner, environment: environment, isWindows: windows);

  test('uses the path set in Settings first', () async {
    runner.on('/custom/adb version', ok(adbVersion));
    final search = await locator().locate(userPath: '/custom/adb');
    expect(
      search.found,
      const AdbLocation(
        path: '/custom/adb',
        source: AdbSource.settings,
        version: 'Android Debug Bridge version 1.0.41',
      ),
    );
    expect(search.tried, ['/custom/adb']);
  });

  test(
    'tries ANDROID_HOME, ANDROID_SDK_ROOT, the default SDK, then Homebrew',
    () async {
      runner.on('/opt/homebrew/bin/adb version', ok(adbVersion));
      final search = await locator(
        environment: const {
          'ANDROID_HOME': '/sdk1',
          'ANDROID_SDK_ROOT': '/sdk2',
          'HOME': '/Users/me',
        },
      ).locate();
      expect(search.found?.source, AdbSource.homebrew);
      expect(search.tried, [
        '/sdk1/platform-tools/adb',
        '/sdk2/platform-tools/adb',
        '/Users/me/Library/Android/sdk/platform-tools/adb',
        '/opt/homebrew/bin/adb',
      ]);
    },
  );

  test('falls back to looking adb up on PATH', () async {
    runner
      ..on('which adb', ok('/custom/bin/adb\n'))
      ..on('/custom/bin/adb version', ok(adbVersion));
    final search = await locator().locate();
    expect(search.found?.path, '/custom/bin/adb');
    expect(search.found?.source, AdbSource.path);
  });

  test(
    'on Windows uses LOCALAPPDATA and adb.exe, and never Homebrew',
    () async {
      const sdkAdb =
          r'C:\Users\me\AppData\Local\Android\Sdk\platform-tools\adb.exe';
      runner.on('$sdkAdb version', ok(adbVersion));
      final search = await locator(
        environment: const {'LOCALAPPDATA': r'C:\Users\me\AppData\Local'},
        windows: true,
      ).locate();
      expect(search.found?.path, sdkAdb);
      expect(search.found?.source, AdbSource.sdkDefault);
      expect(runner.commands.any((c) => c.contains('homebrew')), isFalse);
    },
  );

  test('skips a program that is not adb', () async {
    runner
      ..on('/opt/homebrew/bin/adb version', ok('something else\n'))
      ..on('/usr/local/bin/adb version', ok(adbVersion));
    expect((await locator().locate()).found?.source, AdbSource.usrLocal);
  });

  test('reports every path it tried when nothing works', () async {
    runner.on('which adb', const ProcessOutput(exitCode: 1));
    final search = await locator().locate();
    expect(search.found, isNull);
    expect(search.tried, [
      '/Users/me/Library/Android/sdk/platform-tools/adb',
      '/opt/homebrew/bin/adb',
      '/usr/local/bin/adb',
    ]);
  });
}
