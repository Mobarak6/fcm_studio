# FCM Studio M5: Phones on the Web (WebUSB) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The web build reads FCM tokens from a USB-connected Android phone in Chrome or Edge, the way the desktop app does with adb.

**Architecture:**
- A pure-Dart adb client talks to the phone through a `UsbTransport` interface. It covers the message codec, RSA key pairing, multiplexed streams and shell v2.
- In the browser, the transport is a thin js_interop layer over `navigator.usb`.
- `WebUsbAdbService` implements the existing `AdbService`. Desktop and web share every phone command through a new `AdbCommands` + `DeviceShell` seam, so the Devices screen, `DevicesBloc` and `TokenReaderCubit` are reused unchanged.

**Tech Stack:** Flutter 3.44.9 / Dart 3.12, flutter_bloc, Equatable, `dart:js_interop` + `package:web` 1.1.1, WebCrypto, flutter_test.

**Spec:** [docs/superpowers/specs/2026-10-04-webusb-devices-design.md](../specs/2026-10-04-webusb-devices-design.md). The desktop device feature it extends is main spec [§9](../specs/2026-10-03-fcm-studio-design.md).

**Already proven (2026-10-04, scratch prototype, not in the repo):**
- The `AdbKey`, `AdbMessage`, `AdbConnection`, `ShellV2`, `WebUsbAdbService` and fake-phone code below passed 45 unit tests.
- The signature matches `openssl pkeyutl -pkeyopt digest:sha1`, and the Android public key matches `adb keygen` byte for byte.
- The browser files analyze clean and compile with `dart compile js`.
- dart2js signing takes about 160 ms with CRT (about 510 ms without), measured in Node 22.

## Global Constraints

- **Branch:** work on `main`.
- **Commits:** every commit message ends with `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`.
- **Never stage:** `devtools_options.yaml`, `config/oauth.json`, `config/oauth.example.json` or `.superpowers/`.
- **Desktop unchanged:** every existing test still passes. Existing tests change only where a task says so.
- **Tokens and logcat:**
  - Device tokens never appear in logs or error messages (`FcmTokenPattern.inText` → `<token>`, `redact()`).
  - Never run `logcat -c`.
- **Browser-only imports:** only the four files in `lib/features/devices/data/webusb/browser/` may import `dart:js_interop`, `dart:js_interop_unsafe` or `package:web`. `lib/features/devices/data/webusb/webusb_platform.dart` reaches them through a conditional export. Everything else must run in `flutter test` (the VM).
- **adb values, verbatim** (design §4.3–4.6):

  | Item | Value |
  |---|---|
  | `CNXN` | `0x4E584E43` |
  | `AUTH` | `0x48545541` |
  | `OPEN` | `0x4E45504F` |
  | `OKAY` | `0x59414B4F` |
  | `WRTE` | `0x45545257` |
  | `CLSE` | `0x45534C43` |
  | Version | `0x01000001` |
  | Max payload | `1048576` |
  | Host banner | `host::features=shell_v2,cmd` |
  | `AUTH` types | 1 token, 2 signature, 3 public key |
  | Shell service | `shell,v2,raw:<command>` |
  | Shell v2 packet IDs | 1 stdout, 2 stderr, 3 exit |
  | adb USB interface | class `0xFF`, subclass `0x42`, protocol `0x01` |

- **The browser key** is stored in `SecretStore` under `adb:browser-key`, written with `persist: true`.
- **Platform support:** Android 7+ only (`shell_v2`), Chromium browsers only, USB only.
- **User-visible strings:** exactly as written in the tasks (design §7).
- **Repo style:**
  - private named constructor parameters (`required this._x`, called as `x:`);
  - `prefer_final_locals`, single quotes;
  - `unawaited(...)` for fire-and-forget futures;
  - strict casts, inference and raw types (see `analysis_options.yaml`).
- **Whole suite:** `flutter test`. `flutter analyze` must print `No issues found!`

## Review Focus

These five ways the feature could fail aren't covered by any task's main tests. Each one gets a test in the task that owns the code.

1. **Unplugged while waiting, then replugged:** a phone unplugged while it waits for "Allow USB debugging?" and plugged in again shows one row and connects. No stale or duplicate row. (Task 7 test "unplugged while waiting for approval, then plugged in again")
2. **Two commands at once:** selecting a phone runs device details and the package list together. Each stream on the one connection must get only its own data. (Task 4 test "two streams at once get their own data")
3. **Connect for a listed phone:** **Connect a phone…** for a phone already listed as offline retries it, without adding a duplicate row. (Task 7 test "choosing a phone that is already listed and offline retries it, no duplicate")
4. **Damaged key:** a damaged stored key (for example, site data cleared in the middle of a write) is replaced by a new one. The phone asks once more, and nothing crashes. (Task 6 test "a damaged stored key is replaced")
5. **Cancelled logcat read:** cancelling a logcat read closes its stream on the phone (`CLSE`), so logcat stops there. (Task 5 test "a running process streams stdout; kill closes it on the phone")

## File map

| File | Responsibility | Task |
|---|---|---|
| `lib/features/devices/data/adb_exception.dart` | `AdbException` (moved out of `adb_service.dart`, re-exported there) | 1 |
| `lib/features/devices/data/device_shell.dart` | `PhoneCommand`, `DeviceShell`, `ProcessDeviceShell` (desktop) | 1 |
| `lib/features/devices/data/adb_commands.dart` | The shared phone commands (details, packages, `run-as`, launch, logcat) | 1 |
| `lib/features/devices/data/adb_service.dart` | `AdbService`; `ProcessAdbService` = adb `track-devices` + `AdbCommands` | 1 |
| `lib/features/devices/data/webusb/adb_message.dart` | 24-byte header codec, command constants | 2 |
| `lib/features/devices/data/webusb/adb_key.dart` | RSA signing, Android public key format | 3 |
| `lib/features/devices/data/webusb/usb_transport.dart` | `UsbTransport` interface + USB exceptions | 4 |
| `lib/features/devices/data/webusb/adb_connection.dart` | Handshake, `AdbStream`s, `AdbBanner`, failure messages | 4 |
| `lib/features/devices/data/webusb/shell_v2.dart` | Shell v2 packets, `runShellV2`, `ShellV2Process` | 5 |
| `lib/features/devices/data/webusb/adb_key_store.dart` | Makes and keeps the browser key in `SecretStore` | 6 |
| `lib/features/devices/domain/adb_device.dart` | + `note` (why a phone is offline or connecting) | 7 |
| `lib/features/devices/data/phone_access.dart` | `PhoneAccess` (connect, retry, forget) for the screen | 7 |
| `lib/features/devices/data/webusb/usb_phone.dart` | `UsbPhone`, `UsbPhoneSource` interfaces | 7 |
| `lib/features/devices/data/webusb/web_usb_device_shell.dart` | `DeviceShell` over shell v2 | 7 |
| `lib/features/devices/data/webusb/web_usb_adb_service.dart` | Phone list, connection per phone, `AdbService` + `PhoneAccess` | 7 |
| `lib/core/platform/device_access.dart` | `enum DeviceAccess { adb, webUsb, noWebUsb, notSecure }` | 8 |
| `lib/features/devices/data/webusb/browser/usb_interop.dart` | js_interop types for `navigator.usb` | 8 |
| `lib/features/devices/data/webusb/browser/web_usb_transport.dart` | `WebUsbTransport`, `findAdbInterface` | 8 |
| `lib/features/devices/data/webusb/browser/web_usb_phone.dart` | `WebUsbPhone`, `WebUsbPhoneSource` | 8 |
| `lib/features/devices/data/webusb/browser/webusb_platform_web.dart` | Browser detection, phone source, WebCrypto key, key name | 8 |
| `lib/features/devices/data/webusb/webusb_platform.dart` / `webusb_platform_stub.dart` | Conditional export / VM stand-ins | 8 |
| `lib/core/platform/platform_capabilities.dart` | `PlatformFeatures(deviceAccess:)`, `canRunAdb`, `canReadPhones` | 9 |
| `lib/app/dependencies.dart`, `lib/app/app.dart`, `lib/app/shell.dart`, `lib/features/composer/view/target_picker.dart` | Wiring and navigation | 9 |
| `lib/features/devices/view/devices_screen.dart` | **Connect a phone…**, notes, Retry and Forget, explanations | 10 |
| Test helpers: `fake_usb_transport.dart`, `fake_adbd.dart`, `fake_usb_phone.dart`, `adb_key_fixture.dart`, `fake_phone_access.dart` | Scripted phone side | 3–9 |
| Fixtures: `test/fixtures/adb/test_adbkey.jwk.json`, `test_adbkey.pub`, `test_adbkey_signature.hex` | Throwaway `adb keygen` key | 3 |

---

### Task 1: Shared phone commands (`AdbCommands` + `DeviceShell`)

Move the phone-side logic out of `ProcessAdbService` into `AdbCommands`, which runs commands through a `DeviceShell`. On desktop the shell runs adb exactly as today, so every M3 test passes unchanged. The web gets its own shell in Task 7.

**Files:**
- Create: `lib/features/devices/data/adb_exception.dart`
- Create: `lib/features/devices/data/device_shell.dart`
- Create: `lib/features/devices/data/adb_commands.dart`
- Modify: `lib/features/devices/data/adb_service.dart`
- Test: `test/features/devices/adb_commands_test.dart` (new). `test/features/devices/adb_service_test.dart` must pass **unchanged**.

**Interfaces:**
- Produces:
  - `class AdbException implements Exception { const AdbException(String message); final String message; }`, still importable from `adb_service.dart` through a re-export.
  - `enum PhoneCommandKind { shell, execOut, logcat }`.
  - `class PhoneCommand`, with `const PhoneCommand.shell(String text)`, `const PhoneCommand.execOut(String text)`, `const PhoneCommand.logcat(String text)`, `kind`, `text`, and `String get shellText` (logcat → `'logcat $text'`).
  - `abstract interface class DeviceShell`, with `Future<ProcessOutput> run(String serial, PhoneCommand command)`, `Future<RunningProcess> start(String serial, PhoneCommand command)` and `String describe(String serial, PhoneCommand command)`. `describe` returns the command already in backticks.
  - `class ProcessDeviceShell implements DeviceShell { ProcessDeviceShell({required ProcessRunner runner, required String adbPath}); }`.
  - `class AdbCommands { AdbCommands({required DeviceShell shell, Duration pollInterval, Duration appStartTimeout, Duration logcatTimeout}); static const tokenFile; deviceDetails; listPackages; readTokenWithRunAs; launchApp; readTokenFromLogcat; }`. It has the same signatures as the `AdbService` methods of those names.

- [ ] **Step 1: Write the failing test**

Create `test/features/devices/adb_commands_test.dart`:

```dart
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/features/devices/adb_commands_test.dart`
Expected: FAIL to compile: `adb_commands.dart`, `adb_exception.dart` and `device_shell.dart` don't exist.

- [ ] **Step 3: Create `adb_exception.dart`**

Create `lib/features/devices/data/adb_exception.dart`:

```dart
/// A phone command that failed. The message names the command (spec §11).
class AdbException implements Exception {
  const AdbException(this.message);

  final String message;

  @override
  String toString() => 'AdbException: $message';
}
```

- [ ] **Step 4: Create `device_shell.dart`**

Create `lib/features/devices/data/device_shell.dart`:

```dart
import 'package:fcm_studio/features/devices/data/adb_exception.dart';
import 'package:fcm_studio/features/devices/data/process_runner.dart';

/// How desktop adb runs a phone command (WebUSB design §4.7).
enum PhoneCommandKind { shell, execOut, logcat }

/// A command run on the phone.
class PhoneCommand {
  const PhoneCommand.shell(this.text) : kind = PhoneCommandKind.shell;

  /// Byte-for-byte output, e.g. `run-as <package> cat <file>`.
  const PhoneCommand.execOut(this.text) : kind = PhoneCommandKind.execOut;

  /// `logcat` with [text] as its arguments.
  const PhoneCommand.logcat(this.text) : kind = PhoneCommandKind.logcat;

  final PhoneCommandKind kind;
  final String text;

  /// The command line in the phone's shell.
  String get shellText =>
      kind == PhoneCommandKind.logcat ? 'logcat $text' : text;
}

/// Runs commands on a phone: adb on desktop, WebUSB on the web.
abstract interface class DeviceShell {
  /// Runs [command] to the end. A non-zero exit code is not an error;
  /// throws [AdbException] when the command can't run at all.
  Future<ProcessOutput> run(String serial, PhoneCommand command);

  /// Starts a long-running [command]. Throws [AdbException] when it can't
  /// start.
  Future<RunningProcess> start(String serial, PhoneCommand command);

  /// How messages name [command], already in backticks.
  String describe(String serial, PhoneCommand command);
}

/// Desktop: `adb -s <serial> shell|exec-out|logcat …`, exactly as M3 ran it.
class ProcessDeviceShell implements DeviceShell {
  ProcessDeviceShell({required this._runner, required this._adbPath});

  final ProcessRunner _runner;
  final String _adbPath;

  List<String> _arguments(String serial, PhoneCommand command) => [
    '-s',
    serial,
    ...switch (command.kind) {
      PhoneCommandKind.shell => ['shell', command.text],
      PhoneCommandKind.execOut => ['exec-out', ...command.text.split(' ')],
      PhoneCommandKind.logcat => ['logcat', ...command.text.split(' ')],
    },
  ];

  @override
  Future<ProcessOutput> run(String serial, PhoneCommand command) async {
    try {
      return await _runner.run(_adbPath, _arguments(serial, command));
    } on ProcessRunException catch (e) {
      throw AdbException(e.message);
    }
  }

  @override
  Future<RunningProcess> start(String serial, PhoneCommand command) async {
    try {
      return await _runner.start(_adbPath, _arguments(serial, command));
    } on ProcessRunException catch (e) {
      throw AdbException(e.message);
    }
  }

  @override
  String describe(String serial, PhoneCommand command) =>
      '`${describeCommand(_adbPath, _arguments(serial, command))}`';
}
```

- [ ] **Step 5: Create `adb_commands.dart`**

This is the logic from today's `ProcessAdbService`, unchanged in behaviour, running through the shell. Create `lib/features/devices/data/adb_commands.dart`:

```dart
import 'dart:async';
import 'dart:convert';

import 'package:fcm_studio/core/utils/redact.dart';
import 'package:fcm_studio/features/devices/data/adb_exception.dart';
import 'package:fcm_studio/features/devices/data/device_shell.dart';
import 'package:fcm_studio/features/devices/data/parsers/app_id_prefs_parser.dart';
import 'package:fcm_studio/features/devices/data/parsers/fcm_token_pattern.dart';
import 'package:fcm_studio/features/devices/data/parsers/package_list_parser.dart';
import 'package:fcm_studio/features/devices/data/parsers/run_as_outcome.dart';
import 'package:fcm_studio/features/devices/data/process_runner.dart';
import 'package:fcm_studio/features/devices/domain/adb_device.dart';
import 'package:fcm_studio/features/devices/domain/token_read_results.dart';

/// The phone commands desktop and web both run (spec §9.2, §9.3; WebUSB
/// design §4.7).
class AdbCommands {
  AdbCommands({
    required this._shell,
    this._pollInterval = const Duration(milliseconds: 250),
    this._appStartTimeout = const Duration(seconds: 10),
    this._logcatTimeout = const Duration(seconds: 20),
  });

  static const tokenFile = 'shared_prefs/com.google.android.gms.appid.xml';

  final DeviceShell _shell;
  final Duration _pollInterval;
  final Duration _appStartTimeout;
  final Duration _logcatTimeout;

  Future<DeviceDetails> deviceDetails(String serial) async {
    final output = await _checked(
      serial,
      const PhoneCommand.shell(
        'getprop ro.product.marketname; getprop ro.product.model; '
        'getprop ro.product.brand; getprop ro.build.version.release',
      ),
    );
    final lines = const LineSplitter()
        .convert(output.stdout)
        .map((line) => line.trim())
        .toList();
    String at(int index) => index < lines.length ? lines[index] : '';
    final name = at(0).isNotEmpty
        ? at(0)
        : at(1).isNotEmpty
        ? at(1)
        : serial;
    return DeviceDetails(name: name, brand: at(2), androidVersion: at(3));
  }

  Future<List<String>> listPackages(String serial) async => parsePackageList(
    (await _checked(
      serial,
      const PhoneCommand.shell('pm list packages -3'),
    )).stdout,
  );

  Future<RunAsResult> readTokenWithRunAs(String serial, String package) async {
    final command = PhoneCommand.execOut('run-as $package cat $tokenFile');
    final ProcessOutput output;
    try {
      output = await _shell.run(serial, command);
    } on AdbException catch (e) {
      return RunAsFailed(e.message);
    }
    switch (classifyRunAs(output)) {
      case RunAsOutcome.file:
        final tokens = AppIdPrefsParser.parse(output.stdout);
        return tokens.isEmpty ? const RunAsNoTokenYet() : RunAsTokens(tokens);
      case RunAsOutcome.notDebuggable:
        return const RunAsReleaseBuild();
      case RunAsOutcome.noSuchFile:
        return const RunAsNoTokenYet();
      case RunAsOutcome.unknownPackage:
        return const RunAsNotInstalled();
      case RunAsOutcome.error:
        return RunAsFailed(_failed(serial, command, output));
    }
  }

  Future<void> launchApp(String serial, String package) async {
    final command = PhoneCommand.shell(
      'monkey -p $package -c android.intent.category.LAUNCHER 1',
    );
    final output = await _checked(serial, command);
    if (output.stdout.contains('monkey aborted')) {
      throw AdbException(
        '${_shell.describe(serial, command)} failed: '
        '$package has no launcher activity.',
      );
    }
  }

  /// Restarts the app and watches its log for a token. Only after the user
  /// confirmed, because it restarts the app.
  Stream<LogcatProgress> readTokenFromLogcat(String serial, String package) {
    late final StreamController<LogcatProgress> controller;
    RunningProcess? logcat;
    var cancelled = false;

    void emit(LogcatProgress progress) {
      if (!cancelled) {
        controller.add(progress);
      }
    }

    Future<void> body() async {
      try {
        emit(const LogcatRestartingApp());
        await _checked(serial, PhoneCommand.shell('am force-stop $package'));
        if (cancelled) return;
        await launchApp(serial, package);
        if (cancelled) return;
        emit(const LogcatWaitingForApp());
        final pid = await _waitForPid(serial, package, () => cancelled);
        if (cancelled) return;
        if (pid == null) {
          emit(const LogcatAppDidNotStart());
          return;
        }
        emit(LogcatWatching(pid));
        final token = await _watchLogcat(
          serial,
          pid,
          isCancelled: () => cancelled,
          onStarted: (process) {
            logcat = process;
            if (cancelled) process.kill();
          },
        );
        emit(token == null ? const LogcatNoToken() : LogcatFound(token));
      } on AdbException catch (e) {
        emit(LogcatFailed(e.message));
      } on Object catch (e) {
        emit(LogcatFailed(redact('Reading the token from logcat failed: $e')));
      } finally {
        await controller.close();
      }
    }

    controller = StreamController<LogcatProgress>(
      onListen: () => unawaited(body()),
      // Kill logcat on cancel: the body is parked on its stdout, and only the
      // kill ends it.
      onCancel: () {
        cancelled = true;
        logcat?.kill();
      },
    );
    return controller.stream;
  }

  /// Polls `pidof` until the app runs, or gives up after [_appStartTimeout].
  Future<int?> _waitForPid(
    String serial,
    String package,
    bool Function() isCancelled,
  ) async {
    final command = PhoneCommand.shell('pidof $package');
    final stopwatch = Stopwatch()..start();
    while (!isCancelled() && stopwatch.elapsed < _appStartTimeout) {
      final output = await _shell.run(serial, command);
      if (output.exitCode != 0 &&
          (output.stderr.trim().isNotEmpty ||
              output.stdout.trim().startsWith('error:'))) {
        throw AdbException(_failed(serial, command, output));
      }
      final pid = int.tryParse(
        output.stdout.trim().split(RegExp(r'\s+')).first,
      );
      if (pid != null) {
        return pid;
      }
      await Future<void>.delayed(_pollInterval);
    }
    return null;
  }

  /// `logcat --pid` includes the process's earlier lines. Never `logcat -c`:
  /// other tools keep their logs (spec §9.3).
  Future<String?> _watchLogcat(
    String serial,
    int pid, {
    required bool Function() isCancelled,
    required void Function(RunningProcess process) onStarted,
  }) async {
    final command = PhoneCommand.logcat('--pid=$pid');
    final process = await _shell.start(serial, command);
    onStarted(process);
    try {
      var streamEnded = false;
      final token = await process.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .map(FcmTokenPattern.firstIn)
          .firstWhere(
            (token) => token != null,
            orElse: () {
              streamEnded = true;
              return null;
            },
          )
          .timeout(_logcatTimeout, onTimeout: () => null);
      // `logcat --pid` never ends on its own: if it did, adb or the phone
      // went away. That is a failure, not "no token".
      if (token == null && streamEnded && !isCancelled()) {
        final code = await process.exitCode
            .then<int?>((code) => code)
            .timeout(const Duration(seconds: 1), onTimeout: () => null);
        final described = _shell.describe(serial, command);
        throw AdbException(
          code == null
              ? '$described stopped'
              : '$described stopped (exit code $code)',
        );
      }
      return token;
    } finally {
      process.kill();
    }
  }

  /// Runs [command]; a non-zero exit code is an [AdbException].
  Future<ProcessOutput> _checked(String serial, PhoneCommand command) async {
    final output = await _shell.run(serial, command);
    if (output.exitCode != 0) {
      throw AdbException(_failed(serial, command, output));
    }
    return output;
  }

  String _failed(String serial, PhoneCommand command, ProcessOutput output) {
    final details = output.combined
        .replaceAll(FcmTokenPattern.inText, '<token>')
        .trim();
    return '${_shell.describe(serial, command)} failed: '
        '${details.isEmpty ? 'exit code ${output.exitCode}' : details}';
  }
}
```

