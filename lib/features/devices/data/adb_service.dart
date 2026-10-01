import 'dart:async';
import 'dart:convert';

import 'package:fcm_studio/core/utils/redact.dart';
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
  Stream<List<AdbDevice>> trackDevices() {
    late final StreamController<List<AdbDevice>> controller;
    RunningProcess? process;
    StreamSubscription<List<AdbDevice>>? subscription;
    var cancelled = false;
    var sawError = false;

    // adb exited on its own: say why, then end the stream.
    Future<void> ended(RunningProcess started) async {
      if (!cancelled && !sawError) {
        final code = await started.exitCode
            .then<int?>((code) => code)
            .timeout(const Duration(seconds: 1), onTimeout: () => null);
        if (!cancelled) {
          final command = describeCommand(_adbPath, const [
            'track-devices',
            '-l',
          ]);
          controller.addError(
            AdbException(
              code == null
                  ? '`$command` stopped'
                  : '`$command` exited with code $code',
            ),
          );
        }
      }
      await controller.close();
    }

    Future<void> begin() async {
      try {
        final started = await _start(const ['track-devices', '-l']);
        process = started;
        if (cancelled) {
          started.kill();
          return;
        }
        subscription = started.stdout
            .transform(const TrackDevicesDecoder())
            .listen(
              controller.add,
              onError: (Object error, StackTrace stackTrace) {
                sawError = true;
                controller.addError(error, stackTrace);
              },
              onDone: () => unawaited(ended(started)),
            );
      } on Object catch (e, st) {
        controller.addError(e, st);
        await controller.close();
      }
    }

    controller = StreamController<List<AdbDevice>>(
      onListen: () => unawaited(begin()),
      // Kill adb first. TrackDevicesDecoder.bind is an async* parked in
      // `await for`, so cancelling its stream waits until stdout ends; only
      // the kill ends it. Don't swap these or go back to `yield*`.
      onCancel: () {
        cancelled = true;
        process?.kill();
        return subscription?.cancel();
      },
    );
    return controller.stream;
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
    final arguments = [
      '-s',
      serial,
      'exec-out',
      'run-as',
      package,
      'cat',
      tokenFile,
    ];
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
        await _shell(serial, 'am force-stop $package');
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
      // kill ends it (the same reason as in trackDevices).
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
    final stopwatch = Stopwatch()..start();
    while (!isCancelled() && stopwatch.elapsed < _appStartTimeout) {
      final arguments = ['-s', serial, 'shell', 'pidof', package];
      final output = await _run(arguments);
      if (output.exitCode != 0 &&
          (output.stderr.trim().isNotEmpty ||
              output.stdout.trim().startsWith('error:'))) {
        throw AdbException(_failed(arguments, output));
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
    final arguments = ['-s', serial, 'logcat', '--pid=$pid'];
    final process = await _start(arguments);
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
        final command = describeCommand(_adbPath, arguments);
        throw AdbException(
          code == null
              ? '`$command` stopped'
              : '`$command` stopped (exit code $code)',
        );
      }
      return token;
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
    final details = output.combined
        .replaceAll(FcmTokenPattern.inText, '<token>')
        .trim();
    return '`${describeCommand(_adbPath, arguments)}` failed: '
        '${details.isEmpty ? 'exit code ${output.exitCode}' : details}';
  }
}
