# FCM Studio M3 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Take FCM Studio from M2 to the M3 milestone. Find adb, track plugged-in Android phones, list their apps, and read an app's FCM token with `run-as`, falling back to logcat for release builds. The token becomes the composer's target and is saved as a device target, and a wrong-project token is flagged. M3 is done when the success test works fully on the Redmi in under 30 seconds: plug in the phone, pick an app, pick a preset, see the notification.

**Architecture:** Every adb call goes through an injectable `ProcessRunner`, so tests never start real processes. The web build swaps in a stub, and the UI hides the device features there. A pure-Dart layer parses adb output: `track-devices` framing, device lists, `pm list`, `run-as` messages, the token prefs XML and the logcat token pattern. `ProcessAdbService` builds the adb commands on top of that layer. `AdbSetupCubit` finds adb (spec §9.1), `DevicesBloc` tracks devices with restart backoff (§9.2), and `TokenReaderCubit` runs the run-as → logcat flow (§9.3). A Devices screen and a Settings screen join the navigation rail, and "From device…" in the composer opens the Devices screen.

**Tech Stack:** Flutter 3.44 / Dart 3.12, `flutter_bloc`, `equatable`, `sembast`, `path`, `dart:io` `Process` (desktop only, behind a conditional import). **No new packages.**

**Spec:** `docs/superpowers/specs/2026-10-03-fcm-studio-design.md`. Read §3.1–§3.3, §7.1, §9, §10, §11 and §12 before starting. The M2 plan (`docs/superpowers/plans/2026-10-03-fcm-studio-m2.md`) shows the conventions the code follows.

## Before you start

