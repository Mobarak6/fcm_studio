# M5.1: Phones on the Web through a Local Bridge — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The FCM Studio web build reaches phones through a small local program, `fcm_bridge.dart`. The bridge runs the computer's adb, so the phone stays shared with IDEs. WebUSB stays as the second way.

**Architecture:**
- **The bridge:** a dependency-free Dart script in `web/` (so every web build serves it). It listens on `127.0.0.1:15037`, accepts only FCM Studio origins, and runs only the seven adb commands `AdbCommands` uses.
- **The page:** a `BridgeClient` owns the WebSocket. `BridgeDeviceShell` and `BridgeAdbService` reuse `AdbCommands`.
- **One list:** `WebPhones` merges WebUSB and bridge phones into the single `AdbService` that `DevicesBloc` already consumes.

**Tech Stack:**
- Flutter 3.44.9 / Dart 3.12 (the app); Dart 3.0 language level (the bridge script).
- `dart:io` `HttpServer` + `WebSocketTransformer` (bridge), `package:web` `WebSocket` (page).
- flutter_bloc, equatable, sembast (settings).

**Spec:** [docs/superpowers/specs/2026-10-05-web-bridge-design.md](../specs/2026-10-05-web-bridge-design.md). It builds on the main spec and the WebUSB design.

## Global Constraints

**The bridge file:**
- It is `web/fcm_bridge.dart`, and its first line is `// @dart=3.0`.
- It imports only `dart:` libraries and uses only APIs that exist in Dart 3.0.
- It never calls `print`; it writes with `stdout.writeln` and `stderr.writeln`.

**Protocol and security:**
- The bridge protocol is `1` and the port is `15037`. The page connects to `ws://127.0.0.1:15037`.
- The bridge binds `InternetAddress.loopbackIPv4` only.
- It allows these origins: `http://localhost:<any port>`, `http://127.0.0.1:<any port>`, each `--allow-origin`, and `hostedOrigins` (an empty list in the file).
- The Host header must be `127.0.0.1:<bound port>` or `localhost:<bound port>`.
- Allowed commands, exactly (spec §4.3):

  | kind | text |
  |---|---|
  | shell | `getprop ro.product.marketname; getprop ro.product.model; getprop ro.product.brand; getprop ro.build.version.release` |
  | shell | `pm list packages -3` |
  | shell | `monkey -p <package> -c android.intent.category.LAUNCHER 1` |
  | shell | `am force-stop <package>` |
  | shell | `pidof <package>` |
  | execOut | `run-as <package> cat shared_prefs/com.google.android.gms.appid.xml` |
  | logcat | `--pid=<digits>` |

  The patterns:
  - package `^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$`;
  - serial `^[A-Za-z0-9._:-]+$`, and it must not start with `-`;
  - digits `^[0-9]{1,10}$`.

**Data handling:**
- Device tokens are never logged or printed: the bridge never prints command output.
- Never run `logcat -c`.

**Scope:**
- Desktop (adb) behaviour is unchanged. On desktop, `AdbDevice.link` is null.
- **Copy:** the user-facing texts in spec §6 and §7, and the hello problem `adb wasn't found. Start the bridge with --adb <path to adb>.`

**Code style (repo lints):**
- single quotes, `prefer_final_locals`, `unawaited_futures`;
- braces on every `if` body;
- private named constructor parameters (`required this._x`, called as `x:`).

**Git:**
- Commit on `main`.
- Every commit message ends with `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`.
- Never stage `.metadata`, `devtools_options.yaml`, `.superpowers/`, `config/oauth.example.json` or `config/oauth.json`.

## Review Focus

1. **Two FCM Studio tabs on one bridge:** closing or killing in one tab never touches the other tab's adb processes. Pinned by the Task 2 test "two pages keep their processes apart".
2. **UTF-8 split across output chunks:** a multi-byte character split between two `stdout` messages decodes correctly in `run`. Pinned by the Task 4 test "a character split across chunks decodes whole".
3. **Restarting the bridge with `--adb` after a `noAdb` hello:** the page moves from `noAdb` to `connected` with no click. Pinned by the Task 3 test "restarting the bridge with adb moves noAdb to connected".
4. **Garbage on the wire** (non-JSON text, unknown types, unknown ids, broken base64): ignored, and the connection keeps working. Pinned by the Task 2 test "garbage from the page is ignored" and the Task 3 test "garbage from the bridge is ignored".
5. **adb server restarted while connected** (an IDE restarts it): `track-devices` ends, the bridge phones vanish, and they come back by themselves. Pinned by the Task 5 test "a bridge tracker that ends is started again while connected".

## Decisions made while planning (rulings against the spec's silence)

- **`PlatformFeatures.canReadPhones` is removed** (Task 7). The spec makes it true on every web value, and it was already true on desktop. So it's always true, and **From device…** always shows.
- **`BridgeControl` has `request` and `download`** next to `status`, `statuses`, `start`, `connect` and `disconnect`.
  - Tests fake one object, and `AppDependencies` wires one object.
  - `BridgeDeviceShell`, `BridgeAdbService`, `WebPhones` and `BridgeCubit` all depend on `BridgeControl`; only `AppDependencies` creates a `BridgeClient`.
- **A `--adb` path that doesn't exist** means "adb not found". The bridge doesn't fall back to `PATH`.
- **A refused command's message** follows the shells' convention: `` `adb -s S shell …` (through the bridge) failed: fcm_bridge refused this command. `` Task 8 updates spec §7 to match.
- **The USB-unavailable texts** are "Connecting a phone over USB needs Chrome or Edge. Use the bridge instead." and "Connecting a phone over USB needs FCM Studio opened over https. Use the bridge instead."
- **`BridgeClient.defaultBackoff` is a copy of `DevicesBloc.defaultBackoff`** (1, 2, 4, 8, 16, 30 s). The data layer doesn't import the bloc layer.
- **Bridge tests live in `test/web/`**, mirroring the file's place in `web/`.

## File structure

| File | Responsibility |
|---|---|
| `web/fcm_bridge.dart` (new) | The bridge: rules (allow-lists, adb discovery, arguments) and server (`BridgeServer`, `BridgeSession`, `main`) |
| `lib/features/devices/data/bridge/bridge_protocol.dart` (new) | `BridgeProtocol` constants shared with the bridge |
| `lib/features/devices/data/bridge/bridge_status.dart` (new) | `sealed class BridgeStatus` and its seven states |
| `lib/features/devices/data/bridge/bridge_channel.dart` (new) | `BridgeChannel`, `BridgeConnector`, `BridgeUnreachableException` |
| `lib/features/devices/data/bridge/bridge_client.dart` (new) | `BridgeOutput`, `BridgeCall`, `BridgeControl`, `BridgeClient` |
| `lib/features/devices/data/bridge/bridge_device_shell.dart` (new) | `BridgeDeviceShell implements DeviceShell` |
| `lib/features/devices/data/bridge/bridge_adb_service.dart` (new) | `BridgeAdbService implements AdbService` |
| `lib/features/devices/data/bridge/bridge_platform.dart`, `bridge_platform_stub.dart`, `browser/bridge_platform_web.dart` (new) | The browser WebSocket, Local Network Access check, local-page check and download; stubs on the VM |
| `lib/features/devices/data/web_phones.dart` (new) | `WebPhones implements AdbService`: merges, labels and routes |
| `lib/features/devices/cubit/bridge_cubit.dart` (new) | `BridgeCubit` (state `BridgeStatus`) for the UI |
| `lib/features/devices/domain/adb_device.dart` | + `PhoneLink`, `AdbDevice.link`, `withLink` |
| `lib/features/settings/data/settings_repository.dart` | + `readBridgeAutoConnect` / `writeBridgeAutoConnect` |
| `lib/app/dependencies.dart`, `lib/app/app.dart` | Wiring: `BridgeClient`, `WebPhones`, `BridgeCubit`; all web values tracked |
| `lib/core/platform/platform_capabilities.dart`, `lib/features/composer/view/target_picker.dart` | Remove `canReadPhones` |
| `lib/features/devices/view/devices_screen.dart` | Two buttons, bridge bar and menu, link labels, web texts |
| `test/web/fcm_bridge_rules_test.dart`, `test/web/fcm_bridge_server_test.dart`, `test/web/fcm_bridge_sync_test.dart` (new) | The bridge's tests |
| `test/features/devices/bridge/*_test.dart`, `test/features/devices/web_phones_test.dart`, `test/features/devices/bridge_cubit_test.dart` (new) | The page's tests |
| `test/helpers/eventually.dart`, `fake_adb_process.dart`, `fake_bridge_channel.dart`, `fake_bridge_control.dart` (new) | Helpers |

---

### Task 1: The bridge's rules (allow-lists, adb discovery, command line)

**Files:**
- Create: `web/fcm_bridge.dart`
- Create: `test/web/fcm_bridge_rules_test.dart`
- Create: `test/web/fcm_bridge_sync_test.dart`

**Interfaces:**
- Consumes: `AdbCommands`, `PhoneCommand`, `PhoneCommandKind`, `DeviceShell`, `ProcessOutput`, `RunningProcess` (existing); `FakeRunningProcess` from `test/helpers/fake_process_runner.dart` (existing).
- Produces (top level in `web/fcm_bridge.dart`):
  - constants: `const bridgeProtocol = 1`, `const bridgePort = 15037`, `const hostedOrigins = <String>[]`, `const noAdbProblem`;
  - `bool isAllowedCommand(String kind, String text)`;
  - `bool isAllowedSerial(String serial)`;
  - `bool isAllowedOrigin(String? origin, List<String> allowed)`;
  - `bool isAllowedHost(String? host, int port)`;
  - `String? findAdb({required String? flag, required Map<String, String> environment, required bool isWindows, required bool isMacOS, required bool Function(String path) exists})`;
  - `class BridgeOptions { String? adb; List<String> allowedOrigins; bool help; }`;
  - `BridgeOptions parseArguments(List<String> arguments)` (throws `FormatException`);
  - `String normalizeOrigin(String origin)`.

- [ ] **Step 1: Write the failing rules test**

Create `test/web/fcm_bridge_rules_test.dart`:

```dart
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

  test('origins: localhost pages, --allow-origin, nothing else', () {
    expect(isAllowedOrigin('http://localhost:5050', const []), isTrue);
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
      const environment = {'ANDROID_HOME': '/sdk1', 'ANDROID_SDK_ROOT': '/sdk2'};
      expect(
        find(
          environment: environment,
          files: const {
            '/sdk1/platform-tools/adb',
            '/sdk2/platform-tools/adb',
          },
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
      expect(find(environment: const {'PATH': '/usr/bin', 'HOME': '/h'}), isNull);
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
      expect(options.allowedOrigins, ['https://a.example', 'https://b.example']);
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
```

- [ ] **Step 2: Write the failing sync test (every `AdbCommands` command is allowed)**

Create `test/web/fcm_bridge_sync_test.dart`:

```dart
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
```

- [ ] **Step 3: Run both to verify they fail**

Run: `flutter test test/web/`
Expected: FAIL; the compiler reports `Error when reading 'web/fcm_bridge.dart'` or undefined names (`isAllowedCommand` …).

- [ ] **Step 4: Write the rules half of `web/fcm_bridge.dart`**

Create `web/fcm_bridge.dart`:

```dart
// @dart=3.0
// FCM Studio bridge. Design: docs/superpowers/specs/2026-10-05-web-bridge-design.md
//
// Lets the FCM Studio web page read FCM tokens from phones through this
// computer's adb, so the phone stays shared with Android Studio and other
// tools. Run it with:
//
//   dart fcm_bridge.dart [--adb <path>] [--allow-origin <origin>]...
//
// It listens on 127.0.0.1 only, accepts only FCM Studio pages, and runs only
// the few adb commands FCM Studio needs. It imports only dart: libraries, so
// it runs without a package, and it stays at Dart 3.0 for older SDKs.

/// The page checks this against its own (bridge design §4.2). Raise it
/// whenever the allow-list or the messages change.
const bridgeProtocol = 1;

/// adb's own port is 5037.
const bridgePort = 15037;

/// The hosted FCM Studio addresses. Empty until the hosting URL is decided;
/// until then, use --allow-origin.
const hostedOrigins = <String>[];

/// Sent in `hello` and printed when adb wasn't found.
const noAdbProblem =
    "adb wasn't found. Start the bridge with --adb <path to adb>.";

const _getprop = 'getprop ro.product.marketname; getprop ro.product.model; '
    'getprop ro.product.brand; getprop ro.build.version.release';
const _tokenFile = 'shared_prefs/com.google.android.gms.appid.xml';
final _package = RegExp(r'^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$');
final _serial = RegExp(r'^[A-Za-z0-9._:-]+$');
final _pid = RegExp(r'^--pid=[0-9]{1,10}$');

/// Whether FCM Studio may run [text] as a [kind] command: only the commands
/// its token reading uses (bridge design §4.3).
bool isAllowedCommand(String kind, String text) {
  switch (kind) {
    case 'shell':
      return text == _getprop ||
          text == 'pm list packages -3' ||
          _withPackage(
            text,
            'monkey -p ',
            ' -c android.intent.category.LAUNCHER 1',
          ) ||
          _withPackage(text, 'am force-stop ', '') ||
          _withPackage(text, 'pidof ', '');
    case 'execOut':
      return _withPackage(text, 'run-as ', ' cat $_tokenFile');
    case 'logcat':
      return _pid.hasMatch(text);
    default:
      return false;
  }
}

/// [text] is [prefix], a package name, then [suffix].
bool _withPackage(String text, String prefix, String suffix) {
  if (!text.startsWith(prefix) ||
      !text.endsWith(suffix) ||
      text.length < prefix.length + suffix.length) {
    return false;
  }
  return _package.hasMatch(
    text.substring(prefix.length, text.length - suffix.length),
  );
}

/// A serial adb accepts after `-s`, which can't be mistaken for an option.
bool isAllowedSerial(String serial) =>
    _serial.hasMatch(serial) && !serial.startsWith('-');

/// Whether a page from [origin] may connect (bridge design §4.3).
bool isAllowedOrigin(String? origin, List<String> allowed) {
  if (origin == null) {
    return false;
  }
  if (allowed.contains(origin) || hostedOrigins.contains(origin)) {
    return true;
  }
  final uri = Uri.tryParse(origin);
  return uri != null &&
      uri.scheme == 'http' &&
      (uri.host == 'localhost' || uri.host == '127.0.0.1');
}

/// Whether the Host header names this computer on [port], so a site can't
/// reach the bridge through DNS rebinding.
bool isAllowedHost(String? host, int port) =>
    host == '127.0.0.1:$port' || host == 'localhost:$port';

/// Where adb is, or null (bridge design §4.1): --adb, PATH, ANDROID_HOME,
/// ANDROID_SDK_ROOT, then the Android SDK's usual folder.
String? findAdb({
  required String? flag,
  required Map<String, String> environment,
  required bool isWindows,
  required bool isMacOS,
  required bool Function(String path) exists,
}) {
  if (flag != null) {
    return exists(flag) ? flag : null;
  }
  final separator = isWindows ? r'\' : '/';
  final name = isWindows ? 'adb.exe' : 'adb';
  String inTools(String sdk) => '$sdk${separator}platform-tools$separator$name';
  final candidates = <String>[
    for (final folder
        in (environment['PATH'] ?? '').split(isWindows ? ';' : ':'))
      if (folder.isNotEmpty) '$folder$separator$name',
    for (final key in const ['ANDROID_HOME', 'ANDROID_SDK_ROOT'])
      if ((environment[key] ?? '').isNotEmpty) inTools(environment[key]!),
  ];
  final home = environment['HOME'] ?? '';
  final localAppData = environment['LOCALAPPDATA'] ?? '';
  if (isWindows) {
    if (localAppData.isNotEmpty) {
      candidates.add(inTools('$localAppData\\Android\\Sdk'));
    }
  } else if (home.isNotEmpty) {
    candidates.add(
      inTools(isMacOS ? '$home/Library/Android/sdk' : '$home/Android/Sdk'),
    );
  }
  for (final candidate in candidates) {
    if (exists(candidate)) {
      return candidate;
    }
  }
  return null;
}

/// The command line.
class BridgeOptions {
  BridgeOptions({this.adb, this.allowedOrigins = const [], this.help = false});

  final String? adb;
  final List<String> allowedOrigins;
  final bool help;
}

/// Reads the command line; throws [FormatException] for a bad one.
BridgeOptions parseArguments(List<String> arguments) {
  String? adb;
  final origins = <String>[];
  var help = false;
  for (var i = 0; i < arguments.length; i++) {
    final argument = arguments[i];
    if (argument == '--help' || argument == '-h') {
      help = true;
    } else if (argument == '--adb' || argument == '--allow-origin') {
      if (i + 1 >= arguments.length) {
        throw FormatException('$argument needs a value.');
      }
      final value = arguments[++i];
      if (argument == '--adb') {
        adb = value;
      } else {
        origins.add(normalizeOrigin(value));
      }
    } else {
      throw FormatException('Unknown option: $argument');
    }
  }
  return BridgeOptions(adb: adb, allowedOrigins: origins, help: help);
}

/// Browsers send an origin without a trailing slash.
String normalizeOrigin(String origin) =>
    origin.endsWith('/') ? origin.substring(0, origin.length - 1) : origin;
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `flutter test test/web/`
Expected: PASS (all rules tests and the sync test).

- [ ] **Step 6: Analyze**

Run: `flutter analyze web/fcm_bridge.dart test/web/`
Expected: `No issues found!` If the analyzer reports a language feature newer than 3.0 in `web/fcm_bridge.dart`, rewrite that line with 3.0 syntax. Never remove the `// @dart=3.0` line.

- [ ] **Step 7: Commit**

