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