- Work directly on `main` and commit there, one commit per task (the user's standing preference). Do not create a branch.
- `flutter test` must pass and `flutter analyze` must say `No issues found!` before Task 1. There were 312 tests at the time of writing.
- The test phone is the Redmi 14C, serial `DETWFUOZZHZ5SWFQ`, on Android 16, connected over USB. adb is at `/opt/homebrew/bin/adb` and `~/Library/Android/sdk/platform-tools/adb`. `com.syldel.delivery` on the phone is now a **debug** build, and it has `shared_prefs/com.google.android.gms.appid.xml` (checked 2026-10-04).

## Global Constraints

- Project root: `/Users/mobarak/Documents/learn/fcm_studio`. Package `fcm_studio`. Platforms: **macOS, Windows, web only**.
- Use package imports (`package:fcm_studio/...`) in `lib/` and `tool/`. Tests import helpers with relative paths, as the existing tests do.
- State management uses `flutter_bloc`: Cubits, plus one `Bloc` for devices (`DevicesBloc`, spec §3.3). States extend `Equatable`. Models are hand-written, with **no code generation**.
- Constructors take private fields through private named parameters, e.g. `TargetsCubit({required this._repository, this._clock = const SystemClock()})`, called as `TargetsCubit(repository: …, clock: …)`.
- Lints: `flutter_lints` plus `strict-casts`, `strict-inference`, `strict-raw-types`, `always_declare_return_types`, `avoid_dynamic_calls`, `prefer_final_locals`, `prefer_single_quotes`, `unawaited_futures`. Always write type arguments. Put `child:`/`children:` last in widget constructors. Always use braces in `if`/`for`. The analyzer prefers `?x` null-aware collection elements over `if (x case final y?) y`.
- Each task ends with `dart format lib test`, `flutter analyze` reporting **No issues found!**, and `flutter test` passing.
- **Every adb call goes through `ProcessRunner`** (spec §9.1). A one-shot call has a 10 s timeout. The token file is read with `exec-out`. Output is decoded as UTF-8 with `allowMalformed`. Only `track-devices` and `logcat` run long.
- **adb failures name the command that failed, and never block the rest of the app** (spec §11). The app must work fully without adb.
- **Never run `logcat -c`** (spec §9.3). The logcat step runs only after the user confirms, because it restarts the app.
- **Device tokens never go into logs or `debugPrint`.** Logcat lines are only searched for a token, never shown or stored.
- The device features (Devices screen, Settings screen, "From device…") exist only on desktop. On web the UI hides them (spec §3.1).
- macOS: App Sandbox stays off, so the app can run adb (spec §10). No entitlement changes are needed.
- Commit at the end of each task with the message given there. End every commit message with the Co-Authored-By line your own harness attribution instructions give you.

### Decisions where the spec is silent

1. **"From device…" opens the Devices screen.** When exactly one ready phone is connected, it is selected automatically.
2. **A token found with `run-as` or logcat is used straight away:** it becomes the composer target, is saved as a device target, and the app returns to the composer. If the file holds tokens for several sender IDs, the user picks one. The one matching the selected project's number is preselected.
3. **The run-as → logcat flow lives in a `TokenReaderCubit`,** next to `DevicesBloc`, which tracks devices and selection. Spec §12's "DevicesBloc … run-as → logcat flow" tests become `TokenReaderCubit` tests.
4. **The adb path is typed in Settings** (a text dialog) and checked by running `adb version`. "Find automatically" clears it.
5. **The last 5 packages are remembered per device serial.**
6. **A device that disappears stays selected**, so it is picked up again when it comes back. If a different single ready device appears, that one is selected.
7. **Unauthorized and offline devices are listed with their hint** but cannot be opened.
8. **A device target is saved under the selected project.** Its label uses the phone's market name (`ro.product.marketname`), falling back to the model, then the serial.

## Review Focus

These inputs are the most likely to cause trouble for someone using the app. Each one has a test in the task named.

1. **adb not found.** Either the Android SDK isn't installed, or the app was launched from Finder without the shell's `PATH`. The app keeps working. Devices and Settings say what was tried and how to fix it. *Task 5 ("reports every path it tried when nothing works"), Task 11 ("shows that adb was not found and where it looked") and Task 12 ("without adb, Devices explains and links to Settings").*
2. **The phone shows `unauthorized`** because the USB debugging prompt was never accepted. The app shows the hint, never selects or reads from that phone, and never crashes. *Task 7 ("an unauthorized phone is listed but not selected or queried") and Task 12 ("an unauthorized phone shows the hint and can't be opened").*
3. **The phone is unplugged, or the adb server dies.** The tracker restarts with backoff (1, 2, 4… up to 30 s). A read in flight ends with a message naming the failed command. *Task 7 ("restarts the tracker with backoff after adb exits"), Task 6 ("an adb failure is reported with its command") and Task 8 ("a failed read shows the message").*
4. **A release build never logs its token.** The logcat step stops after 20 s with an explanation, and never runs `logcat -c`. *Task 6 ("stops after the timeout when the app never logs a token", "never clears the log").*
5. **The app is installed but was never opened,** so there is no token file yet. The user sees "Open the app once", Launch app and Retry. *Task 8 ("no token yet, then launch and retry") and Task 12 ("an app that was never opened offers Launch app and Retry").*

## Not in this plan

- Google sign-in (M4). Release builds and the README (M5).
- Reading tokens from iOS devices (out of scope for v1, spec §1).

## File map

New files:

| File | Responsibility |
|---|---|
| `lib/core/platform/platform_capabilities.dart` | `PlatformFeatures` (can this platform run adb?) |
| `lib/features/devices/data/process_runner.dart` | `ProcessRunner`, `RunningProcess`, `ProcessOutput`, `ProcessRunException` |
| `lib/features/devices/data/process_runner_io.dart`, `_stub.dart`, `_platform.dart` | dart:io runner, web stub, conditional export |
| `lib/features/devices/data/parsers/*.dart` | device list, track-devices framing, `pm list`, run-as classifier, token pattern, appid prefs parser |
| `lib/features/devices/domain/adb_device.dart` | `AdbDevice`, `DeviceState`, `DeviceDetails` |
| `lib/features/devices/domain/device_token.dart` | `FoundToken`, `DeviceToken`, `TokenReadMethod` |
| `lib/features/devices/domain/package_order.dart` | recent-first package ordering |
| `lib/features/devices/data/adb_locator.dart` | finds adb (§9.1) |
| `lib/features/devices/data/adb_service.dart` | adb commands (§9.2, §9.3) |
| `lib/features/devices/data/recent_packages_repository.dart` | last 5 packages per device |
| `lib/features/devices/bloc/*.dart` | `DevicesBloc` (tracking, backoff, selection, details) |
| `lib/features/devices/cubit/*.dart` | `TokenReaderCubit` (packages, run-as, logcat) |
| `lib/features/devices/view/*.dart` | Devices screen, use-token action |
| `lib/features/settings/data/settings_repository.dart` | stored adb path |
| `lib/features/settings/cubit/*.dart` | `AdbSetupCubit` |
| `lib/features/settings/view/settings_screen.dart` | adb path, Change…, Find automatically |
| `lib/features/composer/domain/sender_check.dart` | sender-ID mismatch rule (§7.1) |
| `lib/features/composer/view/sender_warning.dart` | the composer warning with Switch project |
| `test/fixtures/adb/appid_prefs_debug.xml` | sanitized real token file (Task 1) |
| `test/helpers/fake_process_runner.dart`, `fake_adb_service.dart`, `device_fixtures.dart` | test doubles |

Changed files: `lib/app/app.dart`, `lib/app/dependencies.dart`, `lib/app/navigation_cubit.dart`, `lib/app/shell.dart`, `lib/features/targets/cubit/targets_cubit.dart`, `lib/features/composer/view/target_picker.dart`, `lib/features/composer/view/composer_screen.dart`, `test/helpers/app_harness.dart` and the spec.

---

### Task 1: Capture the real token file (user-assisted) and record what adb really prints

The M0 check deferred to the start of M3. **Steps 1–2 need the user**, because Claude Code refuses to read FCM tokens. The controller asks the user to run them. An agent can do Steps 3–6.

**Files:**
- Create: `test/fixtures/adb/appid_prefs_debug.xml` (the user's sanitized capture)
- Modify: `docs/superpowers/specs/2026-10-03-fcm-studio-design.md` (§2, §9.3, §13, §14)

- [ ] **Step 1 (the user): open the debug app once** on the Redmi, so it has registered for FCM. `com.syldel.delivery` is installed as a debug build.

- [ ] **Step 2 (the user): capture the token file with tokens and long values replaced.** Run this from the project root:

```bash
mkdir -p test/fixtures/adb
adb -s DETWFUOZZHZ5SWFQ exec-out run-as com.syldel.delivery cat shared_prefs/com.google.android.gms.appid.xml \
  | sed -E \
      -e 's/[A-Za-z0-9_-]{11,}:APA91b[A-Za-z0-9_-]+/fakeInstanceId0000000:APA91bFAKE_TOKEN_FOR_TESTS_ONLY_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/g' \
      -e 's/(name="\|S\|id">)[^<]*/\1REDACTED_FID/g' \
      -e 's/>[A-Za-z0-9+\/=_-]{40,}</>REDACTED_LONG_VALUE</g' \
  > test/fixtures/adb/appid_prefs_debug.xml
```

- [ ] **Step 3: check that the capture is clean.** These commands print only counts:

```bash
grep -o 'APA91b' test/fixtures/adb/appid_prefs_debug.xml | wc -l
grep -o 'APA91bFAKE_TOKEN_FOR_TESTS_ONLY_' test/fixtures/adb/appid_prefs_debug.xml | wc -l
grep -Ec '\|T\|[0-9]+\|' test/fixtures/adb/appid_prefs_debug.xml
```
Expected: the first two counts are equal and at least 1, so every token is the fake one. The third count is at least 1, so there is at least one token key. If the first two differ, delete the file and ask the user to run Step 2 again. Never open the file before this check passes.

- [ ] **Step 4: read the sanitized file** and note its shape: the token key format (e.g. `[DEFAULT]|T|<sender id>|*`), whether the value is JSON `{"token":…,"appVersion":…,"timestamp":…}` with `&quot;` escapes or a raw token, and any other `|T|` keys. Task 4's parser must accept exactly this shape.

- [ ] **Step 5: record the results in the spec.**
  - §9.3, replace the italic sentence *"The exact file format must be confirmed…"* with: `Confirmed on 2026-10-04 with com.syldel.delivery (debug build) on the Redmi 14C. Fixture: test/fixtures/adb/appid_prefs_debug.xml.` Follow it with one sentence describing the key and value shape from Step 4.
  - §9.3 table:
    - Replace `Package '<p>' is unknown` with `run-as: unknown package: <package>` (Android 16, seen 2026-10-04; older Android prints `Package '<p>' is unknown`, and both are handled).
    - Replace `No such file or directory` with `cat: shared_prefs/com.google.android.gms.appid.xml: No such file or directory`.
  - §2, last bullet: append `On 2026-10-04 a debug build of com.syldel.delivery was installed, so run-as works for it.`
  - §13: under the M0/M1 status, change "The M0 token-file capture (moved to M3)" in both pending lists to `The M0 token-file capture: done 2026-10-04 (see §9.3).`
  - §14, "Token file format": append `Confirmed on 2026-10-04 (see §9.3).`

- [ ] **Step 6: Commit**

```bash
git add test/fixtures/adb/appid_prefs_debug.xml docs/superpowers/specs/2026-10-03-fcm-studio-design.md
git commit -m "docs: confirm the token file format and adb messages on the Redmi"
```

---

### Task 2: `ProcessRunner`: run adb safely on desktop, never on web

**Files:**
- Create: `lib/features/devices/data/process_runner.dart`, `lib/features/devices/data/process_runner_io.dart`, `lib/features/devices/data/process_runner_stub.dart`, `lib/features/devices/data/process_runner_platform.dart`, `test/helpers/fake_process_runner.dart`
- Test: `test/features/devices/process_runner_test.dart`, `test/features/devices/fake_process_runner_test.dart`

**Interfaces:**
- Produces:
  - `class ProcessOutput({required int exitCode, String stdout = '', String stderr = ''})` with `combined` (stdout and stderr joined by a newline, empty parts left out).
  - `abstract interface class RunningProcess { Stream<List<int>> get stdout; Future<int> get exitCode; void kill(); }`.
  - `class ProcessRunException(String command, String reason)` with `message` → `` `<command>` <reason> ``.
  - `abstract interface class ProcessRunner { static const defaultTimeout = Duration(seconds: 10); Future<ProcessOutput> run(String executable, List<String> arguments, {Duration timeout}); Future<RunningProcess> start(String executable, List<String> arguments); }`.
  - `String describeCommand(String executable, List<String> arguments)` (joined with spaces).
  - From `process_runner_platform.dart`: `ProcessRunner createProcessRunner()`, `Map<String, String> platformEnvironment()`, `bool platformIsWindows()`. On web these return `UnsupportedProcessRunner`, `{}` and `false`.
  - Test helper `FakeProcessRunner` with `on(String command, Object answer)`, where the answer is a `ProcessOutput`, a `List<ProcessOutput>` (successive calls; the last one repeats) or an `Exception`. It also has `onStart(String command, FakeRunningProcess Function() create)`, `calls`, `commands`, and a helper `ProcessOutput ok(String stdout)`. Unscripted commands throw `ProcessRunException(command, 'could not start: not scripted')`, like a missing program.
  - Test helper `FakeRunningProcess` with `emit(String text)`, `exit([int code = 0])` and `killed`.

- [ ] **Step 1: Write the failing tests**

`test/features/devices/process_runner_test.dart`:
```dart
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
```

`test/features/devices/fake_process_runner_test.dart`:
```dart
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
    expect((await runner.run('adb', ['-s', 'X', 'shell', 'pidof', 'app'])).stdout, '');
    expect((await runner.run('adb', ['-s', 'X', 'shell', 'pidof', 'app'])).stdout, '42\n');
    expect((await runner.run('adb', ['-s', 'X', 'shell', 'pidof', 'app'])).stdout, '42\n');
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
```

- [ ] **Step 2: Run them to see them fail**

Run: `flutter test test/features/devices/process_runner_test.dart test/features/devices/fake_process_runner_test.dart`
Expected: FAIL, compilation errors (the files don't exist).

- [ ] **Step 3: Implement**

`lib/features/devices/data/process_runner.dart`:
```dart
import 'package:equatable/equatable.dart';

/// What a finished command printed.
class ProcessOutput extends Equatable {
  const ProcessOutput({required this.exitCode, this.stdout = '', this.stderr = ''});

  final int exitCode;
  final String stdout;
  final String stderr;

  /// stdout and stderr together. adb prints some errors on either.
  String get combined => [stdout, stderr].where((s) => s.isNotEmpty).join('\n');

  @override
  List<Object?> get props => [exitCode, stdout, stderr];
}

/// A long-running command, e.g. `adb track-devices` or `adb logcat`.
abstract interface class RunningProcess {
  Stream<List<int>> get stdout;
  Future<int> get exitCode;
  void kill();
}

/// A command that could not start or did not finish in time. The message
/// names the command (spec §11).
class ProcessRunException implements Exception {
  const ProcessRunException(this.command, this.reason);

  final String command;
  final String reason;

  String get message => '`$command` $reason';

  @override
  String toString() => 'ProcessRunException: $message';
}

/// Runs external commands (adb). Injected, so tests never start real processes.
abstract interface class ProcessRunner {
  static const defaultTimeout = Duration(seconds: 10);

  /// Runs a command to the end. Throws [ProcessRunException] when it can't
  /// start or doesn't finish within [timeout].
  Future<ProcessOutput> run(
    String executable,
    List<String> arguments, {
    Duration timeout = defaultTimeout,
  });

  /// Starts a long-running command. Throws [ProcessRunException] when it can't start.
  Future<RunningProcess> start(String executable, List<String> arguments);
}

/// A command as one line, for messages.
String describeCommand(String executable, List<String> arguments) =>
    [executable, ...arguments].join(' ');
```

`lib/features/devices/data/process_runner_io.dart`:
```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fcm_studio/features/devices/data/process_runner.dart';

ProcessRunner createProcessRunner() => const IoProcessRunner();

Map<String, String> platformEnvironment() => Platform.environment;

bool platformIsWindows() => Platform.isWindows;

/// Runs commands with dart:io (desktop).
class IoProcessRunner implements ProcessRunner {
  const IoProcessRunner();

  static const _decoder = Utf8Decoder(allowMalformed: true);

  @override
  Future<ProcessOutput> run(
    String executable,
    List<String> arguments, {
    Duration timeout = ProcessRunner.defaultTimeout,
  }) async {
    final command = describeCommand(executable, arguments);
    final Process process;
    try {
      process = await Process.start(executable, arguments);
    } on ProcessException catch (e) {
      throw ProcessRunException(command, 'could not start: ${e.message}');
    }
    final stdout = process.stdout.transform(_decoder).join();
    final stderr = process.stderr.transform(_decoder).join();
    final int exitCode;
    try {
      exitCode = await process.exitCode.timeout(timeout);
    } on TimeoutException {
      process.kill();
      throw ProcessRunException(
        command,
        'did not finish within ${timeout.inSeconds} seconds',
      );
    }
    return ProcessOutput(
      exitCode: exitCode,
      stdout: await stdout,
      stderr: await stderr,
    );
  }

  @override
  Future<RunningProcess> start(String executable, List<String> arguments) async {
    try {
      return _IoRunningProcess(await Process.start(executable, arguments));
    } on ProcessException catch (e) {
      throw ProcessRunException(
        describeCommand(executable, arguments),
        'could not start: ${e.message}',
      );
    }
  }
}

class _IoRunningProcess implements RunningProcess {
  _IoRunningProcess(this._process) {
    // An unread stderr pipe can fill up and block the process.
    unawaited(_process.stderr.drain<void>());
  }

  final Process _process;

  @override
  Stream<List<int>> get stdout => _process.stdout;

  @override
  Future<int> get exitCode => _process.exitCode;

  @override
  void kill() => _process.kill();
}
```

`lib/features/devices/data/process_runner_stub.dart`:
```dart
import 'package:fcm_studio/features/devices/data/process_runner.dart';

ProcessRunner createProcessRunner() => const UnsupportedProcessRunner();

Map<String, String> platformEnvironment() => const {};

bool platformIsWindows() => false;

/// Web: browsers can't start programs, so the device features are hidden there (spec §3.1).
class UnsupportedProcessRunner implements ProcessRunner {
  const UnsupportedProcessRunner();

  @override
  Future<ProcessOutput> run(
    String executable,
    List<String> arguments, {
    Duration timeout = ProcessRunner.defaultTimeout,
  }) async {
    throw UnsupportedError('Running programs is not available on the web.');
  }

  @override
  Future<RunningProcess> start(String executable, List<String> arguments) async {
    throw UnsupportedError('Running programs is not available on the web.');
  }
}
```

`lib/features/devices/data/process_runner_platform.dart`:
```dart
export 'package:fcm_studio/features/devices/data/process_runner_io.dart'
    if (dart.library.js_interop) 'package:fcm_studio/features/devices/data/process_runner_stub.dart';
```

`test/helpers/fake_process_runner.dart`:
```dart
import 'dart:async';
import 'dart:convert';

import 'package:fcm_studio/features/devices/data/process_runner.dart';

ProcessOutput ok(String stdout) => ProcessOutput(exitCode: 0, stdout: stdout);

/// Answers commands from a script. A command is the executable and its
/// arguments joined by spaces. Unscripted commands fail like a missing program.
class FakeProcessRunner implements ProcessRunner {
  final List<List<String>> calls = [];
  final Map<String, Object> _answers = {};
  final Map<String, FakeRunningProcess Function()> _starts = {};

  List<String> get commands => [for (final call in calls) call.join(' ')];

  /// [answer] is a [ProcessOutput], a `List<ProcessOutput>` (one per call;
  /// the last one repeats) or an [Exception] to throw.
  void on(String command, Object answer) => _answers[command] = answer;

  void onStart(String command, FakeRunningProcess Function() create) =>
      _starts[command] = create;

  @override
  Future<ProcessOutput> run(
    String executable,
    List<String> arguments, {
    Duration timeout = ProcessRunner.defaultTimeout,
  }) async {
    calls.add([executable, ...arguments]);
    final command = describeCommand(executable, arguments);
    switch (_answers[command]) {
      case final ProcessOutput output:
        return output;
      case final List<ProcessOutput> outputs:
        return outputs.length > 1 ? outputs.removeAt(0) : outputs.single;
      case final Exception error:
        throw error;
      default:
        throw ProcessRunException(command, 'could not start: not scripted');
    }
  }

  @override
  Future<RunningProcess> start(String executable, List<String> arguments) async {
    calls.add([executable, ...arguments]);
    final command = describeCommand(executable, arguments);
    final create = _starts[command];
    if (create == null) {
      throw ProcessRunException(command, 'could not start: not scripted');
    }
    return create();
  }
}

/// A long-running process whose output the test writes.
class FakeRunningProcess implements RunningProcess {
  final StreamController<List<int>> _stdout = StreamController<List<int>>();
  final Completer<int> _exit = Completer<int>();
  bool killed = false;

  void emit(String text) => _stdout.add(utf8.encode(text));

  void exit([int code = 0]) {
    if (!_exit.isCompleted) {
      _exit.complete(code);
      unawaited(_stdout.close());
    }
  }

  @override
  Stream<List<int>> get stdout => _stdout.stream;

  @override
  Future<int> get exitCode => _exit.future;

  @override
  void kill() {
    killed = true;
    exit(-9);
  }
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `flutter test test/features/devices/process_runner_test.dart test/features/devices/fake_process_runner_test.dart`
Expected: PASS (5 + 3 tests). Then run `flutter analyze` (No issues found!) and `flutter build web` (succeeds, which proves the stub keeps dart:io out of the web build).

- [ ] **Step 5: Commit**

```bash
dart format lib test
git add lib/features/devices/data/process_runner*.dart test/helpers/fake_process_runner.dart test/features/devices/process_runner_test.dart test/features/devices/fake_process_runner_test.dart
git commit -m "feat: run external commands through an injectable process runner"
```

---

### Task 3: adb output parsers

Pure functions for what adb prints, with real output from the Redmi as test data (captured 2026-10-04).

**Files:**
- Create: `lib/features/devices/domain/adb_device.dart`, `lib/features/devices/data/parsers/device_list_parser.dart`, `lib/features/devices/data/parsers/track_devices_decoder.dart`, `lib/features/devices/data/parsers/package_list_parser.dart`, `lib/features/devices/data/parsers/run_as_outcome.dart`, `lib/features/devices/data/parsers/fcm_token_pattern.dart`
- Test: `test/features/devices/adb_parsers_test.dart`

**Interfaces:**
- Consumes: `ProcessOutput` (Task 2).
- Produces:
  - `enum DeviceState { device, unauthorized, offline, other }`.
  - `class AdbDevice({required String serial, required DeviceState state, String rawState = '', String? model, String? product, String? transportId})` with `isReady`.
  - `class DeviceDetails({required String name, String brand = '', String androidVersion = ''})`.
  - `List<AdbDevice> parseDeviceList(String text)`.
  - `class TrackDevicesDecoder extends StreamTransformerBase<List<int>, List<AdbDevice>>` (const).
  - `List<String> parsePackageList(String text)` (sorted).
  - `enum RunAsOutcome { file, notDebuggable, noSuchFile, unknownPackage, error }` and `RunAsOutcome classifyRunAs(ProcessOutput output)`.
  - `abstract final class FcmTokenPattern` with `RegExp inText`, `String? firstIn(String text)` and `bool looksLikeToken(String value)`.

- [ ] **Step 1: Write the failing tests** `test/features/devices/adb_parsers_test.dart`

```dart
import 'dart:async';
import 'dart:convert';

import 'package:fcm_studio/features/devices/data/parsers/device_list_parser.dart';
import 'package:fcm_studio/features/devices/data/parsers/fcm_token_pattern.dart';
import 'package:fcm_studio/features/devices/data/parsers/package_list_parser.dart';
import 'package:fcm_studio/features/devices/data/parsers/run_as_outcome.dart';
import 'package:fcm_studio/features/devices/data/parsers/track_devices_decoder.dart';
import 'package:fcm_studio/features/devices/data/process_runner.dart';
import 'package:fcm_studio/features/devices/domain/adb_device.dart';
import 'package:flutter_test/flutter_test.dart';

// Printed by the Redmi 14C (Android 16) on 2026-10-04.
const redmiLine =
    'DETWFUOZZHZ5SWFQ       device usb:34603008X product:pond_global '
    'model:2409BRN2CA device:pond transport_id:1\n';

String frame(String payload) =>
    '${utf8.encode(payload).length.toRadixString(16).padLeft(4, '0')}$payload';

Future<List<List<AdbDevice>>> decode(List<String> chunks) => Stream.fromIterable(
  [for (final chunk in chunks) utf8.encode(chunk)],
).transform(const TrackDevicesDecoder()).toList();

void main() {
  group('device list', () {
    test('parses adb devices -l, skipping the header and daemon lines', () {
      final devices = parseDeviceList(
        '* daemon not running; starting now at tcp:5037\n'
        '* daemon started successfully\n'
        'List of devices attached\n'
        '$redmiLine'
        'R58M123ABC             unauthorized usb:336855040X transport_id:3\n'
        'emulator-5554          offline transport_id:4\n'
        '\n',
      );
      expect(devices, [
        const AdbDevice(
          serial: 'DETWFUOZZHZ5SWFQ',
          state: DeviceState.device,
          rawState: 'device',
          model: '2409BRN2CA',
          product: 'pond_global',
          transportId: '1',
        ),
        const AdbDevice(
          serial: 'R58M123ABC',
          state: DeviceState.unauthorized,
          rawState: 'unauthorized',
          transportId: '3',
        ),
        const AdbDevice(
          serial: 'emulator-5554',
          state: DeviceState.offline,
          rawState: 'offline',
          transportId: '4',
        ),
      ]);
      expect(devices.first.isReady, isTrue);
      expect(devices[1].isReady, isFalse);
    });

    test('keeps unknown states as "other"', () {
      final device = parseDeviceList('ABC123 recovery transport_id:9\n').single;
      expect(device.state, DeviceState.other);
      expect(device.rawState, 'recovery');
    });
  });

  group('track-devices framing', () {
    test('the real Redmi message is 0x6c bytes long', () {
      expect(utf8.encode(redmiLine).length, 0x6c);
    });

    test('decodes one message per device list, including an empty one', () async {
      final lists = await decode(['${frame(redmiLine)}${frame('')}']);
      expect(lists, hasLength(2));
      expect(lists.first.single.serial, 'DETWFUOZZHZ5SWFQ');
      expect(lists.last, isEmpty);
    });

    test('a message split across chunks is joined', () async {
      final message = frame(redmiLine);
      final lists = await decode([
        message.substring(0, 2),
        message.substring(2, 40),
        message.substring(40),
      ]);
      expect(lists.single.single.model, '2409BRN2CA');
    });

    test('data that is not a length prefix is an error', () async {
      await expectLater(decode(['zzzzhello']), throwsFormatException);
    });
  });

  test('pm list packages -3 becomes a sorted list of names', () {
    expect(
      parsePackageList(
        'package:com.syldel.delivery\n'
        'package:com.alpha.app\n'
        '\n'
        'WARNING: something\n'
        'package:com.zeta.app\n',
      ),
      ['com.alpha.app', 'com.syldel.delivery', 'com.zeta.app'],
    );
  });

  group('run-as output', () {
    ProcessOutput out(String text, {int exitCode = 0}) =>
        ProcessOutput(exitCode: exitCode, stdout: text);

    test('the token file', () {
      expect(
        classifyRunAs(out("<?xml version='1.0' ?>\n<map>\n</map>\n")),
        RunAsOutcome.file,
      );
    });

    test('a release build', () {
      expect(
        classifyRunAs(
          out('run-as: package not debuggable: com.syldel.delivery', exitCode: 1),
        ),
        RunAsOutcome.notDebuggable,
      );
    });

    test('no token file yet', () {
      expect(
        classifyRunAs(
          out(
            'cat: shared_prefs/com.google.android.gms.appid.xml: No such file or directory',
            exitCode: 1,
          ),
        ),
        RunAsOutcome.noSuchFile,
      );
    });

    test('a package that is not installed, in both wordings', () {
      expect(
        classifyRunAs(out('run-as: unknown package: com.does.not.exist', exitCode: 1)),
        RunAsOutcome.unknownPackage,
      );
      expect(
        classifyRunAs(out("Package 'com.does.not.exist' is unknown", exitCode: 1)),
        RunAsOutcome.unknownPackage,
      );
    });

    test('anything else is an error', () {
      expect(
        classifyRunAs(const ProcessOutput(exitCode: 1, stderr: 'error: device offline')),
        RunAsOutcome.error,
      );
    });
  });

  group('FCM token pattern', () {
    final token = 'fakeInstanceId0000000:APA91b${'a' * 60}';

    test('finds a token inside a log line', () {
      expect(
        FcmTokenPattern.firstIn('10-04 12:00:01 I/flutter: FCM token: $token'),
        token,
      );
    });

    test('ignores text that only resembles a token', () {
      expect(FcmTokenPattern.firstIn('short:APA91babc'), isNull);
    });

    test('recognises a whole token, current or legacy', () {
      expect(FcmTokenPattern.looksLikeToken(token), isTrue);
      expect(FcmTokenPattern.looksLikeToken('APA91b${'b' * 120}'), isTrue);
      expect(FcmTokenPattern.looksLikeToken('hello'), isFalse);
    });
  });
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `flutter test test/features/devices/adb_parsers_test.dart`
Expected: FAIL, compilation errors.

- [ ] **Step 3: Implement**

`lib/features/devices/domain/adb_device.dart`:
```dart
import 'package:equatable/equatable.dart';

/// The states spec §9.2 shows; anything else is [other].
enum DeviceState { device, unauthorized, offline, other }

/// One line of `adb devices -l`.
class AdbDevice extends Equatable {
  const AdbDevice({
    required this.serial,
    required this.state,
    this.rawState = '',
    this.model,
    this.product,
    this.transportId,
  });

  final String serial;
  final DeviceState state;

  /// The state as adb printed it, e.g. `recovery` for [DeviceState.other].
  final String rawState;
  final String? model;
  final String? product;
  final String? transportId;

  /// Only a device in the `device` state accepts commands.
  bool get isReady => state == DeviceState.device;

  @override
  List<Object?> get props => [serial, state, rawState, model, product, transportId];
}

/// What `getprop` says about a device (spec §9.2).
class DeviceDetails extends Equatable {
  const DeviceDetails({
    required this.name,
    this.brand = '',
    this.androidVersion = '',
  });

  /// `ro.product.marketname`, falling back to `ro.product.model`.
  final String name;
  final String brand;
  final String androidVersion;

  @override
  List<Object?> get props => [name, brand, androidVersion];
}
```

`lib/features/devices/data/parsers/device_list_parser.dart`:
```dart
import 'dart:convert';

import 'package:fcm_studio/features/devices/domain/adb_device.dart';

/// Parses a device list as `adb devices -l` and `adb track-devices -l` print
/// it: one device per line, `<serial> <state> key:value…`.
List<AdbDevice> parseDeviceList(String text) {
  final devices = <AdbDevice>[];
  for (final line in const LineSplitter().convert(text)) {
    final trimmed = line.trim();
    if (trimmed.startsWith('*') || trimmed.startsWith('List of devices')) {
      continue;
    }
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length < 2) {
      continue;
    }
    final fields = <String, String>{
      for (final part in parts.skip(2))
        if (part.contains(':'))
          part.substring(0, part.indexOf(':')): part.substring(part.indexOf(':') + 1),
    };
    devices.add(
      AdbDevice(
        serial: parts[0],
        state: _state(parts[1]),
        rawState: parts[1],
        model: fields['model'],
        product: fields['product'],
        transportId: fields['transport_id'],
      ),
    );
  }
  return devices;
}

DeviceState _state(String raw) => switch (raw) {
  'device' => DeviceState.device,
  'unauthorized' => DeviceState.unauthorized,
  'offline' => DeviceState.offline,
  _ => DeviceState.other,
};
```

`lib/features/devices/data/parsers/track_devices_decoder.dart`:
```dart
import 'dart:async';
import 'dart:convert';

import 'package:fcm_studio/features/devices/data/parsers/device_list_parser.dart';
import 'package:fcm_studio/features/devices/domain/adb_device.dart';

/// Splits `adb track-devices -l` output into device lists. Each message is a
/// 4-hex-digit length followed by that many bytes of device list (spec §9.2).
/// A message may arrive in several chunks, and a chunk may hold several.
class TrackDevicesDecoder
    extends StreamTransformerBase<List<int>, List<AdbDevice>> {
  const TrackDevicesDecoder();

  @override
  Stream<List<AdbDevice>> bind(Stream<List<int>> stream) async* {
    final buffer = <int>[];
    await for (final chunk in stream) {
      buffer.addAll(chunk);
      while (buffer.length >= 4) {
        final length = int.tryParse(
          ascii.decode(buffer.sublist(0, 4), allowInvalid: true),
          radix: 16,
        );
        if (length == null) {
          throw const FormatException(
            'adb track-devices sent data without a length prefix.',
          );
        }
        if (buffer.length < 4 + length) {
          break;
        }
        final payload = utf8.decode(
          buffer.sublist(4, 4 + length),
          allowMalformed: true,
        );
        buffer.removeRange(0, 4 + length);
        yield parseDeviceList(payload);
      }
    }
  }
}
```

`lib/features/devices/data/parsers/package_list_parser.dart`:
```dart
import 'dart:convert';

/// Parses `pm list packages -3`: one `package:<name>` per line. Sorted.
List<String> parsePackageList(String text) => [
  for (final line in const LineSplitter().convert(text))
    if (line.trim().startsWith('package:'))
      line.trim().substring('package:'.length),
]..sort();
```

`lib/features/devices/data/parsers/run_as_outcome.dart`:
```dart
import 'package:fcm_studio/features/devices/data/process_runner.dart';

/// What `run-as <package> cat <token file>` reported (spec §9.3; messages
/// confirmed on the Redmi 14C, Android 16).
enum RunAsOutcome { file, notDebuggable, noSuchFile, unknownPackage, error }

final RegExp _olderUnknownPackage = RegExp(r"Package '[^']*' is unknown");

RunAsOutcome classifyRunAs(ProcessOutput output) {
  if (output.exitCode == 0 && output.stdout.contains('<map')) {
    return RunAsOutcome.file;
  }
  final text = output.combined;
  if (text.contains('package not debuggable')) {
    return RunAsOutcome.notDebuggable;
  }
  if (text.contains('unknown package') || _olderUnknownPackage.hasMatch(text)) {
    return RunAsOutcome.unknownPackage;
  }
  if (text.contains('No such file or directory')) {
    return RunAsOutcome.noSuchFile;
  }
  return RunAsOutcome.error;
}
```

`lib/features/devices/data/parsers/fcm_token_pattern.dart`:
```dart
/// How an FCM registration token looks (spec §9.3).
abstract final class FcmTokenPattern {
  /// A token inside other text, e.g. a log line.
  static final RegExp inText = RegExp(
    r'[A-Za-z0-9_-]{20,}:APA91b[A-Za-z0-9_-]{50,}',
  );

  /// A whole token: the current format, or the older one without an instance ID.
  static final RegExp _whole = RegExp(
    r'^(?:[A-Za-z0-9_-]{20,}:APA91b[A-Za-z0-9_-]{50,}|APA91b[A-Za-z0-9_-]{100,})$',
  );

  static String? firstIn(String text) => inText.firstMatch(text)?.group(0);

  static bool looksLikeToken(String value) => _whole.hasMatch(value.trim());
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `flutter test test/features/devices/adb_parsers_test.dart`
Expected: PASS. Then `flutter analyze` (No issues found!).

- [ ] **Step 5: Commit**

```bash
dart format lib test
git add lib/features/devices/domain/adb_device.dart lib/features/devices/data/parsers test/features/devices/adb_parsers_test.dart
git commit -m "feat: parse adb device lists, track-devices framing, packages and run-as output"
```

---


### Task 4: The token file parser and the device-token model

**Files:**
- Create: `lib/features/devices/data/parsers/app_id_prefs_parser.dart`, `lib/features/devices/domain/device_token.dart`, `test/helpers/device_fixtures.dart`
- Test: `test/features/devices/app_id_prefs_parser_test.dart`, `test/features/devices/device_token_test.dart`

**Interfaces:**
- Consumes: `FcmTokenPattern` (Task 3); the fixture `test/fixtures/adb/appid_prefs_debug.xml` (Task 1).
- Produces:
  - `class FoundToken({required String token, String? senderId})`.
  - `enum TokenReadMethod { runAs, logcat }`.
  - `class DeviceToken({required token, required TokenReadMethod method, required DateTime readAt, required String serial, required String package, required String deviceName, String? senderId})` with `isDebugBuild` and `label` → `'<deviceName> · <package> (debug|release)'`.
  - `abstract final class AppIdPrefsParser` with `static List<FoundToken> parse(String xml)`: one token per sender ID, sorted by sender ID.
  - Test helpers: `final fakeDeviceToken` (the exact token Task 1's capture writes), `final otherDeviceToken`, `const redmiSerial = 'DETWFUOZZHZ5SWFQ'`, `const redmiTrackLine` (the real `track-devices` line), `String trackFrame(String payload)`, `String appIdPrefsXml(Map<String, String> tokensBySender)`.

- [ ] **Step 1: Add the test fixtures** `test/helpers/device_fixtures.dart`

```dart
import 'dart:convert';

/// The token Task 1's capture writes in place of every real token.
final fakeDeviceToken =
    'fakeInstanceId0000000:APA91bFAKE_TOKEN_FOR_TESTS_ONLY_${'a' * 49}';

final otherDeviceToken =
    'otherInstanceId000000:APA91bOTHER_TOKEN_FOR_TESTS_ONLY_${'b' * 49}';

const redmiSerial = 'DETWFUOZZHZ5SWFQ';

/// What `adb track-devices -l` printed for the Redmi 14C on 2026-10-04.
const redmiTrackLine =
    'DETWFUOZZHZ5SWFQ       device usb:34603008X product:pond_global '
    'model:2409BRN2CA device:pond transport_id:1\n';

/// One `track-devices` message: a 4-hex-digit byte length, then the payload.
String trackFrame(String payload) =>
    '${utf8.encode(payload).length.toRadixString(16).padLeft(4, '0')}$payload';

/// A token file in the current SDK's format (spec §9.3).
String appIdPrefsXml(Map<String, String> tokensBySender) =>
    "<?xml version='1.0' encoding='utf-8' standalone='yes' ?>\n"
    '<map>\n'
    '    <string name="|S||P|">REDACTED_LONG_VALUE</string>\n'
    '    <string name="|S|id">REDACTED_FID</string>\n'
    '${[for (final entry in tokensBySender.entries) '    <string name="[DEFAULT]|T|${entry.key}|*">{&quot;token&quot;:&quot;${entry.value}&quot;,&quot;appVersion&quot;:&quot;1&quot;,&quot;timestamp&quot;:1759550000000}</string>\n'].join()}'
    '    <string name="|S|cre">1759550000</string>\n'
    '</map>\n';
```

- [ ] **Step 2: Write the failing tests**

`test/features/devices/app_id_prefs_parser_test.dart`:
```dart
import 'dart:io';

import 'package:fcm_studio/features/devices/data/parsers/app_id_prefs_parser.dart';
import 'package:fcm_studio/features/devices/domain/device_token.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/device_fixtures.dart';

void main() {
  test('reads the token from the current JSON format', () {
    expect(
      AppIdPrefsParser.parse(appIdPrefsXml({'123456789012': fakeDeviceToken})),
      [FoundToken(token: fakeDeviceToken, senderId: '123456789012')],
    );
  });

  test('lists one token per sender ID, sorted by sender ID', () {
    final tokens = AppIdPrefsParser.parse(
      appIdPrefsXml({'999000999000': otherDeviceToken, '123456789012': fakeDeviceToken}),
    );
    expect(tokens.map((t) => t.senderId), ['123456789012', '999000999000']);
    expect(tokens.last.token, otherDeviceToken);
  });

  test('accepts the older raw-token format and ignores timestamp keys', () {
    final legacy = 'APA91b${'c' * 120}';
    final tokens = AppIdPrefsParser.parse(
      '<map>\n'
      '    <string name="|T|987654321098|*">$legacy</string>\n'
      '    <string name="|T-timestamp|987654321098|*">1600000000000</string>\n'
      '</map>\n',
    );
    expect(tokens, [FoundToken(token: legacy, senderId: '987654321098')]);
  });

  test('skips entries that are not tokens', () {
    expect(
      AppIdPrefsParser.parse(
        '<map>\n'
        '    <string name="[DEFAULT]|T|111|*">{&quot;token&quot;:&quot;nope&quot;}</string>\n'
        '    <string name="[DEFAULT]|T|222|*">{not json</string>\n'
        '    <string name="|S|id">REDACTED_FID</string>\n'
        '</map>\n',
      ),
      isEmpty,
    );
    expect(AppIdPrefsParser.parse(''), isEmpty);
  });

  test('reads the real file captured from the Redmi', () {
    final tokens = AppIdPrefsParser.parse(
      File('test/fixtures/adb/appid_prefs_debug.xml').readAsStringSync(),
    );
    expect(tokens, isNotEmpty);
    for (final token in tokens) {
      expect(token.token, fakeDeviceToken);
      expect(token.senderId, matches(RegExp(r'^\d+$')));
    }
  });
}
```

`test/features/devices/device_token_test.dart`:
```dart
import 'package:fcm_studio/features/devices/domain/device_token.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/device_fixtures.dart';

void main() {
  DeviceToken token(TokenReadMethod method) => DeviceToken(
    token: fakeDeviceToken,
    senderId: '123456789012',
    method: method,
    readAt: DateTime.utc(2026, 10, 4),
    serial: redmiSerial,
    package: 'com.syldel.delivery',
    deviceName: 'Redmi 14C',
  );

  test('the label names the phone, the app and the build type (spec §7.1)', () {
    expect(
      token(TokenReadMethod.runAs).label,
      'Redmi 14C · com.syldel.delivery (debug)',
    );
    expect(
      token(TokenReadMethod.logcat).label,
      'Redmi 14C · com.syldel.delivery (release)',
    );
  });
}
```

- [ ] **Step 3: Run them to see them fail**

Run: `flutter test test/features/devices/app_id_prefs_parser_test.dart test/features/devices/device_token_test.dart`
Expected: FAIL, compilation errors.

- [ ] **Step 4: Implement**

`lib/features/devices/domain/device_token.dart`:
```dart
import 'package:equatable/equatable.dart';

/// A token found on a phone, for one sender (Firebase project number).
class FoundToken extends Equatable {
  const FoundToken({required this.token, this.senderId});

  final String token;

  /// Unknown when the token came from logcat.
  final String? senderId;

  @override
  List<Object?> get props => [token, senderId];
}

/// How a token was read (spec §9.3): `run-as` works for debug builds,
/// logcat for release builds that log their token.
enum TokenReadMethod { runAs, logcat }

/// A token read from a phone, ready to become a target (spec §9.3 "Result").
class DeviceToken extends Equatable {
  const DeviceToken({
    required this.token,
    required this.method,
    required this.readAt,
    required this.serial,
    required this.package,
    required this.deviceName,
    this.senderId,
  });

  final String token;
  final String? senderId;
  final TokenReadMethod method;
  final DateTime readAt;
  final String serial;
  final String package;

  /// The phone's market name, model or serial.
  final String deviceName;

  bool get isDebugBuild => method == TokenReadMethod.runAs;

  /// The saved-target label (spec §7.1).
  String get label =>
      '$deviceName · $package (${isDebugBuild ? 'debug' : 'release'})';

  @override
  List<Object?> get props => [
    token,
    senderId,
    method,
    readAt,
    serial,
    package,
    deviceName,
  ];
}
```

`lib/features/devices/data/parsers/app_id_prefs_parser.dart`:
```dart
import 'dart:convert';

import 'package:fcm_studio/features/devices/data/parsers/fcm_token_pattern.dart';
import 'package:fcm_studio/features/devices/domain/device_token.dart';

/// Reads FCM tokens from `shared_prefs/com.google.android.gms.appid.xml`
/// (spec §9.3). A token key is `<anything>|T|<sender id>|<scope>`. Current
/// SDKs store JSON `{"token", "appVersion", "timestamp"}`; older ones store
/// the raw token.
abstract final class AppIdPrefsParser {
  static final RegExp _entry = RegExp(
    r'<string name="([^"]*)">([\s\S]*?)</string>',
  );
  static final RegExp _tokenKey = RegExp(r'^(.*)\|T\|(\d+)\|(.*)$');
  static final RegExp _entity = RegExp(
    r'&(#x[0-9a-fA-F]+|#\d+|quot|amp|lt|gt|apos);',
  );

  /// One token per sender ID, sorted by sender ID.
  static List<FoundToken> parse(String xml) {
    final bySender = <String, String>{};
    for (final match in _entry.allMatches(xml)) {
      final key = _tokenKey.firstMatch(_unescape(match.group(1)!));
      if (key == null) {
        continue;
      }
      final token = _tokenFrom(_unescape(match.group(2)!));
      if (token != null) {
        bySender[key.group(2)!] = token;
      }
    }
    final senders = bySender.keys.toList()..sort();
    return [
      for (final sender in senders)
        FoundToken(token: bySender[sender]!, senderId: sender),
    ];
  }

  static String? _tokenFrom(String value) {
    final trimmed = value.trim();
    if (!trimmed.startsWith('{')) {
      return FcmTokenPattern.looksLikeToken(trimmed) ? trimmed : null;
    }
    try {
      final json = jsonDecode(trimmed);
      final token = json is Map<String, Object?> ? json['token'] : null;
      return token is String && FcmTokenPattern.looksLikeToken(token)
          ? token
          : null;
    } on FormatException {
      return null;
    }
  }

  static String _unescape(String text) => text.replaceAllMapped(_entity, (m) {
    final entity = m.group(1)!;
    return switch (entity) {
      'quot' => '"',
      'amp' => '&',
      'lt' => '<',
      'gt' => '>',
      'apos' => "'",
      _ when entity.startsWith('#x') => String.fromCharCode(
        int.parse(entity.substring(2), radix: 16),
      ),
      _ => String.fromCharCode(int.parse(entity.substring(1))),
    };
  });
}
```

If the real fixture from Task 1 has a shape this parser doesn't accept (Task 1 Step 4 recorded the shape in the spec), change the parser to accept it. Keep the synthetic tests passing, and say what changed in your report.

- [ ] **Step 5: Run the tests and confirm they pass**

Run: `flutter test test/features/devices/app_id_prefs_parser_test.dart test/features/devices/device_token_test.dart`
Expected: PASS (5 + 1 tests). Then `flutter analyze` (No issues found!).

- [ ] **Step 6: Commit**

```bash
dart format lib test
git add lib/features/devices/data/parsers/app_id_prefs_parser.dart lib/features/devices/domain/device_token.dart test/helpers/device_fixtures.dart test/features/devices/app_id_prefs_parser_test.dart test/features/devices/device_token_test.dart
git commit -m "feat: read FCM tokens from the app's token file"
```

---

### Task 5: Find adb, remember the user's path, and `AdbSetupCubit`

**Files:**
- Create: `lib/features/devices/data/adb_locator.dart`, `lib/features/settings/data/settings_repository.dart`, `lib/features/settings/cubit/adb_setup_state.dart`, `lib/features/settings/cubit/adb_setup_cubit.dart`
- Test: `test/features/devices/adb_locator_test.dart`, `test/features/settings/settings_repository_test.dart`, `test/features/settings/adb_setup_cubit_test.dart`

**Interfaces:**
- Consumes: `ProcessRunner`, `ProcessRunException` (Task 2); `FakeProcessRunner`, `ok` (test helper); `AppDatabase` (existing).
- Produces:
  - `enum AdbSource { settings, androidHome, androidSdkRoot, sdkDefault, homebrew, usrLocal, path }`.
  - `class AdbLocation({required String path, required AdbSource source, required String version})`.
  - `class AdbSearch({AdbLocation? found, List<String> tried = const []})`.
  - `class AdbLocator({required ProcessRunner runner, required Map<String, String> environment, required bool isWindows})` with `Future<AdbSearch> locate({String? userPath})`.
  - `class SettingsRepository({required AppDatabase database})` with `Future<String?> readAdbPath()` and `Future<void> writeAdbPath(String? path)` (null or blank clears it).
  - `enum AdbStatus { unknown, locating, found, notFound }`, `class AdbSetupState` with `status`, `location`, `userPath`, `tried`, `adbPath` and `userPathFailed`.
  - `class AdbSetupCubit({required AdbLocator locator, required SettingsRepository settings})` with `Future<void> locate()` and `Future<void> setUserPath(String? path)`.

- [ ] **Step 1: Write the failing tests**

`test/features/devices/adb_locator_test.dart`:
```dart
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
  }) => AdbLocator(runner: runner, environment: environment, isWindows: windows);

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

  test('tries ANDROID_HOME, ANDROID_SDK_ROOT, the default SDK, then Homebrew', () async {
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
  });

  test('falls back to looking adb up on PATH', () async {
    runner
      ..on('which adb', ok('/custom/bin/adb\n'))
      ..on('/custom/bin/adb version', ok(adbVersion));
    final search = await locator().locate();
    expect(search.found?.path, '/custom/bin/adb');
    expect(search.found?.source, AdbSource.path);
  });

  test('on Windows uses LOCALAPPDATA and adb.exe, and never Homebrew', () async {
    const sdkAdb = r'C:\Users\me\AppData\Local\Android\Sdk\platform-tools\adb.exe';
    runner.on('$sdkAdb version', ok(adbVersion));
    final search = await locator(
      environment: const {'LOCALAPPDATA': r'C:\Users\me\AppData\Local'},
      windows: true,
    ).locate();
    expect(search.found?.path, sdkAdb);
    expect(search.found?.source, AdbSource.sdkDefault);
    expect(runner.commands.any((c) => c.contains('homebrew')), isFalse);
  });

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
```

`test/features/settings/settings_repository_test.dart`:
```dart
import 'package:fcm_studio/core/storage/app_database.dart';
import 'package:fcm_studio/features/settings/data/settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;

  setUp(() async => database = await AppDatabase.inMemory());
  tearDown(() => database.close());

  test('stores, reads and clears the adb path', () async {
    final settings = SettingsRepository(database: database);
    expect(await settings.readAdbPath(), isNull);
    await settings.writeAdbPath('  /custom/adb  ');
    expect(await settings.readAdbPath(), '/custom/adb');
    await settings.writeAdbPath(' ');
    expect(await settings.readAdbPath(), isNull);
    await settings.writeAdbPath('/custom/adb');
    await settings.writeAdbPath(null);
    expect(await settings.readAdbPath(), isNull);
  });
}
```

`test/features/settings/adb_setup_cubit_test.dart`:
```dart
import 'package:fcm_studio/core/storage/app_database.dart';
import 'package:fcm_studio/features/devices/data/adb_locator.dart';
import 'package:fcm_studio/features/settings/cubit/adb_setup_cubit.dart';
import 'package:fcm_studio/features/settings/data/settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_process_runner.dart';

const adbVersion = 'Android Debug Bridge version 1.0.41\n';

void main() {
  late AppDatabase database;
  late FakeProcessRunner runner;
  late SettingsRepository settings;

  setUp(() async {
    database = await AppDatabase.inMemory();
    runner = FakeProcessRunner();
    settings = SettingsRepository(database: database);
  });

  tearDown(() => database.close());

  AdbSetupCubit build() => AdbSetupCubit(
    locator: AdbLocator(
      runner: runner,
      environment: const {'HOME': '/Users/me'},
      isWindows: false,
    ),
    settings: settings,
  );

  test('finds adb at startup', () async {
    runner.on('/opt/homebrew/bin/adb version', ok(adbVersion));
    final cubit = build();
    await cubit.locate();
    expect(cubit.state.status, AdbStatus.found);
    expect(cubit.state.adbPath, '/opt/homebrew/bin/adb');
    expect(cubit.state.userPathFailed, isFalse);
  });

  test('says where it looked when adb is not found', () async {
    final cubit = build();
    await cubit.locate();
    expect(cubit.state.status, AdbStatus.notFound);
    expect(cubit.state.adbPath, isNull);
    expect(cubit.state.tried, contains('/opt/homebrew/bin/adb'));
  });

  test('a path set by the user is stored and used first', () async {
    runner
      ..on('/opt/homebrew/bin/adb version', ok(adbVersion))
      ..on('/custom/adb version', ok(adbVersion));
    final cubit = build();
    await cubit.setUserPath('/custom/adb');
    expect(cubit.state.adbPath, '/custom/adb');
    expect(cubit.state.location?.source, AdbSource.settings);
    expect(await settings.readAdbPath(), '/custom/adb');

    await cubit.setUserPath(null);
    expect(cubit.state.adbPath, '/opt/homebrew/bin/adb');
    expect(cubit.state.userPath, isNull);
  });

  test('a user path that does not run adb is flagged', () async {
    runner.on('/opt/homebrew/bin/adb version', ok(adbVersion));
    final cubit = build();
    await cubit.setUserPath('/wrong/adb');
    expect(cubit.state.adbPath, '/opt/homebrew/bin/adb');
    expect(cubit.state.userPathFailed, isTrue);
  });
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `flutter test test/features/devices/adb_locator_test.dart test/features/settings`
Expected: FAIL, compilation errors.

- [ ] **Step 3: Implement**

`lib/features/devices/data/adb_locator.dart`:
```dart
import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:fcm_studio/features/devices/data/process_runner.dart';
import 'package:path/path.dart' as p;

/// Where adb was found (spec §9.1).
enum AdbSource {
  settings,
  androidHome,
  androidSdkRoot,
  sdkDefault,
  homebrew,
  usrLocal,
  path,
}

class AdbLocation extends Equatable {
  const AdbLocation({
    required this.path,
    required this.source,
    required this.version,
  });

  final String path;
  final AdbSource source;

  /// The first line of `adb version`, e.g. "Android Debug Bridge version 1.0.41".
  final String version;

  @override
  List<Object?> get props => [path, source, version];
}

class AdbSearch extends Equatable {
  const AdbSearch({this.found, this.tried = const []});

  final AdbLocation? found;

  /// Every path tried, in order, for the "not found" message.
  final List<String> tried;

  @override
  List<Object?> get props => [found, tried];
}

/// Finds a working adb (spec §9.1). Apps started from Finder don't get the
/// shell's PATH, so known locations come before the PATH lookup.
class AdbLocator {
  AdbLocator({
    required this._runner,
    required this._environment,
    required this._isWindows,
  });

  final ProcessRunner _runner;
  final Map<String, String> _environment;
  final bool _isWindows;

  Future<AdbSearch> locate({String? userPath}) async {
    final tried = <String>[];
    Future<AdbLocation?> attempt(String path, AdbSource source) async {
      if (tried.contains(path)) {
        return null;
      }
      tried.add(path);
      final version = await _version(path);
      return version == null
          ? null
          : AdbLocation(path: path, source: source, version: version);
    }

    for (final (path, source) in _knownLocations(userPath)) {
      final found = await attempt(path, source);
      if (found != null) {
        return AdbSearch(found: found, tried: tried);
      }
    }
    final onPath = await _lookUpOnPath();
    if (onPath != null) {
      final found = await attempt(onPath, AdbSource.path);
      if (found != null) {
        return AdbSearch(found: found, tried: tried);
      }
    }
    return AdbSearch(tried: tried);
  }

  List<(String, AdbSource)> _knownLocations(String? userPath) {
    final context = _isWindows ? p.windows : p.posix;
    final adb = _isWindows ? 'adb.exe' : 'adb';
    String? env(String name) {
      final value = _environment[name];
      return value == null || value.isEmpty ? null : value;
    }

    final androidHome = env('ANDROID_HOME');
    final sdkRoot = env('ANDROID_SDK_ROOT');
    final localAppData = env('LOCALAPPDATA');
    final home = env('HOME');
    return [
      if (userPath != null && userPath.trim().isNotEmpty)
        (userPath.trim(), AdbSource.settings),
      if (androidHome != null)
        (context.join(androidHome, 'platform-tools', adb), AdbSource.androidHome),
      if (sdkRoot != null)
        (context.join(sdkRoot, 'platform-tools', adb), AdbSource.androidSdkRoot),
      if (_isWindows && localAppData != null)
        (
          context.join(localAppData, 'Android', 'Sdk', 'platform-tools', adb),
          AdbSource.sdkDefault,
        ),
      if (!_isWindows && home != null)
        (
          context.join(home, 'Library', 'Android', 'sdk', 'platform-tools', adb),
          AdbSource.sdkDefault,
        ),
      if (!_isWindows) ('/opt/homebrew/bin/adb', AdbSource.homebrew),
      if (!_isWindows) ('/usr/local/bin/adb', AdbSource.usrLocal),
    ];
  }

  Future<String?> _lookUpOnPath() async {
    try {
      final output = await _runner.run(
        _isWindows ? 'where' : 'which',
        const ['adb'],
      );
      if (output.exitCode != 0) {
        return null;
      }
      return const LineSplitter()
          .convert(output.stdout)
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .firstOrNull;
    } on ProcessRunException {
      return null;
    }
  }

  /// The first line of `adb version`, or null when [path] doesn't run adb.
  Future<String?> _version(String path) async {
    try {
      final output = await _runner.run(path, const ['version']);
      if (output.exitCode != 0 ||
          !output.stdout.contains('Android Debug Bridge')) {
        return null;
      }
      return const LineSplitter().convert(output.stdout).first.trim();
    } on ProcessRunException {
      return null;
    }
  }
}
```

`lib/features/settings/data/settings_repository.dart`:
```dart
import 'package:fcm_studio/core/storage/app_database.dart';
import 'package:sembast/sembast.dart';

/// App settings that are not about one feature's data. The same store holds
/// the selected project (ProjectsRepository).
class SettingsRepository {
  SettingsRepository({required AppDatabase database}) : _db = database.db;

  static final _settings = StoreRef<String, String>('settings');
  static const _adbPathKey = 'adbPath';

  final Database _db;

  Future<String?> readAdbPath() => _settings.record(_adbPathKey).get(_db);

  /// Null or blank clears the path, so adb is found automatically again.
  Future<void> writeAdbPath(String? path) async {
    final record = _settings.record(_adbPathKey);
    final trimmed = path?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      await record.delete(_db);
    } else {
      await record.put(_db, trimmed);
    }
  }
}
```

`lib/features/settings/cubit/adb_setup_state.dart`:
```dart
import 'package:equatable/equatable.dart';
import 'package:fcm_studio/features/devices/data/adb_locator.dart';

enum AdbStatus { unknown, locating, found, notFound }

class AdbSetupState extends Equatable {
  const AdbSetupState({
    this.status = AdbStatus.unknown,
    this.location,
    this.userPath,
    this.tried = const [],
  });

  final AdbStatus status;
  final AdbLocation? location;

  /// The path set in Settings, if any.
  final String? userPath;

  /// Every path tried, for the "not found" message.
  final List<String> tried;

  String? get adbPath => location?.path;

  /// True when a path is set in Settings but adb was found elsewhere, or not at all.
  bool get userPathFailed =>
      userPath != null && location?.source != AdbSource.settings;

  AdbSetupState copyWith({AdbStatus? status}) => AdbSetupState(
    status: status ?? this.status,
    location: location,
    userPath: userPath,
    tried: tried,
  );

  @override
  List<Object?> get props => [status, location, userPath, tried];
}
```

`lib/features/settings/cubit/adb_setup_cubit.dart`:
```dart
import 'package:fcm_studio/features/devices/data/adb_locator.dart';
import 'package:fcm_studio/features/settings/cubit/adb_setup_state.dart';
import 'package:fcm_studio/features/settings/data/settings_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

export 'package:fcm_studio/features/settings/cubit/adb_setup_state.dart';

/// Finds adb at startup and when the user changes its path (spec §9.1).
class AdbSetupCubit extends Cubit<AdbSetupState> {
  AdbSetupCubit({required this._locator, required this._settings})
    : super(const AdbSetupState());

  final AdbLocator _locator;
  final SettingsRepository _settings;

  Future<void> locate() async {
    emit(state.copyWith(status: AdbStatus.locating));
    final userPath = await _settings.readAdbPath();
    final search = await _locator.locate(userPath: userPath);
    if (isClosed) {
      return;
    }
    emit(
      AdbSetupState(
        status: search.found == null ? AdbStatus.notFound : AdbStatus.found,
        location: search.found,
        userPath: userPath,
        tried: search.tried,
      ),
    );
  }

  /// Stores the path typed in Settings (null clears it) and looks again.
  Future<void> setUserPath(String? path) async {
    await _settings.writeAdbPath(path);
    await locate();
  }
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `flutter test test/features/devices/adb_locator_test.dart test/features/settings`
Expected: PASS (6 + 1 + 4 tests). Then `flutter analyze` (No issues found!).

- [ ] **Step 5: Commit**

```bash
dart format lib test
git add lib/features/devices/data/adb_locator.dart lib/features/settings test/features/devices/adb_locator_test.dart test/features/settings
git commit -m "feat: find adb in Settings, the SDK, Homebrew or PATH"
```

---

### Task 6: `AdbService`: device list, details, packages and both ways of reading a token

**Files:**
- Create: `lib/features/devices/domain/token_read_results.dart`, `lib/features/devices/data/adb_service.dart`
- Test: `test/features/devices/adb_service_test.dart`

**Interfaces:**
- Consumes: `ProcessRunner`, `RunningProcess`, `ProcessOutput`, `ProcessRunException`, `describeCommand` (Task 2); `TrackDevicesDecoder`, `parsePackageList`, `classifyRunAs`, `RunAsOutcome`, `FcmTokenPattern`, `AdbDevice`, `DeviceDetails` (Task 3); `AppIdPrefsParser`, `FoundToken` (Task 4); test helpers `FakeProcessRunner`, `FakeRunningProcess`, `ok`, `fakeDeviceToken`, `appIdPrefsXml`, `trackFrame`, `redmiTrackLine`, `redmiSerial`.
- Produces:
  - `class AdbException(String message)`: the message names the failed command.
  - `sealed class RunAsResult` with `RunAsTokens(List<FoundToken> tokens)`, `RunAsReleaseBuild()`, `RunAsNoTokenYet()`, `RunAsNotInstalled()` and `RunAsFailed(String message)`.
  - `sealed class LogcatProgress` with `LogcatRestartingApp()`, `LogcatWaitingForApp()`, `LogcatWatching(int pid)`, `LogcatFound(String token)`, `LogcatAppDidNotStart()`, `LogcatNoToken()` and `LogcatFailed(String message)`.
  - `abstract interface class AdbService` with `Stream<List<AdbDevice>> trackDevices()`, `Future<DeviceDetails> deviceDetails(String serial)`, `Future<List<String>> listPackages(String serial)`, `Future<RunAsResult> readTokenWithRunAs(String serial, String package)`, `Future<void> launchApp(String serial, String package)` and `Stream<LogcatProgress> readTokenFromLogcat(String serial, String package)`.
  - `class ProcessAdbService implements AdbService` with constructor `({required ProcessRunner runner, required String adbPath, Duration pollInterval = 250 ms, Duration appStartTimeout = 10 s, Duration logcatTimeout = 20 s})` and `static const tokenFile = 'shared_prefs/com.google.android.gms.appid.xml'`. Its `deviceDetails`, `listPackages` and `launchApp` throw `AdbException`.

- [ ] **Step 1: Write the failing tests** `test/features/devices/adb_service_test.dart`

```dart
import 'package:fcm_studio/features/devices/data/adb_service.dart';
import 'package:fcm_studio/features/devices/data/process_runner.dart';
import 'package:fcm_studio/features/devices/domain/adb_device.dart';
import 'package:fcm_studio/features/devices/domain/device_token.dart';
import 'package:fcm_studio/features/devices/domain/token_read_results.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/device_fixtures.dart';
import '../../helpers/fake_process_runner.dart';

const adb = '/sdk/adb';
const package = 'com.syldel.delivery';

void main() {
  late FakeProcessRunner runner;

  setUp(() => runner = FakeProcessRunner());

  ProcessAdbService service() => ProcessAdbService(
    runner: runner,
    adbPath: adb,
    pollInterval: const Duration(milliseconds: 1),
    appStartTimeout: const Duration(milliseconds: 50),
    logcatTimeout: const Duration(milliseconds: 100),
  );

  String shell(String command) => '$adb -s $redmiSerial shell $command';
  const runAs =
      '$adb -s $redmiSerial exec-out run-as $package cat '
      'shared_prefs/com.google.android.gms.appid.xml';

  ProcessOutput failed(String text) => ProcessOutput(exitCode: 1, stdout: text);

  group('track-devices', () {
    test('emits each device list and kills adb when cancelled', () async {
      final tracker = FakeRunningProcess();
      runner.onStart('$adb track-devices -l', () => tracker);
      final lists = <List<AdbDevice>>[];
      final subscription = service().trackDevices().listen(lists.add);
      tracker.emit(trackFrame(redmiTrackLine));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(lists.single.single.serial, redmiSerial);
      await subscription.cancel();
      expect(tracker.killed, isTrue);
    });

    test('ends when adb exits', () async {
      final tracker = FakeRunningProcess();
      runner.onStart('$adb track-devices -l', () => tracker);
      final done = service().trackDevices().drain<void>();
      tracker.exit();
      await done;
    });

    test('an adb that cannot start is an AdbException naming the command', () async {
      await expectLater(
        service().trackDevices().first,
        throwsA(
          isA<AdbException>().having(
            (e) => e.message,
            'message',
            contains('track-devices'),
          ),
        ),
      );
    });
  });

  group('details and packages', () {
    const getprop =
        'getprop ro.product.marketname; getprop ro.product.model; '
        'getprop ro.product.brand; getprop ro.build.version.release';

    test('uses the market name, brand and Android version', () async {
      runner.on(shell(getprop), ok('Redmi 14C\n2409BRN2CA\nRedmi\n16\n'));
      expect(
        await service().deviceDetails(redmiSerial),
        const DeviceDetails(name: 'Redmi 14C', brand: 'Redmi', androidVersion: '16'),
      );
    });

    test('falls back to the model when there is no market name', () async {
      runner.on(shell(getprop), ok('\n2409BRN2CA\nRedmi\n16\n'));
      expect((await service().deviceDetails(redmiSerial)).name, '2409BRN2CA');
    });

    test('lists third-party packages, sorted', () async {
      runner.on(shell('pm list packages -3'), ok('package:b.app\npackage:a.app\n'));
      expect(await service().listPackages(redmiSerial), ['a.app', 'b.app']);
    });

    test('an adb failure is reported with its command', () async {
      runner.on(
        shell('pm list packages -3'),
        const ProcessOutput(exitCode: 1, stderr: 'error: device offline'),
      );
      await expectLater(
        service().listPackages(redmiSerial),
        throwsA(
          isA<AdbException>().having(
            (e) => e.message,
            'message',
            allOf(contains('pm list packages -3'), contains('device offline')),
          ),
        ),
      );
    });
  });

  group('run-as', () {
    test('reads the tokens of a debug build', () async {
      runner.on(runAs, ok(appIdPrefsXml({'123456789012': fakeDeviceToken})));
      expect(
        await service().readTokenWithRunAs(redmiSerial, package),
        RunAsTokens([FoundToken(token: fakeDeviceToken, senderId: '123456789012')]),
      );
    });

    test('a release build', () async {
      runner.on(runAs, failed('run-as: package not debuggable: $package'));
      expect(
        await service().readTokenWithRunAs(redmiSerial, package),
        const RunAsReleaseBuild(),
      );
    });

    test('no token yet: no file, or a file without a token', () async {
      runner.on(runAs, <ProcessOutput>[
        failed(
          'cat: shared_prefs/com.google.android.gms.appid.xml: No such file or directory',
        ),
        ok(appIdPrefsXml({})),
      ]);
      expect(
        await service().readTokenWithRunAs(redmiSerial, package),
        const RunAsNoTokenYet(),
      );
      expect(
        await service().readTokenWithRunAs(redmiSerial, package),
        const RunAsNoTokenYet(),
      );
    });

    test('a package that is not installed', () async {
      runner.on(runAs, failed('run-as: unknown package: $package'));
      expect(
        await service().readTokenWithRunAs(redmiSerial, package),
        const RunAsNotInstalled(),
      );
    });

    test('other failures name the command', () async {
      runner.on(runAs, const ProcessOutput(exitCode: 1, stderr: 'error: device offline'));
      final result = await service().readTokenWithRunAs(redmiSerial, package);
      expect(
        result,
        isA<RunAsFailed>().having(
          (r) => r.message,
          'message',
          allOf(contains('exec-out run-as'), contains('device offline')),
        ),
      );
      runner.on(runAs, const ProcessRunException('x', 'did not finish within 10 seconds'));
      expect(
        await service().readTokenWithRunAs(redmiSerial, package),
        isA<RunAsFailed>(),
      );
    });
  });

  group('launch', () {
    const monkey = 'monkey -p $package -c android.intent.category.LAUNCHER 1';

    test('starts the app with monkey', () async {
      runner.on(shell(monkey), ok('Events injected: 1\n'));
      await service().launchApp(redmiSerial, package);
      expect(runner.commands, [shell(monkey)]);
    });

    test('an app without a launcher activity is an error', () async {
      runner.on(shell(monkey), ok('** No activities found to run, monkey aborted.\n'));
      await expectLater(
        service().launchApp(redmiSerial, package),
        throwsA(isA<AdbException>()),
      );
    });
  });

  group('logcat (release builds)', () {
    void scriptRestart({required List<ProcessOutput> pidof}) {
      runner
        ..on(shell('am force-stop $package'), ok(''))
        ..on(
          shell('monkey -p $package -c android.intent.category.LAUNCHER 1'),
          ok('Events injected: 1\n'),
        )
        ..on(shell('pidof $package'), pidof);
    }

    test('restarts the app and finds the token in its log', () async {
      scriptRestart(pidof: <ProcessOutput>[ok(''), ok('4242\n')]);
      final logcat = FakeRunningProcess()
        ..emit('10-04 12:00:00.000 I/flutter: starting\n')
        ..emit('10-04 12:00:01.000 I/flutter: FCM token: $fakeDeviceToken\n');
      runner.onStart('$adb -s $redmiSerial logcat --pid=4242', () => logcat);

      final progress = await service()
          .readTokenFromLogcat(redmiSerial, package)
          .toList();

      expect(progress, [
        const LogcatRestartingApp(),
        const LogcatWaitingForApp(),
        const LogcatWatching(4242),
        LogcatFound(fakeDeviceToken),
      ]);
      expect(logcat.killed, isTrue);
    });

    test('never clears the log', () async {
      scriptRestart(pidof: <ProcessOutput>[ok('4242\n')]);
      final logcat = FakeRunningProcess()..emit('token: $fakeDeviceToken\n');
      runner.onStart('$adb -s $redmiSerial logcat --pid=4242', () => logcat);
      await service().readTokenFromLogcat(redmiSerial, package).drain<void>();
      expect(runner.commands.where((c) => c.contains('logcat -c')), isEmpty);
    });

    test('says so when the app does not start', () async {
      scriptRestart(pidof: <ProcessOutput>[ok('')]);
      expect(await service().readTokenFromLogcat(redmiSerial, package).toList(), [
        const LogcatRestartingApp(),
        const LogcatWaitingForApp(),
        const LogcatAppDidNotStart(),
      ]);
    });

    test('stops after the timeout when the app never logs a token', () async {
      scriptRestart(pidof: <ProcessOutput>[ok('4242\n')]);
      final logcat = FakeRunningProcess()..emit('10-04 I/flutter: nothing here\n');
      runner.onStart('$adb -s $redmiSerial logcat --pid=4242', () => logcat);
      final progress = await service()
          .readTokenFromLogcat(redmiSerial, package)
          .toList();
      expect(progress.last, const LogcatNoToken());
      expect(logcat.killed, isTrue);
    });

    test('an adb failure on the way ends with a message naming the command', () async {
      final progress = await service()
          .readTokenFromLogcat(redmiSerial, package)
          .toList();
      expect(progress.first, const LogcatRestartingApp());
      expect(
        progress.last,
        isA<LogcatFailed>().having(
          (p) => p.message,
          'message',
          contains('am force-stop'),
        ),
      );
    });
  });
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `flutter test test/features/devices/adb_service_test.dart`
Expected: FAIL, compilation errors.

- [ ] **Step 3: Implement**

`lib/features/devices/domain/token_read_results.dart`:
```dart
import 'package:equatable/equatable.dart';
import 'package:fcm_studio/features/devices/domain/device_token.dart';

/// The result of reading the token file with `run-as` (spec §9.3 step 1).
sealed class RunAsResult extends Equatable {
  const RunAsResult();

  @override
  List<Object?> get props => [];
}

final class RunAsTokens extends RunAsResult {
  const RunAsTokens(this.tokens);

  final List<FoundToken> tokens;

  @override
  List<Object?> get props => [tokens];
}

/// `run-as` refuses release builds; logcat (step 2) may work.
final class RunAsReleaseBuild extends RunAsResult {
  const RunAsReleaseBuild();
}

/// The app has no token yet: it was never opened, or hasn't registered.
final class RunAsNoTokenYet extends RunAsResult {
  const RunAsNoTokenYet();
}

final class RunAsNotInstalled extends RunAsResult {
  const RunAsNotInstalled();
}

final class RunAsFailed extends RunAsResult {
  const RunAsFailed(this.message);

  /// Names the command that failed (spec §11).
  final String message;

  @override
  List<Object?> get props => [message];
}

/// Progress of reading the token from logcat (spec §9.3 step 2).
sealed class LogcatProgress extends Equatable {
  const LogcatProgress();

  @override
  List<Object?> get props => [];
}

final class LogcatRestartingApp extends LogcatProgress {
  const LogcatRestartingApp();
}

final class LogcatWaitingForApp extends LogcatProgress {
  const LogcatWaitingForApp();
}

final class LogcatWatching extends LogcatProgress {
  const LogcatWatching(this.pid);

  final int pid;

  @override
  List<Object?> get props => [pid];
}

final class LogcatFound extends LogcatProgress {
  const LogcatFound(this.token);

  final String token;

  @override
  List<Object?> get props => [token];
}

final class LogcatAppDidNotStart extends LogcatProgress {
  const LogcatAppDidNotStart();
}

/// The app ran but printed no token within the time limit.
final class LogcatNoToken extends LogcatProgress {
  const LogcatNoToken();
}

final class LogcatFailed extends LogcatProgress {
  const LogcatFailed(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}
```

`lib/features/devices/data/adb_service.dart`:
```dart
import 'dart:async';
import 'dart:convert';

import 'package:fcm_studio/features/devices/data/parsers/app_id_prefs_parser.dart';
import 'package:fcm_studio/features/devices/data/parsers/fcm_token_pattern.dart';
import 'package:fcm_studio/features/devices/data/parsers/package_list_parser.dart';
import 'package:fcm_studio/features/devices/data/parsers/run_as_outcome.dart';
import 'package:fcm_studio/features/devices/data/parsers/track_devices_decoder.dart';
import 'package:fcm_studio/features/devices/data/process_runner.dart';
import 'package:fcm_studio/features/devices/domain/adb_device.dart';
import 'package:fcm_studio/features/devices/domain/token_read_results.dart';

/// An adb command that failed. The message names the command (spec §11).
class AdbException implements Exception {
  const AdbException(this.message);

  final String message;

  @override
  String toString() => 'AdbException: $message';
}

/// What the app asks adb to do (spec §9.2, §9.3).
abstract interface class AdbService {
  /// Device lists from `adb track-devices -l`, until adb exits.
  Stream<List<AdbDevice>> trackDevices();

  Future<DeviceDetails> deviceDetails(String serial);

  Future<List<String>> listPackages(String serial);

  Future<RunAsResult> readTokenWithRunAs(String serial, String package);

  Future<void> launchApp(String serial, String package);

  /// Restarts the app and watches its log for a token. Only after the user
  /// confirmed, because it restarts the app.
  Stream<LogcatProgress> readTokenFromLogcat(String serial, String package);
}

class ProcessAdbService implements AdbService {
  ProcessAdbService({
    required this._runner,
    required this._adbPath,
    this._pollInterval = const Duration(milliseconds: 250),
    this._appStartTimeout = const Duration(seconds: 10),
    this._logcatTimeout = const Duration(seconds: 20),
  });

  static const tokenFile = 'shared_prefs/com.google.android.gms.appid.xml';

  final ProcessRunner _runner;
  final String _adbPath;
  final Duration _pollInterval;
  final Duration _appStartTimeout;
  final Duration _logcatTimeout;

  @override
  Stream<List<AdbDevice>> trackDevices() async* {
    final process = await _start(const ['track-devices', '-l']);
    try {
      yield* process.stdout.transform(const TrackDevicesDecoder());
    } finally {
      process.kill();
    }
  }

  @override
  Future<DeviceDetails> deviceDetails(String serial) async {
    final output = await _shell(
      serial,
      'getprop ro.product.marketname; getprop ro.product.model; '
      'getprop ro.product.brand; getprop ro.build.version.release',
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

  @override
  Future<List<String>> listPackages(String serial) async =>
      parsePackageList((await _shell(serial, 'pm list packages -3')).stdout);

  @override
  Future<RunAsResult> readTokenWithRunAs(String serial, String package) async {
    final arguments = ['-s', serial, 'exec-out', 'run-as', package, 'cat', tokenFile];
    final ProcessOutput output;
    try {
      output = await _run(arguments);
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
        return RunAsFailed(_failed(arguments, output));
    }
  }

  @override
  Future<void> launchApp(String serial, String package) async {
    final command = 'monkey -p $package -c android.intent.category.LAUNCHER 1';
    final output = await _shell(serial, command);
    if (output.stdout.contains('monkey aborted')) {
      throw AdbException(
        '`${describeCommand(_adbPath, ['-s', serial, 'shell', command])}` '
        'failed: $package has no launcher activity.',
      );
    }
  }

  @override
  Stream<LogcatProgress> readTokenFromLogcat(String serial, String package) async* {
    try {
      yield const LogcatRestartingApp();
      await _shell(serial, 'am force-stop $package');
      await launchApp(serial, package);
      yield const LogcatWaitingForApp();
      final pid = await _waitForPid(serial, package);
      if (pid == null) {
        yield const LogcatAppDidNotStart();
        return;
      }
      yield LogcatWatching(pid);
      final token = await _watchLogcat(serial, pid);
      yield token == null ? const LogcatNoToken() : LogcatFound(token);
    } on AdbException catch (e) {
      yield LogcatFailed(e.message);
    }
  }

  /// Polls `pidof` until the app runs, or gives up after [_appStartTimeout].
  Future<int?> _waitForPid(String serial, String package) async {
    final stopwatch = Stopwatch()..start();
    while (stopwatch.elapsed < _appStartTimeout) {
      final output = await _run(['-s', serial, 'shell', 'pidof', package]);
      final pid = int.tryParse(output.stdout.trim().split(RegExp(r'\s+')).first);
      if (pid != null) {
        return pid;
      }
      await Future<void>.delayed(_pollInterval);
    }
    return null;
  }

  /// `logcat --pid` includes the process's earlier lines. Never `logcat -c`:
  /// other tools keep their logs (spec §9.3).
  Future<String?> _watchLogcat(String serial, int pid) async {
    final process = await _start(['-s', serial, 'logcat', '--pid=$pid']);
    try {
      return await process.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .map(FcmTokenPattern.firstIn)
          .firstWhere((token) => token != null, orElse: () => null)
          .timeout(_logcatTimeout, onTimeout: () => null);
    } finally {
      process.kill();
    }
  }

  Future<ProcessOutput> _run(List<String> arguments) async {
    try {
      return await _runner.run(_adbPath, arguments);
    } on ProcessRunException catch (e) {
      throw AdbException(e.message);
    }
  }

  Future<RunningProcess> _start(List<String> arguments) async {
    try {
      return await _runner.start(_adbPath, arguments);
    } on ProcessRunException catch (e) {
      throw AdbException(e.message);
    }
  }

  Future<ProcessOutput> _shell(String serial, String command) async {
    final arguments = ['-s', serial, 'shell', command];
    final output = await _run(arguments);
    if (output.exitCode != 0) {
      throw AdbException(_failed(arguments, output));
    }
    return output;
  }

  String _failed(List<String> arguments, ProcessOutput output) {
    final details = output.combined.trim();
    return '`${describeCommand(_adbPath, arguments)}` failed: '
        '${details.isEmpty ? 'exit code ${output.exitCode}' : details}';
  }
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `flutter test test/features/devices/adb_service_test.dart`
Expected: PASS. Then `flutter analyze` (No issues found!).

- [ ] **Step 5: Commit**

```bash
dart format lib test
git add lib/features/devices/domain/token_read_results.dart lib/features/devices/data/adb_service.dart test/features/devices/adb_service_test.dart
git commit -m "feat: talk to adb: devices, details, packages, run-as and logcat"
```

---


### Task 7: `DevicesBloc`: track phones, restart with backoff, select, load details

**Files:**
- Create: `lib/features/devices/bloc/devices_event.dart`, `lib/features/devices/bloc/devices_state.dart`, `lib/features/devices/bloc/devices_bloc.dart`, `test/helpers/fake_adb_service.dart`
- Test: `test/features/devices/devices_bloc_test.dart`

**Interfaces:**
- Consumes: `AdbService`, `AdbException` (Task 6); `AdbDevice`, `DeviceDetails`, `DeviceState` (Task 3); `RunAsResult`, `LogcatProgress` and their subclasses (Task 6); test helper `redmiSerial` (Task 4).
- Produces:
  - Events: `abstract class DevicesEvent`, `DevicesAdbChanged(String? adbPath)` (null means adb was lost) and `DeviceSelected(String serial)`.
  - `enum TrackerStatus { noAdb, starting, running, restarting }`.
  - `class DevicesState` with `status`, `adbPath`, `devices`, `selectedSerial`, `details` (`Map<String, DeviceDetails>`), `retryIn`, `lastError`, plus `AdbDevice? get selected` and `String nameOf(AdbDevice)` (getprop name, else adb's model, else the serial).
  - `class DevicesBloc({required AdbService Function(String adbPath) serviceFor, Duration Function(int attempt) backoff = defaultBackoff})` with `static Duration defaultBackoff(int attempt)` (1, 2, 4, 8, 16, then 30 s).
  - Test helper `FakeAdbService implements AdbService` with:
    - `trackers` (one `StreamController` per `trackDevices()` call) and `tracker` (the latest);
    - scripted maps `details`, `packages`, `runAs` (a `List<RunAsResult>` per package; each call takes the next, and the last repeats) and `logcat` (a `List<LogcatProgress>` per package);
    - `Object? packagesError`, `Completer<RunAsResult>? runAsGate`, and a `calls` log.

- [ ] **Step 1: Add the fake** `test/helpers/fake_adb_service.dart`

```dart
import 'dart:async';

import 'package:fcm_studio/features/devices/data/adb_service.dart';
import 'package:fcm_studio/features/devices/domain/adb_device.dart';
import 'package:fcm_studio/features/devices/domain/token_read_results.dart';

/// An [AdbService] whose answers the test scripts. Every call is logged.
class FakeAdbService implements AdbService {
  /// One controller per trackDevices() call, so restarts can be checked.
  final List<StreamController<List<AdbDevice>>> trackers = [];
  final Map<String, DeviceDetails> details = {};
  final Map<String, List<String>> packages = {};

  /// Answers by package; each call takes the next one, and the last repeats.
  final Map<String, List<RunAsResult>> runAs = {};
  final Map<String, List<LogcatProgress>> logcat = {};
  final List<String> calls = [];

  /// Thrown by listPackages when set.
  Object? packagesError;

  /// When set, readTokenWithRunAs waits for it (to test a read in progress).
  Completer<RunAsResult>? runAsGate;

  StreamController<List<AdbDevice>> get tracker => trackers.last;

  @override
  Stream<List<AdbDevice>> trackDevices() {
    calls.add('track-devices');
    final controller = StreamController<List<AdbDevice>>();
    trackers.add(controller);
    return controller.stream;
  }

  @override
  Future<DeviceDetails> deviceDetails(String serial) async {
    calls.add('details $serial');
    return details[serial] ?? DeviceDetails(name: serial);
  }

  @override
  Future<List<String>> listPackages(String serial) async {
    calls.add('packages $serial');
    final error = packagesError;
    if (error != null) {
      throw error;
    }
    return packages[serial] ?? const [];
  }

  @override
  Future<RunAsResult> readTokenWithRunAs(String serial, String package) async {
    calls.add('run-as $serial $package');
    final gate = runAsGate;
    if (gate != null) {
      return gate.future;
    }
    final answers = runAs[package] ?? [const RunAsNotInstalled()];
    return answers.length > 1 ? answers.removeAt(0) : answers.single;
  }

  @override
  Future<void> launchApp(String serial, String package) async {
    calls.add('launch $serial $package');
  }

  @override
  Stream<LogcatProgress> readTokenFromLogcat(String serial, String package) {
    calls.add('logcat $serial $package');
    return Stream.fromIterable(logcat[package] ?? const [LogcatNoToken()]);
  }
}
```

- [ ] **Step 2: Write the failing tests** `test/features/devices/devices_bloc_test.dart`

```dart
import 'package:fcm_studio/features/devices/bloc/devices_bloc.dart';
import 'package:fcm_studio/features/devices/domain/adb_device.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/device_fixtures.dart';
import '../../helpers/fake_adb_service.dart';

const redmi = AdbDevice(
  serial: redmiSerial,
  state: DeviceState.device,
  rawState: 'device',
  model: '2409BRN2CA',
);
const unauthorized = AdbDevice(
  serial: 'R58M123ABC',
  state: DeviceState.unauthorized,
  rawState: 'unauthorized',
);
const emulator = AdbDevice(
  serial: 'emulator-5554',
  state: DeviceState.device,
  rawState: 'device',
);

void main() {
  late FakeAdbService adb;
  final delays = <Duration>[];

  setUp(() {
    adb = FakeAdbService();
    delays.clear();
  });

  DevicesBloc build() {
    final bloc = DevicesBloc(
      serviceFor: (_) => adb,
      backoff: (attempt) {
        delays.add(DevicesBloc.defaultBackoff(attempt));
        return Duration.zero;
      },
    );
    addTearDown(bloc.close);
    return bloc;
  }

  Future<void> flush() async {
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('backoff is 1, 2, 4, 8, 16, then 30 seconds', () {
    expect([for (var i = 1; i <= 7; i++) DevicesBloc.defaultBackoff(i).inSeconds], [
      1,
      2,
      4,
      8,
      16,
      30,
      30,
    ]);
  });

  test('tracks phones once adb is found, selects the only ready one and loads its details', () async {
    adb.details[redmiSerial] = const DeviceDetails(
      name: 'Redmi 14C',
      brand: 'Redmi',
      androidVersion: '16',
    );
    final bloc = build()..add(const DevicesAdbChanged('/sdk/adb'));
    await flush();
    expect(bloc.state.status, TrackerStatus.starting);
    expect(bloc.state.adbPath, '/sdk/adb');

    adb.tracker.add([redmi]);
    await flush();
    expect(bloc.state.status, TrackerStatus.running);
    expect(bloc.state.selected, redmi);
    expect(bloc.state.nameOf(redmi), 'Redmi 14C');
  });

  test('an unauthorized phone is listed but not selected or queried', () async {
    final bloc = build()..add(const DevicesAdbChanged('/sdk/adb'));
    await flush();
    adb.tracker.add([unauthorized]);
    await flush();
    expect(bloc.state.devices, [unauthorized]);
    expect(bloc.state.selectedSerial, isNull);
    expect(adb.calls, ['track-devices']);
    expect(bloc.state.nameOf(unauthorized), 'R58M123ABC');
  });

  test('with two ready phones the user chooses', () async {
    final bloc = build()..add(const DevicesAdbChanged('/sdk/adb'));
    await flush();
    adb.tracker.add([redmi, emulator]);
    await flush();
    expect(bloc.state.selectedSerial, isNull);
    bloc.add(const DeviceSelected('emulator-5554'));
    await flush();
    expect(bloc.state.selected, emulator);
    expect(adb.calls, contains('details emulator-5554'));
  });

  test('restarts the tracker with backoff after adb exits', () async {
    final bloc = build()..add(const DevicesAdbChanged('/sdk/adb'));
    await flush();
    await adb.tracker.close();
    await flush();
    expect(adb.trackers, hasLength(2));
    await adb.tracker.close();
    await flush();
    expect(adb.trackers, hasLength(3));
    expect(delays, [const Duration(seconds: 1), const Duration(seconds: 2)]);

    adb.tracker.add([redmi]);
    await flush();
    await adb.tracker.close();
    await flush();
    expect(
      delays.last,
      const Duration(seconds: 1),
      reason: 'a tracker that worked resets the backoff',
    );
    expect(bloc.state.status, isNot(TrackerStatus.noAdb));
  });

  test('keeps the selection while the phone is unplugged', () async {
    final bloc = build()..add(const DevicesAdbChanged('/sdk/adb'));
    await flush();
    adb.tracker.add([redmi]);
    await flush();
    adb.tracker.add([]);
    await flush();
    expect(bloc.state.selectedSerial, redmiSerial);
    expect(bloc.state.selected, isNull);
    adb.tracker.add([redmi]);
    await flush();
    expect(bloc.state.selected, redmi);
  });

  test('losing adb stops tracking', () async {
    final bloc = build()..add(const DevicesAdbChanged('/sdk/adb'));
    await flush();
    bloc.add(const DevicesAdbChanged(null));
    await flush();
    expect(bloc.state.status, TrackerStatus.noAdb);
    expect(adb.trackers.single.hasListener, isFalse);
  });
}
```

- [ ] **Step 3: Run them to see them fail**

Run: `flutter test test/features/devices/devices_bloc_test.dart`
Expected: FAIL, compilation errors.

- [ ] **Step 4: Implement**

`lib/features/devices/bloc/devices_event.dart`:
```dart
abstract class DevicesEvent {
  const DevicesEvent();
}

/// adb was found at [adbPath], moved, or lost (null).
class DevicesAdbChanged extends DevicesEvent {
  const DevicesAdbChanged(this.adbPath);

  final String? adbPath;
}

class DeviceSelected extends DevicesEvent {
  const DeviceSelected(this.serial);

  final String serial;
}
```

`lib/features/devices/bloc/devices_state.dart`:
```dart
import 'package:equatable/equatable.dart';
import 'package:fcm_studio/features/devices/domain/adb_device.dart';

enum TrackerStatus { noAdb, starting, running, restarting }

class DevicesState extends Equatable {
  const DevicesState({
    this.status = TrackerStatus.noAdb,
    this.adbPath,
    this.devices = const [],
    this.selectedSerial,
    this.details = const {},
    this.retryIn,
    this.lastError,
  });

  final TrackerStatus status;
  final String? adbPath;
  final List<AdbDevice> devices;

  /// Kept while the phone is unplugged, so it is picked up again.
  final String? selectedSerial;
  final Map<String, DeviceDetails> details;

  /// While restarting: how long until the next try.
  final Duration? retryIn;

  /// Why adb stopped, naming the command when known.
  final String? lastError;

  AdbDevice? get selected {
    for (final device in devices) {
      if (device.serial == selectedSerial) {
        return device;
      }
    }
    return null;
  }

  /// The market name from getprop, else adb's model, else the serial.
  String nameOf(AdbDevice device) =>
      details[device.serial]?.name ?? device.model ?? device.serial;

  DevicesState copyWith({
    TrackerStatus? status,
    String? Function()? adbPath,
    List<AdbDevice>? devices,
    String? Function()? selectedSerial,
    Map<String, DeviceDetails>? details,
    Duration? Function()? retryIn,
    String? Function()? lastError,
  }) => DevicesState(
    status: status ?? this.status,
    adbPath: adbPath != null ? adbPath() : this.adbPath,
    devices: devices ?? this.devices,
    selectedSerial: selectedSerial != null ? selectedSerial() : this.selectedSerial,
    details: details ?? this.details,
    retryIn: retryIn != null ? retryIn() : this.retryIn,
    lastError: lastError != null ? lastError() : this.lastError,
  );

  @override
  List<Object?> get props => [
    status,
    adbPath,
    devices,
    selectedSerial,
    details,
    retryIn,
    lastError,
  ];
}
```

`lib/features/devices/bloc/devices_bloc.dart`:
```dart
import 'dart:async';
import 'dart:math';

import 'package:fcm_studio/features/devices/bloc/devices_event.dart';
import 'package:fcm_studio/features/devices/bloc/devices_state.dart';
import 'package:fcm_studio/features/devices/data/adb_service.dart';
import 'package:fcm_studio/features/devices/domain/adb_device.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

export 'package:fcm_studio/features/devices/bloc/devices_event.dart';
export 'package:fcm_studio/features/devices/bloc/devices_state.dart';

/// Tracks plugged-in phones with `adb track-devices -l` and restarts it with
/// backoff when it exits (spec §9.2).
class DevicesBloc extends Bloc<DevicesEvent, DevicesState> {
  DevicesBloc({required this._serviceFor, this._backoff = defaultBackoff})
    : super(const DevicesState()) {
    on<DevicesAdbChanged>(_onAdbChanged);
    on<DeviceSelected>(_onSelected);
    on<_TrackerUpdated>(_onUpdated);
    on<_TrackerEnded>(_onEnded);
    on<_TrackerRestart>(_onRestart);
    on<_DetailsLoaded>(_onDetailsLoaded);
  }

  /// 1, 2, 4, 8, 16, then 30 seconds.
  static Duration defaultBackoff(int attempt) =>
      Duration(seconds: min(30, 1 << (attempt - 1).clamp(0, 5)));

  final AdbService Function(String adbPath) _serviceFor;
  final Duration Function(int attempt) _backoff;
  AdbService? _service;
  StreamSubscription<List<AdbDevice>>? _subscription;
  Timer? _restartTimer;
  int _failures = 0;
  final Set<String> _loadingDetails = {};

  Future<void> _onAdbChanged(
    DevicesAdbChanged event,
    Emitter<DevicesState> emit,
  ) async {
    await _stop();
    _failures = 0;
    final path = event.adbPath;
    if (path == null) {
      _service = null;
      emit(DevicesState(selectedSerial: state.selectedSerial));
      return;
    }
    _service = _serviceFor(path);
    emit(
      state.copyWith(
        status: TrackerStatus.starting,
        adbPath: () => path,
        devices: const [],
        retryIn: () => null,
      ),
    );
    _listen();
  }

  void _listen() {
    final service = _service;
    if (service == null) {
      return;
    }
    _subscription = service.trackDevices().listen(
      (devices) {
        if (!isClosed) {
          add(_TrackerUpdated(devices));
        }
      },
      onError: (Object error) {
        if (!isClosed) {
          add(_TrackerEnded(error));
        }
      },
      onDone: () {
        if (!isClosed) {
          add(const _TrackerEnded());
        }
      },
      cancelOnError: true,
    );
  }

  void _onUpdated(_TrackerUpdated event, Emitter<DevicesState> emit) {
    _failures = 0;
    final devices = event.devices;
    final ready = devices.where((device) => device.isReady).toList();
    var selected = state.selectedSerial;
    final selectedPresent = devices.any((device) => device.serial == selected);
    if ((selected == null || !selectedPresent) && ready.length == 1) {
      selected = ready.single.serial;
    }
    emit(
      state.copyWith(
        status: TrackerStatus.running,
        devices: devices,
        selectedSerial: () => selected,
        retryIn: () => null,
        lastError: () => null,
      ),
    );
    for (final device in ready) {
      _loadDetails(device.serial);
    }
  }

  void _onSelected(DeviceSelected event, Emitter<DevicesState> emit) {
    emit(state.copyWith(selectedSerial: () => event.serial));
    final device = state.selected;
    if (device != null && device.isReady) {
      _loadDetails(device.serial);
    }
  }

  void _loadDetails(String serial) {
    final service = _service;
    if (service == null ||
        state.details.containsKey(serial) ||
        !_loadingDetails.add(serial)) {
      return;
    }
    unawaited(
      service.deviceDetails(serial).then<void>(
        (details) {
          if (!isClosed) {
            add(_DetailsLoaded(serial, details));
          }
        },
        onError: (Object _) {
          if (!isClosed) {
            add(_DetailsLoaded(serial, null));
          }
        },
      ),
    );
  }

  void _onDetailsLoaded(_DetailsLoaded event, Emitter<DevicesState> emit) {
    _loadingDetails.remove(event.serial);
    final details = event.details;
    if (details != null) {
      emit(state.copyWith(details: {...state.details, event.serial: details}));
    }
  }

  void _onEnded(_TrackerEnded event, Emitter<DevicesState> emit) {
    _subscription = null;
    if (_service == null) {
      return;
    }
    _failures++;
    final delay = _backoff(_failures);
    final error = event.error;
    emit(
      state.copyWith(
        status: TrackerStatus.restarting,
        devices: const [],
        retryIn: () => delay,
        lastError: () => error == null ? null : _describe(error),
      ),
    );
    _restartTimer = Timer(delay, () {
      if (!isClosed) {
        add(const _TrackerRestart());
      }
    });
  }

  void _onRestart(_TrackerRestart event, Emitter<DevicesState> emit) {
    if (_service == null || _subscription != null) {
      return;
    }
    emit(state.copyWith(status: TrackerStatus.starting, retryIn: () => null));
    _listen();
  }

  static String _describe(Object error) => switch (error) {
    AdbException(:final message) => message,
    _ => '$error',
  };

  Future<void> _stop() async {
    _restartTimer?.cancel();
    _restartTimer = null;
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
  }

  @override
  Future<void> close() async {
    await _stop();
    return super.close();
  }
}

class _TrackerUpdated extends DevicesEvent {
  const _TrackerUpdated(this.devices);

  final List<AdbDevice> devices;
}

class _TrackerEnded extends DevicesEvent {
  const _TrackerEnded([this.error]);

  final Object? error;
}

class _TrackerRestart extends DevicesEvent {
  const _TrackerRestart();
}

class _DetailsLoaded extends DevicesEvent {
  const _DetailsLoaded(this.serial, this.details);

  final String serial;
  final DeviceDetails? details;
}
```

- [ ] **Step 5: Run the tests and confirm they pass**

Run: `flutter test test/features/devices/devices_bloc_test.dart`
Expected: PASS (7 tests). Then `flutter analyze` (No issues found!).

- [ ] **Step 6: Commit**

```bash
dart format lib test
git add lib/features/devices/bloc test/helpers/fake_adb_service.dart test/features/devices/devices_bloc_test.dart
git commit -m "feat: track plugged-in phones and restart adb with backoff"
```

---

### Task 8: `TokenReaderCubit`: packages, run-as, and the logcat fallback

**Files:**
- Create: `lib/features/devices/domain/package_order.dart`, `lib/features/devices/data/recent_packages_repository.dart`, `lib/features/devices/cubit/token_reader_state.dart`, `lib/features/devices/cubit/token_reader_cubit.dart`
- Test: `test/features/devices/recent_packages_test.dart`, `test/features/devices/token_reader_cubit_test.dart`

**Interfaces:**
- Consumes: `AdbService`, `AdbException`, `RunAsResult` and subclasses, `LogcatProgress` and subclasses (Task 6); `FoundToken`, `TokenReadMethod` (Task 4); `AppDatabase` (existing); test helpers `FakeAdbService` (Task 7), `fakeDeviceToken`, `otherDeviceToken`, `redmiSerial` (Task 4).
- Produces:
  - `List<String> orderPackages(List<String> installed, List<String> recent, String query)`.
  - `class RecentPackagesRepository({required AppDatabase database})` with `static const maxRecent = 5`, `Future<List<String>> recent(String serial)` and `Future<void> remember(String serial, String package)`.
  - `enum PackagesStatus { idle, loading, ready, failed }`.
  - `sealed class TokenRead` → `TokenReadIdle`. Its sealed subclass `TokenReadStep(String package)` → `TokenReading`, `TokenReadFound(package, {required List<FoundToken> tokens, required TokenReadMethod method, String? preselectedSenderId})`, `TokenReadReleaseBuild`, `TokenReadNoTokenYet`, `TokenReadNotInstalled`, `TokenReadWatchingLogcat(package, LogcatProgress progress)`, `TokenReadLogcatNoToken`, `TokenReadAppDidNotStart` and `TokenReadFailed(package, String message)`.
  - `class TokenReaderState` with `serial`, `packagesStatus`, `installed`, `recent`, `query`, `packagesError`, `read`, plus the getters `packages` (ordered and filtered) and `isBusy`.
  - `class TokenReaderCubit({required AdbService Function(String adbPath) serviceFor, required RecentPackagesRepository recent})` with:
    - `Future<void> openDevice(String adbPath, String serial)` and `Future<void> refreshPackages()`;
    - `void search(String query)`;
    - `Future<void> readToken(String package, {String? projectNumber})`;
    - `Future<void> readTokenFromLogcat(String package)`, which completes when the logcat step ends;
    - `Future<void> launchApp(String package)` and `void dismiss()`.

- [ ] **Step 1: Write the failing tests**

`test/features/devices/recent_packages_test.dart`:
```dart
import 'package:fcm_studio/core/storage/app_database.dart';
import 'package:fcm_studio/features/devices/data/recent_packages_repository.dart';
import 'package:fcm_studio/features/devices/domain/package_order.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;

  setUp(() async => database = await AppDatabase.inMemory());
  tearDown(() => database.close());

  test('remembers the last 5 packages per phone, newest first', () async {
    final recent = RecentPackagesRepository(database: database);
    for (final package in ['a', 'b', 'c', 'd', 'e', 'f', 'b']) {
      await recent.remember('phone-1', package);
    }
    expect(await recent.recent('phone-1'), ['b', 'f', 'e', 'd', 'c']);
    expect(await recent.recent('phone-2'), isEmpty);
  });

  test('orders recent packages first, the rest sorted, filtered by the search', () {
    const installed = ['com.zeta', 'com.alpha', 'com.syldel.delivery', 'com.beta'];
    expect(
      orderPackages(installed, ['com.syldel.delivery', 'com.gone'], ''),
      ['com.syldel.delivery', 'com.alpha', 'com.beta', 'com.zeta'],
    );
    expect(orderPackages(installed, ['com.syldel.delivery'], 'ALP'), ['com.alpha']);
  });
}
```

`test/features/devices/token_reader_cubit_test.dart`:
```dart
import 'dart:async';

import 'package:fcm_studio/core/storage/app_database.dart';
import 'package:fcm_studio/features/devices/cubit/token_reader_cubit.dart';
import 'package:fcm_studio/features/devices/data/adb_service.dart';
import 'package:fcm_studio/features/devices/data/recent_packages_repository.dart';
import 'package:fcm_studio/features/devices/domain/device_token.dart';
import 'package:fcm_studio/features/devices/domain/token_read_results.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/device_fixtures.dart';
import '../../helpers/fake_adb_service.dart';

const app = 'com.syldel.delivery';

void main() {
  late AppDatabase database;
  late FakeAdbService adb;
  late RecentPackagesRepository recent;

  setUp(() async {
    database = await AppDatabase.inMemory();
    adb = FakeAdbService();
    recent = RecentPackagesRepository(database: database);
  });

  tearDown(() => database.close());

  Future<TokenReaderCubit> opened({
    List<String> installed = const ['com.alpha', app],
  }) async {
    adb.packages[redmiSerial] = installed;
    final cubit = TokenReaderCubit(serviceFor: (_) => adb, recent: recent);
    addTearDown(cubit.close);
    await cubit.openDevice('/sdk/adb', redmiSerial);
    return cubit;
  }

  test('lists the packages with the recently used ones first, and searches', () async {
    await recent.remember(redmiSerial, app);
    final cubit = await opened(installed: ['com.alpha', 'com.beta', app]);
    expect(cubit.state.packagesStatus, PackagesStatus.ready);
    expect(cubit.state.packages, [app, 'com.alpha', 'com.beta']);
    cubit.search('BET');
    expect(cubit.state.packages, ['com.beta']);
  });

  test('a package list that adb cannot read shows why', () async {
    adb.packagesError = const AdbException(
      '`adb -s X shell pm list packages -3` failed: error: device offline',
    );
    final cubit = await opened();
    expect(cubit.state.packagesStatus, PackagesStatus.failed);
    expect(cubit.state.packagesError, contains('device offline'));
  });

  test("a debug build: the tokens, the project's sender preselected, the app remembered", () async {
    adb.runAs[app] = [
      RunAsTokens([
        FoundToken(token: otherDeviceToken, senderId: '999000999000'),
        FoundToken(token: fakeDeviceToken, senderId: '123456789012'),
      ]),
    ];
    final cubit = await opened();
    await cubit.readToken(app, projectNumber: '123456789012');
    final read = cubit.state.read as TokenReadFound;
    expect(read.method, TokenReadMethod.runAs);
    expect(read.tokens, hasLength(2));
    expect(read.preselectedSenderId, '123456789012');
    expect(await recent.recent(redmiSerial), [app]);
    expect(cubit.state.packages.first, app);
  });

  test('a release build: logcat after the user confirms', () async {
    adb.runAs[app] = [const RunAsReleaseBuild()];
    adb.logcat[app] = [
      const LogcatRestartingApp(),
      const LogcatWaitingForApp(),
      const LogcatWatching(4242),
      LogcatFound(fakeDeviceToken),
    ];
    final cubit = await opened();
    await cubit.readToken(app);
    expect(cubit.state.read, const TokenReadReleaseBuild(app));
    expect(adb.calls.where((c) => c.startsWith('logcat')), isEmpty);

    final steps = <TokenRead>[];
    final subscription = cubit.stream.listen((state) => steps.add(state.read));
    await cubit.readTokenFromLogcat(app);
    await Future<void>.delayed(Duration.zero);
    await subscription.cancel();

    expect(
      steps.whereType<TokenReadWatchingLogcat>().map((step) => step.progress),
      contains(const LogcatWatching(4242)),
    );
    expect(
      cubit.state.read,
      TokenReadFound(
        app,
        tokens: [FoundToken(token: fakeDeviceToken)],
        method: TokenReadMethod.logcat,
      ),
    );
  });

  test('no token yet, then launch and retry', () async {
    adb.runAs[app] = [
      const RunAsNoTokenYet(),
      RunAsTokens([FoundToken(token: fakeDeviceToken, senderId: '123456789012')]),
    ];
    final cubit = await opened();
    await cubit.readToken(app);
    expect(cubit.state.read, const TokenReadNoTokenYet(app));
    await cubit.launchApp(app);
    expect(adb.calls, contains('launch $redmiSerial $app'));
    await cubit.readToken(app);
    expect(cubit.state.read, isA<TokenReadFound>());
  });

  test('a package that is not installed', () async {
    adb.runAs['com.gone'] = [const RunAsNotInstalled()];
    final cubit = await opened();
    await cubit.readToken('com.gone');
    expect(cubit.state.read, const TokenReadNotInstalled('com.gone'));
  });

  test('a failed read shows the message', () async {
    const message = '`adb -s X exec-out run-as app cat …` failed: error: device offline';
    adb.runAs[app] = [const RunAsFailed(message)];
    final cubit = await opened();
    await cubit.readToken(app);
    expect(cubit.state.read, const TokenReadFailed(app, message));
    cubit.dismiss();
    expect(cubit.state.read, const TokenReadIdle());
  });

  test('logcat endings: no token, and an app that does not start', () async {
    adb.logcat['com.release'] = [const LogcatRestartingApp(), const LogcatNoToken()];
    adb.logcat['com.slow'] = [const LogcatRestartingApp(), const LogcatAppDidNotStart()];
    final cubit = await opened();
    await cubit.readTokenFromLogcat('com.release');
    expect(cubit.state.read, const TokenReadLogcatNoToken('com.release'));
    await cubit.readTokenFromLogcat('com.slow');
    expect(cubit.state.read, const TokenReadAppDidNotStart('com.slow'));
  });

  test('ignores a second read while one is running', () async {
    final gate = Completer<RunAsResult>();
    adb.runAsGate = gate;
    final cubit = await opened();
    final first = cubit.readToken(app);
    expect(cubit.state.isBusy, isTrue);
    await cubit.readToken('com.alpha');
    gate.complete(
      RunAsTokens([FoundToken(token: fakeDeviceToken, senderId: '123456789012')]),
    );
    await first;
    expect(adb.calls.where((c) => c.startsWith('run-as')), hasLength(1));
  });
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `flutter test test/features/devices/recent_packages_test.dart test/features/devices/token_reader_cubit_test.dart`
Expected: FAIL, compilation errors.

- [ ] **Step 3: Implement**

`lib/features/devices/domain/package_order.dart`:
```dart
/// The package list for a phone (spec §9.2): the last packages used on it
/// first, then the rest sorted, filtered by [query] (ignoring case).
List<String> orderPackages(
  List<String> installed,
  List<String> recent,
  String query,
) {
  final text = query.trim().toLowerCase();
  bool matches(String package) =>
      text.isEmpty || package.toLowerCase().contains(text);
  final installedSet = installed.toSet();
  final first = [
    for (final package in recent)
      if (installedSet.contains(package) && matches(package)) package,
  ];
  final rest = [
    for (final package in installed)
      if (!first.contains(package) && matches(package)) package,
  ]..sort();
  return [...first, ...rest];
}
```

`lib/features/devices/data/recent_packages_repository.dart`:
```dart
import 'package:fcm_studio/core/storage/app_database.dart';
import 'package:sembast/sembast.dart';

/// The last packages whose token was read, per phone (spec §9.2).
class RecentPackagesRepository {
  RecentPackagesRepository({required AppDatabase database}) : _db = database.db;

  static const maxRecent = 5;
  static final _store = stringMapStoreFactory.store('devices');

  final Database _db;

  /// Newest first.
  Future<List<String>> recent(String serial) async {
    final record = await _store.record(serial).get(_db);
    final packages = record?['recentPackages'];
    return packages is List<Object?>
        ? [
            for (final package in packages)
              if (package is String) package,
          ]
        : const [];
  }

  Future<void> remember(String serial, String package) async {
    final updated = [
      package,
      ...(await recent(serial)).where((p) => p != package),
    ].take(maxRecent).toList();
    await _store.record(serial).put(_db, {
      'schemaVersion': 1,
      'recentPackages': updated,
    });
  }
}
```

`lib/features/devices/cubit/token_reader_state.dart`:
```dart
import 'package:equatable/equatable.dart';
import 'package:fcm_studio/features/devices/domain/device_token.dart';
import 'package:fcm_studio/features/devices/domain/package_order.dart';
import 'package:fcm_studio/features/devices/domain/token_read_results.dart';

enum PackagesStatus { idle, loading, ready, failed }

/// Where reading a package's token stands (spec §9.3).
sealed class TokenRead extends Equatable {
  const TokenRead();

  @override
  List<Object?> get props => [];
}

final class TokenReadIdle extends TokenRead {
  const TokenReadIdle();
}

/// Every step after idle is about one package.
sealed class TokenReadStep extends TokenRead {
  const TokenReadStep(this.package);

  final String package;

  @override
  List<Object?> get props => [package];
}

final class TokenReading extends TokenReadStep {
  const TokenReading(super.package);
}

final class TokenReadFound extends TokenReadStep {
  const TokenReadFound(
    super.package, {
    required this.tokens,
    required this.method,
    this.preselectedSenderId,
  });

  final List<FoundToken> tokens;
  final TokenReadMethod method;

  /// The sender matching the selected project, or the only one.
  final String? preselectedSenderId;

  @override
  List<Object?> get props => [package, tokens, method, preselectedSenderId];
}

final class TokenReadReleaseBuild extends TokenReadStep {
  const TokenReadReleaseBuild(super.package);
}

final class TokenReadNoTokenYet extends TokenReadStep {
  const TokenReadNoTokenYet(super.package);
}

final class TokenReadNotInstalled extends TokenReadStep {
  const TokenReadNotInstalled(super.package);
}

final class TokenReadWatchingLogcat extends TokenReadStep {
  const TokenReadWatchingLogcat(super.package, this.progress);

  final LogcatProgress progress;

  @override
  List<Object?> get props => [package, progress];
}

final class TokenReadLogcatNoToken extends TokenReadStep {
  const TokenReadLogcatNoToken(super.package);
}

final class TokenReadAppDidNotStart extends TokenReadStep {
  const TokenReadAppDidNotStart(super.package);
}

final class TokenReadFailed extends TokenReadStep {
  const TokenReadFailed(super.package, this.message);

  /// Names the failed command (spec §11).
  final String message;

  @override
  List<Object?> get props => [package, message];
}

class TokenReaderState extends Equatable {
  const TokenReaderState({
    this.serial,
    this.packagesStatus = PackagesStatus.idle,
    this.installed = const [],
    this.recent = const [],
    this.query = '',
    this.packagesError,
    this.read = const TokenReadIdle(),
  });

  final String? serial;
  final PackagesStatus packagesStatus;
  final List<String> installed;

  /// Newest first.
  final List<String> recent;
  final String query;
  final String? packagesError;
  final TokenRead read;

  List<String> get packages => orderPackages(installed, recent, query);

  bool get isBusy => read is TokenReading || read is TokenReadWatchingLogcat;

  TokenReaderState copyWith({
    PackagesStatus? packagesStatus,
    List<String>? installed,
    List<String>? recent,
    String? query,
    String? Function()? packagesError,
    TokenRead? read,
  }) => TokenReaderState(
    serial: serial,
    packagesStatus: packagesStatus ?? this.packagesStatus,
    installed: installed ?? this.installed,
    recent: recent ?? this.recent,
    query: query ?? this.query,
    packagesError: packagesError != null ? packagesError() : this.packagesError,
    read: read ?? this.read,
  );

  @override
  List<Object?> get props => [
    serial,
    packagesStatus,
    installed,
    recent,
    query,
    packagesError,
    read,
  ];
}
```

`lib/features/devices/cubit/token_reader_cubit.dart`:
```dart
import 'dart:async';

import 'package:fcm_studio/features/devices/cubit/token_reader_state.dart';
import 'package:fcm_studio/features/devices/data/adb_service.dart';
import 'package:fcm_studio/features/devices/data/recent_packages_repository.dart';
import 'package:fcm_studio/features/devices/domain/device_token.dart';
import 'package:fcm_studio/features/devices/domain/token_read_results.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

export 'package:fcm_studio/features/devices/cubit/token_reader_state.dart';

/// Reads an app's FCM token from the selected phone (spec §9.3): `run-as`
/// for debug builds, then logcat for release builds once the user agrees.
class TokenReaderCubit extends Cubit<TokenReaderState> {
  TokenReaderCubit({required this._serviceFor, required this._recent})
    : super(const TokenReaderState());

  final AdbService Function(String adbPath) _serviceFor;
  final RecentPackagesRepository _recent;
  AdbService? _service;
  StreamSubscription<LogcatProgress>? _logcat;
  Completer<void>? _logcatDone;

  Future<void> openDevice(String adbPath, String serial) async {
    await _cancelLogcat();
    _service = _serviceFor(adbPath);
    emit(TokenReaderState(serial: serial));
    await refreshPackages();
  }

  Future<void> refreshPackages() async {
    final service = _service;
    final serial = state.serial;
    if (service == null || serial == null) {
      return;
    }
    emit(
      state.copyWith(
        packagesStatus: PackagesStatus.loading,
        packagesError: () => null,
      ),
    );
    try {
      final installed = await service.listPackages(serial);
      final recent = await _recent.recent(serial);
      if (isClosed || state.serial != serial) {
        return;
      }
      emit(
        state.copyWith(
          packagesStatus: PackagesStatus.ready,
          installed: installed,
          recent: recent,
        ),
      );
    } on AdbException catch (e) {
      if (isClosed || state.serial != serial) {
        return;
      }
      emit(
        state.copyWith(
          packagesStatus: PackagesStatus.failed,
          packagesError: () => e.message,
        ),
      );
    }
  }

  void search(String query) => emit(state.copyWith(query: query));

  /// Step 1: `run-as` (debug builds).
  Future<void> readToken(String package, {String? projectNumber}) async {
    final service = _service;
    final serial = state.serial;
    if (service == null || serial == null || state.isBusy) {
      return;
    }
    emit(state.copyWith(read: TokenReading(package)));
    final result = await service.readTokenWithRunAs(serial, package);
    if (isClosed || state.serial != serial) {
      return;
    }
    final read = switch (result) {
      RunAsTokens(:final tokens) => TokenReadFound(
        package,
        tokens: tokens,
        method: TokenReadMethod.runAs,
        preselectedSenderId: _preselect(tokens, projectNumber),
      ),
      RunAsReleaseBuild() => TokenReadReleaseBuild(package),
      RunAsNoTokenYet() => TokenReadNoTokenYet(package),
      RunAsNotInstalled() => TokenReadNotInstalled(package),
      RunAsFailed(:final message) => TokenReadFailed(package, message),
    };
    emit(state.copyWith(read: read));
    if (read is TokenReadFound) {
      await _remember(serial, package);
    }
  }

  /// Step 2 (release builds). Restarts the app, so only after the user
  /// confirmed. Completes when the step ends.
  Future<void> readTokenFromLogcat(String package) async {
    final service = _service;
    final serial = state.serial;
    if (service == null || serial == null || state.isBusy) {
      return;
    }
    await _cancelLogcat();
    emit(
      state.copyWith(
        read: TokenReadWatchingLogcat(package, const LogcatRestartingApp()),
      ),
    );
    final done = _logcatDone = Completer<void>();
    _logcat = service.readTokenFromLogcat(serial, package).listen(
      (progress) {
        if (isClosed || state.serial != serial) {
          return;
        }
        final read = switch (progress) {
          LogcatFound(:final token) => TokenReadFound(
            package,
            tokens: [FoundToken(token: token)],
            method: TokenReadMethod.logcat,
          ),
          LogcatNoToken() => TokenReadLogcatNoToken(package),
          LogcatAppDidNotStart() => TokenReadAppDidNotStart(package),
          LogcatFailed(:final message) => TokenReadFailed(package, message),
          LogcatRestartingApp() || LogcatWaitingForApp() || LogcatWatching() =>
            TokenReadWatchingLogcat(package, progress),
        };
        emit(state.copyWith(read: read));
        if (read is TokenReadFound) {
          unawaited(_remember(serial, package));
        }
      },
      onDone: () {
        if (!done.isCompleted) {
          done.complete();
        }
      },
    );
    await done.future;
  }

  Future<void> launchApp(String package) async {
    final service = _service;
    final serial = state.serial;
    if (service == null || serial == null) {
      return;
    }
    try {
      await service.launchApp(serial, package);
    } on AdbException catch (e) {
      if (!isClosed) {
        emit(state.copyWith(read: TokenReadFailed(package, e.message)));
      }
    }
  }

  /// Back to the package list.
  void dismiss() => emit(state.copyWith(read: const TokenReadIdle()));

  static String? _preselect(List<FoundToken> tokens, String? projectNumber) {
    for (final token in tokens) {
      if (projectNumber != null && token.senderId == projectNumber) {
        return token.senderId;
      }
    }
    return tokens.length == 1 ? tokens.single.senderId : null;
  }

  Future<void> _remember(String serial, String package) async {
    await _recent.remember(serial, package);
    final recent = await _recent.recent(serial);
    if (!isClosed && state.serial == serial) {
      emit(state.copyWith(recent: recent));
    }
  }

  Future<void> _cancelLogcat() async {
    final subscription = _logcat;
    _logcat = null;
    await subscription?.cancel();
    final done = _logcatDone;
    _logcatDone = null;
    if (done != null && !done.isCompleted) {
      done.complete();
    }
  }

  @override
  Future<void> close() async {
    await _cancelLogcat();
    return super.close();
  }
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `flutter test test/features/devices/recent_packages_test.dart test/features/devices/token_reader_cubit_test.dart`
Expected: PASS (2 + 9 tests). Then `flutter analyze` (No issues found!).

- [ ] **Step 5: Commit**

```bash
dart format lib test
git add lib/features/devices/domain/package_order.dart lib/features/devices/data/recent_packages_repository.dart lib/features/devices/cubit test/features/devices/recent_packages_test.dart test/features/devices/token_reader_cubit_test.dart
git commit -m "feat: read an app's token with run-as, falling back to logcat"
```

---

### Task 9: Device targets and the sender-ID check

**Files:**
- Create: `lib/features/composer/domain/sender_check.dart`
- Modify: `lib/features/targets/cubit/targets_cubit.dart`
- Test: `test/features/composer/sender_check_test.dart`, `test/features/targets/targets_cubit_test.dart`

**Interfaces:**
- Consumes: `DeviceToken` (Task 4); `SavedTarget`, `TargetSource`, `TargetSourceKind`, `TargetsRepository` (existing); `Project` (existing); `TokenTarget` (existing).
- Produces:
  - `TargetsCubit.saveDeviceToken(DeviceToken token, {String? projectId}) → Future<SavedTarget>`. It upserts by `(serial, package)`: the label is `token.label` and the source is `TargetSource(kind: device, serial, model: deviceName, package)`. It keeps the old `projectId` when none is given.
  - `class SenderMismatch({required String senderId, required Project project, Project? switchTo})` with `message`.
  - `abstract final class SenderCheck` with `static SenderMismatch? check({required String? senderId, required Project? project, required List<Project> projects})`.

- [ ] **Step 1: Write the failing tests**

`test/features/composer/sender_check_test.dart`:
```dart
import 'package:fcm_studio/features/composer/domain/sender_check.dart';
import 'package:fcm_studio/features/projects/domain/project.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const demo = Project(
    id: 'demo-project',
    displayName: 'Demo Project',
    projectNumber: '123456789012',
    credential: ServiceAccountRef('a@demo-project.iam.gserviceaccount.com'),
  );
  const other = Project(
    id: 'other-project',
    displayName: 'Other',
    projectNumber: '999000999000',
    credential: ServiceAccountRef('b@other-project.iam.gserviceaccount.com'),
  );
  const noNumber = Project(
    id: 'no-number',
    displayName: 'no-number',
    credential: ServiceAccountRef('c@no-number.iam.gserviceaccount.com'),
  );

  test('no warning when a number is unknown or the numbers match', () {
    expect(
      SenderCheck.check(senderId: null, project: demo, projects: const [demo]),
      isNull,
    );
    expect(
      SenderCheck.check(senderId: '999', project: noNumber, projects: const [noNumber]),
      isNull,
    );
    expect(
      SenderCheck.check(senderId: '123456789012', project: demo, projects: const [demo]),
      isNull,
    );
    expect(
      SenderCheck.check(senderId: '999', project: null, projects: const []),
      isNull,
    );
  });

  test('warns in the spec wording and offers the project the token belongs to', () {
    final mismatch = SenderCheck.check(
      senderId: '999000999000',
      project: demo,
      projects: const [demo, other],
    )!;
    expect(
      mismatch.message,
      'This token belongs to project number 999000999000, '
      'not Demo Project (demo-project).',
    );
    expect(mismatch.switchTo, other);
  });

  test('offers no switch when no saved project has that number', () {
    expect(
      SenderCheck.check(
        senderId: '555',
        project: demo,
        projects: const [demo],
      )!.switchTo,
      isNull,
    );
  });
}
```

Add to `test/features/targets/targets_cubit_test.dart`. The imports are `package:fcm_studio/features/devices/domain/device_token.dart` and `'../../helpers/device_fixtures.dart'`, and the test uses the file's existing `loaded()` helper and `clock`:
```dart
  test('a token read from a phone is saved once per phone and app, then updated', () async {
    final cubit = await loaded();
    DeviceToken read(String token) => DeviceToken(
      token: token,
      senderId: '123456789012',
      method: TokenReadMethod.runAs,
      readAt: clock.now(),
      serial: redmiSerial,
      package: 'com.syldel.delivery',
      deviceName: 'Redmi 14C',
    );

    final first = await cubit.saveDeviceToken(
      read(fakeDeviceToken),
      projectId: 'demo-project',
    );
    expect(first.label, 'Redmi 14C · com.syldel.delivery (debug)');
    expect(first.kind, TargetKind.token);
    expect(first.value, fakeDeviceToken);
    expect(first.senderId, '123456789012');
    expect(first.projectId, 'demo-project');
    expect(
      first.source,
      const TargetSource(
        kind: TargetSourceKind.device,
        serial: redmiSerial,
        model: 'Redmi 14C',
        package: 'com.syldel.delivery',
      ),
    );

    final second = await cubit.saveDeviceToken(read(otherDeviceToken));
    expect(second.id, first.id);
    expect(cubit.state.targets.single.value, otherDeviceToken);
    expect(
      cubit.state.targets.single.projectId,
      'demo-project',
      reason: 'kept when no project is given',
    );
  });
```

- [ ] **Step 2: Run them to see them fail**

Run: `flutter test test/features/composer/sender_check_test.dart test/features/targets/targets_cubit_test.dart`
Expected: FAIL, compilation errors.

- [ ] **Step 3: Implement**

`lib/features/composer/domain/sender_check.dart`:
```dart
import 'package:equatable/equatable.dart';
import 'package:fcm_studio/features/projects/domain/project.dart';

/// A token that belongs to a different Firebase project than the selected
/// one (spec §7.1).
class SenderMismatch extends Equatable {
  const SenderMismatch({
    required this.senderId,
    required this.project,
    this.switchTo,
  });

  final String senderId;
  final Project project;

  /// A saved project whose number is [senderId], for "Switch project".
  final Project? switchTo;

  String get message =>
      'This token belongs to project number $senderId, not ${project.label}.';

  @override
  List<Object?> get props => [senderId, project, switchTo];
}

abstract final class SenderCheck {
  /// Null unless both numbers are known and differ.
  static SenderMismatch? check({
    required String? senderId,
    required Project? project,
    required List<Project> projects,
  }) {
    final number = project?.projectNumber;
    if (senderId == null ||
        project == null ||
        number == null ||
        senderId == number) {
      return null;
    }
    return SenderMismatch(
      senderId: senderId,
      project: project,
      switchTo: projects.where((p) => p.projectNumber == senderId).firstOrNull,
    );
  }
}
```

In `lib/features/targets/cubit/targets_cubit.dart`, add the import `package:fcm_studio/features/devices/domain/device_token.dart` and this method after `save`:
```dart
  /// Saves a token read from a phone (spec §7.1). Keyed by phone and app, so
  /// reading the same app's token again updates the saved target.
  Future<SavedTarget> saveDeviceToken(
    DeviceToken token, {
    String? projectId,
  }) async {
    final existing = (await _repository.loadAll())
        .where(
          (t) =>
              t.source.kind == TargetSourceKind.device &&
              t.source.serial == token.serial &&
              t.source.package == token.package,
        )
        .firstOrNull;
    final saved = SavedTarget(
      id: existing?.id ?? _newId(),
      label: token.label,
      kind: TargetKind.token,
      value: TokenTarget(token.token).normalized,
      projectId: projectId ?? existing?.projectId,
      senderId: token.senderId,
      source: TargetSource(
        kind: TargetSourceKind.device,
        serial: token.serial,
        model: token.deviceName,
        package: token.package,
      ),
      lastUsedAt: _clock.now(),
    );
    await _repository.save(saved);
    await load();
    return saved;
  }
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `flutter test test/features/composer/sender_check_test.dart test/features/targets/targets_cubit_test.dart`
Expected: PASS. Then `flutter analyze` (No issues found!).

- [ ] **Step 5: Commit**

```bash
dart format lib test
git add lib/features/composer/domain/sender_check.dart lib/features/targets/cubit/targets_cubit.dart test/features/composer/sender_check_test.dart test/features/targets/targets_cubit_test.dart
git commit -m "feat: save phone tokens as device targets and check their sender ID"
```

---


### Task 10: Wire adb into the app

**Files:**
- Create: `lib/core/platform/platform_capabilities.dart`
- Modify: `lib/app/dependencies.dart`, `lib/app/app.dart`, `test/helpers/app_harness.dart`, `test/app/app_test.dart`

**Interfaces:**
- Consumes: Tasks 2–9.
- Produces:
  - `class PlatformFeatures({required bool canRunAdb})` with `static const current` (`canRunAdb: !kIsWeb`), provided to the widget tree as a `RepositoryProvider<PlatformFeatures>`.
  - `AppDependencies` takes `PlatformFeatures platform = PlatformFeatures.current`, `ProcessRunner? processRunner`, `Map<String, String>? environment`, `bool? isWindows` and `AdbService Function(String adbPath)? adbServiceFor`. It gains the fields `platform`, `settingsRepository`, `recentPackagesRepository`, `adbLocator` and `adbServiceFor`.
  - `FcmStudioApp` provides `AdbSetupCubit` (`locate()` at startup, desktop only), `DevicesBloc` and `TokenReaderCubit`, and forwards every change of `AdbSetupState.adbPath` to `DevicesBloc` as `DevicesAdbChanged`.
  - Test harness: `buildTestDependencies(tester, {client, files, ProcessRunner? processRunner, Map<String, String>? environment, FakeAdbService? adb, PlatformFeatures platform})`. With `adb` set, adb is "found" at `fakeAdbPath` and every adb call goes to the fake. `pumpAppWithProject` also takes `FakeAdbService? adb` and `ProcessRunner? processRunner`. `readCubit<T extends BlocBase<Object?>>` now works for blocs too. Without `adb`, widget tests never run a real program: the default runner is an unscripted `FakeProcessRunner`.

- [ ] **Step 1: Write the failing tests.** Add these imports to `test/app/app_test.dart`:
```dart
import 'package:fcm_studio/core/platform/platform_capabilities.dart';
import 'package:fcm_studio/features/devices/bloc/devices_bloc.dart';
import 'package:fcm_studio/features/settings/cubit/adb_setup_cubit.dart';

import '../helpers/fake_adb_service.dart';
import '../helpers/fake_process_runner.dart';
```
and these tests at the end of `main()`:
```dart
  testWidgets('adb found at startup starts tracking phones', (tester) async {
    final adb = FakeAdbService();
    await pumpApp(tester, await buildTestDependencies(tester, adb: adb));
    expect(readCubit<AdbSetupCubit>(tester).state.adbPath, fakeAdbPath);
    expect(adb.trackers, hasLength(1));
  });

  testWidgets('without adb the app works and nothing is tracked', (tester) async {
    await pumpApp(tester, await buildTestDependencies(tester));
    expect(readCubit<AdbSetupCubit>(tester).state.status, AdbStatus.notFound);
    expect(readCubit<DevicesBloc>(tester).state.status, TrackerStatus.noAdb);
    expect(find.text('No projects yet. Add one with a service account key.'), findsOneWidget);
  });

  testWidgets('on the web adb is never looked for', (tester) async {
    final runner = FakeProcessRunner();
    await pumpApp(
      tester,
      await buildTestDependencies(
        tester,
        processRunner: runner,
        platform: const PlatformFeatures(canRunAdb: false),
      ),
    );
    expect(readCubit<AdbSetupCubit>(tester).state.status, AdbStatus.unknown);
    expect(runner.calls, isEmpty);
  });
```

- [ ] **Step 2: Run them to see them fail**

Run: `flutter test test/app/app_test.dart`
Expected: FAIL, compilation errors.

- [ ] **Step 3: Implement**

`lib/core/platform/platform_capabilities.dart`:
```dart
import 'package:flutter/foundation.dart';

/// What this platform can do (spec §3.1). The device features need a
/// desktop: browsers can't run adb.
class PlatformFeatures {
  const PlatformFeatures({required this.canRunAdb});

  static const PlatformFeatures current = PlatformFeatures(canRunAdb: !kIsWeb);

  final bool canRunAdb;
}
```

Replace `lib/app/dependencies.dart` with:
```dart
import 'package:fcm_studio/core/fcm/fcm_client.dart';
import 'package:fcm_studio/core/firebase/firebase_projects_api.dart';
import 'package:fcm_studio/core/platform/file_access.dart';
import 'package:fcm_studio/core/platform/platform_capabilities.dart';
import 'package:fcm_studio/core/storage/app_database.dart';
import 'package:fcm_studio/core/storage/secret_store.dart';
import 'package:fcm_studio/core/utils/clock.dart';
import 'package:fcm_studio/features/composer/data/message_sender.dart';
import 'package:fcm_studio/features/devices/data/adb_locator.dart';
import 'package:fcm_studio/features/devices/data/adb_service.dart';
import 'package:fcm_studio/features/devices/data/process_runner.dart';
import 'package:fcm_studio/features/devices/data/process_runner_platform.dart';
import 'package:fcm_studio/features/devices/data/recent_packages_repository.dart';
import 'package:fcm_studio/features/history/data/history_repository.dart';
import 'package:fcm_studio/features/presets/data/presets_repository.dart';
import 'package:fcm_studio/features/projects/data/project_auth_registry.dart';
import 'package:fcm_studio/features/projects/data/projects_repository.dart';
import 'package:fcm_studio/features/settings/data/settings_repository.dart';
import 'package:fcm_studio/features/targets/data/targets_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

/// Every long-lived service, created once at startup.
class AppDependencies {
  factory AppDependencies({
    required http.Client httpClient,
    required AppDatabase database,
    required SecretStore secrets,
    Clock clock = const SystemClock(),
    FileAccess files = const PlatformFileAccess(),
    Future<String> Function()? loadBuiltInPresets,
    PlatformFeatures platform = PlatformFeatures.current,
    ProcessRunner? processRunner,
    Map<String, String>? environment,
    bool? isWindows,
    AdbService Function(String adbPath)? adbServiceFor,
  }) {
    final projectsRepository = ProjectsRepository(
      database: database,
      secrets: secrets,
    );
    final authRegistry = ProjectAuthRegistry(
      repository: projectsRepository,
      httpClient: httpClient,
      clock: clock,
    );
    final historyRepository = HistoryRepository(database: database);
    final targetsRepository = TargetsRepository(database: database);
    final runner = processRunner ?? createProcessRunner();
    return AppDependencies._(
      httpClient: httpClient,
      database: database,
      clock: clock,
      files: files,
      platform: platform,
      projectsRepository: projectsRepository,
      authRegistry: authRegistry,
      firebaseProjectsApi: FirebaseProjectsApi(httpClient: httpClient),
      presetsRepository: PresetsRepository(
        database: database,
        loadBuiltInJson:
            loadBuiltInPresets ??
            () => rootBundle.loadString(PresetsRepository.builtInAsset),
      ),
      historyRepository: historyRepository,
      targetsRepository: targetsRepository,
      messageSender: MessageSender(
        fcmClient: FcmClient(httpClient: httpClient),
        auth: authRegistry,
        history: historyRepository,
        targets: targetsRepository,
        clock: clock,
      ),
      settingsRepository: SettingsRepository(database: database),
      recentPackagesRepository: RecentPackagesRepository(database: database),
      adbLocator: AdbLocator(
        runner: runner,
        environment: environment ?? platformEnvironment(),
        isWindows: isWindows ?? platformIsWindows(),
      ),
      adbServiceFor:
          adbServiceFor ??
          (path) => ProcessAdbService(runner: runner, adbPath: path),
    );
  }

  AppDependencies._({
    required this.httpClient,
    required this.database,
    required this.clock,
    required this.files,
    required this.platform,
    required this.projectsRepository,
    required this.authRegistry,
    required this.firebaseProjectsApi,
    required this.presetsRepository,
    required this.historyRepository,
    required this.targetsRepository,
    required this.messageSender,
    required this.settingsRepository,
    required this.recentPackagesRepository,
    required this.adbLocator,
    required this.adbServiceFor,
  });

  static Future<AppDependencies> create() async => AppDependencies(
    httpClient: http.Client(),
    database: await AppDatabase.open(),
    // On web, keys stay in memory unless the user ticks "Remember on this browser".
    secrets: LayeredSecretStore(
      persistent: FlutterSecureSecretStore(),
      alwaysPersist: !kIsWeb,
    ),
  );

  final http.Client httpClient;
  final AppDatabase database;
  final Clock clock;
  final FileAccess files;
  final PlatformFeatures platform;
  final ProjectsRepository projectsRepository;
  final ProjectAuthRegistry authRegistry;
  final FirebaseProjectsApi firebaseProjectsApi;
  final PresetsRepository presetsRepository;
  final HistoryRepository historyRepository;
  final TargetsRepository targetsRepository;
  final MessageSender messageSender;
  final SettingsRepository settingsRepository;
  final RecentPackagesRepository recentPackagesRepository;
  final AdbLocator adbLocator;
  final AdbService Function(String adbPath) adbServiceFor;
}
```

Replace `lib/app/app.dart` with:
```dart
import 'package:fcm_studio/app/app_error_banner.dart';
import 'package:fcm_studio/app/app_error_cubit.dart';
import 'package:fcm_studio/app/dependencies.dart';
import 'package:fcm_studio/app/navigation_cubit.dart';
import 'package:fcm_studio/app/shell.dart';
import 'package:fcm_studio/app/theme.dart';
import 'package:fcm_studio/core/platform/file_access.dart';
import 'package:fcm_studio/core/platform/platform_capabilities.dart';
import 'package:fcm_studio/features/composer/cubit/composer_cubit.dart';
import 'package:fcm_studio/features/devices/bloc/devices_bloc.dart';
import 'package:fcm_studio/features/devices/cubit/token_reader_cubit.dart';
import 'package:fcm_studio/features/history/cubit/history_cubit.dart';
import 'package:fcm_studio/features/presets/cubit/presets_cubit.dart';
import 'package:fcm_studio/features/projects/cubit/projects_cubit.dart';
import 'package:fcm_studio/features/settings/cubit/adb_setup_cubit.dart';
import 'package:fcm_studio/features/targets/cubit/targets_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class FcmStudioApp extends StatelessWidget {
  const FcmStudioApp({required this.dependencies, this.errors, super.key});

  final AppDependencies dependencies;

  /// The error banner's cubit. `main()` passes one that also receives
  /// uncaught errors; otherwise the app makes its own.
  final AppErrorCubit? errors;

  @override
  Widget build(BuildContext context) {
    final errors = this.errors;
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<FileAccess>.value(value: dependencies.files),
        RepositoryProvider<PlatformFeatures>.value(value: dependencies.platform),
      ],
      child: MultiBlocProvider(
        providers: [
          if (errors != null)
            BlocProvider.value(value: errors)
          else
            BlocProvider(create: (_) => AppErrorCubit()),
          BlocProvider(
            create: (_) => ProjectsCubit(
              repository: dependencies.projectsRepository,
              authRegistry: dependencies.authRegistry,
              firebaseApi: dependencies.firebaseProjectsApi,
            )..load(),
          ),
          BlocProvider(
            lazy: false,
            create: (_) => PresetsCubit(
              repository: dependencies.presetsRepository,
              clock: dependencies.clock,
            )..load(),
          ),
          BlocProvider(
            lazy: false,
            create: (_) => TargetsCubit(
              repository: dependencies.targetsRepository,
              clock: dependencies.clock,
            )..load(),
          ),
          BlocProvider(
            lazy: false,
            create: (_) => HistoryCubit(
              repository: dependencies.historyRepository,
              sender: dependencies.messageSender,
            )..load(),
          ),
          BlocProvider(create: (_) => NavigationCubit()),
          BlocProvider(
            create: (_) => ComposerCubit(sender: dependencies.messageSender),
          ),
          BlocProvider(
            lazy: false,
            create: (_) {
              final cubit = AdbSetupCubit(
                locator: dependencies.adbLocator,
                settings: dependencies.settingsRepository,
              );
              // Browsers can't run adb (spec §3.1).
              if (dependencies.platform.canRunAdb) {
                cubit.locate();
              }
              return cubit;
            },
          ),
          BlocProvider(
            lazy: false,
            create: (_) => DevicesBloc(serviceFor: dependencies.adbServiceFor),
          ),
          BlocProvider(
            create: (_) => TokenReaderCubit(
              serviceFor: dependencies.adbServiceFor,
              recent: dependencies.recentPackagesRepository,
            ),
          ),
        ],
        child: BlocListener<AdbSetupCubit, AdbSetupState>(
          // Phones are tracked with whichever adb was found, or not at all.
          listenWhen: (previous, current) =>
              previous.adbPath != current.adbPath,
          listener: (context, state) => context.read<DevicesBloc>().add(
            DevicesAdbChanged(state.adbPath),
          ),
          child: MaterialApp(
            title: 'FCM Studio',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            // The error banner stays above every screen and dialog.
            builder: (context, child) => Column(
              children: [
                const AppErrorBanner(),
                Expanded(child: child ?? const SizedBox.shrink()),
              ],
            ),
            home: const AppShell(),
          ),
        ),
      ),
    );
  }
}
```

`cubit.locate()` is not awaited on purpose: `create` must return the cubit straight away. If the analyzer flags it (`unawaited_futures` only applies inside `async` bodies, so it shouldn't), wrap it in `unawaited(...)` from `dart:async`.

- [ ] **Step 4: Update the test harness.** In `test/helpers/app_harness.dart`:
- add the imports `package:fcm_studio/core/platform/platform_capabilities.dart`, `package:fcm_studio/features/devices/data/process_runner.dart`, `'fake_adb_service.dart'` and `'fake_process_runner.dart'`;
- add `const fakeAdbPath = '/fake/sdk/platform-tools/adb';`;
- replace `buildTestDependencies` with:
```dart
/// Real async work (sembast, RSA signing, MockClient) runs inside
/// `tester.runAsync`. No real program ever runs: without [adb], every
/// command fails as if adb were not installed.
Future<AppDependencies> buildTestDependencies(
  WidgetTester tester, {
  http.Client? client,
  FileAccess? files,
  ProcessRunner? processRunner,
  Map<String, String>? environment,
  FakeAdbService? adb,
  PlatformFeatures platform = const PlatformFeatures(canRunAdb: true),
}) async {
  final database = await tester.runAsync(AppDatabase.inMemory);
  final runner = processRunner ?? FakeProcessRunner();
  if (adb != null && runner is FakeProcessRunner) {
    runner.on(
      '$fakeAdbPath version',
      ok('Android Debug Bridge version 1.0.41\n'),
    );
  }
  return AppDependencies(
    httpClient: client ?? fakeGoogle(),
    database: database!,
    secrets: MemorySecretStore(),
    files: files ?? FakeFileAccess(),
    loadBuiltInPresets: loadBuiltInPresetsFromFile,
    platform: platform,
    processRunner: runner,
    environment:
        environment ??
        (adb == null ? const {} : const {'ANDROID_HOME': '/fake/sdk'}),
    isWindows: false,
    adbServiceFor: adb == null ? null : (_) => adb,
  );
}
```
- change `readCubit` to work for blocs too:
```dart
T readCubit<T extends BlocBase<Object?>>(WidgetTester tester) =>
    BlocProvider.of<T>(
      tester.element(find.byType(ProjectSwitcher, skipOffstage: false)),
    );
```
- give `pumpAppWithProject` two more named parameters, `FakeAdbService? adb` and `ProcessRunner? processRunner`, and pass them to `buildTestDependencies(…, adb: adb, processRunner: processRunner)`.

- [ ] **Step 5: Run the tests and confirm they pass**

Run: `flutter test`
Expected: everything passes, including the 3 new app tests. Then `flutter analyze` (No issues found!) and `flutter build web` (succeeds).

- [ ] **Step 6: Commit**

```bash
dart format lib test
git add lib/core/platform/platform_capabilities.dart lib/app/dependencies.dart lib/app/app.dart test/helpers/app_harness.dart test/app/app_test.dart
git commit -m "feat: find adb at startup and track phones with it"
```

---

### Task 11: The Settings screen, and a rail that adapts to the platform

**Files:**
- Create: `lib/features/settings/view/settings_screen.dart`
- Modify: `lib/app/navigation_cubit.dart`, `lib/app/shell.dart`
- Test: `test/features/settings/settings_screen_test.dart`

**Interfaces:**
- Consumes: `AdbSetupCubit`, `AdbSetupState`, `AdbStatus`, `AdbSource` (Task 5); `PlatformFeatures` (Task 10); `promptForText`, `PromptDialog.fieldKey`/`confirmKey` (existing); harness `buildTestDependencies(processRunner:, platform:)` (Task 10); `FakeProcessRunner`, `ok`.
- Produces:
  - `AppSection` gains `settings`.
  - `AppShell.sectionsFor(PlatformFeatures)` gives the rail's sections in order; Settings is desktop only. The rail label key is `Key('nav-settings')`.
  - `SettingsScreen` with `changeKey` and `automaticKey`.

- [ ] **Step 1: Write the failing tests** `test/features/settings/settings_screen_test.dart`

```dart
import 'package:fcm_studio/app/widgets/prompt_dialog.dart';
import 'package:fcm_studio/core/platform/platform_capabilities.dart';
import 'package:fcm_studio/features/settings/view/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/app_harness.dart';
import '../../helpers/fake_process_runner.dart';

const adbVersion = 'Android Debug Bridge version 1.0.41\n';

void main() {
  Future<void> openSettings(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('nav-settings')));
    await tester.pumpAndSettle();
  }

  testWidgets('shows where adb was found and its version', (tester) async {
    final runner = FakeProcessRunner()
      ..on('/opt/homebrew/bin/adb version', ok(adbVersion));
    await pumpApp(tester, await buildTestDependencies(tester, processRunner: runner));
    await openSettings(tester);
    expect(find.text('/opt/homebrew/bin/adb'), findsOneWidget);
    expect(
      find.text('Android Debug Bridge version 1.0.41 · Homebrew'),
      findsOneWidget,
    );
  });

  testWidgets('shows that adb was not found and where it looked', (tester) async {
    await pumpApp(tester, await buildTestDependencies(tester));
    await openSettings(tester);
    expect(find.text('adb was not found'), findsOneWidget);
    expect(find.textContaining('/opt/homebrew/bin/adb'), findsOneWidget);
  });

  testWidgets('Change… uses the typed path; Find automatically clears it', (tester) async {
    final runner = FakeProcessRunner()
      ..on('/opt/homebrew/bin/adb version', ok(adbVersion))
      ..on('/custom/adb version', ok(adbVersion));
    await pumpApp(tester, await buildTestDependencies(tester, processRunner: runner));
    await openSettings(tester);

    await tester.tap(find.byKey(SettingsScreen.changeKey));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(PromptDialog.fieldKey), '/custom/adb');
    await tester.tap(find.byKey(PromptDialog.confirmKey));
    await settleAsync(tester);
    expect(find.text('/custom/adb'), findsOneWidget);
    expect(find.textContaining('set in Settings'), findsOneWidget);

    await tester.tap(find.byKey(SettingsScreen.automaticKey));
    await settleAsync(tester);
    expect(find.text('/opt/homebrew/bin/adb'), findsOneWidget);
    expect(find.byKey(SettingsScreen.automaticKey), findsNothing);
  });

  testWidgets('a typed path that does not run adb is flagged', (tester) async {
    final runner = FakeProcessRunner()
      ..on('/opt/homebrew/bin/adb version', ok(adbVersion));
    await pumpApp(tester, await buildTestDependencies(tester, processRunner: runner));
    await openSettings(tester);
    await tester.tap(find.byKey(SettingsScreen.changeKey));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(PromptDialog.fieldKey), '/wrong/adb');
    await tester.tap(find.byKey(PromptDialog.confirmKey));
    await settleAsync(tester);
    expect(find.textContaining("/wrong/adb doesn't run adb"), findsOneWidget);
  });

  testWidgets('on the web there is no Settings section', (tester) async {
    await pumpApp(
      tester,
      await buildTestDependencies(
        tester,
        platform: const PlatformFeatures(canRunAdb: false),
      ),
    );
    expect(find.byKey(const Key('nav-settings')), findsNothing);
    expect(find.byKey(const Key('nav-history')), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `flutter test test/features/settings/settings_screen_test.dart`
Expected: FAIL, compilation errors.

- [ ] **Step 3: Implement**

In `lib/app/navigation_cubit.dart`, change the enum to:
```dart
/// The app's screens. The rail shows them in [AppShell.sectionsFor] order.
enum AppSection { composer, presets, targets, history, settings }
```

Replace `lib/app/shell.dart` with:
```dart
import 'package:fcm_studio/app/navigation_cubit.dart';
import 'package:fcm_studio/core/platform/platform_capabilities.dart';
import 'package:fcm_studio/features/composer/view/composer_screen.dart';
import 'package:fcm_studio/features/history/view/history_screen.dart';
import 'package:fcm_studio/features/presets/view/presets_screen.dart';
import 'package:fcm_studio/features/settings/view/settings_screen.dart';
import 'package:fcm_studio/features/targets/view/targets_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// The navigation rail and the screens behind it (spec §3.3). Screens stay
/// alive in an IndexedStack, so switching keeps their state.
class AppShell extends StatelessWidget {
  const AppShell({super.key});

  /// The rail's sections, in order. The adb screens need a desktop (spec §3.1).
  static List<AppSection> sectionsFor(PlatformFeatures platform) => [
    AppSection.composer,
    AppSection.presets,
    AppSection.targets,
    AppSection.history,
    if (platform.canRunAdb) AppSection.settings,
  ];

  @override
  Widget build(BuildContext context) {
    final sections = sectionsFor(context.read<PlatformFeatures>());
    final section = context.watch<NavigationCubit>().state;
    final index = sections.contains(section) ? sections.indexOf(section) : 0;
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: index,
            labelType: NavigationRailLabelType.all,
            onDestinationSelected: (i) =>
                context.read<NavigationCubit>().show(sections[i]),
            destinations: [for (final s in sections) _destination(s)],
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: IndexedStack(
              index: index,
              children: [for (final s in sections) _screen(s)],
            ),
          ),
        ],
      ),
    );
  }

  static NavigationRailDestination _destination(AppSection section) =>
      switch (section) {
        AppSection.composer => const NavigationRailDestination(
          icon: Icon(Icons.send_outlined),
          selectedIcon: Icon(Icons.send),
          label: Text('Composer', key: Key('nav-composer')),
        ),
        AppSection.presets => const NavigationRailDestination(
          icon: Icon(Icons.bookmarks_outlined),
          selectedIcon: Icon(Icons.bookmarks),
          label: Text('Presets', key: Key('nav-presets')),
        ),
        AppSection.targets => const NavigationRailDestination(
          icon: Icon(Icons.star_outline),
          selectedIcon: Icon(Icons.star),
          label: Text('Targets', key: Key('nav-targets')),
        ),
        AppSection.history => const NavigationRailDestination(
          icon: Icon(Icons.history),
          label: Text('History', key: Key('nav-history')),
        ),
        AppSection.settings => const NavigationRailDestination(
          icon: Icon(Icons.settings_outlined),
          selectedIcon: Icon(Icons.settings),
          label: Text('Settings', key: Key('nav-settings')),
        ),
      };

  static Widget _screen(AppSection section) => switch (section) {
    AppSection.composer => const ComposerScreen(),
    AppSection.presets => const PresetsScreen(),
    AppSection.targets => const TargetsScreen(),
    AppSection.history => const HistoryScreen(),
    AppSection.settings => const SettingsScreen(),
  };
}
```

`lib/features/settings/view/settings_screen.dart`:
```dart
import 'package:fcm_studio/app/widgets/prompt_dialog.dart';
import 'package:fcm_studio/features/devices/data/adb_locator.dart';
import 'package:fcm_studio/features/settings/cubit/adb_setup_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Where adb is, with Change… and Find automatically (spec §9.1).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static const changeKey = Key('adb-change');
  static const automaticKey = Key('adb-automatic');

  static String sourceLabel(AdbSource source) => switch (source) {
    AdbSource.settings => 'set in Settings',
    AdbSource.androidHome => 'from ANDROID_HOME',
    AdbSource.androidSdkRoot => 'from ANDROID_SDK_ROOT',
    AdbSource.sdkDefault => 'Android SDK default location',
    AdbSource.homebrew => 'Homebrew',
    AdbSource.usrLocal => '/usr/local/bin',
    AdbSource.path => 'found on PATH',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: BlocBuilder<AdbSetupCubit, AdbSetupState>(
        builder: (context, state) {
          final location = state.location;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Android Debug Bridge (adb)',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                'FCM Studio uses adb to read device tokens from phones over USB.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              switch (state.status) {
                AdbStatus.unknown || AdbStatus.locating => const ListTile(
                  leading: SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  title: Text('Looking for adb…'),
                ),
                AdbStatus.found when location != null => ListTile(
                  leading: const Icon(Icons.check_circle, color: Colors.green),
                  title: SelectableText(location.path),
                  subtitle: Text(
                    '${location.version} · ${sourceLabel(location.source)}',
                  ),
                ),
                _ => ListTile(
                  leading: Icon(Icons.error, color: theme.colorScheme.error),
                  title: const Text('adb was not found'),
                  subtitle: Text(
                    'Install Android SDK Platform-Tools, or set the path to adb. '
                    'Looked in: ${state.tried.join(', ')}',
                  ),
                ),
              },
              if (state.userPathFailed)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    "${state.userPath} doesn't run adb.",
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton(
                    key: changeKey,
                    onPressed: () => _change(context),
                    child: const Text('Change…'),
                  ),
                  if (state.userPath != null)
                    TextButton(
                      key: automaticKey,
                      onPressed: () =>
                          context.read<AdbSetupCubit>().setUserPath(null),
                      child: const Text('Find automatically'),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _change(BuildContext context) async {
    final cubit = context.read<AdbSetupCubit>();
    final path = await promptForText(
      context,
      title: 'Path to adb',
      label: 'Full path to the adb program',
      initial: cubit.state.userPath ?? cubit.state.adbPath ?? '',
      confirmLabel: 'Use',
    );
    if (path != null && path.trim().isNotEmpty) {
      await cubit.setUserPath(path);
    }
  }
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `flutter test test/features/settings test/app`
Expected: PASS (5 new screen tests), and the existing app and navigation tests still pass. Then `flutter test` and `flutter analyze` (No issues found!).

- [ ] **Step 5: Commit**

```bash
dart format lib test
git add lib/features/settings/view lib/app/navigation_cubit.dart lib/app/shell.dart test/features/settings/settings_screen_test.dart
git commit -m "feat: add the Settings screen for the adb path"
```

---

### Task 12: The Devices screen, "From device…", and using a token

**Files:**
- Create: `lib/features/devices/view/devices_screen.dart`, `lib/features/devices/view/token_read_view.dart`, `lib/features/devices/view/device_actions.dart`
- Modify: `lib/app/navigation_cubit.dart`, `lib/app/shell.dart`, `lib/features/composer/view/target_picker.dart`
- Test: `test/features/devices/devices_screen_test.dart`

**Interfaces:**
- Consumes: `DevicesBloc`/`DevicesState`/`DeviceSelected`/`TrackerStatus` (Task 7); `TokenReaderCubit` and the `TokenRead*` states (Task 8); `TargetsCubit.saveDeviceToken` (Task 9); `AdbSetupCubit` (Task 5); `PlatformFeatures` (Task 10); `ComposerCubit.setTarget`, `ProjectsCubit`, `NavigationCubit`, `AppErrorCubit`, `shortenMiddle` (existing); harness `pumpAppWithProject(adb:)` (Task 10).
- Produces:
  - `AppSection` gains `devices`, placed before `settings` in the rail; its label key is `Key('nav-devices')`.
  - `Future<void> useDeviceToken(BuildContext, {required String package, required FoundToken found, required TokenReadMethod method})`. It sets the composer target, saves the device target under the selected project, clears the reader, returns to the composer and shows a snackbar.
  - `DevicesScreen` with `openSettingsKey`. Device tiles are keyed `ValueKey('device-<serial>')`, package tiles `ValueKey('package-<name>')`, the search field `Key('devices-search')` and the restarting row `Key('devices-restarting')`.
  - `TokenReadView` with `useTokenKey`, `readLogsKey`, `confirmLogsKey`, `launchKey` and `retryKey`; sender choices are keyed `ValueKey('sender-<id>')`.
  - `TargetPicker.fromDeviceKey` (desktop only).

- [ ] **Step 1: Write the failing tests** `test/features/devices/devices_screen_test.dart`

```dart
import 'package:fcm_studio/app/navigation_cubit.dart';
import 'package:fcm_studio/features/composer/domain/target.dart';
import 'package:fcm_studio/features/composer/view/target_picker.dart';
import 'package:fcm_studio/features/devices/domain/adb_device.dart';
import 'package:fcm_studio/features/devices/domain/device_token.dart';
import 'package:fcm_studio/features/devices/domain/token_read_results.dart';
import 'package:fcm_studio/features/devices/view/devices_screen.dart';
import 'package:fcm_studio/features/devices/view/token_read_view.dart';
import 'package:fcm_studio/features/targets/cubit/targets_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/app_harness.dart';
import '../../helpers/device_fixtures.dart';
import '../../helpers/fake_adb_service.dart';
import '../../helpers/service_account_fixture.dart';

const app = 'com.syldel.delivery';
const redmi = AdbDevice(
  serial: redmiSerial,
  state: DeviceState.device,
  rawState: 'device',
  model: '2409BRN2CA',
);

void main() {
  late FakeAdbService adb;

  setUp(() {
    adb = FakeAdbService()
      ..details[redmiSerial] = const DeviceDetails(
        name: 'Redmi 14C',
        brand: 'Redmi',
        androidVersion: '16',
      )
      ..packages[redmiSerial] = ['com.alpha', app];
  });

  Future<void> openDevices(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('nav-devices')));
    await tester.pumpAndSettle();
  }

  Future<void> plugIn(WidgetTester tester, List<AdbDevice> devices) async {
    adb.tracker.add(devices);
    await settleAsync(tester);
  }

  testWidgets('without adb, Devices explains and links to Settings', (tester) async {
    await pumpAppWithProject(tester);
    await openDevices(tester);
    expect(find.textContaining('adb was not found'), findsOneWidget);
    await tester.tap(find.byKey(DevicesScreen.openSettingsKey));
    await tester.pumpAndSettle();
    expect(readCubit<NavigationCubit>(tester).state, AppSection.settings);
  });

  testWidgets("an unauthorized phone shows the hint and can't be opened", (tester) async {
    await pumpAppWithProject(tester, adb: adb);
    await openDevices(tester);
    await plugIn(tester, const [
      AdbDevice(serial: 'R58M123ABC', state: DeviceState.unauthorized, rawState: 'unauthorized'),
    ]);
    expect(find.text('Accept the USB debugging prompt on the phone'), findsOneWidget);
    expect(
      tester.widget<ListTile>(find.byKey(const ValueKey('device-R58M123ABC'))).enabled,
      isFalse,
    );
    expect(adb.calls.where((c) => c.startsWith('packages')), isEmpty);
  });

  testWidgets('picking an app makes its token the target, saves it, and returns to the composer', (tester) async {
    adb.runAs[app] = [
      RunAsTokens([FoundToken(token: fakeDeviceToken, senderId: testProjectNumber)]),
    ];
    final (_, composer) = await pumpAppWithProject(tester, adb: adb);
    await openDevices(tester);
    await plugIn(tester, const [redmi]);
    expect(find.text('Redmi 14C'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('package-$app')));
    await settleAsync(tester);

    expect(composer.state.targetKind, TargetKind.token);
    expect(composer.state.targetValue, fakeDeviceToken);
    expect(readCubit<NavigationCubit>(tester).state, AppSection.composer);
    final saved = readCubit<TargetsCubit>(tester).state.targets.single;
    expect(saved.label, 'Redmi 14C · $app (debug)');
    expect(saved.projectId, testProjectId);
    expect(saved.senderId, testProjectNumber);
    expect(find.text('Using the token of Redmi 14C · $app (debug).'), findsOneWidget);
  });

  testWidgets("several projects in the file: the selected project's is preselected", (tester) async {
    adb.runAs[app] = [
      RunAsTokens([
        FoundToken(token: fakeDeviceToken, senderId: testProjectNumber),
        FoundToken(token: otherDeviceToken, senderId: '999000999000'),
      ]),
    ];
    final (_, composer) = await pumpAppWithProject(tester, adb: adb);
    await openDevices(tester);
    await plugIn(tester, const [redmi]);
    await tester.tap(find.byKey(const ValueKey('package-$app')));
    await settleAsync(tester);

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('sender-$testProjectNumber')),
        matching: find.byIcon(Icons.radio_button_checked),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(TokenReadView.useTokenKey));
    await settleAsync(tester);
    expect(composer.state.targetValue, fakeDeviceToken);
  });

  testWidgets('a release build: confirm, restart the app and read its log', (tester) async {
    adb.runAs[app] = [const RunAsReleaseBuild()];
    adb.logcat[app] = [
      const LogcatRestartingApp(),
      const LogcatWaitingForApp(),
      const LogcatWatching(4242),
      LogcatFound(fakeDeviceToken),
    ];
    final (_, composer) = await pumpAppWithProject(tester, adb: adb);
    await openDevices(tester);
    await plugIn(tester, const [redmi]);
    await tester.tap(find.byKey(const ValueKey('package-$app')));
    await settleAsync(tester);
    expect(find.textContaining('is a release build'), findsOneWidget);
    expect(adb.calls.where((c) => c.startsWith('logcat')), isEmpty);

    await tester.tap(find.byKey(TokenReadView.readLogsKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(TokenReadView.confirmLogsKey));
    await settleAsync(tester);

    expect(composer.state.targetValue, fakeDeviceToken);
    expect(
      readCubit<TargetsCubit>(tester).state.targets.single.label,
      'Redmi 14C · $app (release)',
    );
  });

  testWidgets('an app that was never opened offers Launch app and Retry', (tester) async {
    adb.runAs[app] = [
      const RunAsNoTokenYet(),
      RunAsTokens([FoundToken(token: fakeDeviceToken, senderId: testProjectNumber)]),
    ];
    final (_, composer) = await pumpAppWithProject(tester, adb: adb);
    await openDevices(tester);
    await plugIn(tester, const [redmi]);
    await tester.tap(find.byKey(const ValueKey('package-$app')));
    await settleAsync(tester);
    expect(find.text('Open the app once so it gets a token.'), findsOneWidget);

    await tester.tap(find.byKey(TokenReadView.launchKey));
    await settleAsync(tester);
    expect(adb.calls, contains('launch $redmiSerial $app'));
    await tester.tap(find.byKey(TokenReadView.retryKey));
    await settleAsync(tester);
    expect(composer.state.targetValue, fakeDeviceToken);
  });

  testWidgets('From device… opens the Devices screen', (tester) async {
    await pumpAppWithProject(tester, adb: adb);
    await tester.tap(find.byKey(TargetPicker.fromDeviceKey));
    await tester.pumpAndSettle();
    expect(readCubit<NavigationCubit>(tester).state, AppSection.devices);
  });

  testWidgets('when adb stops, the screen says it will try again', (tester) async {
    await pumpAppWithProject(tester, adb: adb);
    await openDevices(tester);
    await adb.tracker.close();
    await settleAsync(tester);
    expect(find.byKey(const Key('devices-restarting')), findsOneWidget);
    // Let the 1-second restart timer fire, so no timer is left pending.
    await tester.pump(const Duration(seconds: 2));
    await settleAsync(tester);
    expect(adb.trackers, hasLength(2));
  });
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `flutter test test/features/devices/devices_screen_test.dart`
Expected: FAIL, compilation errors.

- [ ] **Step 3: Add the Devices section.** In `lib/app/navigation_cubit.dart`:
```dart
enum AppSection { composer, presets, targets, history, devices, settings }
```
In `lib/app/shell.dart`:
- import `package:fcm_studio/features/devices/view/devices_screen.dart`;
- in `sectionsFor`, add `if (platform.canRunAdb) AppSection.devices,` before the settings line;
- add to `_destination`:
```dart
        AppSection.devices => const NavigationRailDestination(
          icon: Icon(Icons.phone_android_outlined),
          selectedIcon: Icon(Icons.phone_android),
          label: Text('Devices', key: Key('nav-devices')),
        ),
```
- add to `_screen`: `AppSection.devices => const DevicesScreen(),`.

- [ ] **Step 4: Implement the action and the screen**

`lib/features/devices/view/device_actions.dart`:
```dart
import 'package:fcm_studio/app/app_error_cubit.dart';
import 'package:fcm_studio/app/navigation_cubit.dart';
import 'package:fcm_studio/features/composer/cubit/composer_cubit.dart';
import 'package:fcm_studio/features/composer/domain/target.dart';
import 'package:fcm_studio/features/devices/bloc/devices_bloc.dart';
import 'package:fcm_studio/features/devices/cubit/token_reader_cubit.dart';
import 'package:fcm_studio/features/devices/domain/device_token.dart';
import 'package:fcm_studio/features/projects/cubit/projects_cubit.dart';
import 'package:fcm_studio/features/targets/cubit/targets_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Uses a token read from the phone (spec §9.3 "Result"): it becomes the
/// composer's target and is saved as a device target, and the composer is
/// shown again.
Future<void> useDeviceToken(
  BuildContext context, {
  required String package,
  required FoundToken found,
  required TokenReadMethod method,
}) async {
  final devices = context.read<DevicesBloc>().state;
  final reader = context.read<TokenReaderCubit>();
  final composer = context.read<ComposerCubit>();
  final targets = context.read<TargetsCubit>();
  final projectId = context.read<ProjectsCubit>().state.selectedId;
  final navigation = context.read<NavigationCubit>();
  final errors = context.read<AppErrorCubit>();
  final messenger = ScaffoldMessenger.of(context);
  final serial = reader.state.serial;
  if (serial == null) {
    return;
  }
  final device = devices.devices.where((d) => d.serial == serial).firstOrNull;
  final token = DeviceToken(
    token: found.token,
    senderId: found.senderId,
    method: method,
    readAt: DateTime.now().toUtc(),
    serial: serial,
    package: package,
    deviceName: device == null ? serial : devices.nameOf(device),
  );
  composer.setTarget(TargetKind.token, token.token);
  reader.dismiss();
  navigation.show(AppSection.composer);
  messenger.showSnackBar(
    SnackBar(content: Text('Using the token of ${token.label}.')),
  );
  try {
    await targets.saveDeviceToken(token, projectId: projectId);
  } catch (e) {
    errors.report(e, context: 'Could not save the device target');
  }
}
```

`lib/features/devices/view/token_read_view.dart`:
```dart
import 'package:fcm_studio/core/utils/shorten.dart';
import 'package:fcm_studio/features/devices/cubit/token_reader_cubit.dart';
import 'package:fcm_studio/features/devices/domain/token_read_results.dart';
import 'package:fcm_studio/features/devices/view/device_actions.dart';
import 'package:fcm_studio/features/projects/cubit/projects_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Where reading a token stands, and what the user can do next (spec §9.3).
class TokenReadView extends StatefulWidget {
  const TokenReadView({required this.read, super.key});

  static const useTokenKey = Key('token-use');
  static const readLogsKey = Key('token-read-logs');
  static const confirmLogsKey = Key('token-confirm-logs');
  static const launchKey = Key('token-launch');
  static const retryKey = Key('token-retry');

  final TokenRead read;

  @override
  State<TokenReadView> createState() => _TokenReadViewState();
}

class _TokenReadViewState extends State<TokenReadView> {
  String? _sender;

  @override
  void initState() {
    super.initState();
    _sender = _preselected(widget.read);
  }

  @override
  void didUpdateWidget(TokenReadView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.read != oldWidget.read) {
      _sender = _preselected(widget.read);
    }
  }

  static String? _preselected(TokenRead read) =>
      read is TokenReadFound ? read.preselectedSenderId : null;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<TokenReaderCubit>();
    String? projectNumber() =>
        context.read<ProjectsCubit>().state.selected?.projectNumber;
    final dismiss = TextButton(
      onPressed: cubit.dismiss,
      child: const Text('OK'),
    );
    return switch (widget.read) {
      TokenReadIdle() => const SizedBox.shrink(),
      TokenReading(:final package) => _Note(
        busy: true,
        text: 'Reading the token of $package…',
      ),
      TokenReadFound(:final package, :final tokens, :final method)
          when tokens.length > 1 =>
        _Card(
          children: [
            Text('$package has tokens for several Firebase projects. Pick one:'),
            for (final token in tokens)
              ListTile(
                key: ValueKey('sender-${token.senderId}'),
                dense: true,
                leading: Icon(
                  token.senderId == _sender
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                ),
                title: Text('Project number ${token.senderId ?? 'unknown'}'),
                subtitle: Text(shortenMiddle(token.token)),
                onTap: () => setState(() => _sender = token.senderId),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                key: TokenReadView.useTokenKey,
                onPressed: tokens.any((t) => t.senderId == _sender)
                    ? () => useDeviceToken(
                        context,
                        package: package,
                        found: tokens.firstWhere((t) => t.senderId == _sender),
                        method: method,
                      )
                    : null,
                child: const Text('Use this token'),
              ),
            ),
          ],
        ),
      TokenReadFound(:final package) => _Note(
        text: 'Using the token of $package.',
      ),
      TokenReadReleaseBuild(:final package) => _Card(
        children: [
          Text("$package is a release build, so its files can't be read."),
          const SizedBox(height: 4),
          const Text(
            'FCM Studio can restart the app and look for its token in the log. '
            'This works only if the app logs its token.',
          ),
          Wrap(
            spacing: 8,
            children: [
              FilledButton(
                key: TokenReadView.readLogsKey,
                onPressed: () => _confirmLogcat(context, package),
                child: const Text('Restart the app and read its log…'),
              ),
              dismiss,
            ],
          ),
        ],
      ),
      TokenReadNoTokenYet(:final package) => _Card(
        children: [
          const Text('Open the app once so it gets a token.'),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton(
                key: TokenReadView.launchKey,
                onPressed: () => cubit.launchApp(package),
                child: const Text('Launch app'),
              ),
              FilledButton(
                key: TokenReadView.retryKey,
                onPressed: () =>
                    cubit.readToken(package, projectNumber: projectNumber()),
                child: const Text('Retry'),
              ),
            ],
          ),
        ],
      ),
      TokenReadNotInstalled(:final package) => _Card(
        error: true,
        children: [Text('$package is not installed on this phone.'), dismiss],
      ),
      TokenReadWatchingLogcat(:final progress) => _Note(
        busy: true,
        text: switch (progress) {
          LogcatRestartingApp() => 'Restarting the app…',
          LogcatWaitingForApp() => 'Waiting for the app to start…',
          _ => "Watching the app's log for its token…",
        },
      ),
      TokenReadLogcatNoToken(:final package) => _Card(
        error: true,
        children: [
          Text(
            "$package didn't print its token within 20 seconds. Use a debug "
            'build, or add a debug-only log line that prints the token.',
          ),
          dismiss,
        ],
      ),
      TokenReadAppDidNotStart(:final package) => _Card(
        error: true,
        children: [
          Text("$package didn't start within 10 seconds."),
          Wrap(
            spacing: 8,
            children: [
              FilledButton(
                key: TokenReadView.retryKey,
                onPressed: () => cubit.readTokenFromLogcat(package),
                child: const Text('Retry'),
              ),
              dismiss,
            ],
          ),
        ],
      ),
      TokenReadFailed(:final message) => _Card(
        error: true,
        children: [SelectableText(message), dismiss],
      ),
    };
  }

  /// Logcat restarts the app, so it runs only after the user agrees (spec §9.3).
  Future<void> _confirmLogcat(BuildContext context, String package) async {
    final cubit = context.read<TokenReaderCubit>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restart the app?'),
        content: Text(
          '$package will be closed and opened again on the phone, and its log '
          'watched for up to 20 seconds. Nothing is cleared from the log.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: TokenReadView.confirmLogsKey,
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Restart and read'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await cubit.readTokenFromLogcat(package);
    }
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text, this.busy = false});

  final String text;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: busy
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.check_circle, color: Colors.green),
      title: Text(text),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.children, this.error = false});

  final bool error;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: error ? scheme.errorContainer : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }
}
```

`lib/features/devices/view/devices_screen.dart`:
```dart
import 'package:fcm_studio/app/navigation_cubit.dart';
import 'package:fcm_studio/features/devices/bloc/devices_bloc.dart';
import 'package:fcm_studio/features/devices/cubit/token_reader_cubit.dart';
import 'package:fcm_studio/features/devices/domain/adb_device.dart';
import 'package:fcm_studio/features/devices/domain/device_token.dart';
import 'package:fcm_studio/features/devices/view/device_actions.dart';
import 'package:fcm_studio/features/devices/view/token_read_view.dart';
import 'package:fcm_studio/features/projects/cubit/projects_cubit.dart';
import 'package:fcm_studio/features/settings/cubit/adb_setup_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Plugged-in phones, their apps, and reading an app's token (spec §9).
class DevicesScreen extends StatelessWidget {
  const DevicesScreen({super.key});