- [ ] **Step 6: Make `ProcessAdbService` delegate**

Edit `lib/features/devices/data/adb_service.dart`:

1. Replace the import block with this, and add the export:

```dart
import 'dart:async';

import 'package:fcm_studio/features/devices/data/adb_commands.dart';
import 'package:fcm_studio/features/devices/data/adb_exception.dart';
import 'package:fcm_studio/features/devices/data/device_shell.dart';
import 'package:fcm_studio/features/devices/data/parsers/track_devices_decoder.dart';
import 'package:fcm_studio/features/devices/data/process_runner.dart';
import 'package:fcm_studio/features/devices/domain/adb_device.dart';
import 'package:fcm_studio/features/devices/domain/token_read_results.dart';

export 'package:fcm_studio/features/devices/data/adb_exception.dart';
```

2. Delete the `AdbException` class. It now lives in `adb_exception.dart`.
3. Leave the `AdbService` interface unchanged.
4. In `ProcessAdbService`:
   - Keep the constructor, the five fields and `trackDevices()` exactly as they are.
   - Delete `static const tokenFile`.
   - Keep `_start`, which `trackDevices` uses.
   - Delete `deviceDetails`, `listPackages`, `readTokenWithRunAs`, `launchApp`, `readTokenFromLogcat`, `_waitForPid`, `_watchLogcat`, `_run`, `_shell` and `_failed`.
   - Add the members below after the fields.
   - Change the class's doc comment to `/// Desktop: phones through the adb program. The phone commands are shared with the web in [AdbCommands].`

```dart
  late final AdbCommands _commands = AdbCommands(
    shell: ProcessDeviceShell(runner: _runner, adbPath: _adbPath),
    pollInterval: _pollInterval,
    appStartTimeout: _appStartTimeout,
    logcatTimeout: _logcatTimeout,
  );

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
```

- [ ] **Step 7: Run the tests**

Run: `flutter test test/features/devices/adb_commands_test.dart test/features/devices/adb_service_test.dart`
Expected: PASS. All 5 new tests pass, and every `adb_service_test.dart` test passes unchanged: the desktop messages and commands are identical.

Run: `flutter analyze && flutter test`
Expected: `No issues found!`, and all tests pass (573 plus 5 new).

- [ ] **Step 8: Commit**

```bash
git add lib/features/devices/data/adb_exception.dart lib/features/devices/data/device_shell.dart lib/features/devices/data/adb_commands.dart lib/features/devices/data/adb_service.dart test/features/devices/adb_commands_test.dart
git commit -m "refactor: share the phone commands through AdbCommands and DeviceShell

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: adb message codec

**Files:**
- Create: `lib/features/devices/data/webusb/adb_message.dart`
- Test: `test/features/devices/webusb/adb_message_test.dart`

**Interfaces:**
- Produces:
  - `class AdbProtocolException implements Exception { const AdbProtocolException(String message); final String message; }`.
  - `abstract final class AdbCommand { static const cnxn, auth, open, okay, wrte, clse; }`.
  - `class AdbHeader { const AdbHeader(int command, int arg0, int arg1, int length); }`.
  - `class AdbMessage extends Equatable { AdbMessage(int command, int arg0, int arg1, [List<int> payload]); AdbMessage.text(int command, int arg0, int arg1, String text); static const headerLength = 24; final Uint8List payload; String get text; Uint8List header(); static int checksum(List<int>); static AdbHeader parseHeader(List<int> bytes); }`.

- [ ] **Step 1: Write the failing test**

Create `test/features/devices/webusb/adb_message_test.dart`:

```dart
import 'dart:typed_data';

