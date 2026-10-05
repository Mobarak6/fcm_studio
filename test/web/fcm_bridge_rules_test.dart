import 'package:flutter_test/flutter_test.dart';

import '../../web/fcm_bridge.dart';

const app = 'com.syldel.delivery';
const getprop =
    'getprop ro.product.marketname; getprop ro.product.model; '
    'getprop ro.product.brand; getprop ro.build.version.release';
const tokenFile = 'shared_prefs/com.google.android.gms.appid.xml';

void main() {
  group('isAllowedCommand', () {
    const allowed = <(String, String)>[
      ('shell', getprop),
      ('shell', 'pm list packages -3'),
      ('shell', 'monkey -p $app -c android.intent.category.LAUNCHER 1'),
      ('shell', 'am force-stop $app'),
      ('shell', 'pidof $app'),
      ('execOut', 'run-as $app cat $tokenFile'),
      ('logcat', '--pid=4242'),
    ];
    for (final (kind, text) in allowed) {
      test('allows $kind `$text`', () {
        expect(isAllowedCommand(kind, text), isTrue);
      });
    }

    const refused = <(String, String)>[
      ('shell', 'pm uninstall $app'),
      ('shell', 'rm -rf /sdcard'),
      ('shell', 'pidof $app; reboot'),
      ('shell', 'pidof $app && reboot'),
      ('shell', "pidof '$app'"),
      ('shell', 'pidof app'),
      ('shell', 'pidof 1a.b'),
      ('shell', 'am force-stop $app\nreboot'),
      ('shell', 'monkey -p $app -c android.intent.category.LAUNCHER 1; reboot'),
      ('shell', 'pm list packages -3 -f'),
      ('shell', 'run-as $app cat $tokenFile'),
      ('execOut', 'run-as $app cat /data/system/users.xml'),
      ('execOut', 'run-as $app cat $tokenFile; reboot'),
      ('logcat', '--pid=1 -c'),
      ('logcat', '--pid=x'),
      ('logcat', '-c'),
      ('install', 'app.apk'),
    ];
    for (final (kind, text) in refused) {
      test('refuses $kind `$text`', () {
        expect(isAllowedCommand(kind, text), isFalse);
      });
    }
  });

  test('serials: USB, emulator, wireless; nothing that looks like a flag', () {
    for (final serial in [
      'DETWFUOZZHZ5SWFQ',
      'emulator-5554',
      '192.168.1.20:5555',
      'adb-R5CT10ABCDE-xyz._adb-tls-connect._tcp',
    ]) {
      expect(isAllowedSerial(serial), isTrue, reason: serial);
    }
    for (final serial in ['', '-s', '--pid', 'a b', 'a;b', r'a$b']) {
      expect(isAllowedSerial(serial), isFalse, reason: serial);
    }
  });

  test('origins: localhost pages, --allow-origin, the hosted page, nothing '
      'else', () {
    expect(isAllowedOrigin('http://localhost:5050', const []), isTrue);
    expect(
      isAllowedOrigin('https://fcm-studio-oauth.web.app', const []),
      isTrue,
    );
    expect(
      isAllowedOrigin('http://fcm-studio-oauth.web.app', const []),
      isFalse,
    );
    expect(isAllowedOrigin('http://127.0.0.1:8080', const []), isTrue);
    expect(isAllowedOrigin('http://localhost', const []), isTrue);
    expect(isAllowedOrigin('https://localhost:5050', const []), isFalse);
    expect(isAllowedOrigin('http://localhost.evil.example', const []), isFalse);
    expect(isAllowedOrigin('https://evil.example', const []), isFalse);
    expect(isAllowedOrigin('null', const []), isFalse);
    expect(isAllowedOrigin(null, const []), isFalse);
    expect(
      isAllowedOrigin('https://fcm.example.com', const [
        'https://fcm.example.com',
      ]),
      isTrue,
    );
  });

  test('host: only this computer on the bound port', () {
    expect(isAllowedHost('127.0.0.1:15037', 15037), isTrue);
    expect(isAllowedHost('localhost:15037', 15037), isTrue);
    expect(isAllowedHost('evil.example:15037', 15037), isFalse);
    expect(isAllowedHost('127.0.0.1:80', 15037), isFalse);
    expect(isAllowedHost(null, 15037), isFalse);
  });

  group('findAdb', () {
    String? find({
      String? flag,
      Map<String, String> environment = const {},
      bool windows = false,
      bool mac = true,
      Set<String> files = const {},
    }) => findAdb(
      flag: flag,
      environment: environment,
      isWindows: windows,
      isMacOS: mac,
      exists: files.contains,
    );

    test('--adb wins when the file exists, and only then', () {
      expect(
        find(
          flag: '/my/adb',
          environment: const {'PATH': '/usr/bin'},
          files: const {'/my/adb', '/usr/bin/adb'},
        ),
        '/my/adb',
      );
      expect(
        find(
          flag: '/missing/adb',
          environment: const {'PATH': '/usr/bin'},
          files: const {'/usr/bin/adb'},
        ),
        isNull,
      );
    });

    test('then PATH', () {
      expect(
        find(
          environment: const {'PATH': '/usr/local/bin:/usr/bin'},
          files: const {'/usr/bin/adb'},
        ),
        '/usr/bin/adb',
      );
    });

    test('then ANDROID_HOME, then ANDROID_SDK_ROOT', () {
      const environment = {
        'ANDROID_HOME': '/sdk1',
        'ANDROID_SDK_ROOT': '/sdk2',
      };
      expect(
        find(
          environment: environment,
          files: const {'/sdk1/platform-tools/adb', '/sdk2/platform-tools/adb'},
        ),
        '/sdk1/platform-tools/adb',
      );
      expect(
        find(
          environment: environment,
          files: const {'/sdk2/platform-tools/adb'},
        ),
        '/sdk2/platform-tools/adb',
      );
    });

    test('then the default SDK folder on macOS, Linux and Windows', () {
      expect(
        find(
          environment: const {'HOME': '/Users/x'},
          files: const {'/Users/x/Library/Android/sdk/platform-tools/adb'},
        ),
        '/Users/x/Library/Android/sdk/platform-tools/adb',
      );
      expect(
        find(
          mac: false,
          environment: const {'HOME': '/home/x'},
          files: const {'/home/x/Android/Sdk/platform-tools/adb'},
        ),
        '/home/x/Android/Sdk/platform-tools/adb',
      );
      expect(
        find(
          windows: true,
          mac: false,
          environment: const {
            'PATH': r'C:\tools;C:\Windows',
            'LOCALAPPDATA': r'C:\Users\x\AppData\Local',
          },
          files: const {
            r'C:\Users\x\AppData\Local\Android\Sdk\platform-tools\adb.exe',
          },
        ),
        r'C:\Users\x\AppData\Local\Android\Sdk\platform-tools\adb.exe',
      );
      expect(
        find(
          windows: true,
          mac: false,
          environment: const {'PATH': r'C:\tools;C:\Windows'},
          files: const {r'C:\tools\adb.exe'},
        ),
        r'C:\tools\adb.exe',
      );
    });

    test('null when adb is nowhere', () {
      expect(
        find(environment: const {'PATH': '/usr/bin', 'HOME': '/h'}),
        isNull,
      );
    });
  });

  group('parseArguments', () {
    test('defaults', () {
      final options = parseArguments(const []);
      expect(options.adb, isNull);
      expect(options.allowedOrigins, isEmpty);
      expect(options.help, isFalse);
    });

    test('--adb and repeated --allow-origin (trailing slash dropped)', () {
      final options = parseArguments(const [
        '--adb',
        '/x/adb',
        '--allow-origin',
        'https://a.example/',
        '--allow-origin',
        'https://b.example',
      ]);
      expect(options.adb, '/x/adb');
      expect(options.allowedOrigins, [
        'https://a.example',
        'https://b.example',
      ]);
    });

    test('--help', () {
      expect(parseArguments(const ['--help']).help, isTrue);
    });

    test('a missing value or an unknown option is an error', () {
      expect(() => parseArguments(const ['--adb']), throwsFormatException);
      expect(
        () => parseArguments(const ['--port', '1']),
        throwsFormatException,
      );
    });
  });
}
