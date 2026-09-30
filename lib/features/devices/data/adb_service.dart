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
  Stream<List<AdbDevice>> trackDevices() {
    late final StreamController<List<AdbDevice>> controller;
    RunningProcess? process;
    StreamSubscription<List<AdbDevice>>? subscription;
    var cancelled = false;

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
              onError: controller.addError,
              onDone: () => unawaited(controller.close()),
            );
      } on AdbException catch (e) {
        controller.addError(e);
        await controller.close();
      }
    }

    controller = StreamController<List<AdbDevice>>(
      onListen: () => unawaited(begin()),
      // Kill adb first: cancelling a pipe that is still open can wait for it.
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
  Stream<LogcatProgress> readTokenFromLogcat(
    String serial,
    String package,
  ) async* {
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