import 'package:fcm_studio/features/devices/data/webusb/adb_message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a CNXN header has the AOSP layout', () {
    final message = AdbMessage.text(
      AdbCommand.cnxn,
      0x01000001,
      1048576,
      'host::features=shell_v2,cmd',
    );
    final header = message.header();
    final data = ByteData.sublistView(header);
    expect(header, hasLength(24));
    // 'CNXN' in ASCII, little-endian.
    expect(header.sublist(0, 4), [0x43, 0x4E, 0x58, 0x4E]);
    expect(data.getUint32(4, Endian.little), 0x01000001);
    expect(data.getUint32(8, Endian.little), 1048576);
    expect(data.getUint32(12, Endian.little), 27);
    expect(
      data.getUint32(16, Endian.little),
      'host::features=shell_v2,cmd'.codeUnits.fold<int>(0, (a, b) => a + b),
    );
    expect(data.getUint32(20, Endian.little), 0x4E584E43 ^ 0xFFFFFFFF);
  });

  test('every command reads back from its own header', () {
    for (final command in [
      AdbCommand.cnxn,
      AdbCommand.auth,
      AdbCommand.open,
      AdbCommand.okay,
      AdbCommand.wrte,
      AdbCommand.clse,
    ]) {
      final header = AdbMessage.parseHeader(
        AdbMessage(command, 7, 9, [1, 2, 3]).header(),
      );
      expect(
        (header.command, header.arg0, header.arg1, header.length),
        (command, 7, 9, 3),
      );
    }
  });

  test('a payload over 64 KiB keeps its length and checksum', () {
    final payload = List<int>.filled(70000, 0xFF);
    final data = ByteData.sublistView(
      AdbMessage(AdbCommand.wrte, 1, 2, payload).header(),
    );
    expect(data.getUint32(12, Endian.little), 70000);
    expect(data.getUint32(16, Endian.little), 70000 * 0xFF);
  });

  test('a bad magic or a short header is a protocol error', () {
    final header = AdbMessage(AdbCommand.okay, 1, 2).header()..[20] ^= 1;
    expect(
      () => AdbMessage.parseHeader(header),
      throwsA(isA<AdbProtocolException>()),
    );
    expect(
      () => AdbMessage.parseHeader([1, 2, 3]),
      throwsA(isA<AdbProtocolException>()),
    );
  });

  test('text drops the trailing NUL', () {
    expect(
      AdbMessage.text(AdbCommand.open, 1, 0, 'shell:x\u0000').text,
      'shell:x',
    );
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/features/devices/webusb/adb_message_test.dart`
Expected: FAIL to compile: `adb_message.dart` doesn't exist.

- [ ] **Step 3: Implement the codec**

Create `lib/features/devices/data/webusb/adb_message.dart`:

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:equatable/equatable.dart';

/// The phone sent something the adb protocol doesn't allow.
class AdbProtocolException implements Exception {
  const AdbProtocolException(this.message);

  final String message;

  @override
  String toString() => 'AdbProtocolException: $message';
}

/// The adb wire commands (AOSP `adb/protocol.txt`), little-endian ASCII.
abstract final class AdbCommand {
  static const cnxn = 0x4E584E43;
  static const auth = 0x48545541;
  static const open = 0x4E45504F;
  static const okay = 0x59414B4F;
  static const wrte = 0x45545257;
  static const clse = 0x45534C43;
}

/// What [AdbMessage.parseHeader] reads from 24 header bytes.
class AdbHeader {
  const AdbHeader(this.command, this.arg0, this.arg1, this.length);

  final int command;
  final int arg0;
  final int arg1;

  /// The payload length.
  final int length;
}

/// One adb message: a 24-byte header and its payload (design §4.3).
class AdbMessage extends Equatable {
  AdbMessage(this.command, this.arg0, this.arg1, [List<int> payload = const []])
    : payload = Uint8List.fromList(payload);

  AdbMessage.text(int command, int arg0, int arg1, String text)
    : this(command, arg0, arg1, utf8.encode(text));

  static const headerLength = 24;

  final int command;
  final int arg0;
  final int arg1;
  final Uint8List payload;

  /// The payload as text, without NUL characters.
  String get text =>
      utf8.decode(payload, allowMalformed: true).replaceAll('\u0000', '');

  /// Six little-endian uint32s: command, arg0, arg1, payload length,
  /// payload checksum and magic (`command ^ 0xFFFFFFFF`).
  Uint8List header() {
    final data = ByteData(headerLength)
      ..setUint32(0, command, Endian.little)
      ..setUint32(4, arg0, Endian.little)
      ..setUint32(8, arg1, Endian.little)
      ..setUint32(12, payload.length, Endian.little)
      ..setUint32(16, checksum(payload), Endian.little)
      ..setUint32(20, command ^ 0xFFFFFFFF, Endian.little);
    return data.buffer.asUint8List();
  }

  /// The sum of the payload's bytes. Phones on adb 0x01000001 and later
  /// don't check it, but older ones do.
  static int checksum(List<int> bytes) {
    var sum = 0;
    for (final byte in bytes) {
      sum = (sum + byte) & 0xFFFFFFFF;
    }
    return sum;
  }

  /// Reads a header. Throws [AdbProtocolException] for a wrong size or magic.
  static AdbHeader parseHeader(List<int> bytes) {
    if (bytes.length != headerLength) {
      throw AdbProtocolException(
        'Expected a $headerLength-byte message header, got ${bytes.length} bytes.',
      );
    }
    final data = ByteData.sublistView(Uint8List.fromList(bytes));
    final command = data.getUint32(0, Endian.little);
    if (data.getUint32(20, Endian.little) != command ^ 0xFFFFFFFF) {
      throw const AdbProtocolException(
        'The phone sent a message with a bad header.',
      );
    }
    return AdbHeader(
      command,
      data.getUint32(4, Endian.little),
      data.getUint32(8, Endian.little),
      data.getUint32(12, Endian.little),
    );
  }

  @override
  List<Object?> get props => [command, arg0, arg1, payload];

  @override
  String toString() {
    final name = String.fromCharCodes([
      for (var shift = 0; shift < 32; shift += 8) (command >> shift) & 0xFF,
    ]);
    return 'AdbMessage($name, $arg0, $arg1, "$text")';
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/features/devices/webusb/adb_message_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/devices/data/webusb/adb_message.dart test/features/devices/webusb/adb_message_test.dart
git commit -m "feat: adb message codec for WebUSB

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: The browser's adb key (`AdbKey`) and its test fixtures

**Files:**
- Create: `lib/features/devices/data/webusb/adb_key.dart`
- Create: `test/fixtures/adb/test_adbkey.jwk.json`, `test/fixtures/adb/test_adbkey.pub`, `test/fixtures/adb/test_adbkey_signature.hex`
- Create: `test/helpers/adb_key_fixture.dart`
- Test: `test/features/devices/webusb/adb_key_test.dart`

**Interfaces:**
- Produces:
  - `class AdbKey { AdbKey({required BigInt n, required BigInt e, required BigInt d, BigInt? p, BigInt? q, BigInt? dp, BigInt? dq, BigInt? qi}); factory AdbKey.fromJwk(Map<String, Object?> jwk); static const modulusBits = 2048; Uint8List sign(List<int> token); Uint8List androidPublicKey(); String publicKeyPayload(String name); }`.
  - In tests: `Map<String, Object?> testAdbKeyJwk()` and `AdbKey testAdbKey()`.

- [ ] **Step 1: Make the throwaway key fixtures**

The key is made by real adb, so the tests prove we match it. No phone trusts it.

```bash
mkdir -p test/fixtures/adb
TMPKEY="$(mktemp -d)/test_adbkey"
adb keygen "$TMPKEY"
cp "$TMPKEY.pub" test/fixtures/adb/test_adbkey.pub
python3 - "$TMPKEY" > test/fixtures/adb/test_adbkey.jwk.json <<'PY'
"""Turns `openssl rsa -text` output into a JWK (n, e, d, p, q, dp, dq, qi)."""
import base64, json, re, subprocess, sys

text = subprocess.run(['openssl', 'rsa', '-in', sys.argv[1], '-noout', '-text'],
                      capture_output=True, text=True, check=True).stdout
fields, current = {}, None
for line in text.splitlines():
    m = re.match(r'^(\w+):\s*(.*)$', line)
    if m:
        current = m.group(1)
        if current == 'publicExponent':
            fields[current] = int(m.group(2).split()[0])
            current = None
        else:
            fields[current] = ''
    elif current and line.startswith(' '):
        fields[current] += line.strip().replace(':', '')

def b64(value):
    n = value if isinstance(value, int) else int(fields[value], 16)
    raw = n.to_bytes((n.bit_length() + 7) // 8, 'big')
    return base64.urlsafe_b64encode(raw).rstrip(b'=').decode()

print(json.dumps({
    'kty': 'RSA', 'alg': 'RS1',
    'n': b64('modulus'), 'e': b64(fields['publicExponent']),
    'd': b64('privateExponent'), 'p': b64('prime1'), 'q': b64('prime2'),
    'dp': b64('exponent1'), 'dq': b64('exponent2'), 'qi': b64('coefficient'),
}, indent=2))
PY
python3 -c "open('$TMPKEY.token','wb').write(bytes(range(20)))"
openssl pkeyutl -sign -inkey "$TMPKEY" -pkeyopt digest:sha1 -in "$TMPKEY.token" -out "$TMPKEY.sig"
xxd -p "$TMPKEY.sig" | tr -d '\n' > test/fixtures/adb/test_adbkey_signature.hex
ls -l test/fixtures/adb/test_adbkey*
```

Expected:
- `test_adbkey.jwk.json` holds `n`, `e`, `d`, `p`, `q`, `dp`, `dq`, `qi`, `kty`, `alg`.
- `test_adbkey.pub` begins with `QAAAA`.
- The `.hex` file is 512 hex characters.
- The PEM private key stays in the temp folder and is never committed.

- [ ] **Step 2: Write the fixture helper and the failing test**

Create `test/helpers/adb_key_fixture.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:fcm_studio/features/devices/data/webusb/adb_key.dart';

/// A throwaway key made with `adb keygen` (test/fixtures/adb). No phone
/// trusts it.
Map<String, Object?> testAdbKeyJwk() =>
    jsonDecode(File('test/fixtures/adb/test_adbkey.jwk.json').readAsStringSync())
        as Map<String, Object?>;

AdbKey testAdbKey() => AdbKey.fromJwk(testAdbKeyJwk());
```

Create `test/features/devices/webusb/adb_key_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:fcm_studio/features/devices/data/webusb/adb_key.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/adb_key_fixture.dart';

void main() {
  final token = List<int>.generate(20, (i) => i);

  test('signs a token exactly like adb (openssl -pkeyopt digest:sha1)', () {
    final expected = File(
      'test/fixtures/adb/test_adbkey_signature.hex',
    ).readAsStringSync().trim();
    final signature = testAdbKey().sign(token);
    expect(signature, hasLength(256));
    expect(
      signature.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      expected,
    );
  });

  test('without the CRT values the signature is the same', () {
    final full = testAdbKey();
    expect(AdbKey(n: full.n, e: full.e, d: full.d).sign(token), full.sign(token));
  });

  test('the Android public key matches adb keygen', () {
    final expected = File(
      'test/fixtures/adb/test_adbkey.pub',
    ).readAsStringSync().split(' ').first;
    expect(base64.encode(testAdbKey().androidPublicKey()), expected);
  });

  test('the AUTH payload is the key, a space, the name and a NUL', () {
    final payload = testAdbKey().publicKeyPayload('fcm-studio@example.com');
    expect(payload, endsWith(' fcm-studio@example.com\u0000'));
    expect(
      payload.split(' ').first,
      base64.encode(testAdbKey().androidPublicKey()),
    );
  });

  test('a token that is not 20 bytes is refused', () {
    expect(() => testAdbKey().sign([1, 2, 3]), throwsArgumentError);
  });

  test('a JWK without n, or with a short modulus, is refused', () {
    final jwk = testAdbKeyJwk();
    expect(() => AdbKey.fromJwk({...jwk}..remove('n')), throwsFormatException);
    expect(() => AdbKey.fromJwk({...jwk, 'n': 'AQAB'}), throwsFormatException);
  });
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `flutter test test/features/devices/webusb/adb_key_test.dart`
Expected: FAIL to compile: `adb_key.dart` doesn't exist.

- [ ] **Step 4: Implement `AdbKey`**

Create `lib/features/devices/data/webusb/adb_key.dart`:

```dart
import 'dart:convert';
import 'dart:typed_data';

/// The browser's adb key: signs the phone's challenge and introduces itself
/// in Android's public key format (design §4.5).
class AdbKey {
  AdbKey({
    required this.n,
    required this.e,
    required this.d,
    this.p,
    this.q,
    this.dp,
    this.dq,
    this.qi,
  });

  /// Reads a WebCrypto JWK export. Throws [FormatException] when a value is
  /// missing or the key is not 2048 bits.
  factory AdbKey.fromJwk(Map<String, Object?> jwk) {
    BigInt value(String name) {
      final text = jwk[name];
      if (text is! String || text.isEmpty) {
        throw FormatException('The adb key has no "$name".');
      }
      return _bigInt(base64Url.decode(base64Url.normalize(text)));
    }

    BigInt? optional(String name) => jwk[name] is String ? value(name) : null;

    final key = AdbKey(
      n: value('n'),
      e: value('e'),
      d: value('d'),
      p: optional('p'),
      q: optional('q'),
      dp: optional('dp'),
      dq: optional('dq'),
      qi: optional('qi'),
    );
    if (key.n.bitLength != modulusBits) {
      throw FormatException(
        'The adb key must be $modulusBits bits, not ${key.n.bitLength}.',
      );
    }
    return key;
  }

  static const modulusBits = 2048;
  static const _modulusBytes = modulusBits ~/ 8;

  /// DER prefix of a SHA-1 DigestInfo; adb's token is used as the digest.
  static const _sha1DigestInfo = [
    0x30, 0x21, 0x30, 0x09, 0x06, 0x05, 0x2B, 0x0E, 0x03, 0x02, 0x1A, 0x05,
    0x00, 0x04, 0x14, //
  ];

  final BigInt n;
  final BigInt e;
  final BigInt d;
  final BigInt? p;
  final BigInt? q;
  final BigInt? dp;
  final BigInt? dq;
  final BigInt? qi;

  /// RSA PKCS#1 v1.5 over a SHA-1 DigestInfo holding [token] as the digest,
  /// as adb's `RSA_sign(NID_sha1, …)` does. Returns 256 bytes.
  Uint8List sign(List<int> token) {
    if (token.length != 20) {
      throw ArgumentError.value(token.length, 'token', 'must be 20 bytes');
    }
    final t = [..._sha1DigestInfo, ...token];
    final block = Uint8List(_modulusBytes)..[1] = 0x01;
    block.fillRange(2, _modulusBytes - t.length - 1, 0xFF);
    block.setRange(_modulusBytes - t.length, _modulusBytes, t);
    return _bytes(_power(_bigInt(block)), _modulusBytes);
  }

  /// `m^d mod n`, with the Chinese remainder theorem when the JWK has the
  /// values for it (about 3 times faster in the browser).
  BigInt _power(BigInt m) {
    final (p, q, dp, dq, qi) = (this.p, this.q, this.dp, this.dq, this.qi);
    if (p == null || q == null || dp == null || dq == null || qi == null) {
      return m.modPow(d, n);
    }
    final m1 = m.modPow(dp, p);
    final m2 = m.modPow(dq, q);
    final h = (qi * (m1 - m2)) % p;
    return m2 + h * q;
  }

  /// Android's RSAPublicKey layout, all little-endian: the modulus size in
  /// 32-bit words, n0inv, the modulus, R² mod n, and the exponent.
  Uint8List androidPublicKey() {
    final r32 = BigInt.one << 32;
    final n0inv = (r32 - n.modInverse(r32)) % r32;
    final rr = (BigInt.one << (2 * modulusBits)) % n;
    final data = ByteData(4 + 4 + _modulusBytes * 2 + 4)
      ..setUint32(0, _modulusBytes ~/ 4, Endian.little)
      ..setUint32(4, n0inv.toInt(), Endian.little)
      ..setUint32(8 + _modulusBytes * 2, e.toInt(), Endian.little);
    return data.buffer.asUint8List()
      ..setRange(8, 8 + _modulusBytes, _bytes(n, _modulusBytes).reversed)
      ..setRange(
        8 + _modulusBytes,
        8 + _modulusBytes * 2,
        _bytes(rr, _modulusBytes).reversed,
      );
  }

  /// The `AUTH` public key payload: base64, a space, [name], and a NUL.
  String publicKeyPayload(String name) =>
      '${base64.encode(androidPublicKey())} $name\u0000';

  static BigInt _bigInt(List<int> bytes) => bytes.isEmpty
      ? BigInt.zero
      : BigInt.parse(
          bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
          radix: 16,
        );

  /// [value] as [length] big-endian bytes.
  static Uint8List _bytes(BigInt value, int length) {
    final hex = value.toRadixString(16).padLeft(length * 2, '0');
    return Uint8List.fromList([
      for (var i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ]);
  }
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `flutter test test/features/devices/webusb/adb_key_test.dart`
Expected: PASS (6 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/features/devices/data/webusb/adb_key.dart test/fixtures/adb/test_adbkey.jwk.json test/fixtures/adb/test_adbkey.pub test/fixtures/adb/test_adbkey_signature.hex test/helpers/adb_key_fixture.dart test/features/devices/webusb/adb_key_test.dart
git commit -m "feat: sign adb challenges and write Android public keys in Dart

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 4: USB transport interface and `AdbConnection`

**Files:**
- Create: `lib/features/devices/data/webusb/usb_transport.dart`
- Create: `lib/features/devices/data/webusb/adb_connection.dart`
- Create: `test/helpers/fake_usb_transport.dart`
- Test: `test/features/devices/webusb/adb_connection_test.dart`

**Interfaces:**
- Consumes:
  - `AdbMessage`, `AdbCommand`, `AdbHeader` and `AdbProtocolException` (Task 2);
  - `AdbKey` (Task 3);
  - `AdbException` (Task 1).
- Produces:
  - `class UsbClaimException implements Exception { const UsbClaimException(String message); }` and `class UsbDisconnectedException implements Exception { const UsbDisconnectedException([String message]); }`.
  - `abstract interface class UsbTransport { Future<Uint8List> read(int length); Future<void> write(Uint8List bytes); Future<void> close(); }`.
  - `String connectionFailureMessage(Object error)`.
  - `class AdbBanner { factory AdbBanner.parse(String text); Map<String, String> properties; Set<String> features; bool get hasShellV2; String? get model; }`.
  - `class AdbConnection { AdbConnection({required UsbTransport transport, required Future<AdbKey> Function() loadKey, required String keyName}); Future<AdbBanner> connect({void Function()? onWaitingForApproval}); Future<AdbStream> open(String service); Future<void> close(); Future<Object> get lost; }`.
  - `class AdbStream { int localId; Stream<Uint8List> get data; Future<void> close(); }`.
  - In tests, `FakeUsbTransport`: `maxChunk`, `closed`, `phoneSends(AdbMessage)`, `phoneSendsBytes(List<int>)`, `unplug()`, `Future<AdbMessage> nextHostMessage()`.

- [ ] **Step 1: Write the transport fake**

Create `test/helpers/fake_usb_transport.dart`:

```dart
import 'dart:async';
import 'dart:typed_data';

import 'package:fcm_studio/features/devices/data/webusb/adb_message.dart';
import 'package:fcm_studio/features/devices/data/webusb/usb_transport.dart';

/// The phone end of a [UsbTransport]: the test queues what the phone sends
/// and reads back what the host wrote.
class FakeUsbTransport implements UsbTransport {
  /// At most this many bytes per read, to test messages split across USB
  /// transfers.
  int maxChunk = 1 << 20;
  bool closed = false;

  final List<int> _incoming = [];
  Completer<void>? _arrived;
  Object? _failure;
  final StreamController<AdbMessage> _hostMessages =
      StreamController<AdbMessage>();
  late final StreamIterator<AdbMessage> _host = StreamIterator(
    _hostMessages.stream,
  );
  AdbHeader? _pendingHeader;

  /// The phone sends [message]: header, then payload.
  void phoneSends(AdbMessage message) =>
      phoneSendsBytes([...message.header(), ...message.payload]);

  void phoneSendsBytes(List<int> bytes) {
    _incoming.addAll(bytes);
    _wake();
  }

  /// Every pending and later transfer fails, as when the phone is unplugged.
  void unplug() {
    _failure = const UsbDisconnectedException();
    _wake();
  }

  /// The next message the host wrote.
  Future<AdbMessage> nextHostMessage() async {
    final more = await _host.moveNext().timeout(const Duration(seconds: 2));
    if (!more) {
      throw StateError('The host wrote nothing more.');
    }
    return _host.current;
  }

  void _wake() {
    final arrived = _arrived;
    _arrived = null;
    arrived?.complete();
  }

  @override
  Future<Uint8List> read(int length) async {
    while (true) {
      final failure = _failure;
      if (failure != null) {
        throw failure;
      }
      if (closed) {
        throw const UsbDisconnectedException('The transport is closed.');
      }
      if (_incoming.isNotEmpty) {
        var count = length < _incoming.length ? length : _incoming.length;
        if (count > maxChunk) {
          count = maxChunk;
        }
        final chunk = Uint8List.fromList(_incoming.sublist(0, count));
        _incoming.removeRange(0, count);
        return chunk;
      }
      await (_arrived ??= Completer<void>()).future;
    }
  }

  @override
  Future<void> write(Uint8List bytes) async {
    final failure = _failure;
    if (failure != null) {
      throw failure;
    }
    final header = _pendingHeader;
    if (header == null) {
      final parsed = AdbMessage.parseHeader(bytes);
      if (parsed.length == 0) {
        _hostMessages.add(AdbMessage(parsed.command, parsed.arg0, parsed.arg1));
      } else {
        _pendingHeader = parsed;
      }
    } else {
      _pendingHeader = null;
      _hostMessages.add(
        AdbMessage(header.command, header.arg0, header.arg1, bytes),
      );
    }
  }

  @override
  Future<void> close() async {
    closed = true;
    _wake();
  }
}
```

- [ ] **Step 2: Write the failing test**

Create `test/features/devices/webusb/adb_connection_test.dart`:

```dart
import 'dart:async';
import 'dart:convert';

import 'package:fcm_studio/features/devices/data/adb_exception.dart';
import 'package:fcm_studio/features/devices/data/webusb/adb_connection.dart';
import 'package:fcm_studio/features/devices/data/webusb/adb_message.dart';
import 'package:fcm_studio/features/devices/data/webusb/usb_transport.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/adb_key_fixture.dart';
import '../../../helpers/fake_usb_transport.dart';

const keyName = 'fcm-studio@example.com';
const phoneBanner = 'device::ro.product.model=2409BRN2CA;features=shell_v2,cmd';

void main() {
  late FakeUsbTransport phone;
  late AdbConnection connection;
  var keyLoads = 0;

  setUp(() {
    phone = FakeUsbTransport();
    keyLoads = 0;
    connection = AdbConnection(
      transport: phone,
      loadKey: () async {
        keyLoads++;
        return testAdbKey();
      },
      keyName: keyName,
    );
  });

  AdbMessage banner([String text = phoneBanner]) =>
      AdbMessage.text(AdbCommand.cnxn, 0x01000001, 256 * 1024, text);
  AdbMessage token() =>
      AdbMessage(AdbCommand.auth, 1, 0, List<int>.generate(20, (i) => i));

  Future<void> ready() async {
    final connected = connection.connect();
    await phone.nextHostMessage();
    phone.phoneSends(banner());
    await connected;
  }

  group('handshake', () {
    test('opens with CNXN: version, max payload and shell_v2', () async {
      unawaited(connection.connect());
      expect(
        await phone.nextHostMessage(),
        AdbMessage.text(
          AdbCommand.cnxn,
          0x01000001,
          1048576,
          'host::features=shell_v2,cmd',
        ),
      );
    });

    test('a phone that needs no key is ready at once', () async {
      final connected = connection.connect();
      await phone.nextHostMessage();
      phone.phoneSends(banner());
      final result = await connected;
      expect(result.hasShellV2, isTrue);
      expect(result.model, '2409BRN2CA');
      expect(keyLoads, 0);
    });

    test('a phone that trusts the key gets a signature, then is ready', () async {
      final connected = connection.connect();
      await phone.nextHostMessage();
      phone.phoneSends(token());
      final signature = await phone.nextHostMessage();
      expect((signature.command, signature.arg0), (AdbCommand.auth, 2));
      expect(
        signature.payload,
        testAdbKey().sign(List<int>.generate(20, (i) => i)),
      );
      phone.phoneSends(banner());
      await connected;
    });

    test('an unknown key is offered; the phone asks, then accepts', () async {
      var asked = false;
      final connected = connection.connect(
        onWaitingForApproval: () => asked = true,
      );
      await phone.nextHostMessage();
      phone.phoneSends(token());
      await phone.nextHostMessage(); // the signature
      phone.phoneSends(token()); // not trusted
      final offer = await phone.nextHostMessage();
      expect((offer.command, offer.arg0), (AdbCommand.auth, 3));
      expect(
        offer.text,
        startsWith(base64.encode(testAdbKey().androidPublicKey())),
      );
      expect(utf8.decode(offer.payload), endsWith(' $keyName\u0000'));
      expect(asked, isTrue);
      phone.phoneSends(banner());
      await connected;
    });

    test('while the user has not answered, the handshake waits', () async {
      var done = false;
      unawaited(connection.connect().then((_) => done = true));
      await phone.nextHostMessage();
      phone.phoneSends(token());
      await phone.nextHostMessage();
      phone.phoneSends(token());
      await phone.nextHostMessage();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(done, isFalse);
    });

    test('a banner without shell_v2 says so', () async {
      final connected = connection.connect();
      await phone.nextHostMessage();
      phone.phoneSends(banner('device::ro.product.model=old;features=cmd'));
      expect((await connected).hasShellV2, isFalse);
    });

    test('unplugging during the handshake fails it', () async {
      final connected = connection.connect();
      await phone.nextHostMessage();
      phone.unplug();
      await expectLater(connected, throwsA(isA<UsbDisconnectedException>()));
      expect(await connection.lost, isA<UsbDisconnectedException>());
    });

    test('a bad header from the phone breaks the connection', () async {
      final connected = connection.connect();
      await phone.nextHostMessage();
      phone.phoneSendsBytes(List<int>.filled(24, 0));
      await expectLater(connected, throwsA(isA<AdbProtocolException>()));
    });
  });

  group('streams', () {
    test('OPEN, OKAY, data with an OKAY each, and the phone closing', () async {
      await ready();
      final opening = connection.open('shell,v2,raw:getprop');
      expect(
        await phone.nextHostMessage(),
        AdbMessage.text(AdbCommand.open, 1, 0, 'shell,v2,raw:getprop\u0000'),
      );
      phone.phoneSends(AdbMessage(AdbCommand.okay, 100, 1));
      final stream = await opening;
      final received = <List<int>>[];
      final done = Completer<void>();
      stream.data.listen(received.add, onDone: done.complete);
      phone.phoneSends(AdbMessage(AdbCommand.wrte, 100, 1, [1, 2]));
      expect(
        await phone.nextHostMessage(),
        AdbMessage(AdbCommand.okay, 1, 100),
      );
      phone.phoneSends(AdbMessage(AdbCommand.clse, 100, 1));
      await done.future;
      expect(received, [
        [1, 2],
      ]);
    });

    test('a refused command is an AdbException', () async {
      await ready();
      final opening = connection.open('shell,v2,raw:nope');
      await phone.nextHostMessage();
      phone.phoneSends(AdbMessage(AdbCommand.clse, 0, 1));
      await expectLater(opening, throwsA(isA<AdbException>()));
    });

    test('two streams at once get their own data', () async {
      await ready();
      final first = connection.open('shell,v2,raw:a');
      await phone.nextHostMessage();
      final second = connection.open('shell,v2,raw:b');
      await phone.nextHostMessage();
      phone
        ..phoneSends(AdbMessage(AdbCommand.okay, 200, 2))
        ..phoneSends(AdbMessage(AdbCommand.okay, 100, 1));
      final a = await first;
      final b = await second;
      final aData = <int>[];
      final bData = <int>[];
      a.data.listen(aData.addAll);
      b.data.listen(bData.addAll);
      phone
        ..phoneSends(AdbMessage(AdbCommand.wrte, 200, 2, [2]))
        ..phoneSends(AdbMessage(AdbCommand.wrte, 100, 1, [1]));
      expect(
        await phone.nextHostMessage(),
        AdbMessage(AdbCommand.okay, 2, 200),
      );
      expect(
        await phone.nextHostMessage(),
        AdbMessage(AdbCommand.okay, 1, 100),
      );
      expect(aData, [1]);
      expect(bData, [2]);
    });

    test('closing a stream sends CLSE', () async {
      await ready();
      final opening = connection.open('shell,v2,raw:logcat');
      await phone.nextHostMessage();
      phone.phoneSends(AdbMessage(AdbCommand.okay, 100, 1));
      await (await opening).close();
      expect(
        await phone.nextHostMessage(),
        AdbMessage(AdbCommand.clse, 1, 100),
      );
    });

    test('unplugging fails open streams with the disconnected message', () async {
      await ready();
      final opening = connection.open('shell,v2,raw:logcat');
      await phone.nextHostMessage();
      phone.phoneSends(AdbMessage(AdbCommand.okay, 100, 1));
      final stream = await opening;
      final errors = <Object>[];
      final done = Completer<void>();
      stream.data.listen((_) {}, onError: errors.add, onDone: done.complete);
      phone.unplug();
      await done.future;
      expect(
        errors.single,
        isA<AdbException>().having(
          (e) => e.message,
          'message',
          'The phone was disconnected. Plug it in and click Retry.',
        ),
      );
      await expectLater(
        connection.open('shell,v2,raw:x'),
        throwsA(isA<AdbException>()),
      );
    });

    test('a message split across many USB reads still arrives whole', () async {
      phone.maxChunk = 3;
      await ready();
      final opening = connection.open('shell,v2,raw:cat');
      await phone.nextHostMessage();
      phone.phoneSends(AdbMessage(AdbCommand.okay, 100, 1));
      final stream = await opening;
      final received = <List<int>>[];
      stream.data.listen(received.add);
      phone.phoneSends(
        AdbMessage(AdbCommand.wrte, 100, 1, List<int>.generate(10, (i) => i)),
      );
      await phone.nextHostMessage(); // the OKAY
      expect(received, [List<int>.generate(10, (i) => i)]);
    });

    test('close() releases the transport and fails open streams', () async {
      await ready();
      final opening = connection.open('shell,v2,raw:logcat');
      await phone.nextHostMessage();
      phone.phoneSends(AdbMessage(AdbCommand.okay, 100, 1));
      final stream = await opening;
      final done = Completer<void>();
      stream.data.listen(
        (_) {},
        onError: (Object _) {},
        onDone: done.complete,
      );
      await connection.close();
      await done.future;
      expect(phone.closed, isTrue);
    });
  });
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `flutter test test/features/devices/webusb/adb_connection_test.dart`
Expected: FAIL to compile: `usb_transport.dart` and `adb_connection.dart` don't exist.

- [ ] **Step 4: Implement the transport types**

Create `lib/features/devices/data/webusb/usb_transport.dart`:

```dart
import 'dart:typed_data';

/// The browser couldn't claim the phone's adb interface, usually because adb
/// or Android Studio holds it (design §7).
class UsbClaimException implements Exception {
  const UsbClaimException(this.message);

  final String message;

  @override
  String toString() => 'UsbClaimException: $message';
}

/// A USB transfer failed: the phone was unplugged or reset.
class UsbDisconnectedException implements Exception {
  const UsbDisconnectedException([this.message = 'The phone was disconnected.']);

  final String message;

  @override
  String toString() => 'UsbDisconnectedException: $message';
}

/// Bytes to and from a phone's adb interface (design §4.2).
abstract interface class UsbTransport {
  /// One bulk IN transfer of up to [length] bytes.
  Future<Uint8List> read(int length);

  /// One bulk OUT transfer.
  Future<void> write(Uint8List bytes);

  Future<void> close();
}
```

- [ ] **Step 5: Implement `AdbConnection`**

Create `lib/features/devices/data/webusb/adb_connection.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:fcm_studio/features/devices/data/adb_exception.dart';
import 'package:fcm_studio/features/devices/data/webusb/adb_key.dart';
import 'package:fcm_studio/features/devices/data/webusb/adb_message.dart';
import 'package:fcm_studio/features/devices/data/webusb/usb_transport.dart';

/// What a broken connection means for the user (design §7).
String connectionFailureMessage(Object error) => switch (error) {
  UsbDisconnectedException() =>
    'The phone was disconnected. Plug it in and click Retry.',
  _ =>
    'The connection to the phone failed. Unplug it, plug it in again, and '
        'click Retry.',
};

/// What the phone said about itself in its `CNXN` (design §4.4).
class AdbBanner {
  const AdbBanner({this.properties = const {}, this.features = const {}});

  /// Parses `device::ro.product.model=…;…;features=shell_v2,cmd`.
  factory AdbBanner.parse(String text) {
    final separator = text.indexOf('::');
    final body = separator < 0 ? '' : text.substring(separator + 2);
    final properties = <String, String>{};
    var features = <String>{};
    for (final part in body.split(';')) {
      final equals = part.indexOf('=');
      if (equals <= 0) {
        continue;
      }
      final key = part.substring(0, equals);
      final value = part.substring(equals + 1);
      if (key == 'features') {
        features = {
          for (final feature in value.split(','))
            if (feature.isNotEmpty) feature,
        };
      } else {
        properties[key] = value;
      }
    }
    return AdbBanner(properties: properties, features: features);
  }

  final Map<String, String> properties;
  final Set<String> features;

  /// Android 7 and newer: commands report stdout, stderr and an exit code.
  bool get hasShellV2 => features.contains('shell_v2');

  String? get model => properties['ro.product.model'];
}

/// One adb connection to a phone over USB (design §4.4).
class AdbConnection {
  AdbConnection({
    required this._transport,
    required this._loadKey,
    required this._keyName,
  }) {
    // Errors reach whoever awaits connect(); never report them twice.
    _handshake.future.ignore();
  }

  /// adb 0x01000001 and later skip checksums.
  static const version = 0x01000001;
  static const maxPayload = 1024 * 1024;
  static const hostBanner = 'host::features=shell_v2,cmd';
  static const _authToken = 1;
  static const _authSignature = 2;
  static const _authPublicKey = 3;

  final UsbTransport _transport;
  final Future<AdbKey> Function() _loadKey;

  /// Shown on the phone after the key, e.g. `fcm-studio@studio.example.com`.
  final String _keyName;

  final Map<int, AdbStream> _streams = {};
  final Completer<AdbBanner> _handshake = Completer<AdbBanner>();
  final Completer<Object> _lost = Completer<Object>();
  void Function()? _onWaitingForApproval;
  Future<void> _writes = Future<void>.value();
  int _nextLocalId = 1;
  bool _sentSignature = false;
  bool _started = false;
  bool _closed = false;
  Object? _failure;

  /// Completes with the error when the connection breaks. Never completes
  /// after [close].
  Future<Object> get lost => _lost.future;

  /// Runs the handshake. [onWaitingForApproval] is called when the phone
  /// shows "Allow USB debugging?". Throws what broke the connection.
  Future<AdbBanner> connect({void Function()? onWaitingForApproval}) {
    if (_started) {
      throw StateError('connect() was already called.');
    }
    _started = true;
    _onWaitingForApproval = onWaitingForApproval;
    unawaited(_readLoop());
    unawaited(
      _send(
        AdbMessage.text(AdbCommand.cnxn, version, maxPayload, hostBanner),
      ).catchError((Object error) => _fail(error)),
    );
    return _handshake.future;
  }

  /// Opens [service], e.g. `shell,v2,raw:getprop`. Throws [AdbException]
  /// when the phone refuses it or the connection is gone.
  Future<AdbStream> open(String service) async {
    final failure = _failure;
    if (failure != null) {
      throw AdbException(connectionFailureMessage(failure));
    }
    if (_closed) {
      throw const AdbException('The connection to the phone is closed.');
    }
    final stream = AdbStream._(this, _nextLocalId++);
    _streams[stream.localId] = stream;
    try {
      await _send(
        AdbMessage.text(AdbCommand.open, stream.localId, 0, '$service\u0000'),
      );
    } on Object catch (error) {
      _fail(error);
    }
    await stream._opened.future;
    return stream;
  }

  /// Closes every stream and releases the phone.
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    const closed = AdbException('The connection to the phone is closed.');
    if (_started && !_handshake.isCompleted) {
      _handshake.completeError(closed);
    }
    for (final stream in [..._streams.values]) {
      stream._onFailed(closed);
    }
    _streams.clear();
    await _transport.close();
  }

  Future<void> _readLoop() async {
    try {
      while (!_closed) {
        await _handle(await _readMessage());
      }
    } on Object catch (error) {
      _fail(error);
    }
  }

  Future<AdbMessage> _readMessage() async {
    final header = AdbMessage.parseHeader(
      await _readExactly(AdbMessage.headerLength),
    );
    final payload = header.length == 0
        ? Uint8List(0)
        : await _readExactly(header.length);
    return AdbMessage(header.command, header.arg0, header.arg1, payload);
  }

  /// USB may deliver a message in several transfers.
  Future<Uint8List> _readExactly(int length) async {
    final bytes = BytesBuilder(copy: false);
    while (bytes.length < length) {
      bytes.add(await _transport.read(length - bytes.length));
    }
    return bytes.takeBytes();
  }

  Future<void> _handle(AdbMessage message) async {
    switch (message.command) {
      case AdbCommand.cnxn:
        if (!_handshake.isCompleted) {
          _handshake.complete(AdbBanner.parse(message.text));
        }
      case AdbCommand.auth:
        await _onAuth(message);
      case AdbCommand.okay:
        _streams[message.arg1]?._onOkay(message.arg0);
      case AdbCommand.wrte:
        final stream = _streams[message.arg1];
        if (stream == null) {
          await _send(AdbMessage(AdbCommand.clse, 0, message.arg0));
        } else {
          stream._onData(message.payload);
          await _send(AdbMessage(AdbCommand.okay, message.arg1, message.arg0));
        }
      case AdbCommand.clse:
        _streams.remove(message.arg1)?._onClosed();
    }
  }

  /// The first token gets a signature; a second one means the phone doesn't
  /// know the key yet, so it gets the public key and asks the user.
  Future<void> _onAuth(AdbMessage message) async {
    if (message.arg0 != _authToken) {
      return;
    }
    final key = await _loadKey();
    if (!_sentSignature) {
      _sentSignature = true;
      await _send(
        AdbMessage(
          AdbCommand.auth,
          _authSignature,
          0,
          key.sign(message.payload),
        ),
      );
    } else {
      // The phone shows "Allow USB debugging?" as soon as the key arrives.
      _onWaitingForApproval?.call();
      await _send(
        AdbMessage(
          AdbCommand.auth,
          _authPublicKey,
          0,
          utf8.encode(key.publicKeyPayload(_keyName)),
        ),
      );
    }
  }

  /// Header and payload go out as separate transfers, one message at a time.
  Future<void> _send(AdbMessage message) {
    final sent = _writes.then((_) async {
      await _transport.write(message.header());
      if (message.payload.isNotEmpty) {
        await _transport.write(message.payload);
      }
    });
    _writes = sent.catchError((Object _) {});
    return sent;
  }

  void _fail(Object error) {
    if (_closed || _failure != null) {
      return;
    }
    _failure = error;
    if (_started && !_handshake.isCompleted) {
      _handshake.completeError(error);
    }
    final failure = AdbException(connectionFailureMessage(error));
    for (final stream in [..._streams.values]) {
      stream._onFailed(failure);
    }
    _streams.clear();
    _lost.complete(error);
  }
}

/// One open service on a phone, e.g. a running shell command.
class AdbStream {
  AdbStream._(this._connection, this.localId) {
    // Errors reach open()'s caller; never report them as uncaught.
    _opened.future.ignore();
  }

  final AdbConnection _connection;
  final int localId;
  int? _remoteId;
  final Completer<void> _opened = Completer<void>();
  final StreamController<Uint8List> _data = StreamController<Uint8List>();
  bool _done = false;

  /// What the phone writes, until it closes the stream. Errors are
  /// [AdbException]s.
  Stream<Uint8List> get data => _data.stream;

  void _onOkay(int remoteId) {
    _remoteId ??= remoteId;
    if (!_opened.isCompleted) {
      _opened.complete();
    }
  }

  void _onData(Uint8List bytes) {
    if (!_done) {
      _data.add(bytes);
    }
  }

  void _onClosed() {
    if (!_opened.isCompleted) {
      _opened.completeError(
        const AdbException('The phone refused to run the command.'),
      );
    }
    _finish();
  }

  void _onFailed(AdbException error) {
    if (!_opened.isCompleted) {
      _opened.completeError(error);
    } else if (!_done) {
      _data.addError(error);
    }
    _finish();
  }

  void _finish() {
    if (!_done) {
      _done = true;
      unawaited(_data.close());
    }
  }

  /// Closes the stream, which stops its command on the phone.
  Future<void> close() async {
    if (_done) {
      return;
    }
    _finish();
    _connection._streams.remove(localId);
    final remoteId = _remoteId;
    if (remoteId == null ||
        _connection._closed ||
        _connection._failure != null) {
      return;
    }
    try {
      await _connection._send(AdbMessage(AdbCommand.clse, localId, remoteId));
    } on Object {
      // The connection is going away anyway.
    }
  }
}
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `flutter test test/features/devices/webusb/adb_connection_test.dart`
Expected: PASS (15 tests).

**Ruling (record it in the ledger):**
- **Decision:** `AdbStream` has no `write`, so the design §4.4/§9 flow-control rule ("no second `WRTE` before `OKAY`") has nothing to apply to.
- **Why:** no phone command sends stdin, so the host never writes `WRTE`.
- **Cost if wrong:** adding `write` with an `OKAY` wait later, about 20 lines.
- **Spec:** Task 11 updates the design text.

- [ ] **Step 7: Commit**

```bash
git add lib/features/devices/data/webusb/usb_transport.dart lib/features/devices/data/webusb/adb_connection.dart test/helpers/fake_usb_transport.dart test/features/devices/webusb/adb_connection_test.dart
git commit -m "feat: adb connection over a USB transport: handshake, key pairing and streams

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Shell v2 (`runShellV2`, `ShellV2Process`) and the fake adbd

**Files:**
- Create: `lib/features/devices/data/webusb/shell_v2.dart`
- Create: `test/helpers/fake_adbd.dart`
- Test: `test/features/devices/webusb/shell_v2_test.dart`

**Interfaces:**
- Consumes: `AdbConnection` and `AdbStream` (Task 4), `ProcessOutput` and `RunningProcess` (`process_runner.dart`), `AdbException`.
- Produces:
  - `abstract final class ShellV2 { static const stdout = 1, stderr = 2, exit = 3; static String service(String command); static Uint8List packet(int id, List<int> data); }`.
  - `class ShellV2Packet { int id; Uint8List data; }` and `class ShellV2Decoder { List<ShellV2Packet> add(List<int> chunk); }`.
  - `Future<ProcessOutput> runShellV2(AdbConnection connection, String command)`.
  - `class ShellV2Process implements RunningProcess { static Future<ShellV2Process> start(AdbConnection connection, String command); }`.
  - In tests, `FakeAdbd`:
    - `FakeAdbd({String banner, bool requiresAuth, bool trustsKey, bool approves})`;
    - `transport` (a `FakeUsbTransport`);
    - `commands` (`Map<String, ProcessOutput>`) and `running` (`Map<String, StreamController<String>>`);
    - `opened`, `closedByHost`, `sawPublicKey` and `start()`.

- [ ] **Step 1: Write the fake adbd**

Create `test/helpers/fake_adbd.dart`:

```dart
import 'dart:async';
import 'dart:convert';

import 'package:fcm_studio/features/devices/data/process_runner.dart';
import 'package:fcm_studio/features/devices/data/webusb/adb_message.dart';
import 'package:fcm_studio/features/devices/data/webusb/shell_v2.dart';

import 'fake_usb_transport.dart';

/// Plays adbd on a phone: answers the handshake and runs scripted shell
/// commands over the shell v2 protocol.
class FakeAdbd {
  FakeAdbd({
    this.banner = 'device::ro.product.model=2409BRN2CA;features=shell_v2,cmd',
    this.requiresAuth = true,
    this.trustsKey = true,
    this.approves = true,
  });

  final FakeUsbTransport transport = FakeUsbTransport();
  final String banner;
  final bool requiresAuth;

  /// Accepts the signature (the phone already trusts this browser).
  bool trustsKey;

  /// The user taps Allow when the public key arrives.
  bool approves;

  /// Commands that finish: what they print and their exit code.
  final Map<String, ProcessOutput> commands = {};

  /// Commands that keep running; the test writes their stdout.
  final Map<String, StreamController<String>> running = {};

  /// Every command the host opened, in order.
  final List<String> opened = [];

  /// Long-running commands whose stream the host closed.
  final List<String> closedByHost = [];

  /// Set once the host sent its public key.
  bool sawPublicKey = false;

  final Map<int, String> _commandByRemoteId = {};
  int _nextId = 100;
  bool _serving = false;

  void start() {
    if (_serving) {
      return;
    }
    _serving = true;
    unawaited(_serve());
  }

  Future<void> _serve() async {
    while (true) {
      final AdbMessage message;
      try {
        message = await transport.nextHostMessage();
      } on Object {
        return;
      }
      switch (message.command) {
        case AdbCommand.cnxn:
          if (requiresAuth) {
            _sendToken();
          } else {
            _sendBanner();
          }
        case AdbCommand.auth when message.arg0 == 2:
          if (trustsKey) {
            _sendBanner();
          } else {
            _sendToken();
          }
        case AdbCommand.auth when message.arg0 == 3:
          sawPublicKey = true;
          if (approves) {
            _sendBanner();
          }
        case AdbCommand.open:
          _open(message);
        case AdbCommand.clse:
          final command = _commandByRemoteId.remove(message.arg1);
          if (command != null) {
            closedByHost.add(command);
          }
      }
    }
  }

  void _sendToken() => transport.phoneSends(
    AdbMessage(AdbCommand.auth, 1, 0, List<int>.generate(20, (i) => i)),
  );

  void _sendBanner() => transport.phoneSends(
    AdbMessage.text(AdbCommand.cnxn, 0x01000001, 256 * 1024, banner),
  );

  void _open(AdbMessage message) {
    final hostId = message.arg0;
    final service = message.text;
    const prefix = 'shell,v2,raw:';
    final command = service.startsWith(prefix)
        ? service.substring(prefix.length)
        : service;
    opened.add(command);
    final output = commands[command];
    final stdout = running[command];
    if (output == null && stdout == null) {
      transport.phoneSends(AdbMessage(AdbCommand.clse, 0, hostId));
      return;
    }
    final id = _nextId++;
    transport.phoneSends(AdbMessage(AdbCommand.okay, id, hostId));
    if (output != null) {
      transport
        ..phoneSends(
          AdbMessage(AdbCommand.wrte, id, hostId, [
            if (output.stdout.isNotEmpty)
              ...ShellV2.packet(ShellV2.stdout, utf8.encode(output.stdout)),
            if (output.stderr.isNotEmpty)
              ...ShellV2.packet(ShellV2.stderr, utf8.encode(output.stderr)),
            ...ShellV2.packet(ShellV2.exit, [output.exitCode]),
          ]),
        )
        ..phoneSends(AdbMessage(AdbCommand.clse, id, hostId));
    } else {
      _commandByRemoteId[id] = command;
      stdout!.stream.listen(
        (text) => transport.phoneSends(
          AdbMessage(
            AdbCommand.wrte,
            id,
            hostId,
            ShellV2.packet(ShellV2.stdout, utf8.encode(text)),
          ),
        ),
      );
    }
  }
}
```

- [ ] **Step 2: Write the failing test**

Create `test/features/devices/webusb/shell_v2_test.dart`:

```dart
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

  test('the decoder handles packets split across chunks, or several in one', () {
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
  });

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

  test('a running process streams stdout; kill closes it on the phone', () async {
    final logcat = adbd.running['logcat --pid=42'] = StreamController<String>();
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
  });

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
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `flutter test test/features/devices/webusb/shell_v2_test.dart`
Expected: FAIL to compile: `shell_v2.dart` doesn't exist.

- [ ] **Step 4: Implement shell v2**

Create `lib/features/devices/data/webusb/shell_v2.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:fcm_studio/features/devices/data/adb_exception.dart';
import 'package:fcm_studio/features/devices/data/process_runner.dart';
import 'package:fcm_studio/features/devices/data/webusb/adb_connection.dart';

/// The shell protocol v2 (Android 7+): stdout, stderr and the exit code
/// arrive as separate packets (design §4.6).
abstract final class ShellV2 {
  static const stdout = 1;
  static const stderr = 2;
  static const exit = 3;

  /// No terminal, so the output is passed through byte for byte.
  static String service(String command) => 'shell,v2,raw:$command';

  /// A packet as the phone sends it: id, little-endian length, data.
  static Uint8List packet(int id, List<int> data) {
    final bytes = Uint8List(5 + data.length)..[0] = id;
    ByteData.sublistView(bytes).setUint32(1, data.length, Endian.little);
    return bytes..setRange(5, bytes.length, data);
  }
}

class ShellV2Packet {
  const ShellV2Packet(this.id, this.data);

  final int id;
  final Uint8List data;
}

/// Splits stream data into packets, which may be split across chunks or
/// several to a chunk.
class ShellV2Decoder {
  Uint8List _pending = Uint8List(0);

  List<ShellV2Packet> add(List<int> chunk) {
    final data = Uint8List(_pending.length + chunk.length)
      ..setAll(0, _pending)
      ..setAll(_pending.length, chunk);
    final packets = <ShellV2Packet>[];
    var offset = 0;
    while (data.length - offset >= 5) {
      final length = ByteData.sublistView(
        data,
        offset + 1,
        offset + 5,
      ).getUint32(0, Endian.little);
      if (data.length - offset - 5 < length) {
        break;
      }
      packets.add(
        ShellV2Packet(data[offset], data.sublist(offset + 5, offset + 5 + length)),
      );
      offset += 5 + length;
    }
    _pending = data.sublist(offset);
    return packets;
  }
}

/// Runs [command] on the phone to the end. Throws [AdbException] when the
/// phone refuses it or the connection breaks.
Future<ProcessOutput> runShellV2(
  AdbConnection connection,
  String command,
) async {
  final stream = await connection.open(ShellV2.service(command));
  final decoder = ShellV2Decoder();
  final stdout = BytesBuilder(copy: false);
  final stderr = BytesBuilder(copy: false);
  int? exitCode;
  try {
    await for (final chunk in stream.data) {
      for (final packet in decoder.add(chunk)) {
        switch (packet.id) {
          case ShellV2.stdout:
            stdout.add(packet.data);
          case ShellV2.stderr:
            stderr.add(packet.data);
          case ShellV2.exit:
            exitCode = packet.data.isEmpty ? 0 : packet.data.first;
        }
      }
      if (exitCode != null) {
        break;
      }
    }
  } finally {
    await stream.close();
  }
  final code = exitCode;
  if (code == null) {
    throw const AdbException(
      'The phone ended the command without an exit code.',
    );
  }
  return ProcessOutput(
    exitCode: code,
    stdout: utf8.decode(stdout.takeBytes(), allowMalformed: true),
    stderr: utf8.decode(stderr.takeBytes(), allowMalformed: true),
  );
}

/// A long-running command, e.g. `logcat --pid=…`. [kill] closes its stream,
/// which stops it on the phone.
class ShellV2Process implements RunningProcess {
  ShellV2Process._(this._stream) {
    _subscription = _stream.data.listen(
      _onData,
      onError: _onError,
      onDone: () => _finish(-1),
    );
  }

  static Future<ShellV2Process> start(
    AdbConnection connection,
    String command,
  ) async => ShellV2Process._(await connection.open(ShellV2.service(command)));

  final AdbStream _stream;
  final StreamController<List<int>> _stdout = StreamController<List<int>>();
  final Completer<int> _exit = Completer<int>();
  final ShellV2Decoder _decoder = ShellV2Decoder();
  late final StreamSubscription<Uint8List> _subscription;

  @override
  Stream<List<int>> get stdout => _stdout.stream;

  @override
  Future<int> get exitCode => _exit.future;

  void _onData(Uint8List chunk) {
    for (final packet in _decoder.add(chunk)) {
      switch (packet.id) {
        case ShellV2.stdout:
          if (!_stdout.isClosed) {
            _stdout.add(packet.data);
          }
        case ShellV2.exit:
          _finish(packet.data.isEmpty ? 0 : packet.data.first);
      }
    }
  }

  void _onError(Object error, StackTrace stackTrace) {
    if (!_stdout.isClosed) {
      _stdout.addError(error, stackTrace);
    }
    _finish(-1);
  }

  void _finish(int code) {
    if (!_exit.isCompleted) {
      _exit.complete(code);
      unawaited(_stdout.close());
    }
  }

  @override
  void kill() {
    _finish(-9);
    unawaited(_subscription.cancel());
    unawaited(_stream.close());
  }
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `flutter test test/features/devices/webusb/shell_v2_test.dart`
Expected: PASS (6 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/features/devices/data/webusb/shell_v2.dart test/helpers/fake_adbd.dart test/features/devices/webusb/shell_v2_test.dart
git commit -m "feat: run phone commands over adb shell v2

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Keep the browser key (`AdbKeyStore`)

**Files:**
- Create: `lib/features/devices/data/webusb/adb_key_store.dart`
- Test: `test/features/devices/webusb/adb_key_store_test.dart`

**Interfaces:**
- Consumes: `SecretStore` and `MemorySecretStore` (`lib/core/storage/secret_store.dart`), and `AdbKey` (Task 3).
- Produces: `class AdbKeyStore { AdbKeyStore({required SecretStore secrets, required Future<Map<String, Object?>> Function() generateJwk}); static const secretKey = 'adb:browser-key'; Future<AdbKey> load(); }`.

- [ ] **Step 1: Write the failing test**

Create `test/features/devices/webusb/adb_key_store_test.dart`:

```dart
import 'dart:convert';

import 'package:fcm_studio/core/storage/secret_store.dart';
import 'package:fcm_studio/features/devices/data/webusb/adb_key_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/adb_key_fixture.dart';

void main() {
  late MemorySecretStore secrets;
  late int generated;
  Object? generateError;

  setUp(() {
    secrets = MemorySecretStore();
    generated = 0;
    generateError = null;
  });

  AdbKeyStore store() => AdbKeyStore(
    secrets: secrets,
    generateJwk: () async {
      generated++;
      final error = generateError;
      if (error != null) {
        throw error;
      }
      return testAdbKeyJwk();
    },
  );

  test('makes the key once and keeps it under adb:browser-key', () async {
    final keys = store();
    final first = await keys.load();
    final second = await keys.load();
    expect(identical(first, second), isTrue);
    expect(generated, 1);
    expect(
      jsonDecode((await secrets.read(AdbKeyStore.secretKey))!),
      testAdbKeyJwk(),
    );
  });

  test('loads at the same time share one key', () async {
    final keys = store();
    final both = await Future.wait([keys.load(), keys.load()]);
    expect(identical(both[0], both[1]), isTrue);
    expect(generated, 1);
  });

  test('a stored key is reused on the next visit', () async {
    await secrets.write(AdbKeyStore.secretKey, jsonEncode(testAdbKeyJwk()));
    final key = await store().load();
    expect(generated, 0);
    expect(key.n, testAdbKey().n);
  });

  test('a damaged stored key is replaced', () async {
    await secrets.write(AdbKeyStore.secretKey, '{"n": "AQAB"');
    final key = await store().load();
    expect(generated, 1);
    expect(key.n, testAdbKey().n);
    expect(
      jsonDecode((await secrets.read(AdbKeyStore.secretKey))!),
      testAdbKeyJwk(),
    );
  });

  test('a failed key creation is tried again next time', () async {
    final keys = store();
    generateError = StateError('WebCrypto failed');
    await expectLater(keys.load(), throwsStateError);
    generateError = null;
    await keys.load();
    expect(generated, 2);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/features/devices/webusb/adb_key_store_test.dart`
Expected: FAIL to compile: `adb_key_store.dart` doesn't exist.

- [ ] **Step 3: Implement the store**

Create `lib/features/devices/data/webusb/adb_key_store.dart`:

```dart
import 'dart:convert';

import 'package:fcm_studio/core/storage/secret_store.dart';
import 'package:fcm_studio/features/devices/data/webusb/adb_key.dart';

/// Keeps the browser's adb key in [SecretStore] (design §4.5, §8). It is
/// made once; later visits reuse it, so phones don't ask again.
class AdbKeyStore {
  AdbKeyStore({required this._secrets, required this._generateJwk});

  static const secretKey = 'adb:browser-key';

  final SecretStore _secrets;

  /// Makes a new key as a JWK (WebCrypto in the browser).
  final Future<Map<String, Object?>> Function() _generateJwk;
  Future<AdbKey>? _loading;

  /// The key, made and stored on first use. Loads at the same time share
  /// one; a failed one is tried again next time.
  Future<AdbKey> load() async {
    final loading = _loading ??= _load();
    try {
      return await loading;
    } on Object {
      if (identical(_loading, loading)) {
        _loading = null;
      }
      rethrow;
    }
  }

  Future<AdbKey> _load() async {
    final saved = await _secrets.read(secretKey);
    if (saved != null) {
      try {
        final Object? jwk = jsonDecode(saved);
        if (jwk is Map<String, Object?>) {
          return AdbKey.fromJwk(jwk);
        }
      } on FormatException {
        // A damaged key is replaced; phones then ask once more.
      }
    }
    final jwk = await _generateJwk();
    final key = AdbKey.fromJwk(jwk);
    await _secrets.write(secretKey, jsonEncode(jwk), persist: true);
    return key;
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/features/devices/webusb/adb_key_store_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/devices/data/webusb/adb_key_store.dart test/features/devices/webusb/adb_key_store_test.dart
git commit -m "feat: keep the browser's adb key in the secret store

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 7: The browser's phones (`WebUsbAdbService`)

**Files:**
- Modify: `lib/features/devices/domain/adb_device.dart` (add `note`)
- Create: `lib/features/devices/data/phone_access.dart`
- Create: `lib/features/devices/data/webusb/usb_phone.dart`
- Create: `lib/features/devices/data/webusb/web_usb_device_shell.dart`
- Create: `lib/features/devices/data/webusb/web_usb_adb_service.dart`
- Create: `test/helpers/fake_usb_phone.dart`
- Test: `test/features/devices/webusb/web_usb_adb_service_test.dart`

**Interfaces:**
- Consumes:
  - `AdbCommands`, `DeviceShell`, `PhoneCommand` and `AdbService` (Task 1);
  - `AdbConnection`, `AdbBanner` and `connectionFailureMessage` (Task 4);
  - `runShellV2` and `ShellV2Process` (Task 5);
  - `AdbKey` (Task 3);
  - `UsbTransport` and `UsbClaimException` (Task 4).
- Produces:
  - `AdbDevice.note` (`String?`, part of `props`).
  - `abstract interface class PhoneAccess { Future<void> connectPhone(); Future<void> retry(String serial); Future<void> forget(String serial); }`.
  - `abstract interface class UsbPhone { String get serialNumber; String get productName; int get vendorId; int get productId; Future<UsbTransport> open(); Future<void> forget(); }`.
  - `abstract interface class UsbPhoneSource { Future<List<UsbPhone>> permitted(); Future<UsbPhone?> request(); Stream<UsbPhone> get connected; Stream<UsbPhone> get disconnected; }`.
  - `class WebUsbDeviceShell implements DeviceShell { WebUsbDeviceShell({required AdbConnection Function(String serial) connectionFor, required String Function(String serial) nameOf}); }`.
  - `class WebUsbAdbService implements AdbService, PhoneAccess`:
    - `WebUsbAdbService({required UsbPhoneSource source, required Future<AdbKey> Function() loadKey, required String keyName, bool isWindows = false})`;
    - `static const source = 'webusb'`;
    - `static const connectingNote`, `inUseNote`, `windowsDriverNote`, `tooOldNote` and `notReadyMessage`.
  - In tests, `FakeUsbPhone` (`adbd`, `openError`, `opens`, `forgotten`) and `FakeUsbPhoneSource` (`permittedPhones`, `chosen`, `connectedController`, `disconnectedController`).

- [ ] **Step 1: Add `note` to `AdbDevice`**

In `lib/features/devices/domain/adb_device.dart`:
- Add `this.note,` as the last named constructor parameter.
- Add the field below after `transportId`.
- Add `note` to the end of `props`.

```dart
  /// Why the phone isn't ready, shown instead of the default hint (on the
  /// web, e.g. "Connecting…" or "in use by another program").
  final String? note;
```

- [ ] **Step 2: Write the phone fakes**

Create `test/helpers/fake_usb_phone.dart`:

```dart
import 'dart:async';

import 'package:fcm_studio/features/devices/data/webusb/usb_phone.dart';
import 'package:fcm_studio/features/devices/data/webusb/usb_transport.dart';

import 'fake_adbd.dart';

class FakeUsbPhone implements UsbPhone {
  FakeUsbPhone({
    this.serialNumber = 'DETWFUOZZHZ5SWFQ',
    this.productName = 'Redmi 14C',
    this.vendorId = 0x2717,
    this.productId = 0xFF48,
    FakeAdbd? adbd,
  }) : adbd = adbd ?? FakeAdbd();

  @override
  final String serialNumber;
  @override
  final String productName;
  @override
  final int vendorId;
  @override
  final int productId;

  /// The adbd behind open().
  FakeAdbd adbd;

  /// Thrown by open() when set, e.g. a [UsbClaimException].
  Object? openError;
  int opens = 0;
  bool forgotten = false;

  @override
  Future<UsbTransport> open() async {
    opens++;
    final error = openError;
    if (error != null) {
      throw error;
    }
    adbd.start();
    return adbd.transport;
  }

  @override
  Future<void> forget() async => forgotten = true;
}

class FakeUsbPhoneSource implements UsbPhoneSource {
  final List<UsbPhone> permittedPhones = [];

  /// What the chooser returns; null means the user closed it.
  UsbPhone? chosen;
  final StreamController<UsbPhone> connectedController =
      StreamController<UsbPhone>.broadcast();
  final StreamController<UsbPhone> disconnectedController =
      StreamController<UsbPhone>.broadcast();

  @override
  Future<List<UsbPhone>> permitted() async => [...permittedPhones];

  @override
  Future<UsbPhone?> request() async => chosen;

  @override
  Stream<UsbPhone> get connected => connectedController.stream;

  @override
  Stream<UsbPhone> get disconnected => disconnectedController.stream;
}
```

- [ ] **Step 3: Write the failing test**

Create `test/features/devices/webusb/web_usb_adb_service_test.dart`:

```dart
import 'dart:async';

import 'package:fcm_studio/features/devices/data/adb_exception.dart';
import 'package:fcm_studio/features/devices/data/process_runner.dart';
import 'package:fcm_studio/features/devices/data/webusb/usb_transport.dart';
import 'package:fcm_studio/features/devices/data/webusb/web_usb_adb_service.dart';
import 'package:fcm_studio/features/devices/domain/adb_device.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/adb_key_fixture.dart';
import '../../../helpers/device_fixtures.dart';
import '../../../helpers/fake_adbd.dart';
import '../../../helpers/fake_usb_phone.dart';

void main() {
  late FakeUsbPhoneSource source;
  late WebUsbAdbService service;
  late List<List<AdbDevice>> lists;
  StreamSubscription<List<AdbDevice>>? tracking;

  WebUsbAdbService create({bool isWindows = false}) => WebUsbAdbService(
    source: source,
    loadKey: () async => testAdbKey(),
    keyName: 'fcm-studio@example.com',
    isWindows: isWindows,
  );

  setUp(() {
    source = FakeUsbPhoneSource();
    service = create();
    lists = [];
  });

  tearDown(() => tracking?.cancel());

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 30));

  Future<void> track() async {
    tracking = service.trackDevices().listen(lists.add);
    await settle();
  }

  AdbDevice only() => lists.last.single;

  test('starts with the phones this site may use, and connects them', () async {
    source.permittedPhones.add(FakeUsbPhone());
    await track();
    expect(lists.first, isEmpty);
    expect(only().serial, redmiSerial);
    expect(only().state, DeviceState.device);
    expect(only().model, '2409BRN2CA');
    expect(only().note, isNull);
    expect(
      lists.any(
        (devices) => devices.any(
          (d) =>
              d.rawState == 'connecting' &&
              d.note == WebUsbAdbService.connectingNote,
        ),
      ),
      isTrue,
    );
  });

  test('waiting for "Allow USB debugging?" shows as unauthorized', () async {
    final phone = FakeUsbPhone(
      adbd: FakeAdbd(trustsKey: false, approves: false),
    );
    source.permittedPhones.add(phone);
    await track();
    expect(only().state, DeviceState.unauthorized);
    expect(only().note, isNull);
    expect(phone.adbd.sawPublicKey, isTrue);
  });

  test('a phone held by Android Studio is offline with what to do', () async {
    source.permittedPhones.add(
      FakeUsbPhone()..openError = const UsbClaimException('Unable to claim'),
    );
    await track();
    expect(only().state, DeviceState.offline);
    expect(only().note, WebUsbAdbService.inUseNote);
  });

  test('on Windows the in-use note adds the driver hint', () async {
    service = create(isWindows: true);
    source.permittedPhones.add(
      FakeUsbPhone()..openError = const UsbClaimException('x'),
    );
    await track();
    expect(
      only().note,
      '${WebUsbAdbService.inUseNote}${WebUsbAdbService.windowsDriverNote}',
    );
  });

  test('Retry connects again once the phone is free', () async {
    final phone = FakeUsbPhone()..openError = const UsbClaimException('x');
    source.permittedPhones.add(phone);
    await track();
    phone.openError = null;
    await service.retry(redmiSerial);
    await settle();
    expect(only().state, DeviceState.device);
  });

  test('a phone without shell_v2 is too old', () async {
    source.permittedPhones.add(
      FakeUsbPhone(
        adbd: FakeAdbd(banner: 'device::ro.product.model=old;features=cmd'),
      ),
    );
    await track();
    expect(only().state, DeviceState.offline);
    expect(only().note, WebUsbAdbService.tooOldNote);
  });

  test('plugging in and unplugging update the list', () async {
    await track();
    final phone = FakeUsbPhone();
    source.connectedController.add(phone);
    await settle();
    expect(only().state, DeviceState.device);
    source.disconnectedController.add(phone);
    await settle();
    expect(lists.last, isEmpty);
    expect(phone.adbd.transport.closed, isTrue);
  });

  test('unplugged while waiting for approval, then plugged in again', () async {
    final first = FakeUsbPhone(
      adbd: FakeAdbd(trustsKey: false, approves: false),
    );
    source.permittedPhones.add(first);
    await track();
    expect(only().state, DeviceState.unauthorized);
    source.disconnectedController.add(first);
    await settle();
    expect(lists.last, isEmpty);
    // The browser gives a replugged phone a new device object.
    source.connectedController.add(FakeUsbPhone());
    await settle();
    expect(lists.last, hasLength(1));
    expect(only().state, DeviceState.device);
  });

  test('Connect a phone adds the chosen phone; a closed chooser does nothing', () async {
    await track();
    await service.connectPhone();
    await settle();
    expect(lists.last, isEmpty);
    source.chosen = FakeUsbPhone();
    await service.connectPhone();
    await settle();
    expect(only().state, DeviceState.device);
  });

  test('choosing a phone that is already listed and offline retries it, no duplicate', () async {
    final phone = FakeUsbPhone()..openError = const UsbClaimException('x');
    source.permittedPhones.add(phone);
    await track();
    phone.openError = null;
    source.chosen = phone;
    await service.connectPhone();
    await settle();
    expect(lists.last, hasLength(1));
    expect(only().state, DeviceState.device);
  });

  test('Forget removes the phone and revokes access', () async {
    final phone = FakeUsbPhone();
    source.permittedPhones.add(phone);
    await track();
    await service.forget(redmiSerial);
    await settle();
    expect(lists.last, isEmpty);
    expect(phone.forgotten, isTrue);
  });

  test('two phones with the same serial get a fallback for the second', () async {
    source.permittedPhones
      ..add(FakeUsbPhone())
      ..add(FakeUsbPhone(vendorId: 0x18D1, productId: 0x4EE7));
    await track();
    expect(lists.last.map((d) => d.serial), [redmiSerial, 'usb:18d1:4ee7#1']);
  });

  test('commands run over the connection; a lost phone names the command', () async {
    final phone = FakeUsbPhone();
    phone.adbd.commands['pm list packages -3'] = const ProcessOutput(
      exitCode: 0,
      stdout: 'package:com.b\npackage:com.a\n',
    );
    source.permittedPhones.add(phone);
    await track();
    expect(await service.listPackages(redmiSerial), ['com.a', 'com.b']);

    phone.adbd.transport.unplug();
    await settle();
    expect(only().state, DeviceState.offline);
    expect(
      only().note,
      'The phone was disconnected. Plug it in and click Retry.',
    );
    await expectLater(
      service.listPackages(redmiSerial),
      throwsA(
        isA<AdbException>().having(
          (e) => e.message,
          'message',
          '`pm list packages -3` on Redmi 14C failed: '
              'The phone is not connected. Plug it in and click Retry.',
        ),
      ),
    );
  });
}
```

- [ ] **Step 4: Run the test to verify it fails**

Run: `flutter test test/features/devices/webusb/web_usb_adb_service_test.dart`
Expected: FAIL to compile: `web_usb_adb_service.dart` doesn't exist.

- [ ] **Step 5: Create `PhoneAccess` and the USB phone interfaces**

Create `lib/features/devices/data/phone_access.dart`:

```dart
/// What the Devices screen asks the browser to do with phones (WebUSB
/// design §4.8). Desktop has no such thing: adb finds phones itself.
abstract interface class PhoneAccess {
  /// Shows the browser's chooser. Must follow a button press.
  Future<void> connectPhone();

  /// Connects again to a phone that is offline or waiting for approval.
  Future<void> retry(String serial);

  /// Revokes this site's access to the phone and removes it.
  Future<void> forget(String serial);
}
```

Create `lib/features/devices/data/webusb/usb_phone.dart`:

```dart
import 'package:fcm_studio/features/devices/data/webusb/usb_transport.dart';

/// A USB device with an adb interface that this site may use (design §4.8).
abstract interface class UsbPhone {
  /// May be empty.
  String get serialNumber;
  String get productName;
  int get vendorId;
  int get productId;

  /// Opens the device and claims its adb interface. Throws
  /// [UsbClaimException] when another program holds it.
  Future<UsbTransport> open();

  /// Revokes this site's access to the phone.
  Future<void> forget();
}

/// The browser's phones: the ones this site may use, and the chooser.
abstract interface class UsbPhoneSource {
  Future<List<UsbPhone>> permitted();

  /// Shows the browser's chooser (needs a button press). Null when closed.
  Future<UsbPhone?> request();

  /// A permitted phone was plugged in. The same phone is the same object.
  Stream<UsbPhone> get connected;

  Stream<UsbPhone> get disconnected;
}
```

- [ ] **Step 6: Create `WebUsbDeviceShell`**

Create `lib/features/devices/data/webusb/web_usb_device_shell.dart`:

```dart
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
```

- [ ] **Step 7: Create `WebUsbAdbService`**

Create `lib/features/devices/data/webusb/web_usb_adb_service.dart`:

```dart
import 'dart:async';

import 'package:fcm_studio/features/devices/data/adb_commands.dart';
import 'package:fcm_studio/features/devices/data/adb_service.dart';
import 'package:fcm_studio/features/devices/data/phone_access.dart';
import 'package:fcm_studio/features/devices/data/webusb/adb_connection.dart';
import 'package:fcm_studio/features/devices/data/webusb/adb_key.dart';
import 'package:fcm_studio/features/devices/data/webusb/usb_phone.dart';
import 'package:fcm_studio/features/devices/data/webusb/usb_transport.dart';
import 'package:fcm_studio/features/devices/data/webusb/web_usb_device_shell.dart';
import 'package:fcm_studio/features/devices/domain/adb_device.dart';
import 'package:fcm_studio/features/devices/domain/token_read_results.dart';

/// The browser's phones as an [AdbService] (design §4.8): one adb connection
/// per phone, and the same phone commands as desktop.
class WebUsbAdbService implements AdbService, PhoneAccess {
  WebUsbAdbService({
    required this._source,
    required this._loadKey,
    required this._keyName,
    this._isWindows = false,
  });

  /// On the web there is no adb path; this stands in for it, so
  /// `DevicesBloc` and `TokenReaderCubit` work unchanged.
  static const source = 'webusb';

  static const connectingNote = 'Connecting…';
  static const inUseNote =
      'This phone is in use by another program. Close Android Studio or run '
      '`adb kill-server`, then click Retry.';
  static const windowsDriverNote =
      ' If it still fails, install the Google USB Driver for this phone.';
  static const tooOldNote =
      'This phone runs Android 6 or older. Use the desktop app for it.';
  static const notReadyMessage =
      'The phone is not connected. Plug it in and click Retry.';

  final UsbPhoneSource _source;
  final Future<AdbKey> Function() _loadKey;
  final String _keyName;
  final bool _isWindows;
  final List<_Phone> _phones = [];
  final StreamController<List<AdbDevice>> _changes =
      StreamController<List<AdbDevice>>.broadcast();
  late final AdbCommands _commands = AdbCommands(
    shell: WebUsbDeviceShell(connectionFor: _connectionFor, nameOf: _nameOf),
  );
  Future<void>? _started;
  int _fallbackSerials = 0;

  /// The current phones at once, then every change. Never ends.
  @override
  Stream<List<AdbDevice>> trackDevices() {
    late final StreamController<List<AdbDevice>> controller;
    StreamSubscription<List<AdbDevice>>? changes;
    controller = StreamController<List<AdbDevice>>(
      onListen: () {
        changes = _changes.stream.listen(controller.add);
        controller.add(_devices());
        unawaited(_start());
      },
      onCancel: () => changes?.cancel(),
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

  @override
  Future<void> connectPhone() async {
    await _start();
    final usb = await _source.request();
    if (usb == null) {
      return;
    }
    final known = _phoneFor(usb);
    if (known == null) {
      _add(usb);
    } else if (known.state != DeviceState.device) {
      unawaited(_connect(known));
    }
  }

  @override
  Future<void> retry(String serial) async {
    final phone = _find(serial);
    if (phone != null) {
      unawaited(_connect(phone));
    }
  }

  @override
  Future<void> forget(String serial) async {
    final phone = _find(serial);
    if (phone == null) {
      return;
    }
    _remove(phone.usb);
    await phone.usb.forget();
  }

  Future<void> _start() => _started ??= _listen();

  Future<void> _listen() async {
    _source.connected.listen(_add);
    _source.disconnected.listen(_remove);
    for (final usb in await _source.permitted()) {
      _add(usb);
    }
  }

  _Phone? _phoneFor(UsbPhone usb) {
    for (final phone in _phones) {
      if (identical(phone.usb, usb)) {
        return phone;
      }
    }
    return null;
  }

  _Phone? _find(String serial) {
    for (final phone in _phones) {
      if (phone.serial == serial) {
        return phone;
      }
    }
    return null;
  }

  void _add(UsbPhone usb) {
    if (_phoneFor(usb) != null) {
      return;
    }
    final phone = _Phone(usb, _serialFor(usb));
    _phones.add(phone);
    unawaited(_connect(phone));
  }

  /// The USB serial number, or `usb:<vendor>:<product>#<n>` when it is empty
  /// or another phone already has it (design §4.8).
  String _serialFor(UsbPhone usb) {
    final serial = usb.serialNumber;
    if (serial.isNotEmpty && _find(serial) == null) {
      return serial;
    }
    _fallbackSerials++;
    String hex(int id) => id.toRadixString(16).padLeft(4, '0');
    return 'usb:${hex(usb.vendorId)}:${hex(usb.productId)}#$_fallbackSerials';
  }

  void _remove(UsbPhone usb) {
    final phone = _phoneFor(usb);
    if (phone == null) {
      return;
    }
    _phones.remove(phone);
    phone.attempt++;
    final connection = phone.connection;
    phone.connection = null;
    if (connection != null) {
      unawaited(connection.close());
    }
    _emit();
  }

  /// Claims the phone and runs the handshake. A newer attempt, or the phone
  /// going away, makes an older one stop quietly.
  Future<void> _connect(_Phone phone) async {
    final attempt = ++phone.attempt;
    bool current() => phone.attempt == attempt && _phones.contains(phone);
    final old = phone.connection;
    phone.connection = null;
    _set(
      phone,
      DeviceState.other,
      rawState: 'connecting',
      note: connectingNote,
    );
    if (old != null) {
      await old.close();
    }
    try {
      final transport = await phone.usb.open();
      if (!current()) {
        await transport.close();
        return;
      }
      final connection = AdbConnection(
        transport: transport,
        loadKey: _loadKey,
        keyName: _keyName,
      );
      phone.connection = connection;
      unawaited(
        connection.lost.then((error) {
          if (current()) {
            _set(
              phone,
              DeviceState.offline,
              note: connectionFailureMessage(error),
            );
          }
        }),
      );
      final banner = await connection.connect(
        onWaitingForApproval: () {
          if (current()) {
            _set(phone, DeviceState.unauthorized);
          }
        },
      );
      if (!current()) {
        return;
      }
      if (!banner.hasShellV2) {
        phone.connection = null;
        await connection.close();
        _set(phone, DeviceState.offline, note: tooOldNote);
        return;
      }
      phone.model = banner.model;
      _set(phone, DeviceState.device);
    } on UsbClaimException {
      if (current()) {
        _set(
          phone,
          DeviceState.offline,
          note: _isWindows ? '$inUseNote$windowsDriverNote' : inUseNote,
        );
      }
    } on Object catch (error) {
      if (current()) {
        _set(
          phone,
          DeviceState.offline,
          note: connectionFailureMessage(error),
        );
      }
    }
  }

  void _set(
    _Phone phone,
    DeviceState state, {
    String? rawState,
    String? note,
  }) {
    phone
      ..state = state
      ..rawState = rawState ?? state.name
      ..note = note;
    _emit();
  }

  void _emit() => _changes.add(_devices());

  List<AdbDevice> _devices() => [
    for (final phone in _phones)
      AdbDevice(
        serial: phone.serial,
        state: phone.state,
        rawState: phone.rawState,
        model: phone.model ?? _nonEmpty(phone.usb.productName),
        note: phone.note,
      ),
  ];

  AdbConnection _connectionFor(String serial) {
    final phone = _find(serial);
    final connection = phone?.connection;
    if (phone == null ||
        phone.state != DeviceState.device ||
        connection == null) {
      throw const AdbException(notReadyMessage);
    }
    return connection;
  }

  String _nameOf(String serial) {
    final phone = _find(serial);
    if (phone == null) {
      return serial;
    }
    return _nonEmpty(phone.usb.productName) ?? phone.model ?? serial;
  }

  static String? _nonEmpty(String text) => text.isEmpty ? null : text;
}

class _Phone {
  _Phone(this.usb, this.serial);

  final UsbPhone usb;
  final String serial;
  DeviceState state = DeviceState.other;
  String rawState = 'connecting';
  String? note = WebUsbAdbService.connectingNote;
  String? model;
  AdbConnection? connection;

  /// Bumped by every connect and by removal; older attempts stop.
  int attempt = 0;
}
```

- [ ] **Step 8: Run the tests**

Run: `flutter test test/features/devices/webusb/`
Expected: PASS (5 + 6 + 15 + 6 + 5 + 13 = 50 tests).

Run: `flutter analyze && flutter test`
Expected: `No issues found!`, and everything passes. `AdbDevice.note` defaults to null, so desktop is unchanged.

- [ ] **Step 9: Commit**

```bash
git add lib/features/devices/domain/adb_device.dart lib/features/devices/data/phone_access.dart lib/features/devices/data/webusb/usb_phone.dart lib/features/devices/data/webusb/web_usb_device_shell.dart lib/features/devices/data/webusb/web_usb_adb_service.dart test/helpers/fake_usb_phone.dart test/features/devices/webusb/web_usb_adb_service_test.dart
git commit -m "feat: track the browser's phones and run their commands over WebUSB

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 8: The browser layer (WebUSB interop, WebCrypto key)

This task has no unit tests, because these files can only run in a browser. It's verified by the analyzer and a `dart compile js` check, and Task 9's `flutter build web` compiles it inside the app.

**Files:**
- Create: `lib/core/platform/device_access.dart`
- Create: `lib/features/devices/data/webusb/browser/usb_interop.dart`
- Create: `lib/features/devices/data/webusb/browser/web_usb_transport.dart`
- Create: `lib/features/devices/data/webusb/browser/web_usb_phone.dart`
- Create: `lib/features/devices/data/webusb/browser/webusb_platform_web.dart`
- Create: `lib/features/devices/data/webusb/webusb_platform_stub.dart`
- Create: `lib/features/devices/data/webusb/webusb_platform.dart`
- Modify: `pubspec.yaml` (add `web: ^1.1.1`, already a transitive dependency)

**Interfaces:**
- Consumes: `UsbTransport`, `UsbClaimException` and `UsbDisconnectedException` (Task 4); `UsbPhone` and `UsbPhoneSource` (Task 7).
- Produces:
  - `enum DeviceAccess { adb, webUsb, noWebUsb, notSecure }`.
  - From `webusb_platform.dart`: `DeviceAccess browserDeviceAccess()`, `UsbPhoneSource createUsbPhoneSource()`, `String adbKeyName()` and `Future<Map<String, Object?>> generateAdbKeyJwk()`.

- [ ] **Step 1: Add the dependency and `DeviceAccess`**

In `pubspec.yaml`, under `dependencies:`, add this line after `url_launcher: ^6.3.3`:

```yaml
  web: ^1.1.1
```

Run: `flutter pub get`
Expected: it resolves; `web` stays at 1.1.1.

Create `lib/core/platform/device_access.dart`. It has no Flutter imports, so `dart compile js` can check the browser files:

```dart
/// How this platform reaches phones (WebUSB design §4.9).
enum DeviceAccess {
  /// Desktop: the adb program.
  adb,

  /// Chrome, Edge or Opera on https or localhost: WebUSB.
  webUsb,

  /// A browser without WebUSB, e.g. Firefox or Safari.
  noWebUsb,

  /// A web page not opened over https (or localhost).
  notSecure,
}
```

- [ ] **Step 2: Write the WebUSB interop**

Create `lib/features/devices/data/webusb/browser/usb_interop.dart`:

```dart
// WebUSB isn't in package:web (it only covers standards-track APIs), so the
// few calls FCM Studio needs are declared here. Web only (design §4.1).
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// `navigator.usb`, or null in browsers without WebUSB.
Usb? get navigatorUsb {
  final usb = (web.window.navigator as JSObject).getProperty<JSAny?>(
    'usb'.toJS,
  );
  return usb.isUndefinedOrNull ? null : usb as Usb;
}

extension type Usb._(JSObject _) implements web.EventTarget {
  external JSPromise<JSArray<UsbDevice>> getDevices();
  external JSPromise<UsbDevice> requestDevice(UsbDeviceRequestOptions options);
}

extension type UsbDeviceRequestOptions._(JSObject _) implements JSObject {
  external factory UsbDeviceRequestOptions({
    required JSArray<UsbDeviceFilter> filters,
  });
}

extension type UsbDeviceFilter._(JSObject _) implements JSObject {
  external factory UsbDeviceFilter({
    int classCode,
    int subclassCode,
    int protocolCode,
  });
}

extension type UsbDevice._(JSObject _) implements JSObject {
  external String? get serialNumber;
  external String? get productName;
  external int get vendorId;
  external int get productId;
  external bool get opened;
  external UsbConfiguration? get configuration;
  external JSArray<UsbConfiguration> get configurations;
  external JSPromise<JSAny?> open();
  external JSPromise<JSAny?> close();
  external JSPromise<JSAny?> forget();
  external JSPromise<JSAny?> selectConfiguration(int configurationValue);
  external JSPromise<JSAny?> claimInterface(int interfaceNumber);
  external JSPromise<JSAny?> releaseInterface(int interfaceNumber);
  external JSPromise<UsbInTransferResult> transferIn(
    int endpointNumber,
    int length,
  );
  external JSPromise<UsbOutTransferResult> transferOut(
    int endpointNumber,
    JSUint8Array data,
  );
}

extension type UsbConfiguration._(JSObject _) implements JSObject {
  external int get configurationValue;
  external JSArray<UsbInterface> get interfaces;
}

extension type UsbInterface._(JSObject _) implements JSObject {
  external int get interfaceNumber;
  external JSArray<UsbAlternateInterface> get alternates;
}

extension type UsbAlternateInterface._(JSObject _) implements JSObject {
  external int get interfaceClass;
  external int get interfaceSubclass;
  external int get interfaceProtocol;
  external JSArray<UsbEndpoint> get endpoints;
}

extension type UsbEndpoint._(JSObject _) implements JSObject {
  external int get endpointNumber;

  /// `in` or `out`.
  external String get direction;

  /// `bulk`, `interrupt` or `isochronous`.
  external String get type;
  external int get packetSize;
}

extension type UsbInTransferResult._(JSObject _) implements JSObject {
  external JSDataView? get data;

  /// `ok`, `stall` or `babble`.
  external String get status;
}

extension type UsbOutTransferResult._(JSObject _) implements JSObject {
  external int get bytesWritten;
  external String get status;
}

extension type UsbConnectionEvent._(JSObject _) implements web.Event {
  external UsbDevice get device;
}
```

- [ ] **Step 3: Write `WebUsbTransport`**

Create `lib/features/devices/data/webusb/browser/web_usb_transport.dart`:

```dart
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:fcm_studio/features/devices/data/webusb/browser/usb_interop.dart';
import 'package:fcm_studio/features/devices/data/webusb/usb_transport.dart';

/// The adb interface: class 0xFF, subclass 0x42, protocol 0x01.
const adbClass = 0xFF;
const adbSubclass = 0x42;
const adbProtocol = 0x01;

/// Where a device's adb interface and its bulk endpoints are.
class AdbInterface {
  const AdbInterface({
    required this.configurationValue,
    required this.interfaceNumber,
    required this.inEndpoint,
    required this.outEndpoint,
    required this.packetSize,
  });

  final int configurationValue;
  final int interfaceNumber;
  final int inEndpoint;
  final int outEndpoint;
  final int packetSize;
}

/// The device's adb interface, or null when it has none.
AdbInterface? findAdbInterface(UsbDevice device) {
  for (final configuration in device.configurations.toDart) {
    for (final interface in configuration.interfaces.toDart) {
      for (final alternate in interface.alternates.toDart) {
        if (alternate.interfaceClass != adbClass ||
            alternate.interfaceSubclass != adbSubclass ||
            alternate.interfaceProtocol != adbProtocol) {
          continue;
        }
        UsbEndpoint? inEndpoint;
        UsbEndpoint? outEndpoint;
        for (final endpoint in alternate.endpoints.toDart) {
          if (endpoint.type != 'bulk') {
            continue;
          }
          if (endpoint.direction == 'in') {
            inEndpoint = endpoint;
          } else {
            outEndpoint = endpoint;
          }
        }
        if (inEndpoint != null && outEndpoint != null) {
          return AdbInterface(
            configurationValue: configuration.configurationValue,
            interfaceNumber: interface.interfaceNumber,
            inEndpoint: inEndpoint.endpointNumber,
            outEndpoint: outEndpoint.endpointNumber,
            packetSize: outEndpoint.packetSize,
          );
        }
      }
    }
  }
  return null;
}

/// A claimed adb interface (design §4.2).
class WebUsbTransport implements UsbTransport {
  WebUsbTransport._(this._device, this._interface);

  /// Opens [device] and claims its adb interface. Throws
  /// [UsbClaimException] when that fails, usually because adb or Android
  /// Studio holds the phone.
  static Future<WebUsbTransport> open(UsbDevice device) async {
    final interface = findAdbInterface(device);
    if (interface == null) {
      throw const UsbClaimException('This device has no adb interface.');
    }
    try {
      if (!device.opened) {
        await device.open().toDart;
      }
      if (device.configuration?.configurationValue !=
          interface.configurationValue) {
        await device.selectConfiguration(interface.configurationValue).toDart;
      }
      await device.claimInterface(interface.interfaceNumber).toDart;
    } on Object catch (error) {
      throw UsbClaimException('$error');
    }
    return WebUsbTransport._(device, interface);
  }

  final UsbDevice _device;
  final AdbInterface _interface;

  @override
  Future<Uint8List> read(int length) async {
    final UsbInTransferResult result;
    try {
      result = await _device.transferIn(_interface.inEndpoint, length).toDart;
    } on Object catch (error) {
      throw UsbDisconnectedException('$error');
    }
    final data = result.data;
    if (result.status != 'ok' || data == null) {
      throw UsbDisconnectedException('USB read failed: ${result.status}.');
    }
    final bytes = data.toDart;
    return Uint8List.fromList(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    );
  }

  @override
  Future<void> write(Uint8List bytes) async {
    try {
      await _transfer(bytes);
      // Some phones wait for a zero-length packet after a transfer that
      // fills its last USB packet exactly (design §12).
      if (bytes.isNotEmpty && bytes.length % _interface.packetSize == 0) {
        await _transfer(Uint8List(0));
      }
    } on UsbDisconnectedException {
      rethrow;
    } on Object catch (error) {
      throw UsbDisconnectedException('$error');
    }
  }

  Future<void> _transfer(Uint8List bytes) async {
    final result = await _device
        .transferOut(_interface.outEndpoint, bytes.toJS)
        .toDart;
    if (result.status != 'ok') {
      throw UsbDisconnectedException('USB write failed: ${result.status}.');
    }
  }

  @override
  Future<void> close() async {
    try {
      await _device.releaseInterface(_interface.interfaceNumber).toDart;
      await _device.close().toDart;
    } on Object {
      // Unplugged phones can't be released; the browser cleans up.
    }
  }
}
```

- [ ] **Step 4: Write the phone source**

Create `lib/features/devices/data/webusb/browser/web_usb_phone.dart`:

```dart
import 'dart:async';
import 'dart:js_interop';

import 'package:fcm_studio/features/devices/data/webusb/browser/usb_interop.dart';
import 'package:fcm_studio/features/devices/data/webusb/browser/web_usb_transport.dart';
import 'package:fcm_studio/features/devices/data/webusb/usb_phone.dart';
import 'package:fcm_studio/features/devices/data/webusb/usb_transport.dart';
import 'package:web/web.dart' as web;

/// One browser USB device with an adb interface.
class WebUsbPhone implements UsbPhone {
  WebUsbPhone(this.device);

  final UsbDevice device;

  @override
  String get serialNumber => device.serialNumber ?? '';

  @override
  String get productName => device.productName ?? '';

  @override
  int get vendorId => device.vendorId;

  @override
  int get productId => device.productId;

  @override
  Future<UsbTransport> open() => WebUsbTransport.open(device);

  @override
  Future<void> forget() async {
    try {
      await device.forget().toDart;
    } on Object {
      // Browsers before Chrome 101 can't forget; the phone stays allowed.
    }
  }
}

/// `navigator.usb`, limited to phones with an adb interface.
class WebUsbPhoneSource implements UsbPhoneSource {
  WebUsbPhoneSource(this._usb);

  final Usb _usb;

  /// One wrapper per device, so the same phone is the same object.
  final List<WebUsbPhone> _phones = [];

  WebUsbPhone _wrap(UsbDevice device) {
    for (final phone in _phones) {
      if (phone.device == device) {
        return phone;
      }
    }
    final phone = WebUsbPhone(device);
    _phones.add(phone);
    return phone;
  }

  @override
  Future<List<UsbPhone>> permitted() async => [
    for (final device in (await _usb.getDevices().toDart).toDart)
      if (findAdbInterface(device) != null) _wrap(device),
  ];

  @override
  Future<UsbPhone?> request() async {
    try {
      final device = await _usb
          .requestDevice(
            UsbDeviceRequestOptions(
              filters: [
                UsbDeviceFilter(
                  classCode: adbClass,
                  subclassCode: adbSubclass,
                  protocolCode: adbProtocol,
                ),
              ].toJS,
            ),
          )
          .toDart;
      return _wrap(device);
    } on Object {
      // The user closed the chooser (NotFoundError).
      return null;
    }
  }

  @override
  Stream<UsbPhone> get connected => _events(
    'connect',
  ).where((device) => findAdbInterface(device) != null).map(_wrap);

  @override
  Stream<UsbPhone> get disconnected => _events('disconnect').map(_wrap);

  Stream<UsbDevice> _events(String type) => web.EventStreamProvider<web.Event>(
    type,
  ).forTarget(_usb).map((event) => (event as UsbConnectionEvent).device);
}
```

- [ ] **Step 5: Write the platform files**

Create `lib/features/devices/data/webusb/browser/webusb_platform_web.dart`:

```dart
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:fcm_studio/core/platform/device_access.dart';
import 'package:fcm_studio/features/devices/data/webusb/browser/usb_interop.dart';
import 'package:fcm_studio/features/devices/data/webusb/browser/web_usb_phone.dart';
import 'package:fcm_studio/features/devices/data/webusb/usb_phone.dart';
import 'package:web/web.dart' as web;

/// What this browser can do with phones (design §4.9).
DeviceAccess browserDeviceAccess() {
  // Browsers only expose navigator.usb on https (or localhost) pages.
  if (!web.window.isSecureContext) {
    return DeviceAccess.notSecure;
  }
  return navigatorUsb == null ? DeviceAccess.noWebUsb : DeviceAccess.webUsb;
}

UsbPhoneSource createUsbPhoneSource() => WebUsbPhoneSource(navigatorUsb!);

/// The name the phone shows next to the browser's key.
String adbKeyName() => 'fcm-studio@${web.window.location.host}';

/// A new 2048-bit RSA key from WebCrypto, exported as a JWK (design §4.5).
Future<Map<String, Object?>> generateAdbKeyJwk() async {
  final subtle = web.window.crypto.subtle;
  final pair =
      await subtle
              .generateKey(
                _RsaKeyGenParams(
                  name: 'RSASSA-PKCS1-v1_5',
                  modulusLength: 2048,
                  publicExponent: Uint8List.fromList([1, 0, 1]).toJS,
                  hash: 'SHA-1',
                ),
                true,
                ['sign'.toJS].toJS,
              )
              .toDart
          as _KeyPair;
  final jwk = await subtle.exportKey('jwk', pair.privateKey).toDart;
  final map = jwk.dartify()! as Map<Object?, Object?>;
  return {for (final entry in map.entries) '${entry.key}': entry.value};
}

extension type _RsaKeyGenParams._(JSObject _) implements JSObject {
  external factory _RsaKeyGenParams({
    required String name,
    required int modulusLength,
    required JSUint8Array publicExponent,
    required String hash,
  });
}

extension type _KeyPair._(JSObject _) implements JSObject {
  external web.CryptoKey get privateKey;
}
```

Create `lib/features/devices/data/webusb/webusb_platform_stub.dart`:

```dart
import 'package:fcm_studio/core/platform/device_access.dart';
import 'package:fcm_studio/features/devices/data/webusb/usb_phone.dart';

// Desktop and `flutter test` have no browser. These are only called on the
// web, where webusb_platform_web.dart replaces them.

DeviceAccess browserDeviceAccess() => DeviceAccess.noWebUsb;

UsbPhoneSource createUsbPhoneSource() =>
    throw UnsupportedError('WebUSB needs a browser.');

String adbKeyName() => 'fcm-studio';

Future<Map<String, Object?>> generateAdbKeyJwk() async =>
    throw UnsupportedError('WebCrypto needs a browser.');
```

Create `lib/features/devices/data/webusb/webusb_platform.dart`:

```dart
// The browser half of WebUSB (design §4.1); desktop and tests get stand-ins.
export 'package:fcm_studio/features/devices/data/webusb/webusb_platform_stub.dart'
    if (dart.library.js_interop) 'package:fcm_studio/features/devices/data/webusb/browser/webusb_platform_web.dart';
```

- [ ] **Step 6: Verify**

Run: `flutter analyze`
Expected: `No issues found!`

Check that the browser files compile to JavaScript (no Flutter imports on this path):

```bash
CHECK="$(mktemp -d)"
cat > "$CHECK/webusb_check.dart" <<'EOF'
import 'package:fcm_studio/features/devices/data/webusb/browser/webusb_platform_web.dart';

Future<void> main() async {
  print(browserDeviceAccess());
  print(adbKeyName());
  print(await createUsbPhoneSource().permitted());
  print((await generateAdbKeyJwk()).keys);
}
EOF
dart compile js --packages=.dart_tool/package_config.json -o "$CHECK/webusb_check.js" "$CHECK/webusb_check.dart"
```

Expected: `Compiled … to … characters JavaScript`, with no errors.

Run: `flutter test`
Expected: all pass. Nothing uses these files in the VM yet.

- [ ] **Step 7: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/core/platform/device_access.dart lib/features/devices/data/webusb/browser/ lib/features/devices/data/webusb/webusb_platform.dart lib/features/devices/data/webusb/webusb_platform_stub.dart
git commit -m "feat: WebUSB and WebCrypto browser layer for phones on the web

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 9: Platform features and app wiring

`PlatformFeatures` changes from `canRunAdb` to `deviceAccess`:
- **Devices** is always in the rail;
- **From device…** shows when phones can be read;
- **Settings** stays desktop-only.

On the web with WebUSB, the app creates the `WebUsbAdbService` and starts tracking at once.

**Files:**
- Modify: `lib/core/platform/platform_capabilities.dart`
- Modify: `lib/app/shell.dart`, `lib/features/composer/view/target_picker.dart`, `lib/app/app.dart`, `lib/app/dependencies.dart`
- Create: `test/helpers/fake_phone_access.dart`
- Modify: `test/helpers/app_harness.dart`, `test/app/app_test.dart`, `test/features/settings/settings_screen_test.dart`

**Interfaces:**
- Consumes:
  - `DeviceAccess` (Task 8);
  - `browserDeviceAccess`, `createUsbPhoneSource`, `adbKeyName` and `generateAdbKeyJwk` (Task 8);
  - `AdbKeyStore` (Task 6);
  - `WebUsbAdbService` and `PhoneAccess` (Task 7).
- Produces:
  - `class PlatformFeatures { const PlatformFeatures({required DeviceAccess deviceAccess}); bool get canRunAdb; bool get canReadPhones; }`.
  - `AppDependencies.phoneAccess` (`PhoneAccess?`), and the `AppDependencies(platform: PlatformFeatures?, phoneAccess: PhoneAccess?)` parameters.
  - `PhoneAccess` provided in the widget tree when it isn't null.
  - In tests: `FakePhoneAccess`, and `buildTestDependencies(phoneAccess:)`.

- [ ] **Step 1: Write the fake and update the harness**

Create `test/helpers/fake_phone_access.dart`:

```dart
import 'package:fcm_studio/features/devices/data/phone_access.dart';

/// Records what the Devices screen asked the browser to do.
class FakePhoneAccess implements PhoneAccess {
  int connects = 0;
  final List<String> retried = [];
  final List<String> forgotten = [];

  /// Thrown by connectPhone when set.
  Object? connectError;

  @override
  Future<void> connectPhone() async {
    connects++;
    final error = connectError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<void> retry(String serial) async => retried.add(serial);

  @override
  Future<void> forget(String serial) async => forgotten.add(serial);
}
```

In `test/helpers/app_harness.dart`:
- Change the parameter `PlatformFeatures platform = const PlatformFeatures(canRunAdb: true),` to `PlatformFeatures platform = const PlatformFeatures(deviceAccess: DeviceAccess.adb),`.
- Add the parameter `PhoneAccess? phoneAccess,` after it.
- Pass `phoneAccess: phoneAccess,` in the `AppDependencies(...)` call.
- Add `import 'package:fcm_studio/features/devices/data/phone_access.dart';`.

- [ ] **Step 2: Write the failing tests**

In `test/features/settings/settings_screen_test.dart`, change `platform: const PlatformFeatures(canRunAdb: false),` to `platform: const PlatformFeatures(deviceAccess: DeviceAccess.noWebUsb),`.

In `test/app/app_test.dart`:

1. Add these imports:

```dart
import 'package:fcm_studio/features/devices/data/webusb/web_usb_adb_service.dart';

import '../helpers/fake_phone_access.dart';
```

2. In the test `'on the web adb is never looked for'`, change `const PlatformFeatures(canRunAdb: false)` to `const PlatformFeatures(deviceAccess: DeviceAccess.noWebUsb)`.

3. Replace the whole test `'on the web there are no device entry points'` with these two tests:

```dart
  testWidgets('without WebUSB, Devices stays but From device is hidden', (
    tester,
  ) async {
    await pumpApp(
      tester,
      await buildTestDependencies(
        tester,
        platform: const PlatformFeatures(deviceAccess: DeviceAccess.noWebUsb),
      ),
    );
    await addTestProject(tester);
    // The composer is on screen, so the target picker is built.
    expect(find.text('Target'), findsOneWidget);
    expect(find.byKey(const Key('nav-devices')), findsOneWidget);
    expect(find.byKey(const Key('nav-settings')), findsNothing);
    expect(find.byKey(TargetPicker.fromDeviceKey), findsNothing);
  });

  testWidgets('with WebUSB, phones are tracked at once and Settings is hidden', (
    tester,
  ) async {
    final adb = FakeAdbService();
    await pumpApp(
      tester,
      await buildTestDependencies(
        tester,
        adb: adb,
        platform: const PlatformFeatures(deviceAccess: DeviceAccess.webUsb),
        phoneAccess: FakePhoneAccess(),
      ),
    );
    expect(adb.trackers, hasLength(1));
    expect(
      readCubit<DevicesBloc>(tester).state.adbPath,
      WebUsbAdbService.source,
    );
    expect(readCubit<AdbSetupCubit>(tester).state.status, AdbStatus.unknown);
    expect(find.byKey(const Key('nav-devices')), findsOneWidget);
    expect(find.byKey(const Key('nav-settings')), findsNothing);
    await addTestProject(tester);
    expect(find.byKey(TargetPicker.fromDeviceKey), findsOneWidget);
  });
```

Then search for other uses of the old API: `grep -rn "canRunAdb:" test lib`. Expected: no matches left after this step and Step 4.

- [ ] **Step 3: Run the tests to verify they fail**

Run: `flutter test test/app/app_test.dart`
Expected: FAIL to compile: `PlatformFeatures` has no `deviceAccess` parameter, and `buildTestDependencies` passes a `phoneAccess` that `AppDependencies` doesn't accept.

- [ ] **Step 4: Implement**

Replace `lib/core/platform/platform_capabilities.dart` with:

```dart
import 'package:fcm_studio/core/platform/device_access.dart';

export 'package:fcm_studio/core/platform/device_access.dart';

/// What this platform can do (spec §3.1; WebUSB design §4.9).
class PlatformFeatures {
  const PlatformFeatures({required this.deviceAccess});

  final DeviceAccess deviceAccess;

  /// Desktop: adb runs, and its path is set in Settings.
  bool get canRunAdb => deviceAccess == DeviceAccess.adb;

  /// Phones can be read: adb on desktop, WebUSB in Chromium browsers.
  bool get canReadPhones =>
      deviceAccess == DeviceAccess.adb || deviceAccess == DeviceAccess.webUsb;
}
```

In `lib/app/shell.dart`, replace `sectionsFor` and its comment with:

```dart
  /// The rail's sections, in order. Devices is always there: on the web it
  /// explains when the browser can't reach phones. Settings holds the adb
  /// path, so it is desktop only (spec §3.1; WebUSB design §4.9).
  static List<AppSection> sectionsFor(PlatformFeatures platform) => [
    AppSection.composer,
    AppSection.presets,
    AppSection.targets,
    AppSection.history,
    AppSection.devices,
    if (platform.canRunAdb) AppSection.settings,
  ];
```

In `lib/features/composer/view/target_picker.dart`, change `if (context.read<PlatformFeatures>().canRunAdb)` to `if (context.read<PlatformFeatures>().canReadPhones)`.

In `lib/app/dependencies.dart`:

1. Add these imports:

```dart
import 'package:fcm_studio/features/devices/data/phone_access.dart';
import 'package:fcm_studio/features/devices/data/webusb/adb_key_store.dart';
import 'package:fcm_studio/features/devices/data/webusb/web_usb_adb_service.dart';
import 'package:fcm_studio/features/devices/data/webusb/webusb_platform.dart';
```

2. In the factory parameters, change `PlatformFeatures platform = PlatformFeatures.current,` to `PlatformFeatures? platform,`. Add `PhoneAccess? phoneAccess,` after `adbServiceFor`.

3. At the start of the factory body, before `final projectsRepository`, add:

```dart
    final features =
        platform ??
        PlatformFeatures(
          deviceAccess: kIsWeb ? browserDeviceAccess() : DeviceAccess.adb,
        );
    // The web build's phones (WebUSB design §4.8). Tests pass their own.
    final webUsb =
        features.deviceAccess == DeviceAccess.webUsb && adbServiceFor == null
        ? WebUsbAdbService(
            source: createUsbPhoneSource(),
            loadKey: AdbKeyStore(
              secrets: secrets,
              generateJwk: generateAdbKeyJwk,
            ).load,
            keyName: adbKeyName(),
            isWindows: defaultTargetPlatform == TargetPlatform.windows,
          )
        : null;
```

4. In the `AppDependencies._(...)` call:
   - change `platform: platform,` to `platform: features,`;
   - replace the `adbServiceFor:` argument with the code below;
   - add `phoneAccess: phoneAccess ?? webUsb,` after it.

```dart
      adbServiceFor:
          adbServiceFor ??
          switch (webUsb) {
            final service? => (_) => service,
            null => (path) => ProcessAdbService(runner: runner, adbPath: path),
          },
```

5. Add `required this.phoneAccess,` to the `AppDependencies._` constructor, and add this field after `adbServiceFor`:

```dart
  /// Connect, Retry and Forget for the web's phones; null on desktop.
  final PhoneAccess? phoneAccess;
```

**Ruling (record it in the ledger):**
- **Decision:** `_AdbExitGuard` stays desktop-only (`enabled: dependencies.platform.canRunAdb`, unchanged).
- **Why:** a web app has no exit request; the browser releases the phones when the tab closes. Design §4.9 said the guard would be "replaced by closing all connections".
- **Cost if wrong:** a phone held until the browser notices the tab is gone.
- **Spec:** Task 11 updates the design text.

In `lib/app/app.dart`:

1. Add these imports:

```dart
import 'package:fcm_studio/features/devices/data/phone_access.dart';
import 'package:fcm_studio/features/devices/data/webusb/web_usb_adb_service.dart';
```

2. In `MultiRepositoryProvider`'s `providers`, add after the `PlatformFeatures` provider:

```dart
        if (dependencies.phoneAccess case final phoneAccess?)
          RepositoryProvider<PhoneAccess>.value(value: phoneAccess),
```

3. Replace the `DevicesBloc` provider's `create` with:

```dart
            create: (_) {
              final bloc = DevicesBloc(serviceFor: dependencies.adbServiceFor);
              // There is no adb to find on the web: WebUSB phones are
              // tracked at once (WebUSB design §4.9).
              if (dependencies.platform.deviceAccess == DeviceAccess.webUsb) {
                bloc.add(const DevicesAdbChanged(WebUsbAdbService.source));
              }
              return bloc;
            },
```

- [ ] **Step 5: Run the tests**

Run: `flutter test test/app/app_test.dart test/features/settings/settings_screen_test.dart`
Expected: PASS.

Run: `grep -rn "canRunAdb:" test lib`
Expected: no output.

Run: `flutter analyze && flutter test`
Expected: `No issues found!`, and all tests pass.

Run: `flutter build web`
Expected: `✓ Built build/web`. This is the first build that compiles the browser layer inside the app.

- [ ] **Step 6: Commit**

```bash
git add lib/core/platform/platform_capabilities.dart lib/app/shell.dart lib/features/composer/view/target_picker.dart lib/app/app.dart lib/app/dependencies.dart test/helpers/fake_phone_access.dart test/helpers/app_harness.dart test/app/app_test.dart test/features/settings/settings_screen_test.dart
git commit -m "feat: devices on the web: WebUSB wiring, Devices in the rail everywhere

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 10: The Devices screen on the web

**Files:**
- Modify: `lib/features/devices/view/devices_screen.dart` (full replacement below)
- Test: `test/features/devices/devices_screen_web_test.dart` (new). `test/features/devices/devices_screen_test.dart` must pass unchanged.

**Interfaces:**
- Consumes: `PhoneAccess` (Task 7, provided in Task 9), `AdbDevice.note` (Task 7), `PlatformFeatures.deviceAccess` (Task 9), `AppErrorCubit.report(Object, {String? context})`.
- Produces:
  - `DevicesScreen.connectPhoneKey`, `DevicesScreen.deviceMenuKey(String serial)`;
  - `DevicesScreen.noWebUsbMessage`, `DevicesScreen.notSecureMessage`, `DevicesScreen.keyNotice`.

- [ ] **Step 1: Write the failing test**

Create `test/features/devices/devices_screen_web_test.dart`:

```dart
import 'package:fcm_studio/core/platform/platform_capabilities.dart';
import 'package:fcm_studio/features/composer/view/target_picker.dart';
import 'package:fcm_studio/features/devices/data/webusb/web_usb_adb_service.dart';
import 'package:fcm_studio/features/devices/domain/adb_device.dart';
import 'package:fcm_studio/features/devices/view/devices_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/app_harness.dart';
import '../../helpers/device_fixtures.dart';
import '../../helpers/fake_adb_service.dart';
import '../../helpers/fake_phone_access.dart';

const app = 'com.syldel.delivery';
const webUsb = PlatformFeatures(deviceAccess: DeviceAccess.webUsb);

void main() {
  late FakeAdbService adb;
  late FakePhoneAccess phones;

  setUp(() {
    adb = FakeAdbService()..packages[redmiSerial] = ['com.alpha', app];
    phones = FakePhoneAccess();
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

  AdbDevice phone(DeviceState state, {String? note}) => AdbDevice(
    serial: redmiSerial,
    state: state,
    rawState: state.name,
    model: '2409BRN2CA',
    note: note,
  );

  testWidgets('Connect a phone… opens the browser chooser', (tester) async {
    await openDevices(tester);
    await phonesAre(tester, const []);
    expect(find.text('No phones yet'), findsOneWidget);
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

  testWidgets('an offline phone says why; Retry and Forget reach the browser', (
    tester,
  ) async {
    await openDevices(tester);
    await phonesAre(tester, [
      phone(DeviceState.offline, note: WebUsbAdbService.inUseNote),
    ]);
    expect(find.text(WebUsbAdbService.inUseNote), findsOneWidget);

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

  testWidgets('a ready phone lists its apps like on desktop; no Retry', (
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

  testWidgets('the screen says the browser keeps a key', (tester) async {
    await openDevices(tester);
    await phonesAre(tester, const []);
    expect(find.text(DevicesScreen.keyNotice), findsOneWidget);
  });

  testWidgets('without WebUSB, Devices explains what to do', (tester) async {
    await openDevices(
      tester,
      platform: const PlatformFeatures(deviceAccess: DeviceAccess.noWebUsb),
    );
    expect(find.text(DevicesScreen.noWebUsbMessage), findsOneWidget);
    expect(find.byKey(DevicesScreen.connectPhoneKey), findsNothing);
    await tester.tap(find.byKey(const Key('nav-composer')));
    await tester.pumpAndSettle();
    expect(find.byKey(TargetPicker.fromDeviceKey), findsNothing);
  });

  testWidgets('over plain http, Devices says to use https', (tester) async {
    await openDevices(
      tester,
      platform: const PlatformFeatures(deviceAccess: DeviceAccess.notSecure),
    );
    expect(find.text(DevicesScreen.notSecureMessage), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/features/devices/devices_screen_web_test.dart`
Expected: FAIL to compile: `DevicesScreen.connectPhoneKey` and the other constants don't exist.

- [ ] **Step 3: Replace `devices_screen.dart`**

Replace `lib/features/devices/view/devices_screen.dart` with the following. `_DevicePanel` and `_PackageList` are unchanged from today's file:

```dart
import 'package:fcm_studio/app/app_error_cubit.dart';
import 'package:fcm_studio/app/navigation_cubit.dart';
import 'package:fcm_studio/core/platform/platform_capabilities.dart';
import 'package:fcm_studio/features/devices/bloc/devices_bloc.dart';
import 'package:fcm_studio/features/devices/cubit/token_reader_cubit.dart';
import 'package:fcm_studio/features/devices/data/phone_access.dart';
import 'package:fcm_studio/features/devices/domain/adb_device.dart';
import 'package:fcm_studio/features/devices/domain/device_token.dart';
import 'package:fcm_studio/features/devices/view/device_actions.dart';
import 'package:fcm_studio/features/devices/view/token_read_view.dart';
import 'package:fcm_studio/features/projects/cubit/projects_cubit.dart';
import 'package:fcm_studio/features/settings/cubit/adb_setup_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Plugged-in phones, their apps, and reading an app's token (spec §9; on
/// the web through WebUSB, design §4.9).
class DevicesScreen extends StatelessWidget {
  const DevicesScreen({super.key});

  static const openSettingsKey = Key('devices-open-settings');
  static const connectPhoneKey = Key('devices-connect-phone');

  static Key deviceMenuKey(String serial) => ValueKey('device-menu-$serial');

  static const noWebUsbMessage =
      'Reading tokens from a phone needs Chrome or Edge. You can still paste '
      'a token in Target.';
  static const notSecureMessage =
      'Open FCM Studio over https to connect a phone.';
  static const keyNotice =
      'This browser keeps a USB debugging key for this site. Forget removes '
      'its access to a phone.';

  /// Changes when a different phone becomes ready to read.
  static String? _readyPhone(DevicesState state) {
    final device = state.selected;
    return device != null && device.isReady
        ? '${state.adbPath}|${device.serial}'
        : null;
  }

  static FoundToken? _singleToken(TokenRead read) =>
      read is TokenReadFound && read.tokens.length == 1
      ? read.tokens.single
      : null;

  /// The browser only shows its chooser after a button press.
  static Future<void> _connectPhone(BuildContext context) async {
    final errors = context.read<AppErrorCubit>();
    try {
      await context.read<PhoneAccess>().connectPhone();
    } on Object catch (error) {
      errors.report(error, context: 'Could not connect the phone');
    }
  }

  @override
  Widget build(BuildContext context) {
    final access = context.read<PlatformFeatures>().deviceAccess;
    if (access == DeviceAccess.noWebUsb || access == DeviceAccess.notSecure) {
      return _NoPhoneAccess(
        message: access == DeviceAccess.noWebUsb
            ? noWebUsbMessage
            : notSecureMessage,
      );
    }
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
            if (webUsb)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: FilledButton.icon(
                  key: connectPhoneKey,
                  onPressed: () => _connectPhone(context),
                  icon: const Icon(Icons.usb),
                  label: const Text('Connect a phone…'),
                ),
              ),
          ],
        ),
        body: BlocBuilder<DevicesBloc, DevicesState>(
          builder: (context, state) {
            if (state.status == TrackerStatus.noAdb && !webUsb) {
              return const _NoAdb();
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 320,
                  child: _DeviceList(state: state, webUsb: webUsb),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: _DevicePanel(state: state)),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Firefox, Safari, or a page not opened over https (design §7).
class _NoPhoneAccess extends StatelessWidget {
  const _NoPhoneAccess({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Devices')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.usb_off, size: 48),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoAdb extends StatelessWidget {
  const _NoAdb();

  @override
  Widget build(BuildContext context) {
    final status = context.watch<AdbSetupCubit>().state.status;
    if (status == AdbStatus.unknown || status == AdbStatus.locating) {
      return const Center(child: Text('Looking for adb…'));
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.usb_off, size: 48),
            const SizedBox(height: 12),
            const Text("adb was not found, so phones can't be read."),
            const SizedBox(height: 8),
            const Text(
              'Install Android SDK Platform-Tools, or set the path to adb in Settings.',
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: DevicesScreen.openSettingsKey,
              onPressed: () =>
                  context.read<NavigationCubit>().show(AppSection.settings),
              child: const Text('Open Settings'),
            ),
          ],
        ),
      ),
    );
  }
}

enum _PhoneAction { retry, forget }

class _DeviceList extends StatelessWidget {
  const _DeviceList({required this.state, required this.webUsb});

  final DevicesState state;
  final bool webUsb;

  /// A WebUSB phone's note (e.g. "in use by another program") wins.
  static String _stateText(AdbDevice device) =>
      device.note ??
      switch (device.state) {
        DeviceState.device => 'Ready',
        DeviceState.unauthorized =>
          'Accept the USB debugging prompt on the phone',
        DeviceState.offline => 'Offline. Unplug the phone and plug it in again.',
        DeviceState.other => device.rawState,
      };

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        if (state.status == TrackerStatus.starting)
          ListTile(
            title: Text(webUsb ? 'Looking for phones…' : 'Starting adb…'),
          ),
        if (state.status == TrackerStatus.restarting)
          ListTile(
            key: const Key('devices-restarting'),
            leading: Icon(Icons.sync_problem, color: error),
            title: Text(
              'adb stopped. Trying again in '
              '${state.retryIn?.inSeconds ?? 0} s…',
            ),
            subtitle: switch (state.lastError) {
              final message? => Text(message),
              null => null,
            },
          ),
        if (state.status == TrackerStatus.running && state.devices.isEmpty)
          ListTile(
            leading: const Icon(Icons.phone_android),
            title: Text(webUsb ? 'No phones yet' : 'No phone connected'),
            subtitle: Text(
              webUsb
                  ? 'Turn on USB debugging on the phone, plug it in, then '
                        'click Connect a phone…'
                  : 'Connect an Android phone with USB debugging turned on.',
            ),
          ),
        for (final device in state.devices)
          ListTile(
            key: ValueKey('device-${device.serial}'),
            selected: device.serial == state.selectedSerial,
            enabled: device.isReady,
            leading: Icon(
              device.isReady ? Icons.phone_android : Icons.phonelink_erase,
            ),
            title: Text(state.nameOf(device)),
            subtitle: Text(_stateText(device)),
            trailing: webUsb ? _PhoneMenu(device: device) : null,
            onTap: device.isReady
                ? () => context.read<DevicesBloc>().add(
                    DeviceSelected(device.serial),
                  )
                : null,
          ),
        if (webUsb)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              DevicesScreen.keyNotice,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}

/// Retry (when not ready) and Forget, for a WebUSB phone.
class _PhoneMenu extends StatelessWidget {
  const _PhoneMenu({required this.device});

  final AdbDevice device;

  Future<void> _run(BuildContext context, _PhoneAction action) async {
    final phones = context.read<PhoneAccess>();
    final errors = context.read<AppErrorCubit>();
    try {
      switch (action) {
        case _PhoneAction.retry:
          await phones.retry(device.serial);
        case _PhoneAction.forget:
          await phones.forget(device.serial);
      }
    } on Object catch (error) {
      errors.report(error, context: 'Could not ${action.name} the phone');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_PhoneAction>(
      key: DevicesScreen.deviceMenuKey(device.serial),
      tooltip: 'Phone options',
      onSelected: (action) => _run(context, action),
      itemBuilder: (context) => [
        if (!device.isReady)
          const PopupMenuItem(value: _PhoneAction.retry, child: Text('Retry')),
        const PopupMenuItem(value: _PhoneAction.forget, child: Text('Forget')),
      ],
    );
  }
}
```

After `_PhoneMenu`, keep today's `_DevicePanel` and `_PackageList` classes **exactly** as they are (copy them over unchanged from the current file, lines 188–306).

- [ ] **Step 4: Run the tests**

Run: `flutter test test/features/devices/devices_screen_web_test.dart test/features/devices/devices_screen_test.dart`
Expected: PASS. All 8 new tests pass, and every desktop test passes unchanged (a desktop phone has no note, so its texts are the same).

If tapping `deviceMenuKey` on the offline row doesn't open the menu (a disabled `ListTile` blocking its trailing widget), give the `ListTile` `enabled: true` and keep `onTap` null for phones that aren't ready. Record that as a ruling.

Run: `flutter analyze && flutter test`
Expected: `No issues found!`, and all tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/features/devices/view/devices_screen.dart test/features/devices/devices_screen_web_test.dart
git commit -m "feat: Devices on the web: Connect a phone, why it's offline, Retry and Forget

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 11: Documents and final checks

**Files:**
- Modify: `docs/superpowers/specs/2026-10-04-webusb-devices-design.md`
- Modify: `docs/superpowers/specs/2026-10-03-fcm-studio-design.md`

- [ ] **Step 1: Record the status in the WebUSB design**

In `docs/superpowers/specs/2026-10-04-webusb-devices-design.md`:

1. Replace the `**Status:**` line with:

```markdown
**Status:**
- **Implemented:** 2026-10-04 (M5 code with tests).
- **Pending:** the manual success test in §10, on the Redmi in Chrome.
```

2. In §3, add this row to the table:

```markdown
| Signing in the browser takes about 160 ms with CRT (about 510 ms without), once per connection | Measured 2026-10-04 with the dart2js build in Node 22 |
```

3. In §4.4, replace the line ``- Each `write` waits for the phone's `OKAY` before the next `WRTE` (classic flow control; we don't announce `delayed_ack`).`` with:

```markdown
- Streams only receive. No command sends stdin, so the host never writes `WRTE`, and the design has no flow control for host writes (no `delayed_ack` either).
```

4. In §9, delete the line ``  - flow control (no second `WRTE` before `OKAY`);``.

5. In §4.9, replace ``The adb exit guard is replaced by closing all connections when the app exits.`` with ``The adb exit guard stays desktop-only: when the tab closes, the browser releases the phones.``

6. In §12, replace the "Slow signing" bullet with:

```markdown
- **Slow signing:** measured at about 160 ms per connection (§3), so it isn't a problem.
```

- [ ] **Step 2: Record the status in the main spec**

In `docs/superpowers/specs/2026-10-03-fcm-studio-design.md` §13, find the M4 status block. Add an M5 block after it, in the same style:

```markdown
**M5 status (2026-10-04):**
- **Done:** the code with its automated tests passing and a clean `flutter analyze`; `flutter build web` succeeds.
- **Covered by unit tests:** the adb protocol, key pairing, shell v2 and the phone list, run against a fake phone. The browser layer (`webusb/browser/`) is checked by compiling it.
- **Pending (manual):** the WebUSB success test (WebUSB design §10) on the Redmi in Chrome. That test also fills in the design's "to check" rows.
```

- [ ] **Step 3: Final verification**

Run: `flutter analyze`
Expected: `No issues found!`

Run: `flutter test`
Expected: all pass, about 637 tests. That's 573 before M5 plus 64 new: Task 1 5, Task 2 5, Task 3 6, Task 4 15, Task 5 6, Task 6 5, Task 7 13, Task 9 net +1, Task 10 8.

Run: `flutter build web`
Expected: `✓ Built build/web`.

Run: `flutter build macos --debug`
Expected: `✓ Built build/macos/Build/Products/Debug/FCM Studio.app`. Desktop still builds.

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/specs/2026-10-04-webusb-devices-design.md docs/superpowers/specs/2026-10-03-fcm-studio-design.md
git commit -m "docs: record M5 (phones on the web) status

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

- [ ] **Step 5: Hand over the manual success test**

Give the user the design §10 checklist:
1. Run `flutter run -d chrome` (or open the hosted build) in Chrome, with Android Studio open.
2. **Connect a phone…** shows the "in use" note. Quit Android Studio, click **Retry**, and accept "Allow USB debugging?" with "Always allow".
3. Read a debug 6amMart build's token with `run-as`, and a release build's with the logcat fallback.
4. Reload the page: the phone reconnects without the chooser or the prompt.
5. Unplug during a logcat read: "The phone was disconnected".
6. Firefox shows the Chrome-or-Edge message.