```bash
dart format web/fcm_bridge.dart test/web/
git add web/fcm_bridge.dart test/web/fcm_bridge_rules_test.dart test/web/fcm_bridge_sync_test.dart
git commit -m "feat: bridge rules: allowed commands, origins, adb discovery

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: The bridge server (protocol, processes, `main`)

**Files:**
- Modify: `web/fcm_bridge.dart` (add imports at the top, append the server)
- Create: `test/helpers/eventually.dart`
- Create: `test/helpers/fake_adb_process.dart`
- Create: `test/web/fcm_bridge_server_test.dart`

**Interfaces:**
- Consumes: Task 1's rules.
- Produces (in `web/fcm_bridge.dart`):
  - `const usage`;
  - `typedef StartProcess = Future<Process> Function(String executable, List<String> arguments)`;
  - `List<String> adbArguments(String serial, String kind, String text)`;
  - `class BridgeServer({required String? adbPath, required List<String> allowedOrigins, required StartProcess startProcess, required void Function(String line) log})` with `Future<void> serve(HttpServer server)`;
  - `class BridgeSession`;
  - `Future<void> main(List<String> arguments)`.
- Produces (test helpers):
  - `Future<void> eventually(bool Function() condition, {Duration timeout})`;
  - `class FakeAdbProcess implements Process` (`arguments`, `out(String)`, `err(String)`, `finish([int])`, `killed`);
  - `class FakeAdb` (`started`, `onStart`, `startError`, `Future<Process> start(String, List<String>)`).

- [ ] **Step 1: Write the helpers**

Create `test/helpers/eventually.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';

