import 'dart:async';

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
      final done = Completer<void>();
      service().trackDevices().listen(
        (_) {},
        onError: (Object _) {},
        onDone: done.complete,
      );
      tracker.exit();
      await done.future.timeout(const Duration(seconds: 2));
    });

    test('an adb that exits says so, then the stream is done', () async {
      final tracker = FakeRunningProcess();
      runner.onStart('$adb track-devices -l', () => tracker);
      final errors = <Object>[];
      final done = Completer<void>();
      service().trackDevices().listen(
        (_) {},
        onError: errors.add,
        onDone: done.complete,
      );
      tracker.exit(1);
      await done.future.timeout(const Duration(seconds: 2));
      expect(
        errors.single,
        isA<AdbException>().having(
          (e) => e.message,
          'message',
          allOf(contains('track-devices'), contains('1')),
        ),
      );
    });

    test('a cancelled tracker reports no exit error', () async {
      final tracker = FakeRunningProcess();
      runner.onStart('$adb track-devices -l', () => tracker);
      final errors = <Object>[];
      final subscription = service().trackDevices().listen(
        (_) {},
        onError: errors.add,
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await subscription.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(errors, isEmpty);
    });

    test(
      'an adb that cannot start is an AdbException naming the command',
      () async {
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
      },
    );
  });

  group('track-devices lifecycle', () {
    test('cancelled before adb starts, still kills it', () async {
      final tracker = FakeRunningProcess();
      runner.onStart('$adb track-devices -l', () => tracker);
      final subscription = service().trackDevices().listen((_) {});
      await subscription.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(tracker.killed, isTrue);
    });

    test('a decoder error is a stream error, then done, adb killed', () async {
      final tracker = FakeRunningProcess();
      runner.onStart('$adb track-devices -l', () => tracker);
      final errors = <Object>[];
      final done = Completer<void>();
      service().trackDevices().listen(
        (_) {},
        onError: errors.add,
        onDone: done.complete,
      );
      tracker.emit('zzzz');
      await done.future.timeout(const Duration(seconds: 2));
      expect(errors, hasLength(1));
      expect(tracker.killed, isTrue);
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
        const DeviceDetails(
          name: 'Redmi 14C',
          brand: 'Redmi',
          androidVersion: '16',
        ),
      );
    });

    test('falls back to the model when there is no market name', () async {
      runner.on(shell(getprop), ok('\n2409BRN2CA\nRedmi\n16\n'));
      expect((await service().deviceDetails(redmiSerial)).name, '2409BRN2CA');
    });

    test('lists third-party packages, sorted', () async {
      runner.on(
        shell('pm list packages -3'),
        ok('package:b.app\npackage:a.app\n'),
      );
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
        RunAsTokens([
          FoundToken(token: fakeDeviceToken, senderId: '123456789012'),
        ]),
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

    test('a failure message never contains a token', () async {
      runner.on(runAs, failed('oops $fakeDeviceToken oops'));
      final result = await service().readTokenWithRunAs(redmiSerial, package);
      expect(result, isA<RunAsFailed>());
      expect((result as RunAsFailed).message, isNot(contains(fakeDeviceToken)));
    });

    test('other failures name the command', () async {
      runner.on(
        runAs,
        const ProcessOutput(exitCode: 1, stderr: 'error: device offline'),
      );
      final result = await service().readTokenWithRunAs(redmiSerial, package);
      expect(
        result,
        isA<RunAsFailed>().having(
          (r) => r.message,
          'message',
          allOf(contains('exec-out run-as'), contains('device offline')),
        ),
      );
      runner.on(
        runAs,
        const ProcessRunException('x', 'did not finish within 10 seconds'),
      );
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
      runner.on(
        shell(monkey),
        ok('** No activities found to run, monkey aborted.\n'),
      );
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

    test('cancelling kills logcat at once, however long the timeout', () async {
      scriptRestart(pidof: <ProcessOutput>[ok('4242\n')]);
      final logcat = FakeRunningProcess()..emit('10-04 I/flutter: nothing\n');
      runner.onStart('$adb -s $redmiSerial logcat --pid=4242', () => logcat);
      final slow = ProcessAdbService(
        runner: runner,
        adbPath: adb,
        pollInterval: const Duration(milliseconds: 1),
        logcatTimeout: const Duration(minutes: 1),
      );
      final watching = Completer<void>();
      final subscription = slow
          .readTokenFromLogcat(redmiSerial, package)
          .listen((p) {
            if (p is LogcatWatching) watching.complete();
          });
      await watching.future.timeout(const Duration(seconds: 2));
      await subscription.cancel().timeout(const Duration(milliseconds: 500));
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
      expect(
        await service().readTokenFromLogcat(redmiSerial, package).toList(),
        [
          const LogcatRestartingApp(),
          const LogcatWaitingForApp(),
          const LogcatAppDidNotStart(),
        ],
      );
    });

    test('stops after the timeout when the app never logs a token', () async {
      scriptRestart(pidof: <ProcessOutput>[ok('4242\n')]);
      final logcat = FakeRunningProcess()
        ..emit('10-04 I/flutter: nothing here\n');
      runner.onStart('$adb -s $redmiSerial logcat --pid=4242', () => logcat);
      final progress = await service()
          .readTokenFromLogcat(redmiSerial, package)
          .toList();
      expect(progress.last, const LogcatNoToken());
      expect(logcat.killed, isTrue);
    });

    test(
      'an adb failure on the way ends with a message naming the command',
      () async {
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
      },
    );

    test('logcat ending early is a failure naming the exit code', () async {
      scriptRestart(pidof: <ProcessOutput>[ok('4242\n')]);
      final logcat = FakeRunningProcess();
      runner.onStart('$adb -s $redmiSerial logcat --pid=4242', () => logcat);
      final progress = <LogcatProgress>[];
      final done = Completer<void>();
      service().readTokenFromLogcat(redmiSerial, package).listen((p) {
        progress.add(p);
        if (p is LogcatWatching) {
          Future<void>.delayed(
            const Duration(milliseconds: 5),
            () => logcat.exit(1),
          );
        }
      }, onDone: done.complete);
      await done.future.timeout(const Duration(seconds: 2));
      expect(
        progress.last,
        isA<LogcatFailed>().having(
          (p) => p.message,
          'message',
          allOf(contains('logcat'), contains('1')),
        ),
      );
    });

    test('a pidof adb error is a failure, not "not running yet"', () async {
      scriptRestart(
        pidof: <ProcessOutput>[
          const ProcessOutput(exitCode: 1, stderr: 'error: device offline'),
        ],
      );
      final progress = await service()
          .readTokenFromLogcat(redmiSerial, package)
          .toList();
      expect(
        progress.last,
        isA<LogcatFailed>().having(
          (p) => p.message,
          'message',
          allOf(contains('pidof'), contains('device offline')),
        ),
      );
    });

    test('pidof exit 1 with no output still means not running yet', () async {
      scriptRestart(pidof: <ProcessOutput>[const ProcessOutput(exitCode: 1)]);
      final progress = await service()
          .readTokenFromLogcat(redmiSerial, package)
          .toList();
      expect(progress.last, const LogcatAppDidNotStart());
    });

    test('cancelling during force-stop never launches the app', () async {
      final gated = _GatedRunner();
      gated
        ..on(shell('am force-stop $package'), ok(''))
        ..on(
          shell('monkey -p $package -c android.intent.category.LAUNCHER 1'),
          ok('Events injected: 1\n'),
        )
        ..on(shell('pidof $package'), ok('4242\n'));
      final svc = ProcessAdbService(
        runner: gated,
        adbPath: adb,
        pollInterval: const Duration(milliseconds: 1),
      );
      final restarting = Completer<void>();
      final subscription = svc.readTokenFromLogcat(redmiSerial, package).listen(
        (p) {
          if (p is LogcatRestartingApp) restarting.complete();
        },
      );
      await restarting.future;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await subscription.cancel();
      gated.gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(gated.commands.where((c) => c.contains('monkey')), isEmpty);
    });

    test('an unexpected error is LogcatFailed, never a zone error', () async {
      scriptRestart(pidof: <ProcessOutput>[ok('4242\n')]);
      final zoneErrors = <Object>[];
      late List<LogcatProgress> progress;
      await runZonedGuarded(() async {
        progress = await ProcessAdbService(
          runner: _ThrowingStartRunner(runner),
          adbPath: adb,
          pollInterval: const Duration(milliseconds: 1),
        ).readTokenFromLogcat(redmiSerial, package).toList();
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }, (e, _) => zoneErrors.add(e));
      expect(zoneErrors, isEmpty);
      expect(
        progress.last,
        isA<LogcatFailed>().having(
          (p) => p.message,
          'message',
          contains('logcat'),
        ),
      );
    });
  });
}

/// Holds `am force-stop` until [gate] completes.
class _GatedRunner extends FakeProcessRunner {
  final Completer<void> gate = Completer<void>();

  @override
  Future<ProcessOutput> run(
    String executable,
    List<String> arguments, {
    Duration timeout = ProcessRunner.defaultTimeout,
  }) async {
    final output = await super.run(executable, arguments, timeout: timeout);
    if (arguments.last.contains('force-stop')) {
      await gate.future;
    }
    return output;
  }
}

/// Throws an Error (not a ProcessRunException) when logcat starts.
class _ThrowingStartRunner implements ProcessRunner {
  _ThrowingStartRunner(this._inner);

  final FakeProcessRunner _inner;

  @override
  Future<ProcessOutput> run(
    String executable,
    List<String> arguments, {
    Duration timeout = ProcessRunner.defaultTimeout,
  }) => _inner.run(executable, arguments, timeout: timeout);

  @override
  Future<RunningProcess> start(
    String executable,
    List<String> arguments,
  ) async => throw UnsupportedError('no processes here');
}
