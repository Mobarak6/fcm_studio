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

  /// Thrown by launchApp when set.
  Object? launchError;

  /// How long cancelling a tracker takes, like the real service killing adb.
  Duration trackerCancelDelay = Duration.zero;

  StreamController<List<AdbDevice>> get tracker => trackers.last;

  @override
  Stream<List<AdbDevice>> trackDevices() {
    calls.add('track-devices');
    final controller = StreamController<List<AdbDevice>>(
      onCancel: () async {
        if (trackerCancelDelay != Duration.zero) {
          await Future<void>.delayed(trackerCancelDelay);
        }
      },
    );
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
    final error = launchError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Stream<LogcatProgress> readTokenFromLogcat(String serial, String package) {
    calls.add('logcat $serial $package');
    return Stream.fromIterable(logcat[package] ?? const [LogcatNoToken()]);
  }
}
