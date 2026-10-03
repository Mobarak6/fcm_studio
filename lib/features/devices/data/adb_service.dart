import 'dart:async';

import 'package:fcm_studio/features/devices/data/adb_commands.dart';
import 'package:fcm_studio/features/devices/data/adb_exception.dart';
import 'package:fcm_studio/features/devices/data/device_shell.dart';
import 'package:fcm_studio/features/devices/data/parsers/track_devices_decoder.dart';
import 'package:fcm_studio/features/devices/data/process_runner.dart';
import 'package:fcm_studio/features/devices/domain/adb_device.dart';
import 'package:fcm_studio/features/devices/domain/token_read_results.dart';

export 'package:fcm_studio/features/devices/data/adb_exception.dart';

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

/// Desktop: phones through the adb program. The phone commands are shared
/// with the web in [AdbCommands].
class ProcessAdbService implements AdbService {
  ProcessAdbService({
    required this._runner,
    required this._adbPath,
    this._pollInterval = const Duration(milliseconds: 250),
    this._appStartTimeout = const Duration(seconds: 10),
    this._logcatTimeout = const Duration(seconds: 20),
  });

  final ProcessRunner _runner;
  final String _adbPath;
  final Duration _pollInterval;
  final Duration _appStartTimeout;
  final Duration _logcatTimeout;

  late final AdbCommands _commands = AdbCommands(
    shell: ProcessDeviceShell(runner: _runner, adbPath: _adbPath),
    pollInterval: _pollInterval,
    appStartTimeout: _appStartTimeout,
    logcatTimeout: _logcatTimeout,
  );

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

  Future<RunningProcess> _start(List<String> arguments) async {
    try {
      return await _runner.start(_adbPath, arguments);
    } on ProcessRunException catch (e) {
      throw AdbException(e.message);
    }
  }
}
