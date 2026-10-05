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

  test(
    'a release build token comes from logcat, and logcat is stopped',
    () async {
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
    },
  );

  test('phones are tracked through the real bridge', () async {
    adb.onStart = (process) => process.out(trackFrame(redmiTrackLine));
    final devices = await service.trackDevices().first;
    expect(devices.single.serial, redmiSerial);
    await eventually(() => adb.started.single.killed);
  });
}