  static const openSettingsKey = Key('devices-open-settings');

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

  @override
  Widget build(BuildContext context) {
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
                reader.state.serial != device.serial) {
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
        appBar: AppBar(title: const Text('Devices')),
        body: BlocBuilder<DevicesBloc, DevicesState>(
          builder: (context, state) {
            if (state.status == TrackerStatus.noAdb) {
              return const _NoAdb();
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(width: 320, child: _DeviceList(state: state)),
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

class _DeviceList extends StatelessWidget {
  const _DeviceList({required this.state});

  final DevicesState state;

  static String _stateText(AdbDevice device) => switch (device.state) {
    DeviceState.device => 'Ready',
    DeviceState.unauthorized => 'Accept the USB debugging prompt on the phone',
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
          const ListTile(title: Text('Starting adb…')),
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
          const ListTile(
            leading: Icon(Icons.phone_android),
            title: Text('No phone connected'),
            subtitle: Text('Connect an Android phone with USB debugging turned on.'),
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
            onTap: device.isReady
                ? () => context.read<DevicesBloc>().add(
                    DeviceSelected(device.serial),
                  )
                : null,
          ),
      ],
    );
  }
}

class _DevicePanel extends StatelessWidget {
  const _DevicePanel({required this.state});

  final DevicesState state;

  @override
  Widget build(BuildContext context) {
    if (state.selectedSerial == null) {
      return const Center(child: Text('Select a phone on the left.'));
    }
    final device = state.selected;
    if (device == null || !device.isReady) {
      return const Center(
        child: Text('The phone is disconnected. Plug it in again.'),
      );
    }
    final details = state.details[device.serial];
    return BlocBuilder<TokenReaderCubit, TokenReaderState>(
      builder: (context, reader) {
        final cubit = context.read<TokenReaderCubit>();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              title: Text(
                state.nameOf(device),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              subtitle: Text(
                [
                  if (details != null && details.brand.isNotEmpty) details.brand,
                  if (details != null && details.androidVersion.isNotEmpty)
                    'Android ${details.androidVersion}',
                  device.serial,
                ].join(' · '),
              ),
              trailing: IconButton(
                tooltip: 'Refresh the app list',
                icon: const Icon(Icons.refresh),
                onPressed: cubit.refreshPackages,
              ),
            ),
            TokenReadView(read: reader.read),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                key: const Key('devices-search'),
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search apps',
                  border: OutlineInputBorder(),
                ),
                onChanged: cubit.search,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(child: _PackageList(reader: reader)),
          ],
        );
      },
    );
  }
}

