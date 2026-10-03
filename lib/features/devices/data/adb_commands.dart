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