/// Waits in real time until [condition] holds, and fails after [timeout].
Future<void> eventually(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final stopwatch = Stopwatch()..start();
  while (!condition()) {
    if (stopwatch.elapsed > timeout) {
      fail('Timed out waiting for a condition.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}
```

Create `test/helpers/fake_adb_process.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A dart:io [Process] the test drives, standing in for adb behind the
/// bridge. [arguments] starts with the executable.
class FakeAdbProcess implements Process {
  FakeAdbProcess(this.arguments);

  final List<String> arguments;
  final StreamController<List<int>> _stdout = StreamController<List<int>>();
  final StreamController<List<int>> _stderr = StreamController<List<int>>();
  final Completer<int> _exit = Completer<int>();
  bool killed = false;

  void out(String text) => _stdout.add(utf8.encode(text));

  void err(String text) => _stderr.add(utf8.encode(text));

  void finish([int code = 0]) {
    if (!_exit.isCompleted) {
      unawaited(_stdout.close());
      unawaited(_stderr.close());
      _exit.complete(code);
    }
  }

  @override
  Stream<List<int>> get stdout => _stdout.stream;

  @override
  Stream<List<int>> get stderr => _stderr.stream;

  @override
  Future<int> get exitCode => _exit.future;

  @override
  int get pid => 4242;

  @override
  IOSink get stdin => throw UnimplementedError('The bridge never writes to adb.');

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killed = true;
    finish(-15);
    return true;
  }
}

/// Starts [FakeAdbProcess]es and keeps them. [onStart] scripts each one.
class FakeAdb {
  final List<FakeAdbProcess> started = [];
  void Function(FakeAdbProcess process)? onStart;
  Object? startError;

  Future<Process> start(String executable, List<String> arguments) async {
    final error = startError;
    if (error != null) {
      throw error;
    }
    final process = FakeAdbProcess([executable, ...arguments]);
    started.add(process);
    onStart?.call(process);
    return process;
  }
}
```

- [ ] **Step 2: Write the failing server test**

Create `test/web/fcm_bridge_server_test.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../web/fcm_bridge.dart';
import '../helpers/eventually.dart';
import '../helpers/fake_adb_process.dart';

const adbPath = '/sdk/platform-tools/adb';
const serial = 'DETWFUOZZHZ5SWFQ';
const app = 'com.syldel.delivery';
const tokenFile = 'shared_prefs/com.google.android.gms.appid.xml';

/// A page connected to the bridge, keeping every message it got.
class TestPage {
  TestPage._(this.socket) {
    socket.listen(
      (data) {
        received.add(jsonDecode(data as String) as Map<String, Object?>);
        _changes.add(null);
      },
      onDone: () => unawaited(_changes.close()),
    );
  }

  static Future<TestPage> open(
    int port, {
    String? origin = 'http://localhost:5050',
  }) async => TestPage._(
    await WebSocket.connect(
      'ws://127.0.0.1:$port',
      headers: {if (origin != null) 'origin': origin},
    ),
  );

  final WebSocket socket;
  final List<Map<String, Object?>> received = [];
  final StreamController<void> _changes = StreamController<void>.broadcast();

  void send(Map<String, Object?> message) => socket.add(jsonEncode(message));

  void sendText(String text) => socket.add(text);

  /// The first message so far, or to come, that matches [test].
  Future<Map<String, Object?>> waitFor(
    bool Function(Map<String, Object?> message) test,
  ) async {
    while (true) {
      for (final message in received) {
        if (test(message)) {
          return message;
        }
      }
      await _changes.stream.first.timeout(const Duration(seconds: 2));
    }
  }

  /// What arrived on [stream] (`stdout` or `stderr`) for request [id].
  String output(int id, String stream) => received
      .where((m) => m['id'] == id && m['type'] == stream)
      .map((m) => utf8.decode(base64Decode(m['data']! as String)))
      .join();
}

void main() {
  late FakeAdb adb;

  setUp(() => adb = FakeAdb());

  /// The bridge on a free port, with [adb] behind it. [adbPathOrNull] null
  /// is a bridge that found no adb.
  Future<(HttpServer, List<String>)> startBridge({
    String? adbPathOrNull = adbPath,
    List<String> allowed = const [],
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final log = <String>[];
    unawaited(
      BridgeServer(
        adbPath: adbPathOrNull,
        allowedOrigins: allowed,
        startProcess: adb.start,
        log: log.add,
      ).serve(server),
    );
    return (server, log);
  }

  test('says hello with the adb it found', () async {
    final (server, _) = await startBridge();
    final page = await TestPage.open(server.port);
    expect(await page.waitFor((m) => m['type'] == 'hello'), {
      'type': 'hello',
      'protocol': bridgeProtocol,
      'adb': adbPath,
    });
  });

  test('without adb, hello says how to fix it and requests fail', () async {
    final (server, _) = await startBridge(adbPathOrNull: null);
    final page = await TestPage.open(server.port);
    expect(await page.waitFor((m) => m['type'] == 'hello'), {
      'type': 'hello',
      'protocol': bridgeProtocol,
      'adb': null,
      'problem': noAdbProblem,
    });
    page.send({'type': 'track', 'id': 1});
    expect(await page.waitFor((m) => m['id'] == 1), {
      'type': 'error',
      'id': 1,
      'message': noAdbProblem,
    });
  });

  test('run passes the command to adb and streams its output', () async {
    adb.onStart = (process) => process
      ..out('package:$app\n')
      ..err('warning\n')
      ..finish(0);
    final (server, _) = await startBridge();
    final page = await TestPage.open(server.port);
    page.send({
      'type': 'run',
      'id': 7,
      'serial': serial,
      'kind': 'shell',
      'text': 'pm list packages -3',
    });
    expect(await page.waitFor((m) => m['type'] == 'exit'), {
      'type': 'exit',
      'id': 7,
      'code': 0,
    });
    expect(adb.started.single.arguments, [
      adbPath,
      '-s',
      serial,
      'shell',
      'pm list packages -3',
    ]);
    expect(page.output(7, 'stdout'), 'package:$app\n');
    expect(page.output(7, 'stderr'), 'warning\n');
  });

  test('exec-out and logcat split their arguments like the desktop app', () async {
    adb.onStart = (process) => process.finish(0);
    final (server, _) = await startBridge();
    final page = await TestPage.open(server.port);
    page
      ..send({
        'type': 'run',
        'id': 1,
        'serial': serial,
        'kind': 'execOut',
        'text': 'run-as $app cat $tokenFile',
      })
      ..send({
        'type': 'run',
        'id': 2,
        'serial': serial,
        'kind': 'logcat',
        'text': '--pid=4242',
      });
    await page.waitFor((m) => m['type'] == 'exit' && m['id'] == 1);
    await page.waitFor((m) => m['type'] == 'exit' && m['id'] == 2);
    expect(adb.started.map((p) => p.arguments), [
      [adbPath, '-s', serial, 'exec-out', 'run-as', app, 'cat', tokenFile],
      [adbPath, '-s', serial, 'logcat', '--pid=4242'],
    ]);
  });

  test('a command FCM Studio never sends is refused and never reaches adb', () async {
    final (server, log) = await startBridge();
    final page = await TestPage.open(server.port);
    page.send({
      'type': 'run',
      'id': 1,
      'serial': serial,
      'kind': 'shell',
      'text': 'pm uninstall $app',
    });
    expect(await page.waitFor((m) => m['id'] == 1), {
      'type': 'error',
      'id': 1,
      'message': 'fcm_bridge refused this command.',
    });
    expect(adb.started, isEmpty);
    expect(log, contains('Refused a command: shell pm uninstall $app'));
  });

  test('track streams adb track-devices', () async {
    adb.onStart = (process) => process.out('0000');
    final (server, _) = await startBridge();
    final page = await TestPage.open(server.port);
    page.send({'type': 'track', 'id': 3});
    await page.waitFor((m) => m['type'] == 'stdout' && m['id'] == 3);
    expect(page.output(3, 'stdout'), '0000');
    expect(adb.started.single.arguments, [adbPath, 'track-devices', '-l']);
  });

  test('kill stops a running command', () async {
    final (server, _) = await startBridge();
    final page = await TestPage.open(server.port);
    page.send({
      'type': 'run',
      'id': 4,
      'serial': serial,
      'kind': 'logcat',
      'text': '--pid=42',
    });
    await eventually(() => adb.started.isNotEmpty);
    page.send({'type': 'kill', 'id': 4});
    expect(await page.waitFor((m) => m['type'] == 'exit'), {
      'type': 'exit',
      'id': 4,
      'code': -15,
    });
    expect(adb.started.single.killed, isTrue);
  });

  test('closing the page kills what it started', () async {
    final (server, _) = await startBridge();
    final page = await TestPage.open(server.port);
    page.send({'type': 'track', 'id': 5});
    await eventually(() => adb.started.isNotEmpty);
    await page.socket.close();
    await eventually(() => adb.started.single.killed);
  });

  test('two pages keep their processes apart', () async {
    final (server, _) = await startBridge();
    final first = await TestPage.open(server.port);
    final second = await TestPage.open(server.port);
    first.send({'type': 'track', 'id': 1});
    await eventually(() => adb.started.length == 1);
    second.send({'type': 'track', 'id': 1});
    await eventually(() => adb.started.length == 2);

    second.send({'type': 'kill', 'id': 1});
    await eventually(() => adb.started[1].killed);
    expect(adb.started[0].killed, isFalse);

    await second.socket.close();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(adb.started[0].killed, isFalse);
    await first.socket.close();
    await eventually(() => adb.started[0].killed);
  });

  test('garbage from the page is ignored', () async {
    adb.onStart = (process) => process.finish(0);
    final (server, _) = await startBridge();
    final page = await TestPage.open(server.port);
    page
      ..sendText('not json')
      ..sendText('[1, 2]')
      ..send({'type': 'run'})
      ..send({'type': 'dance', 'id': 9})
      ..send({'type': 'kill', 'id': 99})
      ..send({'type': 'track', 'id': 10});
    expect(await page.waitFor((m) => m['id'] == 9), {
      'type': 'error',
      'id': 9,
      'message': 'fcm_bridge does not know "dance" requests.',
    });
    expect(await page.waitFor((m) => m['type'] == 'exit'), {
      'type': 'exit',
      'id': 10,
      'code': 0,
    });
  });

  test("adb that can't start is reported", () async {
    adb.startError = const ProcessException('adb', [], 'No such file');
    final (server, _) = await startBridge();
    final page = await TestPage.open(server.port);
    page.send({'type': 'track', 'id': 1});
    final error = await page.waitFor((m) => m['id'] == 1);
    expect(error['type'], 'error');
    expect(error['message'], startsWith('Could not start adb at $adbPath'));
  });

  test('pages from other sites are refused; --allow-origin lets one in', () async {
    final (server, log) = await startBridge(
      allowed: const ['https://fcm.example.com'],
    );
    await expectLater(
      TestPage.open(server.port, origin: 'https://evil.example'),
      throwsA(isA<WebSocketException>()),
    );
    expect(
      log,
      contains(
        'Refused a connection from https://evil.example. '
        'To allow it: --allow-origin https://evil.example',
      ),
    );
    final allowed = await TestPage.open(
      server.port,
      origin: 'https://fcm.example.com',
    );
    expect((await allowed.waitFor((m) => m['type'] == 'hello'))['adb'], adbPath);
  });

  test('a page with no origin is refused', () async {
    final (server, log) = await startBridge();
    await expectLater(
      TestPage.open(server.port, origin: null),
      throwsA(isA<WebSocketException>()),
    );
    expect(log, contains('Refused a connection with no origin.'));
  });

  test('plain requests get a short explanation', () async {
    final (server, _) = await startBridge();
    final client = HttpClient();
    addTearDown(client.close);
    final request = await client.getUrl(
      Uri.parse('http://127.0.0.1:${server.port}/'),
    );
    final response = await request.close();
    expect(response.statusCode, HttpStatus.badRequest);
    expect(
      await response.transform(utf8.decoder).join(),
      'FCM Studio bridge: open FCM Studio to use it.',
    );
  });
}
```

- [ ] **Step 3: Run it to verify it fails**

Run: `flutter test test/web/fcm_bridge_server_test.dart`
Expected: FAIL to compile: `BridgeServer` isn't defined.

- [ ] **Step 4: Add the server to `web/fcm_bridge.dart`**

Insert these imports directly below the header comment block (above `const bridgeProtocol`):

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
```

Append to the end of the file:

```dart
/// What `--help` prints.
const usage = '''
FCM Studio bridge: lets the FCM Studio web page read FCM tokens from phones
through this computer's adb, so the phone stays shared with your IDE.

Usage: dart fcm_bridge.dart [--adb <path>] [--allow-origin <origin>]...

  --adb <path>             the adb to use (default: PATH, ANDROID_HOME,
                           ANDROID_SDK_ROOT, then the Android SDK's folder)
  --allow-origin <origin>  also accept FCM Studio from this address,
                           e.g. https://fcm-studio.example.com
  --help                   show this help
''';

/// Starts a process; tests pass a fake.
typedef StartProcess = Future<Process> Function(
  String executable,
  List<String> arguments,
);

/// adb's arguments for a `run` request, exactly as FCM Studio's desktop app
/// builds them (bridge design §4.2).
List<String> adbArguments(String serial, String kind, String text) => [
      '-s',
      serial,
      ...switch (kind) {
        'shell' => ['shell', text],
        'execOut' => ['exec-out', ...text.split(' ')],
        _ => ['logcat', ...text.split(' ')],
      },
    ];

/// Accepts FCM Studio pages and serves each one (bridge design §4.1, §4.3).
class BridgeServer {
  BridgeServer({
    required this.adbPath,
    required this.allowedOrigins,
    required this.startProcess,
    required this.log,
  });

  final String? adbPath;
  final List<String> allowedOrigins;
  final StartProcess startProcess;
  final void Function(String line) log;

  /// Serves [server] until it closes.
  Future<void> serve(HttpServer server) async {
    await for (final request in server) {
      unawaited(_handle(request, server.port));
    }
  }

  Future<void> _handle(HttpRequest request, int port) async {
    try {
      if (!WebSocketTransformer.isUpgradeRequest(request)) {
        request.response
          ..statusCode = HttpStatus.badRequest
          ..write('FCM Studio bridge: open FCM Studio to use it.');
        await request.response.close();
        return;
      }
      final host = '${request.headers.host}:${request.headers.port}';
      final origin = request.headers.value('origin');
      if (!isAllowedHost(host, port)) {
        log('Refused a connection for host $host.');
        await _refuse(request);
        return;
      }
      if (!isAllowedOrigin(origin, allowedOrigins)) {
        log(origin == null
            ? 'Refused a connection with no origin.'
            : 'Refused a connection from $origin. '
                'To allow it: --allow-origin $origin');
        await _refuse(request);
        return;
      }
      final socket = await WebSocketTransformer.upgrade(request);
      log('FCM Studio connected ($origin).');
      await BridgeSession(
        socket: socket,
        adbPath: adbPath,
        startProcess: startProcess,
        log: log,
      ).run();
      log('FCM Studio disconnected ($origin).');
    } on Object catch (error) {
      log('A connection failed: $error');
    }
  }

  Future<void> _refuse(HttpRequest request) async {
    request.response.statusCode = HttpStatus.forbidden;
    await request.response.close();
  }
}

/// One page's connection: its requests, and the adb processes they started.
/// When it closes, they are all killed.
class BridgeSession {
  BridgeSession({
    required this.socket,
    required this.adbPath,
    required this.startProcess,
    required this.log,
  });

  final WebSocket socket;
  final String? adbPath;
  final StartProcess startProcess;
  final void Function(String line) log;
  final Map<int, Process> _processes = {};
  bool _closed = false;

  Future<void> run() async {
    final hello = <String, Object?>{
      'type': 'hello',
      'protocol': bridgeProtocol,
      'adb': adbPath,
    };
    if (adbPath == null) {
      hello['problem'] = noAdbProblem;
    }
    _send(hello);
    try {
      await for (final message in socket) {
        if (message is String) {
          _onMessage(message);
        }
      }
    } on Object {
      // A broken connection ends the session like a closed one.
    } finally {
      _closed = true;
      for (final process in _processes.values) {
        process.kill();
      }
      _processes.clear();
    }
  }

  void _onMessage(String text) {
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      return;
    }
    if (decoded is! Map<String, Object?>) {
      return;
    }
    final id = decoded['id'];
    if (id is! int) {
      return;
    }
    final type = decoded['type'];
    if (type == 'track') {
      unawaited(_start(id, const ['track-devices', '-l']));
    } else if (type == 'run') {
      _run(id, decoded['serial'], decoded['kind'], decoded['text']);
    } else if (type == 'kill') {
      _processes.remove(id)?.kill();
    } else {
      _send({
        'type': 'error',
        'id': id,
        'message': 'fcm_bridge does not know "$type" requests.',
      });
    }
  }

  void _run(int id, Object? serial, Object? kind, Object? text) {
    if (serial is! String ||
        kind is! String ||
        text is! String ||
        !isAllowedSerial(serial) ||
        !isAllowedCommand(kind, text)) {
      log('Refused a command: ${kind is String ? kind : '?'} '
          '${text is String ? text : ''}');
      _send({
        'type': 'error',
        'id': id,
        'message': 'fcm_bridge refused this command.',
      });
      return;
    }
    unawaited(_start(id, adbArguments(serial, kind, text)));
  }

  Future<void> _start(int id, List<String> arguments) async {
    final adb = adbPath;
    if (adb == null) {
      _send({'type': 'error', 'id': id, 'message': noAdbProblem});
      return;
    }
    final Process process;
    try {
      process = await startProcess(adb, arguments);
    } on Object catch (error) {
      _send({
        'type': 'error',
        'id': id,
        'message': 'Could not start adb at $adb: $error',
      });
      return;
    }
    if (_closed) {
      process.kill();
      return;
    }
    _processes[id] = process;
    final output = Future.wait([
      process.stdout
          .listen((data) => _send({
                'type': 'stdout',
                'id': id,
                'data': base64Encode(data),
              }))
          .asFuture<void>(),
      process.stderr
          .listen((data) => _send({
                'type': 'stderr',
                'id': id,
                'data': base64Encode(data),
              }))
          .asFuture<void>(),
    ]);
    final code = await process.exitCode;
    try {
      // A helper (the adb server) may keep a pipe open, or a pipe broke.
      await output.timeout(const Duration(seconds: 1));
    } on Object {
      // Send the exit anyway.
    }
    _processes.remove(id);
    _send({'type': 'exit', 'id': id, 'code': code});
  }

  void _send(Map<String, Object?> message) {
    if (_closed || socket.closeCode != null) {
      return;
    }
    socket.add(jsonEncode(message));
  }
}

Future<void> main(List<String> arguments) async {
  final BridgeOptions options;
  try {
    options = parseArguments(arguments);
  } on FormatException catch (error) {
    stderr
      ..writeln(error.message)
      ..write(usage);
    exitCode = 64;
    return;
  }
  if (options.help) {
    stdout.write(usage);
    return;
  }
  final adb = findAdb(
    flag: options.adb,
    environment: Platform.environment,
    isWindows: Platform.isWindows,
    isMacOS: Platform.isMacOS,
    exists: (path) => File(path).existsSync(),
  );
  final HttpServer server;
  try {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, bridgePort);
  } on SocketException {
    stderr.writeln(
      'Port $bridgePort is in use; is another bridge already running?',
    );
    exitCode = 1;
    return;
  }
  if (adb == null) {
    stderr.writeln(noAdbProblem);
  }
  stdout.writeln(
    'FCM Studio bridge ready on 127.0.0.1:$bridgePort '
    '(adb: ${adb ?? 'not found'}). Keep this window open.',
  );
  await BridgeServer(
    adbPath: adb,
    allowedOrigins: options.allowedOrigins,
    startProcess: Process.start,
    log: stdout.writeln,
  ).serve(server);
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `flutter test test/web/`
Expected: PASS (rules, sync and server tests).
- If "says hello" fails with a `WebSocketException`, the Host check is wrong: print `request.headers.host` / `request.headers.port` in a scratch run.
- Then fix the server's `host` string; never loosen `isAllowedHost`.

- [ ] **Step 6: Smoke-test the script and the web build copy**

Run: `dart web/fcm_bridge.dart --help; echo "exit $?"; dart web/fcm_bridge.dart --port 1; echo "exit $?"`
Expected: the usage text and `exit 0`; then `Unknown option: --port`, the usage text, and `exit 64`.

Run: `flutter build web > /tmp/fcm_bridge_build.log 2>&1; tail -3 /tmp/fcm_bridge_build.log; test -f build/web/fcm_bridge.dart && echo COPIED`
Expected: the build succeeds and `COPIED` is printed.
- If the build tries to compile `web/fcm_bridge.dart`, stop: that contradicts spec §3. Rule on a location (for example `tool/fcm_bridge.dart`, with a copy step) and record the ruling.

- [ ] **Step 7: Analyze and commit**

```bash
flutter analyze web/fcm_bridge.dart test/web/ test/helpers/
dart format web/fcm_bridge.dart test/web/ test/helpers/eventually.dart test/helpers/fake_adb_process.dart
git add web/fcm_bridge.dart test/web/fcm_bridge_server_test.dart test/helpers/eventually.dart test/helpers/fake_adb_process.dart
git commit -m "feat: bridge server: hello, run/track/kill over a loopback WebSocket

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

Expected from analyze: `No issues found!`

---

### Task 3: The page's bridge client

**Files:**
- Create: `lib/features/devices/data/bridge/bridge_protocol.dart`
- Create: `lib/features/devices/data/bridge/bridge_status.dart`
- Create: `lib/features/devices/data/bridge/bridge_channel.dart`
- Create: `lib/features/devices/data/bridge/bridge_client.dart`
- Create: `test/helpers/fake_bridge_channel.dart`
- Create: `test/features/devices/bridge/bridge_client_test.dart`
- Modify: `test/web/fcm_bridge_sync_test.dart` (add the constants test)

**Interfaces:**
- Consumes: `AdbException` (existing); the bridge constants (Task 1) in the sync test only.
- Produces:
  - `abstract final class BridgeProtocol { static const version = 1; static const port = 15037; static final Uri url; static const startCommand = 'dart fcm_bridge.dart'; }`.
  - `sealed class BridgeStatus` with `BridgeOff()`, `BridgeConnecting()`, `BridgeConnected(String adbPath)`, `BridgeNotRunning()`, `BridgeWrongVersion(int bridgeProtocol)`, `BridgeNoAdb(String problem)`, `BridgeBlocked()`.
  - `abstract interface class BridgeChannel { Stream<String> get messages; void send(String message); Future<void> close(); }`, `typedef BridgeConnector = Future<BridgeChannel> Function(Uri url)`, `class BridgeUnreachableException`.
  - `class BridgeOutput { List<int> bytes; bool isError; }`.
  - `class BridgeCall { int id; Stream<BridgeOutput> output; Future<int> exitCode; void kill(); }`.
  - `abstract interface class BridgeControl { BridgeStatus get status; Stream<BridgeStatus> get statuses; Future<void> start(); void connect(); Future<void> disconnect(); void download(); BridgeCall request(Map<String, Object?> message); }`.
  - `class BridgeClient implements BridgeControl`:
    - constructor `({required BridgeConnector connector, required Future<bool> Function() readAutoConnect, required Future<void> Function(bool on) writeAutoConnect, Future<bool> Function() isBlocked, void Function() download, bool alwaysAutoConnect = false, Duration Function(int attempt) backoff, Duration helloTimeout = 5 s})`;
    - statics `notConnectedMessage`, `stoppedMessage`, `noAdbProblem`, `defaultBackoff`;
    - `Future<void> dispose()`.
  - Test helpers:
    - `FakeBridgeChannel` (`fromBridge`, `hello`, `drop`, `sent`, `runs`, `closed`);
    - `FakeBridgeConnector` (`connect`, `channels`, `running`, `attempts`);
    - `Future<(BridgeClient, FakeBridgeChannel)> connectedBridgeClient()`.

- [ ] **Step 1: Write the protocol, status and channel types (no logic yet)**

Create `lib/features/devices/data/bridge/bridge_protocol.dart`:

```dart
/// What the page and fcm_bridge.dart agree on (bridge design §4.2). A test
/// checks these against the bridge's own constants.
abstract final class BridgeProtocol {
  static const version = 1;
  static const port = 15037;
  static final url = Uri.parse('ws://127.0.0.1:$port');

  /// What the Devices screen tells people to run.
  static const startCommand = 'dart fcm_bridge.dart';
}
```

Create `lib/features/devices/data/bridge/bridge_status.dart`:

```dart
import 'package:equatable/equatable.dart';

/// Where the page's connection to the bridge stands (bridge design §6).
sealed class BridgeStatus extends Equatable {
  const BridgeStatus();

  @override
  List<Object?> get props => const [];
}

/// Not wanted: never connected in this browser, or disconnected.
final class BridgeOff extends BridgeStatus {
  const BridgeOff();
}

final class BridgeConnecting extends BridgeStatus {
  const BridgeConnecting();
}

/// Ready: phones come from [adbPath] on the user's computer.
final class BridgeConnected extends BridgeStatus {
  const BridgeConnected(this.adbPath);

  final String adbPath;

  @override
  List<Object?> get props => [adbPath];
}

/// Nothing answered, or the bridge refused this page. Retrying.
final class BridgeNotRunning extends BridgeStatus {
  const BridgeNotRunning();
}

/// The bridge file is from another version; waits for Try again.
final class BridgeWrongVersion extends BridgeStatus {
  const BridgeWrongVersion(this.bridgeProtocol);

  final int bridgeProtocol;

  @override
  List<Object?> get props => [bridgeProtocol];
}

/// Connected, but the bridge found no adb.
final class BridgeNoAdb extends BridgeStatus {
  const BridgeNoAdb(this.problem);

  final String problem;

  @override
  List<Object?> get props => [problem];
}

/// The browser denied this site access to apps on this computer.
final class BridgeBlocked extends BridgeStatus {
  const BridgeBlocked();
}
```

Create `lib/features/devices/data/bridge/bridge_channel.dart`:

```dart
/// A WebSocket to the bridge (bridge design §4.4). The browser's is in
/// browser/bridge_platform_web.dart; tests use fakes.
abstract interface class BridgeChannel {
  /// Text frames from the bridge. Ends when the connection closes.
  Stream<String> get messages;

  void send(String message);

  Future<void> close();
}

/// Opens a channel to [url]. Throws [BridgeUnreachableException] when
/// nothing accepts the connection.
typedef BridgeConnector = Future<BridgeChannel> Function(Uri url);

/// No bridge answered (not running, refused, or blocked by the browser).
class BridgeUnreachableException implements Exception {
  const BridgeUnreachableException();

  @override
  String toString() => 'BridgeUnreachableException';
}
```

- [ ] **Step 2: Write the fake channel helper**

Create `test/helpers/fake_bridge_channel.dart`:

```dart
import 'dart:async';
import 'dart:convert';

import 'package:fcm_studio/features/devices/data/bridge/bridge_channel.dart';
import 'package:fcm_studio/features/devices/data/bridge/bridge_client.dart';
import 'package:fcm_studio/features/devices/data/bridge/bridge_status.dart';
import 'package:flutter_test/flutter_test.dart';

import 'eventually.dart';

/// The bridge's side of one connection, played by the test.
class FakeBridgeChannel implements BridgeChannel {
  final StreamController<String> _fromBridge = StreamController<String>();
  final List<Map<String, Object?>> sent = [];
  bool closed = false;

  void fromBridge(Map<String, Object?> message) =>
      _fromBridge.add(jsonEncode(message));

  void fromBridgeText(String text) => _fromBridge.add(text);

  void hello({int protocol = 1, String? adb = '/sdk/adb', String? problem}) =>
      fromBridge({
        'type': 'hello',
        'protocol': protocol,
        'adb': adb,
        if (problem != null) 'problem': problem,
      });

  /// The bridge going away.
  Future<void> drop() => _fromBridge.close();

  /// Every `run` request the page sent, in order.
  Iterable<Map<String, Object?>> get runs =>
      sent.where((message) => message['type'] == 'run');

  @override
  Stream<String> get messages => _fromBridge.stream;

  @override
  void send(String message) =>
      sent.add(jsonDecode(message) as Map<String, Object?>);

  @override
  Future<void> close() async {
    closed = true;
    if (!_fromBridge.isClosed) {
      unawaited(_fromBridge.close());
    }
  }
}

/// Connects to new [FakeBridgeChannel]s, or fails while [running] is false.
class FakeBridgeConnector {
  final List<FakeBridgeChannel> channels = [];
  bool running = true;
  int attempts = 0;

  Future<BridgeChannel> connect(Uri url) async {
    attempts++;
    if (!running) {
      throw const BridgeUnreachableException();
    }
    final channel = FakeBridgeChannel();
    channels.add(channel);
    return channel;
  }
}

/// A [BridgeClient] already connected to a [FakeBridgeChannel].
Future<(BridgeClient, FakeBridgeChannel)> connectedBridgeClient() async {
  final connector = FakeBridgeConnector();
  final client = BridgeClient(
    connector: connector.connect,
    readAutoConnect: () async => false,
    writeAutoConnect: (_) async {},
  )..connect();
  addTearDown(client.dispose);
  await eventually(() => connector.channels.isNotEmpty);
  final channel = connector.channels.single..hello();
  await eventually(() => client.status is BridgeConnected);
  return (client, channel);
}
```

- [ ] **Step 3: Write the failing client test**

Create `test/features/devices/bridge/bridge_client_test.dart`:

```dart
import 'dart:convert';

import 'package:fcm_studio/features/devices/data/adb_exception.dart';
import 'package:fcm_studio/features/devices/data/bridge/bridge_client.dart';
import 'package:fcm_studio/features/devices/data/bridge/bridge_status.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/eventually.dart';
import '../../../helpers/fake_bridge_channel.dart';

Matcher adbError(String message) =>
    isA<AdbException>().having((e) => e.message, 'message', message);

Map<String, Object?> out(int id, String text) => {
  'type': 'stdout',
  'id': id,
  'data': base64Encode(utf8.encode(text)),
};

void main() {
  late FakeBridgeConnector bridge;
  late List<bool> saved;
  late int downloads;
  final clients = <BridgeClient>[];

  setUp(() {
    bridge = FakeBridgeConnector();
    saved = [];
    downloads = 0;
  });

  tearDown(() async {
    for (final client in clients) {
      await client.dispose();
    }
    clients.clear();
  });

  BridgeClient client({
    bool autoConnect = false,
    bool local = false,
    bool blocked = false,
    Duration helloTimeout = const Duration(seconds: 1),
  }) {
    final created = BridgeClient(
      connector: bridge.connect,
      readAutoConnect: () async => autoConnect,
      writeAutoConnect: (on) async => saved.add(on),
      isBlocked: () async => blocked,
      download: () => downloads++,
      alwaysAutoConnect: local,
      backoff: (_) => const Duration(milliseconds: 10),
      helloTimeout: helloTimeout,
    );
    clients.add(created);
    return created;
  }

  Future<BridgeClient> connected() async {
    final created = client()..connect();
    await eventually(() => bridge.channels.isNotEmpty);
    bridge.channels.last.hello();
    await eventually(
      () => created.status == const BridgeConnected('/sdk/adb'),
    );
    return created;
  }

  test('connects, checks hello, reports each status and saves auto-connect', () async {
    final created = client();
    final statuses = <BridgeStatus>[];
    created.statuses.listen(statuses.add);
    expect(created.status, const BridgeOff());
    created.connect();
    await eventually(() => bridge.channels.isNotEmpty);
    bridge.channels.single.hello();
    await eventually(() => statuses.length == 2);
    expect(statuses, [
      const BridgeConnecting(),
      const BridgeConnected('/sdk/adb'),
    ]);
    expect(saved, [true]);
  });

  test('start connects only when auto-connect is on, or on a local page', () async {
    await client().start();
    expect(bridge.attempts, 0);
    expect(clients.last.status, const BridgeOff());
    await client(autoConnect: true).start();
    expect(bridge.attempts, 1);
    await client(local: true).start();
    expect(bridge.attempts, 2);
  });

  test('a bridge that is not running is retried until it starts', () async {
    bridge.running = false;
    final created = client()..connect();
    await eventually(() => created.status == const BridgeNotRunning());
    await eventually(() => bridge.attempts >= 3);
    bridge.running = true;
    await eventually(() => bridge.channels.isNotEmpty);
    bridge.channels.last.hello();
    await eventually(
      () => created.status == const BridgeConnected('/sdk/adb'),
    );
    expect(saved, [true]);
  });

  test('blocked when the browser says so', () async {
    bridge.running = false;
    final created = client(blocked: true)..connect();
    await eventually(() => created.status == const BridgeBlocked());
  });

  test('another protocol shows wrongVersion and waits for connect', () async {
    final created = client()..connect();
    await eventually(() => bridge.channels.isNotEmpty);
    bridge.channels.last.hello(protocol: 2);
    await eventually(() => created.status == const BridgeWrongVersion(2));
    expect(bridge.channels.last.closed, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(bridge.attempts, 1);
    expect(saved, isEmpty);
    created.connect();
    await eventually(() => bridge.attempts == 2);
  });

  test('no hello in time counts as not running', () async {
    final created = client(helloTimeout: const Duration(milliseconds: 20))
      ..connect();
    await eventually(() => created.status == const BridgeNotRunning());
    expect(bridge.channels.first.closed, isTrue);
    await eventually(() => bridge.attempts >= 2);
  });

  test('hello without adb reports the problem and stays connected', () async {
    final created = client()..connect();
    await eventually(() => bridge.channels.isNotEmpty);
    bridge.channels.last.hello(adb: null, problem: 'adb is missing');
    await eventually(() => created.status == const BridgeNoAdb('adb is missing'));
    expect(bridge.channels.last.closed, isFalse);
    expect(saved, [true]);
    expect(
      () => created.request(const {'type': 'track'}),
      throwsA(adbError(BridgeClient.notConnectedMessage)),
    );
  });

  test('restarting the bridge with adb moves noAdb to connected', () async {
    final created = client()..connect();
    await eventually(() => bridge.channels.isNotEmpty);
    bridge.channels.last.hello(adb: null, problem: 'adb is missing');
    await eventually(() => created.status is BridgeNoAdb);
    await bridge.channels.last.drop();
    await eventually(() => bridge.channels.length == 2);
    bridge.channels.last.hello();
    await eventually(
      () => created.status == const BridgeConnected('/sdk/adb'),
    );
  });

  test('replies are routed by id', () async {
    final created = await connected();
    final channel = bridge.channels.last;
    final first = created.request(const {
      'type': 'run',
      'serial': 'S',
      'kind': 'shell',
      'text': 'pm list packages -3',
    });
    final second = created.request(const {'type': 'track'});
    expect(channel.sent, [
      {
        'type': 'run',
        'serial': 'S',
        'kind': 'shell',
        'text': 'pm list packages -3',
        'id': 1,
      },
      {'type': 'track', 'id': 2},
    ]);
    channel
      ..fromBridge(out(2, '0000'))
      ..fromBridge({'type': 'exit', 'id': 2, 'code': 0})
      ..fromBridge({
        'type': 'error',
        'id': 1,
        'message': 'fcm_bridge refused this command.',
      });
    final chunks = await second.output.toList();
    expect(utf8.decode(chunks.single.bytes), '0000');
    expect(chunks.single.isError, isFalse);
    expect(await second.exitCode, 0);
    await expectLater(
      first.output.toList(),
      throwsA(adbError('fcm_bridge refused this command.')),
    );
    expect(await first.exitCode, -1);
  });

  test('garbage from the bridge is ignored', () async {
    final created = await connected();
    final channel = bridge.channels.last;
    final call = created.request(const {'type': 'track'});
    channel
      ..fromBridgeText('not json')
      ..fromBridge({'type': 'stdout', 'id': 99, 'data': 'AAAA'})
      ..fromBridge({'type': 'stdout', 'id': 1, 'data': '%%%'})
      ..fromBridge({'type': 'dance', 'id': 1})
      ..fromBridge(out(1, 'ok'))
      ..fromBridge({'type': 'exit', 'id': 1, 'code': 0});
    final chunks = await call.output.toList();
    expect(chunks.map((c) => utf8.decode(c.bytes)), ['ok']);
    expect(created.status, const BridgeConnected('/sdk/adb'));
  });

  test('losing the connection fails pending calls and retries', () async {
    final created = await connected();
    final call = created.request(const {'type': 'track'});
    await bridge.channels.last.drop();
    await expectLater(
      call.output.toList(),
      throwsA(adbError(BridgeClient.stoppedMessage)),
    );
    expect(await call.exitCode, -1);
    await eventually(() => bridge.attempts == 2);
    expect(created.status, isNot(const BridgeOff()));
  });

  test('disconnect closes, stops retrying and turns auto-connect off', () async {
    final created = await connected();
    await created.disconnect();
    expect(created.status, const BridgeOff());
    expect(bridge.channels.last.closed, isTrue);
    expect(saved, [true, false]);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(bridge.attempts, 1);
  });

  test('a request before connecting throws', () {
    expect(
      () => client().request(const {'type': 'track'}),
      throwsA(adbError(BridgeClient.notConnectedMessage)),
    );
  });

  test('kill asks the bridge to stop that request', () async {
    final created = await connected();
    created.request(const {'type': 'track'}).kill();
    expect(bridge.channels.last.sent.last, {'type': 'kill', 'id': 1});
  });

  test('download uses the page download', () {
    client().download();
    expect(downloads, 1);
  });
}
```

- [ ] **Step 4: Add the constants test to the sync test**

In `test/web/fcm_bridge_sync_test.dart`, add these imports:

```dart
import 'package:fcm_studio/features/devices/data/bridge/bridge_client.dart';
import 'package:fcm_studio/features/devices/data/bridge/bridge_protocol.dart';
```

and add this test inside `main()`:

```dart
  test('the page and fcm_bridge.dart agree on protocol, port and texts', () {
    expect(BridgeProtocol.version, bridge.bridgeProtocol);
    expect(BridgeProtocol.port, bridge.bridgePort);
    expect(BridgeProtocol.url, Uri.parse('ws://127.0.0.1:${bridge.bridgePort}'));
    expect(BridgeClient.noAdbProblem, bridge.noAdbProblem);
  });
```

- [ ] **Step 5: Run to verify it fails**

Run: `flutter test test/features/devices/bridge/bridge_client_test.dart test/web/fcm_bridge_sync_test.dart`
Expected: FAIL to compile: `bridge_client.dart` doesn't exist.

- [ ] **Step 6: Write `bridge_client.dart`**

Create `lib/features/devices/data/bridge/bridge_client.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:fcm_studio/features/devices/data/adb_exception.dart';
import 'package:fcm_studio/features/devices/data/bridge/bridge_channel.dart';
import 'package:fcm_studio/features/devices/data/bridge/bridge_protocol.dart';
import 'package:fcm_studio/features/devices/data/bridge/bridge_status.dart';

/// A chunk of a command's output.
class BridgeOutput {
  const BridgeOutput({required this.bytes, this.isError = false});

  final List<int> bytes;

  /// From standard error rather than standard output.
  final bool isError;
}

/// One request's replies (bridge design §4.2): output chunks, then the exit
/// code. An `error` reply, or losing the connection, ends [output] with an
/// [AdbException] and completes [exitCode] with -1.
class BridgeCall {
  BridgeCall._(this.id, this._kill);

  final int id;
  final void Function() _kill;
  final StreamController<BridgeOutput> _output =
      StreamController<BridgeOutput>();
  final Completer<int> _exit = Completer<int>();

  /// Single-subscription; buffered until listened to.
  Stream<BridgeOutput> get output => _output.stream;

  Future<int> get exitCode => _exit.future;

  /// Asks the bridge to stop the process.
  void kill() => _kill();

  void _add(BridgeOutput chunk) {
    if (!_output.isClosed) {
      _output.add(chunk);
    }
  }

  void _finish(int code) {
    if (!_output.isClosed) {
      unawaited(_output.close());
    }
    if (!_exit.isCompleted) {
      _exit.complete(code);
    }
  }

  void _fail(AdbException error) {
    if (!_output.isClosed) {
      _output.addError(error);
      unawaited(_output.close());
    }
    if (!_exit.isCompleted) {
      _exit.complete(-1);
    }
  }
}

/// What the app asks of the bridge (bridge design §4.4, §4.6).
abstract interface class BridgeControl {
  BridgeStatus get status;

  /// Every status change. Never ends.
  Stream<BridgeStatus> get statuses;

  /// At app start: connects when auto-connect is on or the page is local.
  Future<void> start();

  /// Connects now and keeps retrying until connected; also "Try again".
  void connect();

  /// Closes the connection, stops retrying and turns auto-connect off.
  Future<void> disconnect();

  /// Saves fcm_bridge.dart from this site.
  void download();

  /// Sends [message] with a new id. Throws [AdbException] unless connected.
  BridgeCall request(Map<String, Object?> message);
}

/// The page's side of the bridge: one WebSocket, retried while wanted, with
/// replies routed by request id.
class BridgeClient implements BridgeControl {
  BridgeClient({
    required this._connector,
    required this._readAutoConnect,
    required this._writeAutoConnect,
    this._isBlocked = _neverBlocked,
    this._download = _noDownload,
    this._alwaysAutoConnect = false,
    this._backoff = defaultBackoff,
    this._helloTimeout = const Duration(seconds: 5),
  });

  static const notConnectedMessage = 'The bridge is not connected.';
  static const stoppedMessage = 'The bridge stopped.';

  /// What the bridge says when it has no adb; also used if it says nothing.
  static const noAdbProblem =
      "adb wasn't found. Start the bridge with --adb <path to adb>.";

  /// 1, 2, 4, 8, 16, then 30 seconds; the same as DevicesBloc's.
  static Duration defaultBackoff(int attempt) =>
      Duration(seconds: min(30, 1 << (attempt - 1).clamp(0, 5)));

  static Future<bool> _neverBlocked() async => false;

  static void _noDownload() {}

  final BridgeConnector _connector;
  final Future<bool> Function() _readAutoConnect;
  final Future<void> Function(bool on) _writeAutoConnect;
  final Future<bool> Function() _isBlocked;
  final void Function() _download;
  final bool _alwaysAutoConnect;
  final Duration Function(int attempt) _backoff;
  final Duration _helloTimeout;

  final StreamController<BridgeStatus> _statuses =
      StreamController<BridgeStatus>.broadcast();
  final Map<int, BridgeCall> _calls = {};
  BridgeStatus _status = const BridgeOff();
  BridgeChannel? _channel;
  StreamSubscription<String>? _subscription;
  Completer<Map<String, Object?>?>? _hello;
  Timer? _retry;
  bool _wanted = false;
  bool _opening = false;
  int _attempt = 0;
  int _nextId = 1;

  /// Bumped by every open and by disconnect, so late events are ignored.
  int _generation = 0;

  @override
  BridgeStatus get status => _status;

  @override
  Stream<BridgeStatus> get statuses => _statuses.stream;

  @override
  Future<void> start() async {
    if (_alwaysAutoConnect || await _readAutoConnect()) {
      connect();
    }
  }

  @override
  void connect() {
    _wanted = true;
    _attempt = 0;
    _retry?.cancel();
    _retry = null;
    if (_channel == null && !_opening) {
      unawaited(_open());
    }
  }

  @override
  Future<void> disconnect() async {
    _wanted = false;
    _retry?.cancel();
    _retry = null;
    _generation++;
    _opening = false;
    await _drop();
    _setStatus(const BridgeOff());
    await _writeAutoConnect(false);
  }

  @override
  void download() => _download();

  @override
  BridgeCall request(Map<String, Object?> message) {
    if (_channel == null || _status is! BridgeConnected) {
      throw const AdbException(notConnectedMessage);
    }
    final id = _nextId++;
    final call = BridgeCall._(id, () => _send({'type': 'kill', 'id': id}));
    _calls[id] = call;
    _send({...message, 'id': id});
    return call;
  }

  /// Stops retrying and closes the connection (tests and shutdown).
  Future<void> dispose() async {
    _wanted = false;
    _retry?.cancel();
    _generation++;
    await _drop();
    await _statuses.close();
  }

  Future<void> _open() async {
    final generation = ++_generation;
    _opening = true;
    _setStatus(const BridgeConnecting());
    final BridgeChannel channel;
    try {
      channel = await _connector(BridgeProtocol.url);
    } on Object {
      if (generation == _generation) {
        _opening = false;
        await _failed(generation);
      }
      return;
    }
    if (generation != _generation) {
      unawaited(channel.close());
      return;
    }
    final hello = Completer<Map<String, Object?>?>();
    _channel = channel;
    _hello = hello;
    _subscription = channel.messages.listen(
      _onMessage,
      onError: (Object _) {},
      onDone: () => _onClosed(generation),
    );
    final first = await hello.future.timeout(
      _helloTimeout,
      onTimeout: () => null,
    );
    if (generation != _generation) {
      return;
    }
    _opening = false;
    final protocol = first?['protocol'];
    if (first == null || first['type'] != 'hello' || protocol is! int) {
      await _drop();
      await _failed(generation);
      return;
    }
    if (protocol != BridgeProtocol.version) {
      await _drop();
      _setStatus(BridgeWrongVersion(protocol));
      return;
    }
    _attempt = 0;
    final adb = first['adb'];
    final problem = first['problem'];
    _setStatus(
      adb is String
          ? BridgeConnected(adb)
          : BridgeNoAdb(problem is String ? problem : noAdbProblem),
    );
    await _writeAutoConnect(true);
  }

  void _onMessage(String text) {
    Map<String, Object?>? message;
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, Object?>) {
        message = decoded;
      }
    } on FormatException {
      message = null;
    }
    final hello = _hello;
    if (hello != null) {
      _hello = null;
      if (!hello.isCompleted) {
        hello.complete(message);
      }
      return;
    }
    if (message == null) {
      return;
    }
    final id = message['id'];
    final call = id is int ? _calls[id] : null;
    if (call == null) {
      return;
    }
    switch (message['type']) {
      case 'stdout' || 'stderr':
        final data = message['data'];
        if (data is String) {
          try {
            call._add(
              BridgeOutput(
                bytes: base64Decode(data),
                isError: message['type'] == 'stderr',
              ),
            );
          } on FormatException {
            // A broken chunk is dropped.
          }
        }
      case 'exit':
        _calls.remove(id);
        final code = message['code'];
        call._finish(code is int ? code : -1);
      case 'error':
        _calls.remove(id);
        final reason = message['message'];
        call._fail(
          AdbException(reason is String ? reason : 'The bridge failed.'),
        );
    }
  }

  void _onClosed(int generation) {
    if (generation != _generation) {
      return;
    }
    final hello = _hello;
    if (hello != null) {
      // Closed before hello: _open sees no hello and handles it.
      _hello = null;
      if (!hello.isCompleted) {
        hello.complete(null);
      }
      return;
    }
    _channel = null;
    _subscription = null;
    _failCalls();
    if (_status is BridgeWrongVersion) {
      return;
    }
    unawaited(_failed(generation));
  }

  Future<void> _failed(int generation) async {
    final blocked = await _isBlocked();
    if (generation != _generation) {
      return;
    }
    _setStatus(blocked ? const BridgeBlocked() : const BridgeNotRunning());
    if (!_wanted) {
      return;
    }
    _retry?.cancel();
    _retry = Timer(_backoff(++_attempt), () {
      _retry = null;
      if (_wanted && _channel == null && !_opening) {
        unawaited(_open());
      }
    });
  }

  /// Closes the channel without the close counting as the bridge stopping.
  Future<void> _drop() async {
    final channel = _channel;
    final subscription = _subscription;
    _channel = null;
    _subscription = null;
    final hello = _hello;
    _hello = null;
    if (hello != null && !hello.isCompleted) {
      hello.complete(null);
    }
    _failCalls();
    await subscription?.cancel();
    await channel?.close();
  }

  void _failCalls() {
    final calls = List.of(_calls.values);
    _calls.clear();
    for (final call in calls) {
      call._fail(const AdbException(stoppedMessage));
    }
  }

  void _send(Map<String, Object?> message) =>
      _channel?.send(jsonEncode(message));

  void _setStatus(BridgeStatus status) {
    if (status == _status) {
      return;
    }
    _status = status;
    if (!_statuses.isClosed) {
      _statuses.add(status);
    }
  }
}
```

- [ ] **Step 7: Run to verify it passes**

Run: `flutter test test/features/devices/bridge/bridge_client_test.dart test/web/`
Expected: PASS.

- [ ] **Step 8: Analyze, run the suite, commit**

```bash
flutter analyze
flutter test > /tmp/m51_task3.log 2>&1; tail -3 /tmp/m51_task3.log
dart format lib/features/devices/data/bridge/ test/features/devices/bridge/ test/helpers/fake_bridge_channel.dart test/web/
git add lib/features/devices/data/bridge/ test/features/devices/bridge/bridge_client_test.dart test/helpers/fake_bridge_channel.dart test/web/fcm_bridge_sync_test.dart
git commit -m "feat: the page's bridge client: hello, retries, requests by id

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

Expected: analyze `No issues found!`; the suite ends with `All tests passed!`

---

### Task 4: `BridgeDeviceShell`, `BridgeAdbService`, and the end-to-end test

**Files:**
- Create: `lib/features/devices/data/bridge/bridge_device_shell.dart`
- Create: `lib/features/devices/data/bridge/bridge_adb_service.dart`
- Create: `test/features/devices/bridge/bridge_device_shell_test.dart`
- Create: `test/features/devices/bridge/bridge_adb_service_test.dart`
- Create: `test/features/devices/bridge/bridge_end_to_end_test.dart`

**Interfaces:**
- Consumes:
  - `BridgeControl.request`, `BridgeCall`, `BridgeOutput` (Task 3);
  - `AdbCommands`, `DeviceShell`, `PhoneCommand`, `TrackDevicesDecoder`, `AdbService` (existing);
  - `BridgeServer` (Task 2) and `FakeAdb` (Task 2) in the end-to-end test.
- Produces:
  - `class BridgeDeviceShell implements DeviceShell` (`BridgeDeviceShell({required BridgeControl bridge})`);
  - `class BridgeAdbService implements AdbService` (`BridgeAdbService({required BridgeControl bridge})`, `static const trackStoppedMessage`).

- [ ] **Step 1: Write the failing shell test**

Create `test/features/devices/bridge/bridge_device_shell_test.dart`:

```dart
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
```

- [ ] **Step 2: Write the failing service test**

Create `test/features/devices/bridge/bridge_adb_service_test.dart`:

```dart
import 'dart:async';
import 'dart:convert';

import 'package:fcm_studio/features/devices/data/adb_exception.dart';
import 'package:fcm_studio/features/devices/data/bridge/bridge_adb_service.dart';
import 'package:fcm_studio/features/devices/domain/adb_device.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/device_fixtures.dart';
import '../../../helpers/eventually.dart';
import '../../../helpers/fake_bridge_channel.dart';

const app = 'com.syldel.delivery';

Map<String, Object?> out(int id, String text) => {
  'type': 'stdout',
  'id': id,
  'data': base64Encode(utf8.encode(text)),
};

void main() {
  test('trackDevices decodes adb track-devices; cancel kills it', () async {
    final (client, channel) = await connectedBridgeClient();
    final lists = <List<AdbDevice>>[];
    final subscription = BridgeAdbService(
      bridge: client,
    ).trackDevices().listen(lists.add);
    expect(channel.sent.single, {'type': 'track', 'id': 1});
    channel.fromBridge(out(1, trackFrame(redmiTrackLine)));
    await eventually(() => lists.isNotEmpty);
    expect(lists.single.single.serial, redmiSerial);
    await subscription.cancel();
    expect(channel.sent.last, {'type': 'kill', 'id': 1});
  });

  test('when adb track-devices ends, the stream fails and ends', () async {
    final (client, channel) = await connectedBridgeClient();
    final errors = <Object>[];
    final done = Completer<void>();
    BridgeAdbService(bridge: client).trackDevices().listen(
      (_) {},
      onError: errors.add,
      onDone: done.complete,
    );
    channel.fromBridge({'type': 'exit', 'id': 1, 'code': 1});
    await done.future;
    expect(
      errors.single,
      isA<AdbException>().having(
        (e) => e.message,
        'message',
        BridgeAdbService.trackStoppedMessage,
      ),
    );
  });

  test('phone commands go through the bridge', () async {
    final (client, channel) = await connectedBridgeClient();
    final packages = BridgeAdbService(bridge: client).listPackages(redmiSerial);
    await eventually(() => channel.runs.isNotEmpty);
    expect(channel.runs.single['text'], 'pm list packages -3');
    channel
      ..fromBridge(out(1, 'package:$app\n'))
      ..fromBridge({'type': 'exit', 'id': 1, 'code': 0});
    expect(await packages, [app]);
  });
}
```

- [ ] **Step 3: Write the failing end-to-end test**

Create `test/features/devices/bridge/bridge_end_to_end_test.dart`:

```dart
import 'dart:async';
import 'dart:io';

import 'package:fcm_studio/features/devices/data/adb_commands.dart';
import 'package:fcm_studio/features/devices/data/bridge/bridge_adb_service.dart';
import 'package:fcm_studio/features/devices/data/bridge/bridge_channel.dart';
import 'package:fcm_studio/features/devices/data/bridge/bridge_client.dart';
import 'package:fcm_studio/features/devices/data/bridge/bridge_status.dart';
import 'package:fcm_studio/features/devices/domain/token_read_results.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../web/fcm_bridge.dart' as bridge;
import '../../../helpers/device_fixtures.dart';
import '../../../helpers/eventually.dart';
import '../../../helpers/fake_adb_process.dart';

const app = 'com.syldel.delivery';
const adbPath = '/sdk/platform-tools/adb';

/// The page's channel over a real dart:io WebSocket, as a browser opens it.
class IoBridgeChannel implements BridgeChannel {
  IoBridgeChannel._(this._socket);

  static Future<BridgeChannel> connect(Uri url) async {
    try {
      return IoBridgeChannel._(
        await WebSocket.connect(
          url.toString(),
          headers: const {'origin': 'http://localhost:5050'},
        ),
      );
    } on Object {
      throw const BridgeUnreachableException();
    }
  }

  final WebSocket _socket;

  @override
  late final Stream<String> messages = _socket
      .where((data) => data is String)
      .cast<String>();

  @override
  void send(String message) => _socket.add(message);

  @override
  Future<void> close() => _socket.close();
}

void main() {
  late FakeAdb adb;
  late BridgeAdbService service;

  setUp(() async {
    adb = FakeAdb();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    unawaited(
      bridge.BridgeServer(
        adbPath: adbPath,
        allowedOrigins: const [],
        startProcess: adb.start,
        log: (_) {},
      ).serve(server),
    );
    final client = BridgeClient(
      connector: (_) =>
          IoBridgeChannel.connect(Uri.parse('ws://127.0.0.1:${server.port}')),
      readAutoConnect: () async => false,
      writeAutoConnect: (_) async {},
    )..connect();
    addTearDown(client.dispose);
    await eventually(() => client.status == const BridgeConnected(adbPath));
    service = BridgeAdbService(bridge: client);
  });

  test('a debug build token is read through the real bridge', () async {
    adb.onStart = (process) {
      if (process.arguments.contains('exec-out')) {
        process
          ..out(appIdPrefsXml({'123456789012': fakeDeviceToken}))
          ..finish(0);
      }
    };
    final result = await service.readTokenWithRunAs(redmiSerial, app);
    expect(result, isA<RunAsTokens>());
    expect((result as RunAsTokens).tokens.single.token, fakeDeviceToken);
    expect(adb.started.single.arguments, [
      adbPath,
      '-s',
      redmiSerial,
      'exec-out',
      'run-as',
      app,
      'cat',
      AdbCommands.tokenFile,
    ]);
  });

  test('a release build token comes from logcat, and logcat is stopped', () async {
    adb.onStart = (process) {
      final command = process.arguments.skip(3).join(' ');
      if (command == 'shell am force-stop $app') {
        process.finish(0);
      } else if (command.startsWith('shell monkey')) {
        process
          ..out('Events injected: 1\n')
          ..finish(0);
      } else if (command == 'shell pidof $app') {
        process
          ..out('4242\n')
          ..finish(0);
      } else if (command == 'logcat --pid=4242') {
        process.out(
          '10-04 12:00:01.000 I/flutter: FCM token: $fakeDeviceToken\n',
        );
      }
    };
    final progress = await service
        .readTokenFromLogcat(redmiSerial, app)
        .toList();
    expect(progress.last, LogcatFound(fakeDeviceToken));
    final logcat = adb.started.last;
    expect(logcat.arguments.last, '--pid=4242');
    await eventually(() => logcat.killed);
  });

  test('phones are tracked through the real bridge', () async {
    adb.onStart = (process) => process.out(trackFrame(redmiTrackLine));
    final devices = await service.trackDevices().first;
    expect(devices.single.serial, redmiSerial);
    await eventually(() => adb.started.single.killed);
  });
}
```

- [ ] **Step 4: Run to verify they fail**

Run: `flutter test test/features/devices/bridge/`
Expected: FAIL to compile: `bridge_device_shell.dart` and `bridge_adb_service.dart` don't exist.

- [ ] **Step 5: Write `BridgeDeviceShell`**

Create `lib/features/devices/data/bridge/bridge_device_shell.dart`:

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:fcm_studio/features/devices/data/adb_exception.dart';
import 'package:fcm_studio/features/devices/data/bridge/bridge_client.dart';
import 'package:fcm_studio/features/devices/data/device_shell.dart';
import 'package:fcm_studio/features/devices/data/process_runner.dart';

/// Runs phone commands with the computer's adb, through the bridge (bridge
/// design §4.4). Messages name the adb command.
class BridgeDeviceShell implements DeviceShell {
  BridgeDeviceShell({required this._bridge});

  final BridgeControl _bridge;

  static const _decoder = Utf8Decoder(allowMalformed: true);

  @override
  Future<ProcessOutput> run(String serial, PhoneCommand command) async {
    final call = _request(serial, command);
    final stdout = BytesBuilder(copy: false);
    final stderr = BytesBuilder(copy: false);
    try {
      await for (final chunk in call.output) {
        (chunk.isError ? stderr : stdout).add(chunk.bytes);
      }
    } on AdbException catch (e) {
      throw _failed(serial, command, e);
    }
    return ProcessOutput(
      exitCode: await call.exitCode,
      stdout: _decoder.convert(stdout.takeBytes()),
      stderr: _decoder.convert(stderr.takeBytes()),
    );
  }

  @override
  Future<RunningProcess> start(String serial, PhoneCommand command) async =>
      _BridgeProcess(_request(serial, command));

  @override
  String describe(String serial, PhoneCommand command) {
    final words = switch (command.kind) {
      PhoneCommandKind.shell => 'shell ${command.text}',
      PhoneCommandKind.execOut => 'exec-out ${command.text}',
      PhoneCommandKind.logcat => 'logcat ${command.text}',
    };
    return '`adb -s $serial $words` (through the bridge)';
  }

  BridgeCall _request(String serial, PhoneCommand command) {
    try {
      return _bridge.request({
        'type': 'run',
        'serial': serial,
        'kind': command.kind.name,
        'text': command.text,
      });
    } on AdbException catch (e) {
      throw _failed(serial, command, e);
    }
  }

  AdbException _failed(String serial, PhoneCommand command, AdbException e) =>
      AdbException('${describe(serial, command)} failed: ${e.message}');
}

/// A long-running command on the bridge, e.g. `logcat --pid`.
class _BridgeProcess implements RunningProcess {
  _BridgeProcess(this._call);

  final BridgeCall _call;

  /// Standard output only, as desktop drains standard error.
  @override
  late final Stream<List<int>> stdout = _call.output
      .where((chunk) => !chunk.isError)
      .map((chunk) => chunk.bytes);

  @override
  Future<int> get exitCode => _call.exitCode;

  @override
  void kill() => _call.kill();
}
```

- [ ] **Step 6: Write `BridgeAdbService`**

Create `lib/features/devices/data/bridge/bridge_adb_service.dart`:

```dart
import 'dart:async';

import 'package:fcm_studio/features/devices/data/adb_commands.dart';
import 'package:fcm_studio/features/devices/data/adb_service.dart';
import 'package:fcm_studio/features/devices/data/bridge/bridge_client.dart';
import 'package:fcm_studio/features/devices/data/bridge/bridge_device_shell.dart';
import 'package:fcm_studio/features/devices/data/parsers/track_devices_decoder.dart';
import 'package:fcm_studio/features/devices/domain/adb_device.dart';
import 'package:fcm_studio/features/devices/domain/token_read_results.dart';

/// The bridge's phones as an [AdbService] (bridge design §4.4): adb's
/// device list, and the same phone commands as desktop.
class BridgeAdbService implements AdbService {
  BridgeAdbService({required this._bridge});

  static const trackStoppedMessage =
      '`adb track-devices -l` stopped (through the bridge)';

  final BridgeControl _bridge;

  late final AdbCommands _commands = AdbCommands(
    shell: BridgeDeviceShell(bridge: _bridge),
  );

  @override
  Stream<List<AdbDevice>> trackDevices() {
    late final StreamController<List<AdbDevice>> controller;
    BridgeCall? call;
    StreamSubscription<List<AdbDevice>>? subscription;
    var failed = false;

    controller = StreamController<List<AdbDevice>>(
      onListen: () {
        try {
          final started = _bridge.request(const {'type': 'track'});
          call = started;
          subscription = started.output
              .where((chunk) => !chunk.isError)
              .map((chunk) => chunk.bytes)
              .transform(const TrackDevicesDecoder())
              .listen(
                controller.add,
                onError: (Object error, StackTrace stackTrace) {
                  failed = true;
                  controller.addError(error, stackTrace);
                },
                onDone: () {
                  if (!failed) {
                    controller.addError(
                      const AdbException(trackStoppedMessage),
                    );
                  }
                  unawaited(controller.close());
                },
              );
        } on AdbException catch (e, stackTrace) {
          controller.addError(e, stackTrace);
          unawaited(controller.close());
        }
      },
      // Like ProcessAdbService: the decoder only ends once the process does,
      // so kill first and don't wait for the cancel.
      onCancel: () {
        call?.kill();
        unawaited(subscription?.cancel());
      },
    );
    return controller.stream;
  }

  @override
  Future<DeviceDetails> deviceDetails(String serial) =>
      _commands.deviceDetails(serial);

  @override
  Future<List<String>> listPackages(String serial) =>
      _commands.listPackages(serial);

  @override
  Future<RunAsResult> readTokenWithRunAs(String serial, String package) =>
      _commands.readTokenWithRunAs(serial, package);

  @override
  Future<void> launchApp(String serial, String package) =>
      _commands.launchApp(serial, package);

  @override
  Stream<LogcatProgress> readTokenFromLogcat(String serial, String package) =>
      _commands.readTokenFromLogcat(serial, package);
}
```

- [ ] **Step 7: Run to verify they pass**

Run: `flutter test test/features/devices/bridge/`
Expected: PASS (shell, service and end-to-end tests).

- [ ] **Step 8: Analyze, run the suite, commit**

```bash
flutter analyze
flutter test > /tmp/m51_task4.log 2>&1; tail -3 /tmp/m51_task4.log
dart format lib/features/devices/data/bridge/ test/features/devices/bridge/
git add lib/features/devices/data/bridge/bridge_device_shell.dart lib/features/devices/data/bridge/bridge_adb_service.dart test/features/devices/bridge/
git commit -m "feat: phone commands and device tracking through the bridge

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

Expected: analyze clean; `All tests passed!`

---

### Task 5: `WebPhones` and `AdbDevice.link`

**Files:**
- Modify: `lib/features/devices/domain/adb_device.dart`
- Create: `lib/features/devices/data/web_phones.dart`
- Create: `test/helpers/fake_bridge_control.dart`
- Create: `test/features/devices/web_phones_test.dart`

**Interfaces:**
- Consumes: `BridgeControl`, `BridgeClient.defaultBackoff`, `BridgeStatus` (Task 3); `AdbService` (existing); `FakeAdbService` (existing helper).
- Produces:
  - `enum PhoneLink { usb, bridge }`;
  - `AdbDevice.link` (`PhoneLink?`, in `props`) and `AdbDevice withLink(PhoneLink link)`;
  - `class WebPhones implements AdbService`:
    - constructor `({required BridgeControl bridge, required AdbService bridgeService, AdbService? usb, Duration Function(int) backoff})`;
    - `static const source = 'web'` and `static const goneMessage`;
  - `class FakeBridgeControl implements BridgeControl`:
    - constructor `([BridgeStatus status])`, `emit`;
    - counters `starts`, `connects`, `disconnects`, `downloads`.

- [ ] **Step 1: Write the fake bridge control**

Create `test/helpers/fake_bridge_control.dart`:

```dart
import 'dart:async';

import 'package:fcm_studio/features/devices/data/adb_exception.dart';
import 'package:fcm_studio/features/devices/data/bridge/bridge_client.dart';
import 'package:fcm_studio/features/devices/data/bridge/bridge_status.dart';

/// A bridge whose status the test sets. Records what the app asked.
class FakeBridgeControl implements BridgeControl {
  FakeBridgeControl([this._status = const BridgeOff()]);

  BridgeStatus _status;
  final StreamController<BridgeStatus> _statuses =
      StreamController<BridgeStatus>.broadcast(sync: true);
  int starts = 0;
  int connects = 0;
  int disconnects = 0;
  int downloads = 0;

  /// Moves the bridge to [status], as the real client would.
  void emit(BridgeStatus status) {
    _status = status;
    _statuses.add(status);
  }

  @override
  BridgeStatus get status => _status;

  @override
  Stream<BridgeStatus> get statuses => _statuses.stream;

  @override
  Future<void> start() async {
    starts++;
  }

  @override
  void connect() => connects++;

  @override
  Future<void> disconnect() async {
    disconnects++;
  }

  @override
  void download() => downloads++;

  @override
  BridgeCall request(Map<String, Object?> message) =>
      throw const AdbException(BridgeClient.notConnectedMessage);
}
```

- [ ] **Step 2: Write the failing test**

Create `test/features/devices/web_phones_test.dart`:

```dart
import 'dart:async';

import 'package:fcm_studio/features/devices/data/adb_exception.dart';
import 'package:fcm_studio/features/devices/data/bridge/bridge_status.dart';
import 'package:fcm_studio/features/devices/data/web_phones.dart';
import 'package:fcm_studio/features/devices/domain/adb_device.dart';
import 'package:fcm_studio/features/devices/domain/token_read_results.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/eventually.dart';
import '../../helpers/fake_adb_service.dart';
import '../../helpers/fake_bridge_control.dart';

const app = 'com.syldel.delivery';
const connected = BridgeConnected('/sdk/adb');

AdbDevice phone(String serial) =>
    AdbDevice(serial: serial, state: DeviceState.device, rawState: 'device');

void main() {
  late FakeAdbService usb;
  late FakeAdbService viaBridge;
  late FakeBridgeControl bridge;

  setUp(() {
    usb = FakeAdbService();
    viaBridge = FakeAdbService();
    bridge = FakeBridgeControl();
  });

  WebPhones phones({bool withUsb = true}) => WebPhones(
    bridge: bridge,
    bridgeService: viaBridge,
    usb: withUsb ? usb : null,
    backoff: (_) => const Duration(milliseconds: 10),
  );

  Future<List<List<AdbDevice>>> track(
    WebPhones web, {
    void Function()? onDone,
  }) async {
    final lists = <List<AdbDevice>>[];
    final subscription = web.trackDevices().listen(
      lists.add,
      onError: (Object _) {},
      onDone: onDone,
    );
    addTearDown(subscription.cancel);
    await pumpEventQueue();
    return lists;
  }

  test('USB phones are listed at once, labelled USB; the bridge waits', () async {
    final lists = await track(phones());
    expect(lists.last, isEmpty);
    expect(viaBridge.trackers, isEmpty);
    usb.tracker.add([phone('USB1')]);
    await pumpEventQueue();
    expect(lists.last, [phone('USB1').withLink(PhoneLink.usb)]);
  });

  test('bridge phones join once it connects; the bridge wins a shared serial', () async {
    final lists = await track(phones());
    usb.tracker.add([phone('SAME'), phone('USB1')]);
    bridge.emit(connected);
    await pumpEventQueue();
    expect(viaBridge.trackers, hasLength(1));
    viaBridge.tracker.add([phone('SAME')]);
    await pumpEventQueue();
    expect(lists.last, [
      phone('SAME').withLink(PhoneLink.bridge),
      phone('USB1').withLink(PhoneLink.usb),
    ]);
  });

  test('when the bridge goes away its phones go, and tracking stops', () async {
    final lists = await track(phones());
    bridge.emit(connected);
    await pumpEventQueue();
    viaBridge.tracker.add([phone('BR1')]);
    await pumpEventQueue();
    expect(lists.last, [phone('BR1').withLink(PhoneLink.bridge)]);
    bridge.emit(const BridgeNotRunning());
    await pumpEventQueue();
    expect(lists.last, isEmpty);
    expect(viaBridge.tracker.hasListener, isFalse);
  });

  test('a bridge tracker that ends is started again while connected', () async {
    var ended = false;
    final lists = await track(phones(), onDone: () => ended = true);
    bridge.emit(connected);
    await pumpEventQueue();
    viaBridge.tracker.add([phone('BR1')]);
    await pumpEventQueue();
    viaBridge.tracker.addError(const AdbException('adb server restarted'));
    await viaBridge.tracker.close();
    await pumpEventQueue();
    expect(lists.last, isEmpty);
    await eventually(() => viaBridge.trackers.length == 2);
    viaBridge.tracker.add([phone('BR1')]);
    await pumpEventQueue();
    expect(lists.last, [phone('BR1').withLink(PhoneLink.bridge)]);
    usb.tracker.add([phone('USB1')]);
    await pumpEventQueue();
    expect(lists.last, hasLength(2));
    expect(ended, isFalse);
  });

  test('calls go to the side that lists the phone', () async {
    final web = phones();
    await track(web);
    usb.tracker.add([phone('USB1')]);
    bridge.emit(connected);
    await pumpEventQueue();
    viaBridge.tracker.add([phone('BR1')]);
    await pumpEventQueue();

    await web.deviceDetails('USB1');
    await web.listPackages('BR1');
    await web.readTokenWithRunAs('BR1', app);
    await web.launchApp('USB1', app);
    await web.readTokenFromLogcat('BR1', app).drain<void>();
    expect(usb.calls, containsAll(['details USB1', 'launch USB1 $app']));
    expect(
      viaBridge.calls,
      containsAll(['packages BR1', 'run-as BR1 $app', 'logcat BR1 $app']),
    );
  });

  test('a phone that is gone gets a clear message', () async {
    final web = phones();
    await expectLater(
      web.deviceDetails('GONE'),
      throwsA(
        isA<AdbException>().having(
          (e) => e.message,
          'message',
          WebPhones.goneMessage,
        ),
      ),
    );
    expect(
      await web.readTokenWithRunAs('GONE', app),
      const RunAsFailed(WebPhones.goneMessage),
    );
    expect(await web.readTokenFromLogcat('GONE', app).toList(), [
      const LogcatFailed(WebPhones.goneMessage),
    ]);
  });

  test('without WebUSB, only the bridge phones are listed', () async {
    final lists = await track(phones(withUsb: false));
    bridge.emit(connected);
    await pumpEventQueue();
    viaBridge.tracker.add([phone('BR1')]);
    await pumpEventQueue();
    expect(lists.last, [phone('BR1').withLink(PhoneLink.bridge)]);
    expect(usb.trackers, isEmpty);
  });

  test('cancelling stops both sides', () async {
    final subscription = phones().trackDevices().listen((_) {});
    bridge.emit(connected);
    await pumpEventQueue();
    await subscription.cancel();
    expect(usb.tracker.hasListener, isFalse);
    expect(viaBridge.tracker.hasListener, isFalse);
  });
}
```

- [ ] **Step 3: Run to verify it fails**

Run: `flutter test test/features/devices/web_phones_test.dart`
Expected: FAIL to compile: `web_phones.dart` doesn't exist, and `PhoneLink` is undefined.

- [ ] **Step 4: Add `PhoneLink` and `link` to `AdbDevice`**

In `lib/features/devices/domain/adb_device.dart`, add the enum below `enum DeviceState`:

```dart
/// How a web phone is reached (bridge design §4.5). Null on desktop.
enum PhoneLink { usb, bridge }
```

Then change `AdbDevice` to this (new `link` parameter, field, `withLink`, and `props` entry):

```dart
/// One line of `adb devices -l`.
class AdbDevice extends Equatable {
  const AdbDevice({
    required this.serial,
    required this.state,
    this.rawState = '',
    this.model,
    this.product,
    this.transportId,
    this.note,
    this.link,
  });

  final String serial;
  final DeviceState state;

  /// The state as adb printed it, e.g. `recovery` for [DeviceState.other].
  final String rawState;
  final String? model;
  final String? product;
  final String? transportId;

  /// Why the phone isn't ready, shown instead of the default hint (on the
  /// web, e.g. "Connecting…" or "in use by another program").
  final String? note;

  /// USB or the bridge, on the web; null on desktop.
  final PhoneLink? link;

  /// Only a device in the `device` state accepts commands.
  bool get isReady => state == DeviceState.device;

  AdbDevice withLink(PhoneLink link) => AdbDevice(
    serial: serial,
    state: state,
    rawState: rawState,
    model: model,
    product: product,
    transportId: transportId,
    note: note,
    link: link,
  );

  @override
  List<Object?> get props => [
    serial,
    state,
    rawState,
    model,
    product,
    transportId,
    note,
    link,
  ];
}
```

- [ ] **Step 5: Write `WebPhones`**

Create `lib/features/devices/data/web_phones.dart`:

```dart
import 'dart:async';

import 'package:fcm_studio/features/devices/data/adb_service.dart';
import 'package:fcm_studio/features/devices/data/bridge/bridge_client.dart';
import 'package:fcm_studio/features/devices/data/bridge/bridge_status.dart';
import 'package:fcm_studio/features/devices/domain/adb_device.dart';
import 'package:fcm_studio/features/devices/domain/token_read_results.dart';

/// The web's phones (bridge design §4.5): WebUSB's and the bridge's in one
/// list, each labelled. The bridge wins when both list a serial, so the
/// "in use" WebUSB row never shows while the bridge runs.
class WebPhones implements AdbService {
  WebPhones({
    required this._bridge,
    required this._bridgeService,
    this._usb,
    this._backoff = BridgeClient.defaultBackoff,
  });

  /// Stands in for an adb path, so `DevicesBloc` and `TokenReaderCubit`
  /// work unchanged.
  static const source = 'web';

  static const goneMessage = 'That phone is no longer connected.';

  final BridgeControl _bridge;
  final AdbService _bridgeService;
  final AdbService? _usb;
  final Duration Function(int attempt) _backoff;
  List<AdbDevice> _usbPhones = const [];
  List<AdbDevice> _bridgePhones = const [];

  /// The current phones at once, then every change. A failing bridge never
  /// ends it; a failing WebUSB side does (DevicesBloc restarts it).
  @override
  Stream<List<AdbDevice>> trackDevices() {
    late final StreamController<List<AdbDevice>> controller;
    StreamSubscription<List<AdbDevice>>? usb;
    StreamSubscription<BridgeStatus>? statuses;
    StreamSubscription<List<AdbDevice>>? bridge;
    Timer? retry;
    var attempt = 0;
    var cancelled = false;

    void emit() {
      if (!cancelled) {
        controller.add(_merged());
      }
    }

    void clearBridge() {
      if (_bridgePhones.isNotEmpty) {
        _bridgePhones = const [];
        emit();
      }
    }

    void trackBridge() {
      bridge = _bridgeService.trackDevices().listen(
        (devices) {
          attempt = 0;
          _bridgePhones = devices;
          emit();
        },
        onError: (Object _) {},
        onDone: () {
          bridge = null;
          clearBridge();
          if (!cancelled && _bridge.status is BridgeConnected) {
            retry = Timer(_backoff(++attempt), () {
              retry = null;
              if (!cancelled &&
                  bridge == null &&
                  _bridge.status is BridgeConnected) {
                trackBridge();
              }
            });
          }
        },
      );
    }

    void stopBridge() {
      retry?.cancel();
      retry = null;
      final current = bridge;
      bridge = null;
      unawaited(current?.cancel());
      clearBridge();
    }

    void onStatus(BridgeStatus status) {
      if (status is BridgeConnected) {
        if (bridge == null && retry == null) {
          trackBridge();
        }
      } else {
        stopBridge();
      }
    }

    controller = StreamController<List<AdbDevice>>(
      onListen: () {
        emit();
        usb = _usb?.trackDevices().listen((devices) {
          _usbPhones = devices;
          emit();
        }, onError: controller.addError);
        statuses = _bridge.statuses.listen(onStatus);
        onStatus(_bridge.status);
      },
      onCancel: () async {
        cancelled = true;
        retry?.cancel();
        final current = bridge;
        bridge = null;
        unawaited(current?.cancel());
        await statuses?.cancel();
        await usb?.cancel();
      },
    );
    return controller.stream;
  }

  List<AdbDevice> _merged() {
    final bridgeSerials = {for (final device in _bridgePhones) device.serial};
    return [
      for (final device in _bridgePhones) device.withLink(PhoneLink.bridge),
      for (final device in _usbPhones)
        if (!bridgeSerials.contains(device.serial))
          device.withLink(PhoneLink.usb),
    ];
  }

  /// The bridge if its latest list has [serial], else WebUSB if its has.
  AdbService _owner(String serial) {
    if (_bridgePhones.any((device) => device.serial == serial)) {
      return _bridgeService;
    }
    final usb = _usb;
    if (usb != null && _usbPhones.any((device) => device.serial == serial)) {
      return usb;
    }
    throw const AdbException(goneMessage);
  }

  @override
  Future<DeviceDetails> deviceDetails(String serial) =>
      Future.sync(() => _owner(serial).deviceDetails(serial));

  @override
  Future<List<String>> listPackages(String serial) =>
      Future.sync(() => _owner(serial).listPackages(serial));

  @override
  Future<RunAsResult> readTokenWithRunAs(String serial, String package) {
    final AdbService owner;
    try {
      owner = _owner(serial);
    } on AdbException catch (e) {
      return Future.value(RunAsFailed(e.message));
    }
    return owner.readTokenWithRunAs(serial, package);
  }

  @override
  Future<void> launchApp(String serial, String package) =>
      Future.sync(() => _owner(serial).launchApp(serial, package));

  @override
  Stream<LogcatProgress> readTokenFromLogcat(String serial, String package) {
    try {
      return _owner(serial).readTokenFromLogcat(serial, package);
    } on AdbException catch (e) {
      return Stream.value(LogcatFailed(e.message));
    }
  }
}
```

- [ ] **Step 6: Run to verify it passes**

Run: `flutter test test/features/devices/web_phones_test.dart`
Expected: PASS.

- [ ] **Step 7: Analyze, run the suite, commit**

```bash
flutter analyze
flutter test > /tmp/m51_task5.log 2>&1; tail -3 /tmp/m51_task5.log
dart format lib/features/devices/ test/features/devices/web_phones_test.dart test/helpers/fake_bridge_control.dart
git add lib/features/devices/domain/adb_device.dart lib/features/devices/data/web_phones.dart test/features/devices/web_phones_test.dart test/helpers/fake_bridge_control.dart
git commit -m "feat: WebPhones: WebUSB and bridge phones in one labelled list

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

Expected: analyze clean; `All tests passed!` (`AdbDevice` equality now includes `link`; existing tests build devices without it, so they still compare equal).

---

### Task 6: Browser layer, auto-connect setting, `BridgeCubit`, and wiring

**Files:**
- Create: `lib/features/devices/data/bridge/bridge_platform.dart`
- Create: `lib/features/devices/data/bridge/bridge_platform_stub.dart`
- Create: `lib/features/devices/data/bridge/browser/bridge_platform_web.dart`
- Create: `lib/features/devices/cubit/bridge_cubit.dart`
- Modify: `lib/features/settings/data/settings_repository.dart`
- Modify: `lib/app/dependencies.dart`
- Modify: `lib/app/app.dart`
- Modify: `test/helpers/app_harness.dart`
- Modify: `test/features/settings/settings_repository_test.dart`
- Create: `test/features/devices/bridge_cubit_test.dart`
- Modify: `test/app/app_test.dart`

**Interfaces:**
- Consumes: `BridgeClient`, `BridgeControl`, `BridgeChannel` (Task 3); `BridgeAdbService` (Task 4); `WebPhones` (Task 5); `FakeBridgeControl` (Task 5).
- Produces:
  - `Future<BridgeChannel> connectBridgeChannel(Uri url)`, `Future<bool> bridgeBlockedByBrowser()`, `bool pageIsLocal()`, `void downloadBridgeFile()`;
  - `SettingsRepository.readBridgeAutoConnect()` and `writeBridgeAutoConnect(bool on)`;
  - `class BridgeCubit extends Cubit<BridgeStatus>`: `BridgeCubit({required BridgeControl control})`, with `start()`, `connect()`, `disconnect()`, `download()`;
  - `AppDependencies.bridge` (`BridgeControl?`) and the `bridge:` parameter;
  - `buildTestDependencies(bridge:)`.

- [ ] **Step 1: Write the failing tests**

Add to `test/features/settings/settings_repository_test.dart`, inside `main()`:

```dart
  test('remembers whether the bridge connects by itself', () async {
    final settings = SettingsRepository(database: database);
    expect(await settings.readBridgeAutoConnect(), isFalse);
    await settings.writeBridgeAutoConnect(true);
    expect(await settings.readBridgeAutoConnect(), isTrue);
    await settings.writeBridgeAutoConnect(false);
    expect(await settings.readBridgeAutoConnect(), isFalse);
  });
```

Create `test/features/devices/bridge_cubit_test.dart`:

```dart
import 'package:fcm_studio/features/devices/cubit/bridge_cubit.dart';
import 'package:fcm_studio/features/devices/data/bridge/bridge_status.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_bridge_control.dart';

void main() {
  test('follows the bridge and forwards the buttons', () async {
    final bridge = FakeBridgeControl(const BridgeNotRunning());
    final cubit = BridgeCubit(control: bridge);
    addTearDown(cubit.close);
    expect(cubit.state, const BridgeNotRunning());
    bridge.emit(const BridgeConnected('/sdk/adb'));
    expect(cubit.state, const BridgeConnected('/sdk/adb'));

    await cubit.start();
    cubit.connect();
    await cubit.disconnect();
    cubit.download();
    expect(
      [bridge.starts, bridge.connects, bridge.disconnects, bridge.downloads],
      [1, 1, 1, 1],
    );
  });
}
```

In `test/app/app_test.dart`:
- add the imports `package:fcm_studio/features/devices/data/web_phones.dart` and `../helpers/fake_bridge_control.dart`;
- in the test 'with WebUSB, phones are tracked at once and Settings is hidden', replace `WebUsbAdbService.source` with `WebPhones.source`, and remove the `web_usb_adb_service.dart` import if nothing else uses it;
- add these tests inside `main()`:

```dart
  testWidgets('on the web the bridge starts with the app and phones are tracked', (
    tester,
  ) async {
    final bridge = FakeBridgeControl();
    await pumpApp(
      tester,
      await buildTestDependencies(
        tester,
        adb: FakeAdbService(),
        platform: const PlatformFeatures(deviceAccess: DeviceAccess.noWebUsb),
        bridge: bridge,
      ),
    );
    expect(bridge.starts, 1);
    expect(readCubit<DevicesBloc>(tester).state.adbPath, WebPhones.source);
  });

  testWidgets('on the web WebPhones serves the phones; desktop has no bridge', (
    tester,
  ) async {
    final bridge = FakeBridgeControl();
    final web = await buildTestDependencies(
      tester,
      platform: const PlatformFeatures(deviceAccess: DeviceAccess.noWebUsb),
      bridge: bridge,
    );
    expect(web.adbServiceFor(WebPhones.source), isA<WebPhones>());
    expect(web.bridge, same(bridge));
    final desktop = await buildTestDependencies(tester);
    expect(desktop.bridge, isNull);
  });
```

In `test/helpers/app_harness.dart`:
- add the import `package:fcm_studio/features/devices/data/bridge/bridge_client.dart`;
- add the parameter `BridgeControl? bridge,` to `buildTestDependencies` (after `phoneAccess`);
- pass `bridge: bridge,` to `AppDependencies(...)`.

- [ ] **Step 2: Run to verify they fail**

Run: `flutter test test/features/settings/settings_repository_test.dart test/features/devices/bridge_cubit_test.dart test/app/app_test.dart`
Expected: FAIL to compile: `readBridgeAutoConnect`, `bridge_cubit.dart` and the `bridge` parameter don't exist.

- [ ] **Step 3: Settings**

In `lib/features/settings/data/settings_repository.dart`, add below `_adbPathKey`:

```dart
  static const _bridgeAutoConnectKey = 'bridgeAutoConnect';
```

and below `writeAdbPath`:

```dart
  /// Whether the web page connects to the bridge by itself (bridge design
  /// §4.4): on after the first connection, off after Disconnect.
  Future<bool> readBridgeAutoConnect() async =>
      await _settings.record(_bridgeAutoConnectKey).get(_db) == 'true';

  Future<void> writeBridgeAutoConnect(bool on) async {
    final record = _settings.record(_bridgeAutoConnectKey);
    if (on) {
      await record.put(_db, 'true');
    } else {
      await record.delete(_db);
    }
  }
```

- [ ] **Step 4: The cubit**

Create `lib/features/devices/cubit/bridge_cubit.dart`:

```dart
import 'dart:async';

import 'package:fcm_studio/features/devices/data/bridge/bridge_client.dart';
import 'package:fcm_studio/features/devices/data/bridge/bridge_status.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// The bridge's status for the Devices screen, and its buttons (bridge
/// design §4.6).
class BridgeCubit extends Cubit<BridgeStatus> {
  BridgeCubit({required BridgeControl control})
    : _control = control,
      super(control.status) {
    _subscription = _control.statuses.listen(emit);
  }

  final BridgeControl _control;
  late final StreamSubscription<BridgeStatus> _subscription;

  Future<void> start() => _control.start();

  void connect() => _control.connect();

  Future<void> disconnect() => _control.disconnect();

  void download() => _control.download();

  @override
  Future<void> close() async {
    await _subscription.cancel();
    return super.close();
  }
}
```

- [ ] **Step 5: The browser layer**

Create `lib/features/devices/data/bridge/bridge_platform.dart`:

```dart
// The browser half of the bridge (bridge design §4.4); desktop and tests
// get stand-ins.
export 'package:fcm_studio/features/devices/data/bridge/bridge_platform_stub.dart'
    if (dart.library.js_interop) 'package:fcm_studio/features/devices/data/bridge/browser/bridge_platform_web.dart';
```

Create `lib/features/devices/data/bridge/bridge_platform_stub.dart`:

```dart
import 'package:fcm_studio/features/devices/data/bridge/bridge_channel.dart';

// Desktop and `flutter test` have no browser. These are only called on the
// web, where bridge_platform_web.dart replaces them.

Future<BridgeChannel> connectBridgeChannel(Uri url) async =>
    throw const BridgeUnreachableException();

Future<bool> bridgeBlockedByBrowser() async => false;

bool pageIsLocal() => false;

void downloadBridgeFile() =>
    throw UnsupportedError('Downloading fcm_bridge.dart needs a browser.');
```

Create `lib/features/devices/data/bridge/browser/bridge_platform_web.dart`:

```dart
import 'dart:async';
import 'dart:js_interop';

import 'package:fcm_studio/features/devices/data/bridge/bridge_channel.dart';
import 'package:web/web.dart' as web;

/// Opens the browser's WebSocket to the bridge (bridge design §4.4).
Future<BridgeChannel> connectBridgeChannel(Uri url) =>
    WebBridgeChannel.connect(url);

/// Whether the browser denied this site access to apps on this computer
/// (Chrome's Local Network Access). Unknown counts as no.
Future<bool> bridgeBlockedByBrowser() async {
  for (final name in const ['loopback-network', 'local-network-access']) {
    try {
      final status = await web.window.navigator.permissions
          .query(_PermissionDescriptor(name: name))
          .toDart;
      if (status.state == 'denied') {
        return true;
      }
    } on Object {
      // This browser doesn't know that permission.
    }
  }
  return false;
}

/// A page served from this computer connects to the bridge by itself.
bool pageIsLocal() {
  final host = web.window.location.hostname;
  return host == 'localhost' || host == '127.0.0.1';
}

/// Saves fcm_bridge.dart, which every web build serves next to index.html.
void downloadBridgeFile() {
  web.HTMLAnchorElement()
    ..href = 'fcm_bridge.dart'
    ..download = 'fcm_bridge.dart'
    ..click();
}

/// The browser's WebSocket as a [BridgeChannel].
class WebBridgeChannel implements BridgeChannel {
  WebBridgeChannel._(this._socket);

  final web.WebSocket _socket;
  final StreamController<String> _messages = StreamController<String>();

  /// Completes once the socket opens; fails if it closes first.
  static Future<BridgeChannel> connect(Uri url) {
    final web.WebSocket socket;
    try {
      socket = web.WebSocket(url.toString());
    } on Object {
      return Future.error(const BridgeUnreachableException());
    }
    final channel = WebBridgeChannel._(socket);
    final opened = Completer<BridgeChannel>();
    socket
      ..onopen = ((web.Event _) {
        if (!opened.isCompleted) {
          opened.complete(channel);
        }
      }).toJS
      ..onmessage = ((web.MessageEvent event) {
        final data = event.data;
        if (data.isA<JSString>()) {
          channel._messages.add((data as JSString).toDart);
        }
      }).toJS
      ..onclose = ((web.CloseEvent _) {
        if (!opened.isCompleted) {
          opened.completeError(const BridgeUnreachableException());
        }
        unawaited(channel._messages.close());
      }).toJS;
    return opened.future;
  }

  @override
  Stream<String> get messages => _messages.stream;

  @override
  void send(String message) => _socket.send(message.toJS);

  @override
  Future<void> close() async => _socket.close();
}

extension type _PermissionDescriptor._(JSObject _) implements JSObject {
  external factory _PermissionDescriptor({required String name});
}
```

- [ ] **Step 6: Wire `AppDependencies`**

In `lib/app/dependencies.dart`:

1. Add the imports:

```dart
import 'package:fcm_studio/features/devices/data/bridge/bridge_adb_service.dart';
import 'package:fcm_studio/features/devices/data/bridge/bridge_client.dart';
import 'package:fcm_studio/features/devices/data/bridge/bridge_platform.dart';
import 'package:fcm_studio/features/devices/data/web_phones.dart';
```

2. Add the factory parameter `BridgeControl? bridge,` after `PhoneAccess? phoneAccess,`.

3. Directly after the `final webUsb = …;` statement, add:

```dart
    final settings = SettingsRepository(database: database);
    // The web's second way to phones (bridge design §4.6). Tests pass their
    // own.
    final bridgeControl = features.canRunAdb
        ? null
        : bridge ??
              BridgeClient(
                connector: connectBridgeChannel,
                readAutoConnect: settings.readBridgeAutoConnect,
                writeAutoConnect: settings.writeBridgeAutoConnect,
                isBlocked: bridgeBlockedByBrowser,
                download: downloadBridgeFile,
                alwaysAutoConnect: pageIsLocal(),
              );
    final webPhones = bridgeControl == null
        ? null
        : WebPhones(
            bridge: bridgeControl,
            bridgeService: BridgeAdbService(bridge: bridgeControl),
            usb: webUsb,
          );
```

4. In the `AppDependencies._(` call:
   - replace `settingsRepository: SettingsRepository(database: database),` with `settingsRepository: settings,`;
   - replace the `adbServiceFor:` argument with:

```dart
      adbServiceFor:
          adbServiceFor ??
          switch (webPhones) {
            final phones? => (_) => phones,
            null => (path) => ProcessAdbService(runner: runner, adbPath: path),
          },
```

   - after `phoneAccess: phoneAccess ?? webUsb,`, add `bridge: bridgeControl,`.

5. Add `required this.bridge,` to the `AppDependencies._({…})` constructor. Then add the field below `phoneAccess`:

```dart
  /// The web's bridge to the computer's adb; null on desktop.
  final BridgeControl? bridge;
```

- [ ] **Step 7: Wire `app.dart`**

In `lib/app/app.dart`:
- add the imports `package:fcm_studio/features/devices/cubit/bridge_cubit.dart` and `package:fcm_studio/features/devices/data/web_phones.dart`;
- remove the `web_usb_adb_service.dart` import.

In the `MultiBlocProvider` providers list, insert before the `DevicesBloc` provider:

```dart
          if (dependencies.bridge case final bridge?)
            BlocProvider(
              lazy: false,
              create: (_) => BridgeCubit(control: bridge)..start(),
            ),
```

Replace the `DevicesBloc` provider's body:

```dart
          BlocProvider(
            lazy: false,
            create: (_) {
              final bloc = DevicesBloc(serviceFor: dependencies.adbServiceFor);
              // There is no adb to find on the web: its phones (WebUSB and
              // the bridge) are tracked at once (bridge design §4.6).
              if (!dependencies.platform.canRunAdb) {
                bloc.add(const DevicesAdbChanged(WebPhones.source));
              }
              return bloc;
            },
          ),
```

- [ ] **Step 8: Run to verify they pass**

Run: `flutter test test/features/settings/settings_repository_test.dart test/features/devices/bridge_cubit_test.dart test/app/app_test.dart`
Expected: PASS.

- [ ] **Step 9: Analyze, build web, run the suite, commit**

```bash
flutter analyze
flutter build web > /tmp/m51_task6_build.log 2>&1; tail -3 /tmp/m51_task6_build.log; test -f build/web/fcm_bridge.dart && echo COPIED
flutter test > /tmp/m51_task6.log 2>&1; tail -3 /tmp/m51_task6.log
dart format lib/ test/
git add lib/features/devices/data/bridge/bridge_platform.dart lib/features/devices/data/bridge/bridge_platform_stub.dart lib/features/devices/data/bridge/browser/bridge_platform_web.dart lib/features/devices/cubit/bridge_cubit.dart lib/features/settings/data/settings_repository.dart lib/app/dependencies.dart lib/app/app.dart test/helpers/app_harness.dart test/features/settings/settings_repository_test.dart test/features/devices/bridge_cubit_test.dart test/app/app_test.dart
git commit -m "feat: wire the bridge into the web app: client, WebPhones, BridgeCubit

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

Expected:
- analyze clean;
- `flutter build web` succeeds (this compiles `bridge_platform_web.dart`) and prints `COPIED`;
- `All tests passed!`
- If `dart format lib/ test/` touches files outside this task, unstage them: only add the files listed.

---

### Task 7: The Devices screen on the web (two buttons, bridge bar, labels)

**Files:**
- Modify: `lib/features/devices/view/devices_screen.dart`
- Modify: `lib/core/platform/platform_capabilities.dart`
- Modify: `lib/features/composer/view/target_picker.dart:113`
- Modify: `test/features/devices/devices_screen_web_test.dart`
- Modify: `test/app/app_test.dart`

**Interfaces:**
- Consumes:
  - `BridgeCubit` (Task 6);
  - `BridgeStatus` and its subclasses, and `BridgeProtocol.startCommand` / `version` (Task 3);
  - `PhoneLink` (Task 5); `FakeBridgeControl` (Task 5); `mockClipboard` (existing).
- Produces (`DevicesScreen`):
  - keys `bridgeMenuKey`, `bridgeConnectKey`, `bridgeDisconnectKey`, `bridgeRetryKey`, `bridgeCopyKey`, `bridgeDownloadKey`, `deviceLinkKey(serial)`;
  - texts `bridgeOffText`, `bridgeConnectingText`, `bridgeConnectedText(adb)`, `bridgeNotRunningText`, `bridgeWrongVersionText(n)`, `bridgeBlockedText`, `emptyWebText`, `emptyBridgeText`, plus the new `noWebUsbMessage` / `notSecureMessage`.

- [ ] **Step 1: Rewrite the web screen test (failing)**

Replace the whole of `test/features/devices/devices_screen_web_test.dart` with:

```dart
import 'package:fcm_studio/core/platform/platform_capabilities.dart';
import 'package:fcm_studio/features/composer/view/target_picker.dart';
import 'package:fcm_studio/features/devices/data/bridge/bridge_status.dart';
import 'package:fcm_studio/features/devices/data/webusb/web_usb_adb_service.dart';
import 'package:fcm_studio/features/devices/domain/adb_device.dart';
import 'package:fcm_studio/features/devices/view/devices_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/app_harness.dart';
import '../../helpers/clipboard.dart';
import '../../helpers/device_fixtures.dart';
import '../../helpers/fake_adb_service.dart';
import '../../helpers/fake_bridge_control.dart';
import '../../helpers/fake_phone_access.dart';

const app = 'com.syldel.delivery';
const webUsb = PlatformFeatures(deviceAccess: DeviceAccess.webUsb);
const noWebUsb = PlatformFeatures(deviceAccess: DeviceAccess.noWebUsb);

void main() {
  late FakeAdbService adb;
  late FakePhoneAccess phones;
  late FakeBridgeControl bridge;

  setUp(() {
    adb = FakeAdbService()..packages[redmiSerial] = ['com.alpha', app];
    phones = FakePhoneAccess();
    bridge = FakeBridgeControl();
  });

  Future<void> openDevices(
    WidgetTester tester, {
    PlatformFeatures platform = webUsb,
  }) async {
    await pumpApp(
      tester,
      await buildTestDependencies(
        tester,
        adb: adb,
        platform: platform,
        phoneAccess: phones,
        bridge: bridge,
      ),
    );
    await addTestProject(tester);
    await tester.tap(find.byKey(const Key('nav-devices')));
    await tester.pumpAndSettle();
  }

  Future<void> phonesAre(WidgetTester tester, List<AdbDevice> devices) async {
    adb.tracker.add(devices);
    await settleAsync(tester);
  }

  Future<void> bridgeIs(WidgetTester tester, BridgeStatus status) async {
    bridge.emit(status);
    await tester.pump();
  }

  AdbDevice phone(
    DeviceState state, {
    String? note,
    PhoneLink link = PhoneLink.usb,
  }) => AdbDevice(
    serial: redmiSerial,
    state: state,
    rawState: state.name,
    model: '2409BRN2CA',
    note: note,
    link: link,
  );

  String? linkText(WidgetTester tester) => tester
      .widget<Text>(find.byKey(DevicesScreen.deviceLinkKey(redmiSerial)))
      .data;

  testWidgets('Connect a phone (USB) opens the browser chooser', (tester) async {
    await openDevices(tester);
    await phonesAre(tester, const []);
    expect(find.text('No phones yet'), findsOneWidget);
    expect(find.text(DevicesScreen.emptyWebText), findsOneWidget);
    expect(find.text('Connect a phone (USB)'), findsOneWidget);
    await tester.tap(find.byKey(DevicesScreen.connectPhoneKey));
    await settleAsync(tester);
    expect(phones.connects, 1);
  });

  testWidgets('a failing chooser is reported in the error banner', (
    tester,
  ) async {
    phones.connectError = StateError('boom');
    await openDevices(tester);
    await tester.tap(find.byKey(DevicesScreen.connectPhoneKey));
    await settleAsync(tester);
    expect(find.textContaining('Could not connect the phone'), findsOneWidget);
  });

  testWidgets('an offline USB phone says why; Retry and Forget reach the browser', (
    tester,
  ) async {
    await openDevices(tester);
    await phonesAre(tester, [
      phone(DeviceState.offline, note: WebUsbAdbService.inUseNote),
    ]);
    expect(find.text(WebUsbAdbService.inUseNote), findsOneWidget);
    expect(linkText(tester), 'USB');

    await tester.tap(find.byKey(DevicesScreen.deviceMenuKey(redmiSerial)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retry'));
    await settleAsync(tester);
    expect(phones.retried, [redmiSerial]);

    await tester.tap(find.byKey(DevicesScreen.deviceMenuKey(redmiSerial)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Forget'));
    await settleAsync(tester);
    expect(phones.forgotten, [redmiSerial]);
  });

  testWidgets('a connecting phone shows Connecting…', (tester) async {
    await openDevices(tester);
    await phonesAre(tester, [
      phone(DeviceState.other, note: WebUsbAdbService.connectingNote),
    ]);
    expect(find.text(WebUsbAdbService.connectingNote), findsOneWidget);
  });

  testWidgets('a ready USB phone lists its apps like on desktop; no Retry', (
    tester,
  ) async {
    await openDevices(tester);
    await phonesAre(tester, [phone(DeviceState.device)]);
    expect(find.byKey(const ValueKey('package-$app')), findsOneWidget);
    await tester.tap(find.byKey(DevicesScreen.deviceMenuKey(redmiSerial)));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsNothing);
    expect(find.text('Forget'), findsOneWidget);
  });

  testWidgets('a bridge phone is labelled Bridge and has no menu', (
    tester,
  ) async {
    await openDevices(tester);
    await phonesAre(tester, [
      phone(DeviceState.device, link: PhoneLink.bridge),
    ]);
    expect(linkText(tester), 'Bridge');
    expect(find.byKey(DevicesScreen.deviceMenuKey(redmiSerial)), findsNothing);
    expect(find.byKey(const ValueKey('package-$app')), findsOneWidget);
  });

  testWidgets('the screen says the browser keeps a key', (tester) async {
    await openDevices(tester);
    await phonesAre(tester, const []);
    expect(find.text(DevicesScreen.keyNotice), findsOneWidget);
  });

  testWidgets('the bridge starts with the app, and its line follows its status', (
    tester,
  ) async {
    await openDevices(tester);
    expect(bridge.starts, 1);
    expect(find.text(DevicesScreen.bridgeOffText), findsOneWidget);
    await bridgeIs(tester, const BridgeConnecting());
    expect(find.text(DevicesScreen.bridgeConnectingText), findsOneWidget);
    await bridgeIs(tester, const BridgeConnected('/sdk/adb'));
    expect(
      find.text(DevicesScreen.bridgeConnectedText('/sdk/adb')),
      findsOneWidget,
    );
    await bridgeIs(tester, const BridgeWrongVersion(2));
    expect(find.text(DevicesScreen.bridgeWrongVersionText(2)), findsOneWidget);
    await bridgeIs(tester, const BridgeNoAdb('adb is missing'));
    expect(find.text('adb is missing'), findsOneWidget);
    await bridgeIs(tester, const BridgeBlocked());
    expect(find.text(DevicesScreen.bridgeBlockedText), findsOneWidget);
  });

  testWidgets('Connect through bridge, Try again and Disconnect reach the bridge', (
    tester,
  ) async {
    await openDevices(tester);
    await tester.tap(find.byKey(DevicesScreen.bridgeConnectKey));
    await tester.pump();
    expect(bridge.connects, 1);
    await bridgeIs(tester, const BridgeNotRunning());
    expect(find.text(DevicesScreen.bridgeNotRunningText), findsOneWidget);
    await tester.tap(find.byKey(DevicesScreen.bridgeRetryKey));
    await tester.pump();
    expect(bridge.connects, 2);
    await bridgeIs(tester, const BridgeConnected('/sdk/adb'));
    await tester.tap(find.byKey(DevicesScreen.bridgeDisconnectKey));
    await settleAsync(tester);
    expect(bridge.disconnects, 1);
  });

  testWidgets('Copy and Download help start the bridge', (tester) async {
    final copied = mockClipboard(tester);
    await openDevices(tester);
    await bridgeIs(tester, const BridgeNotRunning());
    await tester.tap(find.byKey(DevicesScreen.bridgeCopyKey));
    await settleAsync(tester);
    expect(copied(), 'dart fcm_bridge.dart');
    await tester.tap(find.byKey(DevicesScreen.bridgeDownloadKey));
    await tester.pump();
    expect(bridge.downloads, 1);
  });

  testWidgets('the Bridge menu connects and downloads', (tester) async {
    await openDevices(tester);
    await tester.tap(find.byKey(DevicesScreen.bridgeMenuKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Connect through bridge').last);
    await tester.pumpAndSettle();
    expect(bridge.connects, 1);
    await tester.tap(find.byKey(DevicesScreen.bridgeMenuKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Download fcm_bridge.dart').last);
    await tester.pumpAndSettle();
    expect(bridge.downloads, 1);
  });

  testWidgets('without WebUSB, USB is off and says why; the bridge still reads phones', (
    tester,
  ) async {
    await openDevices(tester, platform: noWebUsb);
    final button = tester.widget<FilledButton>(
      find.byKey(DevicesScreen.connectPhoneKey),
    );
    expect(button.onPressed, isNull);
    expect(find.text(DevicesScreen.noWebUsbMessage), findsOneWidget);
    expect(find.text(DevicesScreen.bridgeOffText), findsOneWidget);
    await phonesAre(tester, const []);
    expect(find.text(DevicesScreen.emptyBridgeText), findsOneWidget);
    await phonesAre(tester, [
      phone(DeviceState.device, link: PhoneLink.bridge),
    ]);
    expect(find.byKey(const ValueKey('package-$app')), findsOneWidget);
    await tester.tap(find.byKey(const Key('nav-composer')));
    await tester.pumpAndSettle();
    expect(find.byKey(TargetPicker.fromDeviceKey), findsOneWidget);
  });

  testWidgets('over plain http, USB says to use https', (tester) async {
    await openDevices(
      tester,
      platform: const PlatformFeatures(deviceAccess: DeviceAccess.notSecure),
    );
    expect(find.text(DevicesScreen.notSecureMessage), findsOneWidget);
    expect(find.text(DevicesScreen.bridgeOffText), findsOneWidget);
  });
}
```

In `test/app/app_test.dart`, replace the test 'without WebUSB, Devices stays but From device is hidden' with:

```dart
  testWidgets('without WebUSB, Devices and From device stay: the bridge reads phones', (
    tester,
  ) async {
    await pumpApp(
      tester,
      await buildTestDependencies(
        tester,
        platform: const PlatformFeatures(deviceAccess: DeviceAccess.noWebUsb),
        bridge: FakeBridgeControl(),
      ),
    );
    await addTestProject(tester);
    expect(find.text('Target'), findsOneWidget);
    expect(find.byKey(const Key('nav-devices')), findsOneWidget);
    expect(find.byKey(const Key('nav-settings')), findsNothing);
    expect(find.byKey(TargetPicker.fromDeviceKey), findsOneWidget);
  });
```

- [ ] **Step 2: Run to verify they fail**

Run: `flutter test test/features/devices/devices_screen_web_test.dart test/app/app_test.dart`
Expected: FAIL to compile: `DevicesScreen.bridgeOffText`, `deviceLinkKey` and the other new members are undefined.

- [ ] **Step 3: Remove `canReadPhones`**

In `lib/core/platform/platform_capabilities.dart`, delete the `canReadPhones` getter and its doc comment, and change the class doc to:

```dart
/// What this platform can do (spec §3.1; WebUSB design §4.9; bridge design
/// §4.6). Every platform can read phones: adb on desktop, WebUSB or the
/// bridge on the web.
```

In `lib/features/composer/view/target_picker.dart`, change:

```dart
              if (context.read<PlatformFeatures>().canReadPhones)
                TextButton.icon(
```

to:

```dart
              TextButton.icon(
```

and re-indent that `TextButton.icon(...)` block one level out. If `PlatformFeatures` is now unused in `target_picker.dart`, remove its import.

- [ ] **Step 4: Rewrite the top of `devices_screen.dart`**

In `lib/features/devices/view/devices_screen.dart`:

1. **Imports:** replace the import block with:

```dart
import 'package:fcm_studio/app/app_error_cubit.dart';
import 'package:fcm_studio/app/navigation_cubit.dart';
import 'package:fcm_studio/core/platform/platform_capabilities.dart';
import 'package:fcm_studio/features/devices/bloc/devices_bloc.dart';
import 'package:fcm_studio/features/devices/cubit/bridge_cubit.dart';
import 'package:fcm_studio/features/devices/cubit/token_reader_cubit.dart';
import 'package:fcm_studio/features/devices/data/bridge/bridge_protocol.dart';
import 'package:fcm_studio/features/devices/data/bridge/bridge_status.dart';
import 'package:fcm_studio/features/devices/data/phone_access.dart';
import 'package:fcm_studio/features/devices/domain/adb_device.dart';
import 'package:fcm_studio/features/devices/domain/device_token.dart';
import 'package:fcm_studio/features/devices/view/device_actions.dart';
import 'package:fcm_studio/features/devices/view/token_read_view.dart';
import 'package:fcm_studio/features/projects/cubit/projects_cubit.dart';
import 'package:fcm_studio/features/settings/cubit/adb_setup_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
```

2. **Class doc and constants:** replace the class doc and every member from `static const openSettingsKey` through the end of `static const keyNotice = …;` with:

```dart
/// Plugged-in phones, their apps, and reading an app's token (spec §9; on
/// the web through WebUSB or the bridge: WebUSB design §4.9, bridge design
/// §4.6).
class DevicesScreen extends StatelessWidget {
  const DevicesScreen({super.key});

  static const openSettingsKey = Key('devices-open-settings');
  static const connectPhoneKey = Key('devices-connect-phone');
  static const bridgeMenuKey = Key('devices-bridge-menu');
  static const bridgeConnectKey = Key('devices-bridge-connect');
  static const bridgeDisconnectKey = Key('devices-bridge-disconnect');
  static const bridgeRetryKey = Key('devices-bridge-retry');
  static const bridgeCopyKey = Key('devices-bridge-copy');
  static const bridgeDownloadKey = Key('devices-bridge-download');

  static Key deviceMenuKey(String serial) => ValueKey('device-menu-$serial');
  static Key deviceLinkKey(String serial) => ValueKey('device-link-$serial');

  static const noWebUsbMessage =
      'Connecting a phone over USB needs Chrome or Edge. Use the bridge '
      'instead.';
  static const notSecureMessage =
      'Connecting a phone over USB needs FCM Studio opened over https. Use '
      'the bridge instead.';
  static const keyNotice =
      'This browser keeps a USB debugging key for this site. Forget removes '
      'its access to a phone.';
  static const emptyWebText =
      'Start the bridge (if you have adb), or turn on USB debugging, plug the '
      'phone in, and click Connect a phone (USB).';
  static const emptyBridgeText =
      'Start the bridge to read phones through adb on this computer.';

  static const bridgeOffText = 'Bridge: off';
  static const bridgeConnectingText = 'Bridge: connecting…';
  static String bridgeConnectedText(String adbPath) =>
      'Bridge: connected · adb: $adbPath';
  static const bridgeNotRunningText =
      "The bridge isn't running. In the folder where you saved it, run "
      '`${BridgeProtocol.startCommand}`. '
      "If it's running, its window says why it refused this page.";
  static String bridgeWrongVersionText(int bridgeProtocol) =>
      "This fcm_bridge.dart doesn't match this page (bridge protocol "
      '$bridgeProtocol, page ${BridgeProtocol.version}). Download it again '
      'and restart it.';
  static const bridgeBlockedText =
      'The browser is blocking this site from reaching apps on this '
      'computer. Allow it in the site settings (the icon left of the '
      'address), then try again.';
```

Keep `_readyPhone`, `_singleToken` and `_connectPhone` as they are.

3. **`build`:** replace the whole method with:

```dart
  @override
  Widget build(BuildContext context) {
    final access = context.read<PlatformFeatures>().deviceAccess;
    final onWeb = access != DeviceAccess.adb;
    final webUsb = access == DeviceAccess.webUsb;
    return MultiBlocListener(
      listeners: [
        BlocListener<DevicesBloc, DevicesState>(
          listenWhen: (previous, current) =>
              _readyPhone(previous) != _readyPhone(current),
          listener: (context, state) {
            final device = state.selected;
            final adbPath = state.adbPath;
            final reader = context.read<TokenReaderCubit>();
            if (device != null &&
                device.isReady &&
                adbPath != null &&
                (reader.state.serial != device.serial ||
                    reader.adbPath != adbPath)) {
              reader.openDevice(adbPath, device.serial);
            }
          },
        ),
        BlocListener<TokenReaderCubit, TokenReaderState>(
          // A single token is used straight away.
          listenWhen: (previous, current) =>
              previous.read != current.read &&
              _singleToken(current.read) != null,
          listener: (context, state) {
            final found = state.read as TokenReadFound;
            useDeviceToken(
              context,
              package: found.package,
              found: found.tokens.single,
              method: found.method,
            );
          },
        ),
      ],
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Devices'),
          actions: [
            if (onWeb) ...[
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilledButton.icon(
                  key: connectPhoneKey,
                  onPressed: webUsb ? () => _connectPhone(context) : null,
                  icon: const Icon(Icons.usb),
                  label: const Text('Connect a phone (USB)'),
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(right: 12),
                child: _BridgeMenu(),
              ),
            ],
          ],
        ),
        body: BlocBuilder<DevicesBloc, DevicesState>(
          builder: (context, state) {
            if (state.status == TrackerStatus.noAdb && !onWeb) {
              return const _NoAdb();
            }
            final lists = Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 320,
                  child: _DeviceList(
                    state: state,
                    onWeb: onWeb,
                    webUsb: webUsb,
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: _DevicePanel(state: state)),
              ],
            );
            if (!onWeb) {
              return lists;
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _BridgeBar(
                  usbProblem: switch (access) {
                    DeviceAccess.noWebUsb => noWebUsbMessage,
                    DeviceAccess.notSecure => notSecureMessage,
                    _ => null,
                  },
                ),
                const Divider(height: 1),
                Expanded(child: lists),
              ],
            );
          },
        ),
      ),
    );
  }
}
```

4. **Remove `_NoPhoneAccess`:** delete the whole class.

5. **Add the bridge widgets:** insert them directly above `class _NoAdb`:

```dart
enum _BridgeAction { connect, disconnect, download, copy }

/// What the bridge buttons and menu do.
Future<void> _runBridgeAction(
  BuildContext context,
  _BridgeAction action,
) async {
  final bridge = context.read<BridgeCubit>();
  final errors = context.read<AppErrorCubit>();
  final messenger = ScaffoldMessenger.of(context);
  try {
    switch (action) {
      case _BridgeAction.connect:
        bridge.connect();
      case _BridgeAction.disconnect:
        await bridge.disconnect();
      case _BridgeAction.download:
        bridge.download();
      case _BridgeAction.copy:
        await Clipboard.setData(
          const ClipboardData(text: BridgeProtocol.startCommand),
        );
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Copied: ${BridgeProtocol.startCommand}'),
          ),
        );
    }
  } on Object catch (error) {
    errors.report(error, context: 'The bridge action failed');
  }
}

/// The app bar's Bridge menu (bridge design §4.6).
class _BridgeMenu extends StatelessWidget {
  const _BridgeMenu();

  @override
  Widget build(BuildContext context) {
    final off = context.watch<BridgeCubit>().state is BridgeOff;
    return PopupMenuButton<_BridgeAction>(
      key: DevicesScreen.bridgeMenuKey,
      tooltip: 'Bridge options',
      onSelected: (action) => _runBridgeAction(context, action),
      itemBuilder: (context) => [
        if (off)
          const PopupMenuItem(
            value: _BridgeAction.connect,
            child: Text('Connect through bridge'),
          )
        else
          const PopupMenuItem(
            value: _BridgeAction.disconnect,
            child: Text('Disconnect'),
          ),
        const PopupMenuItem(
          value: _BridgeAction.download,
          child: Text('Download fcm_bridge.dart'),
        ),
        const PopupMenuItem(
          value: _BridgeAction.copy,
          child: Text('Copy the start command'),
        ),
      ],
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cable),
            SizedBox(width: 4),
            Text('Bridge'),
            Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }
}

/// The bridge's status line with what to do next (bridge design §6), and
/// why USB is unavailable in this browser.
class _BridgeBar extends StatelessWidget {
  const _BridgeBar({required this.usbProblem});

  final String? usbProblem;

  @override
  Widget build(BuildContext context) {
    final status = context.watch<BridgeCubit>().state;
    Widget button(Key key, String label, _BridgeAction action) => TextButton(
      key: key,
      onPressed: () => _runBridgeAction(context, action),
      child: Text(label),
    );
    final retry = button(
      DevicesScreen.bridgeRetryKey,
      'Try again',
      _BridgeAction.connect,
    );
    final download = button(
      DevicesScreen.bridgeDownloadKey,
      'Download fcm_bridge.dart',
      _BridgeAction.download,
    );
    final (IconData icon, String text, List<Widget> actions) =
        switch (status) {
          BridgeOff() => (
            Icons.cable,
            DevicesScreen.bridgeOffText,
            <Widget>[
              button(
                DevicesScreen.bridgeConnectKey,
                'Connect through bridge',
                _BridgeAction.connect,
              ),
            ],
          ),
          BridgeConnecting() => (
            Icons.sync,
            DevicesScreen.bridgeConnectingText,
            <Widget>[],
          ),
          BridgeConnected(:final adbPath) => (
            Icons.check_circle_outline,
            DevicesScreen.bridgeConnectedText(adbPath),
            <Widget>[
              button(
                DevicesScreen.bridgeDisconnectKey,
                'Disconnect',
                _BridgeAction.disconnect,
              ),
            ],
          ),
          BridgeNotRunning() => (
            Icons.cable,
            DevicesScreen.bridgeNotRunningText,
            <Widget>[
              button(DevicesScreen.bridgeCopyKey, 'Copy', _BridgeAction.copy),
              download,
              retry,
            ],
          ),
          BridgeWrongVersion(:final bridgeProtocol) => (
            Icons.error_outline,
            DevicesScreen.bridgeWrongVersionText(bridgeProtocol),
            <Widget>[download],
          ),
          BridgeNoAdb(:final problem) => (
            Icons.error_outline,
            problem,
            <Widget>[retry],
          ),
          BridgeBlocked() => (
            Icons.block,
            DevicesScreen.bridgeBlockedText,
            <Widget>[retry],
          ),
        };
    final problem = usbProblem;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(text)),
              ...actions,
            ],
          ),
          if (problem != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  const Icon(Icons.usb_off, size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: Text(problem)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// "USB" or "Bridge": how a web phone is reached.
class _LinkLabel extends StatelessWidget {
  const _LinkLabel({required this.serial, required this.link});

  final String serial;
  final PhoneLink link;

  @override
  Widget build(BuildContext context) => Text(
    switch (link) {
      PhoneLink.usb => 'USB',
      PhoneLink.bridge => 'Bridge',
    },
    key: DevicesScreen.deviceLinkKey(serial),
    style: Theme.of(context).textTheme.labelSmall,
  );
}
```

6. **Update `_DeviceList`:**
   - Its constructor and fields become:

```dart
class _DeviceList extends StatelessWidget {
  const _DeviceList({
    required this.state,
    required this.onWeb,
    required this.webUsb,
  });

  final DevicesState state;
  final bool onWeb;
  final bool webUsb;
```

   - The starting tile's title becomes `Text(onWeb ? 'Looking for phones…' : 'Starting adb…')`.
   - The empty-state tile becomes:

```dart
        if (state.status == TrackerStatus.running && state.devices.isEmpty)
          ListTile(
            leading: const Icon(Icons.phone_android),
            title: Text(onWeb ? 'No phones yet' : 'No phone connected'),
            subtitle: Text(
              webUsb
                  ? DevicesScreen.emptyWebText
                  : onWeb
                  ? DevicesScreen.emptyBridgeText
                  : 'Connect an Android phone with USB debugging turned on.',
            ),
          ),
```

   - Each device tile's `trailing:` becomes:

```dart
            trailing: switch (device.link) {
              PhoneLink.bridge => _LinkLabel(
                serial: device.serial,
                link: PhoneLink.bridge,
              ),
              PhoneLink.usb => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _LinkLabel(serial: device.serial, link: PhoneLink.usb),
                  _PhoneMenu(device: device),
                ],
              ),
              null => null,
            },
```

   - The `keyNotice` padding stays under `if (webUsb)`.

- [ ] **Step 5: Run to verify they pass**

Run: `flutter test test/features/devices/devices_screen_web_test.dart test/features/devices/devices_screen_test.dart test/app/app_test.dart test/features/composer/`
Expected: PASS (web screen, desktop screen unchanged, app, composer).

- [ ] **Step 6: Analyze, run the suite, commit**

```bash
flutter analyze
flutter test > /tmp/m51_task7.log 2>&1; tail -3 /tmp/m51_task7.log
dart format lib/features/devices/view/devices_screen.dart lib/core/platform/platform_capabilities.dart lib/features/composer/view/target_picker.dart test/features/devices/devices_screen_web_test.dart test/app/app_test.dart
git add lib/features/devices/view/devices_screen.dart lib/core/platform/platform_capabilities.dart lib/features/composer/view/target_picker.dart test/features/devices/devices_screen_web_test.dart test/app/app_test.dart
git commit -m "feat: Devices on the web: USB and Bridge buttons, bridge status, link labels

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

Expected: analyze clean; `All tests passed!` If any other test referenced `canReadPhones` or the old `'Connect a phone…'` label, update it to the new behaviour and list it in the task's ledger line.

---

### Task 8: Docs (specs and status)

**Files:**
- Modify: `docs/superpowers/specs/2026-10-05-web-bridge-design.md`
- Modify: `docs/superpowers/specs/2026-10-03-fcm-studio-design.md`
- Modify: `docs/superpowers/specs/2026-10-04-webusb-devices-design.md`

**Interfaces:** none (documentation).

- [ ] **Step 1: Bridge design status and §7**

In `docs/superpowers/specs/2026-10-05-web-bridge-design.md`, replace the status line with:

```markdown
**Status:**
- **Implemented:** 2026-10-05 (M5.1 code with tests).
- **Pending:** the manual success test in §9, on the Redmi in Chrome, Firefox and Safari.
```

Replace the §7 row that starts `| A command is refused` with:

```markdown
| A command is refused (only possible with a mismatched file) | The read's error: "`adb -s <serial> shell …` (through the bridge) failed: fcm_bridge refused this command." |
```

- [ ] **Step 2: Main spec §3.1, §9 and §13**

In `docs/superpowers/specs/2026-10-03-fcm-studio-design.md`:

**§3.1:** in the footnote line that begins `` `*` On desktop the device feature runs adb. ``, replace its last sentence, "Other browsers show an explanation on the Devices screen instead.", with:

```markdown
From M5.1, any browser can also reach phones through a small local bridge program that runs the computer's adb, so the phone stays shared with IDEs ([2026-10-05-web-bridge-design.md](2026-10-05-web-bridge-design.md)).
```

**§9:**
- Replace the heading `## 9. Device tokens (desktop: adb; web: WebUSB)` with `## 9. Device tokens (desktop: adb; web: WebUSB or the local bridge)`.
- In the next paragraph, after the sentence ending "…see [2026-10-04-webusb-devices-design.md](2026-10-04-webusb-devices-design.md).", add: ` The web can also run them through the local bridge (M5.1); see [2026-10-05-web-bridge-design.md](2026-10-05-web-bridge-design.md).`

**§13:**
- In the milestone table, insert after the M5 row:

```markdown
| M5.1 | **Phones on the web through a local bridge.** `fcm_bridge.dart` (loopback WebSocket, Origin check, command allow-list), `BridgeClient`, `WebPhones`, two connect options on the web Devices screen ([design](2026-10-05-web-bridge-design.md)) | The bridge success test (design §9) passes on the Redmi in Chrome |
```

- After the **M5 status (2026-10-04)** block, add:

```markdown
**M5.1 status (2026-10-05):**
- *Done:* the M5.1 code with its automated tests passing and a clean `flutter analyze`; `flutter build web` succeeds and serves `fcm_bridge.dart`.
- *Covered by tests:* the bridge's rules and server (with a fake adb), the page's client, shell, service and `WebPhones`, and a real-WebSocket end-to-end read. The browser layer (`bridge/browser/`) is checked by compiling it.
- *Manual, pending:* the bridge success test (bridge design §9). It also fills in the design's "to check" rows.
```

- [ ] **Step 3: WebUSB design §11**

In `docs/superpowers/specs/2026-10-04-webusb-devices-design.md`, replace the line `- Firefox and Safari: no WebUSB.` with:

```markdown
- Firefox and Safari: no WebUSB. They can use the local bridge instead ([2026-10-05-web-bridge-design.md](2026-10-05-web-bridge-design.md)).
```

- [ ] **Step 4: Check and commit**

Run: `grep -n "M5.1" docs/superpowers/specs/2026-10-03-fcm-studio-design.md | head; grep -n "local bridge" docs/superpowers/specs/2026-10-04-webusb-devices-design.md`
Expected: the new M5.1 row and status lines; the new WebUSB §11 line.

```bash
git add docs/superpowers/specs/2026-10-05-web-bridge-design.md docs/superpowers/specs/2026-10-03-fcm-studio-design.md docs/superpowers/specs/2026-10-04-webusb-devices-design.md
git commit -m "docs: record M5.1 (phones on the web through the bridge) status

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

## Final verification (after Task 8)

- `flutter analyze`: `No issues found!`
- `flutter test`: `All tests passed!` (639 before M5.1, plus the new tests).
- `flutter build web` succeeds, and `build/web/fcm_bridge.dart` exists.
- `dart web/fcm_bridge.dart --help` prints the usage.
- **Manual (the user, spec §9):**
  1. Run `dart fcm_bridge.dart` in a terminal.
  2. Open `flutter run -d chrome --web-port 5050`; it connects by itself, because the page is local.
  3. Read a token from the Redmi while Antigravity runs an app on it.