class _PackageList extends StatelessWidget {
  const _PackageList({required this.reader});

  final TokenReaderState reader;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<TokenReaderCubit>();
    switch (reader.packagesStatus) {
      case PackagesStatus.idle || PackagesStatus.loading:
        return const Center(child: CircularProgressIndicator());
      case PackagesStatus.failed:
        return Padding(
          padding: const EdgeInsets.all(16),
          child: SelectableText(reader.packagesError ?? 'Could not list the apps.'),
        );
      case PackagesStatus.ready:
        final packages = reader.packages;
        if (packages.isEmpty) {
          return const Center(child: Text('No apps found.'));
        }
        return ListView(
          children: [
            for (final package in packages)
              ListTile(
                key: ValueKey('package-$package'),
                dense: true,
                enabled: !reader.isBusy,
                title: Text(package),
                trailing: reader.recent.contains(package)
                    ? const Text('recent')
                    : null,
                onTap: () => cubit.readToken(
                  package,
                  projectNumber: context
                      .read<ProjectsCubit>()
                      .state
                      .selected
                      ?.projectNumber,
                ),
              ),
          ],
        );
    }
  }
}
```

- [ ] **Step 5: Add "From device…" to the composer.** In `lib/features/composer/view/target_picker.dart`:
- import `package:fcm_studio/app/navigation_cubit.dart` and `package:fcm_studio/core/platform/platform_capabilities.dart`;
- add `static const fromDeviceKey = Key('target-from-device');` to `TargetPicker`;
- in the header `Row`, insert this before the star `IconButton`:
```dart
              if (context.read<PlatformFeatures>().canRunAdb)
                TextButton.icon(
                  key: TargetPicker.fromDeviceKey,
                  onPressed: () =>
                      context.read<NavigationCubit>().show(AppSection.devices),
                  icon: const Icon(Icons.phone_android, size: 18),
                  label: const Text('From device…'),
                ),
```

- [ ] **Step 6: Run the tests and confirm they pass**

Run: `flutter test test/features/devices test/features/composer test/app`
Expected: PASS, including the 8 new screen tests. Then `flutter test` and `flutter analyze` (No issues found!).

- [ ] **Step 7: Commit**

```bash
dart format lib test
git add lib/features/devices/view lib/app/navigation_cubit.dart lib/app/shell.dart lib/features/composer/view/target_picker.dart test/features/devices/devices_screen_test.dart
git commit -m "feat: read a phone app's token from the Devices screen and use it"
```

---

### Task 13: The sender-ID warning in the composer

**Files:**
- Create: `lib/features/composer/view/sender_warning.dart`
- Modify: `lib/features/composer/view/composer_screen.dart`
- Test: `test/features/composer/sender_warning_test.dart`

**Interfaces:**
- Consumes: `SenderCheck`, `SenderMismatch` (Task 9); `TargetsCubit.state.matching`, `saveDeviceToken` (Task 9); `DeviceToken`, `TokenReadMethod` (Task 4); `ProjectsCubit` (`select`, `setProjectNumber`, `addFromServiceAccount`), `ComposerCubit.setTarget`/`setTargetValue`, `TokenTarget`, `TargetKind` (existing); harness `pumpAppWithProject`, `readCubit`, `settleAsync`; fixtures `serviceAccountJson`, `testProjectId`, `fakeDeviceToken`, `redmiSerial`.
- Produces: `SenderWarning` (keyed `Key('sender-warning')` when shown) with `switchKey`. It is placed under the target picker in the composer's left column.

- [ ] **Step 1: Write the failing tests** `test/features/composer/sender_warning_test.dart`

```dart
import 'package:fcm_studio/features/composer/domain/target.dart';
import 'package:fcm_studio/features/composer/view/sender_warning.dart';
import 'package:fcm_studio/features/devices/domain/device_token.dart';
import 'package:fcm_studio/features/targets/cubit/targets_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/app_harness.dart';
import '../../helpers/device_fixtures.dart';
import '../../helpers/service_account_fixture.dart';

void main() {
  testWidgets('a phone token from another project is flagged, and Switch project fixes it', (tester) async {
    final (projects, composer) = await pumpAppWithProject(tester);
    final targets = readCubit<TargetsCubit>(tester);
    await tester.runAsync(() async {
      await projects.addFromServiceAccount(
        serviceAccountJson(
          projectId: 'other-project',
          clientEmail: 'sender@other-project.iam.gserviceaccount.com',
        ),
        persistKey: true,
      );
      await projects.setProjectNumber('other-project', '999000999000');
      await projects.select(testProjectId);
      await targets.saveDeviceToken(
        DeviceToken(
          token: fakeDeviceToken,
          senderId: '999000999000',
          method: TokenReadMethod.runAs,
          readAt: DateTime.utc(2026, 10, 4),
          serial: redmiSerial,
          package: 'com.syldel.delivery',
          deviceName: 'Redmi 14C',
        ),
        projectId: 'other-project',
      );
    });
    composer.setTarget(TargetKind.token, fakeDeviceToken);
    await tester.pump();

    expect(
      find.text(
        'This token belongs to project number 999000999000, '
        'not Demo Project (demo-project).',
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(SenderWarning.switchKey));
    await settleAsync(tester);
    expect(projects.state.selectedId, 'other-project');
    expect(find.byKey(const Key('sender-warning')), findsNothing);
  });

  testWidgets('a pasted token with no known sender shows no warning', (tester) async {
    final (_, composer) = await pumpAppWithProject(tester);
    composer.setTargetValue(fakeDeviceToken);
    await tester.pump();
    expect(find.byKey(const Key('sender-warning')), findsNothing);
  });
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `flutter test test/features/composer/sender_warning_test.dart`
Expected: FAIL, compilation errors.

- [ ] **Step 3: Implement**

`lib/features/composer/view/sender_warning.dart`:
```dart
import 'package:fcm_studio/features/composer/cubit/composer_cubit.dart';
import 'package:fcm_studio/features/composer/domain/sender_check.dart';
import 'package:fcm_studio/features/composer/domain/target.dart';
import 'package:fcm_studio/features/projects/cubit/projects_cubit.dart';
import 'package:fcm_studio/features/targets/cubit/targets_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Warns when the target token belongs to another Firebase project, and
/// offers to switch to it (spec §7.1). The token's sender ID is known when
/// it was read from a phone.
class SenderWarning extends StatelessWidget {
  const SenderWarning({super.key});

  static const switchKey = Key('sender-switch-project');

  @override
  Widget build(BuildContext context) {
    final target = context.select((ComposerCubit c) => c.state.target);
    final senderId = context.select(
      (TargetsCubit c) =>
          target is TokenTarget ? c.state.matching(target)?.senderId : null,
    );
    final projects = context.watch<ProjectsCubit>().state;
    final mismatch = SenderCheck.check(
      senderId: senderId,
      project: projects.selected,
      projects: projects.projects,
    );
    if (mismatch == null) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    return Card(
      key: const Key('sender-warning'),
      margin: const EdgeInsets.only(top: 12),
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber, color: scheme.onErrorContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    mismatch.message,
                    style: TextStyle(color: scheme.onErrorContainer),
                  ),
                ),
              ],
            ),
            if (mismatch.switchTo case final project?)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  key: switchKey,
                  onPressed: () =>
                      context.read<ProjectsCubit>().select(project.id),
                  child: Text('Switch to ${project.label}'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
```

In `lib/features/composer/view/composer_screen.dart`, import `package:fcm_studio/features/composer/view/sender_warning.dart` and make `_SetupPane`'s children:
```dart
      children: const [
        ProjectSwitcher(),
        SizedBox(height: 24),
        TargetPicker(),
        SenderWarning(),
        SizedBox(height: 24),
        PresetPicker(),
      ],
```

If the analyzer asks for `?mismatch.switchTo`-style elements (`use_null_aware_elements`), keep the `if (… case final project?)` form here: the element is a widget built from `project`, not `project` itself, so the null-aware form doesn't apply.

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `flutter test test/features/composer`
Expected: PASS. Then `flutter test` and `flutter analyze` (No issues found!).

- [ ] **Step 5: Commit**

```bash
dart format lib test
git add lib/features/composer/view/sender_warning.dart lib/features/composer/view/composer_screen.dart test/features/composer/sender_warning_test.dart
git commit -m "feat: warn when a phone token belongs to another project"
```

---

### Task 14: Builds, the M3 success test, and the spec

Steps 3 and 4 need the user, because they need the phone and a person at it. An agent does Steps 1, 2 and 5 and records Steps 3–4 as pending.

**Files:**
- Modify: `docs/superpowers/specs/2026-10-03-fcm-studio-design.md` (§5.5, §9, §12, §13)

- [ ] **Step 1: Run the full checks**

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter test
```
Expected: no formatting changes, `No issues found!`, and both test runs pass. The second run is there to catch flaky tests.

- [ ] **Step 2: Build every target that can be built here**

```bash
flutter build macos --debug
flutter build web
```
Expected: both succeed. The web build has no Devices or Settings section.

- [ ] **Step 3 (the user): the M3 success test on the Redmi.** Run `flutter run -d macos` with the Redmi plugged in and unlocked:
  1. Start a timer. In the composer, press **From device…**. The Redmi is selected automatically. Tap `com.syldel.delivery`.
  2. Check that FCM Studio is back in the composer with the token as the target.
  3. Pick **Simple notification** and press **Send**.
  4. Stop the timer when the notification appears. **Done when: under 30 seconds.**
  5. Targets shows `Redmi 14C · com.syldel.delivery (debug)`. Read the token again and check that it updates the same saved target.
  6. Unplug the phone: Devices says no phone is connected. Plug it back in: it comes back selected.
  7. Revoke USB debugging authorisations on the phone and plug it in again: Devices shows "Accept the USB debugging prompt on the phone".
  8. In Settings, check the adb path shown. Set a wrong path: it is flagged. Press **Find automatically**.
  9. Optional, if a release build of an app that logs its token is installed: tap it, confirm the restart, and check that the token is found from the log.

- [ ] **Step 4 (the user): Windows smoke test**, if a teammate's Windows machine is available: adb is found in `%LOCALAPPDATA%\Android\Sdk\platform-tools`, and a phone's token can be read.

- [ ] **Step 5: Record the decisions and the status in the spec**
  - §5.5, Left column: after "**From device…** on desktop", add `(it opens the Devices screen; the only ready phone is selected automatically)`.
  - §9.2, add a last bullet: `A phone that disappears stays selected, so it is picked up again when it comes back. Unauthorized and offline phones are listed with their hint but can't be opened. The last 5 packages are remembered per phone serial.`
  - §9.3 "Result": append `A single token is used straight away and the composer is shown again. When the file holds tokens for several sender IDs, the user picks one; the one matching the selected project's number is preselected. The device target is saved under the selected project, with the phone's market name in its label.`
  - §9.1: append `The path is typed in Settings and checked with adb version. "Find automatically" clears it. On the web, the Devices and Settings screens are hidden.`
  - §12, "Cubit/Bloc tests": change the `DevicesBloc` bullet to `DevicesBloc with a fake AdbService (plug/unplug, restart backoff), and TokenReaderCubit (the run-as → logcat flow).`
  - §13, add under the M2 status:
    ```
    **M3 status (<date>):**
    - *Done:* the M3 code with its automated tests passing and a clean `flutter analyze`; the macOS debug and web builds succeed. The token file format is confirmed (§9.3).
    - *Manual, pending:* <the success test and the checks in plan Task 14 Step 3 that are still open, as a plain list; nothing claimed as done unless the user reported it>.
    ```

- [ ] **Step 6: Commit**

```bash
git add docs/superpowers/specs/2026-10-03-fcm-studio-design.md
git commit -m "docs: record M3 status and the decisions made for it"
```
