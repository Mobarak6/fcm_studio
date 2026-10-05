import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../web/fcm_bridge.dart';
import '../helpers/eventually.dart';
import '../helpers/fake_adb_process.dart';

const adbPath = '/sdk/platform-tools/adb';
const serial = 'DETWFUOZZHZ5SWFQ';
const app = 'com.syldel.delivery';
const tokenFile = 'shared_prefs/com.google.android.gms.appid.xml';

/// A page connected to the bridge, keeping every message it got.
class TestPage {
  TestPage._(this.socket) {
    socket.listen((data) {
      received.add(jsonDecode(data as String) as Map<String, Object?>);
      _changes.add(null);
    }, onDone: () => unawaited(_changes.close()));
  }

  static Future<TestPage> open(
    int port, {
    String? origin = 'http://localhost:5050',
  }) async => TestPage._(
    await WebSocket.connect(
      'ws://127.0.0.1:$port',
      headers: {'origin': ?origin},
    ),
  );

  final WebSocket socket;
  final List<Map<String, Object?>> received = [];
  final StreamController<void> _changes = StreamController<void>.broadcast();

  void send(Map<String, Object?> message) => socket.add(jsonEncode(message));

  void sendText(String text) => socket.add(text);

  /// The first message so far, or to come, that matches [test].
  Future<Map<String, Object?>> waitFor(
    bool Function(Map<String, Object?> message) test,
  ) async {
    while (true) {
      for (final message in received) {
        if (test(message)) {
          return message;
        }
      }
      await _changes.stream.first.timeout(const Duration(seconds: 2));
    }
  }

  /// What arrived on [stream] (`stdout` or `stderr`) for request [id].
  String output(int id, String stream) => received
      .where((m) => m['id'] == id && m['type'] == stream)
      .map((m) => utf8.decode(base64Decode(m['data']! as String)))
      .join();
}

void main() {
  late FakeAdb adb;

  setUp(() => adb = FakeAdb());

  /// The bridge on a free port, with [adb] behind it. [adbPathOrNull] null
  /// is a bridge that found no adb.
  Future<(HttpServer, List<String>)> startBridge({
    String? adbPathOrNull = adbPath,
    List<String> allowed = const [],
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final log = <String>[];
    unawaited(
      BridgeServer(
        adbPath: adbPathOrNull,
        allowedOrigins: allowed,
        startProcess: adb.start,
        log: log.add,
      ).serve(server),
    );
    return (server, log);
  }

  test('says hello with the adb it found', () async {
    final (server, _) = await startBridge();
    final page = await TestPage.open(server.port);
    expect(await page.waitFor((m) => m['type'] == 'hello'), {
      'type': 'hello',
      'protocol': bridgeProtocol,
      'adb': adbPath,
    });
  });

  test('without adb, hello says how to fix it and requests fail', () async {
    final (server, _) = await startBridge(adbPathOrNull: null);
    final page = await TestPage.open(server.port);
    expect(await page.waitFor((m) => m['type'] == 'hello'), {
      'type': 'hello',
      'protocol': bridgeProtocol,
      'adb': null,
      'problem': noAdbProblem,
    });
    page.send({'type': 'track', 'id': 1});
    expect(await page.waitFor((m) => m['id'] == 1), {
      'type': 'error',
      'id': 1,
      'message': noAdbProblem,
    });
  });

  test('run passes the command to adb and streams its output', () async {
    adb.onStart = (process) => process
      ..out('package:$app\n')
      ..err('warning\n')
      ..finish(0);
    final (server, _) = await startBridge();
    final page = await TestPage.open(server.port);
    page.send({
      'type': 'run',
      'id': 7,
      'serial': serial,
      'kind': 'shell',
      'text': 'pm list packages -3',
    });
    expect(await page.waitFor((m) => m['type'] == 'exit'), {
      'type': 'exit',
      'id': 7,
      'code': 0,
    });
    expect(adb.started.single.arguments, [
      adbPath,
      '-s',
      serial,
      'shell',
      'pm list packages -3',
    ]);
    expect(page.output(7, 'stdout'), 'package:$app\n');
    expect(page.output(7, 'stderr'), 'warning\n');
  });

  test(
    'exec-out and logcat split their arguments like the desktop app',
    () async {
      adb.onStart = (process) => process.finish(0);
      final (server, _) = await startBridge();
      final page = await TestPage.open(server.port);
      page
        ..send({
          'type': 'run',
          'id': 1,
          'serial': serial,
          'kind': 'execOut',
          'text': 'run-as $app cat $tokenFile',
        })
        ..send({
          'type': 'run',
          'id': 2,
          'serial': serial,
          'kind': 'logcat',
          'text': '--pid=4242',
        });
      await page.waitFor((m) => m['type'] == 'exit' && m['id'] == 1);
      await page.waitFor((m) => m['type'] == 'exit' && m['id'] == 2);
      expect(adb.started.map((p) => p.arguments), [
        [adbPath, '-s', serial, 'exec-out', 'run-as', app, 'cat', tokenFile],
        [adbPath, '-s', serial, 'logcat', '--pid=4242'],
      ]);
    },
  );

  test(
    'a command FCM Studio never sends is refused and never reaches adb',
    () async {
      final (server, log) = await startBridge();
      final page = await TestPage.open(server.port);
      page.send({
        'type': 'run',
        'id': 1,
        'serial': serial,
        'kind': 'shell',
        'text': 'pm uninstall $app',
      });
      expect(await page.waitFor((m) => m['id'] == 1), {
        'type': 'error',
        'id': 1,
        'message': 'fcm_bridge refused this command.',
      });
      expect(adb.started, isEmpty);
      expect(log, contains('Refused a command: shell pm uninstall $app'));
    },
  );

  test('track streams adb track-devices', () async {
    adb.onStart = (process) => process.out('0000');
    final (server, _) = await startBridge();
    final page = await TestPage.open(server.port);
    page.send({'type': 'track', 'id': 3});
    await page.waitFor((m) => m['type'] == 'stdout' && m['id'] == 3);
    expect(page.output(3, 'stdout'), '0000');
    expect(adb.started.single.arguments, [adbPath, 'track-devices', '-l']);
  });

  test('kill stops a running command', () async {
    final (server, _) = await startBridge();
    final page = await TestPage.open(server.port);
    page.send({
      'type': 'run',
      'id': 4,
      'serial': serial,
      'kind': 'logcat',
      'text': '--pid=42',
    });
    await eventually(() => adb.started.isNotEmpty);
    page.send({'type': 'kill', 'id': 4});
    expect(await page.waitFor((m) => m['type'] == 'exit'), {
      'type': 'exit',
      'id': 4,
      'code': -15,
    });
    expect(adb.started.single.killed, isTrue);
  });

  test('closing the page kills what it started', () async {
    final (server, _) = await startBridge();
    final page = await TestPage.open(server.port);
    page.send({'type': 'track', 'id': 5});
    await eventually(() => adb.started.isNotEmpty);
    await page.socket.close();
    await eventually(() => adb.started.single.killed);
  });

  test('two pages keep their processes apart', () async {
    final (server, _) = await startBridge();
    final first = await TestPage.open(server.port);
    final second = await TestPage.open(server.port);
    first.send({'type': 'track', 'id': 1});
    await eventually(() => adb.started.length == 1);
    second.send({'type': 'track', 'id': 1});
    await eventually(() => adb.started.length == 2);

    second.send({'type': 'kill', 'id': 1});
    await eventually(() => adb.started[1].killed);
    expect(adb.started[0].killed, isFalse);

    await second.socket.close();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(adb.started[0].killed, isFalse);
    await first.socket.close();
    await eventually(() => adb.started[0].killed);
  });

  test('garbage from the page is ignored', () async {
    adb.onStart = (process) => process.finish(0);
    final (server, _) = await startBridge();
    final page = await TestPage.open(server.port);
    page
      ..sendText('not json')
      ..sendText('[1, 2]')
      ..send({'type': 'run'})
      ..send({'type': 'dance', 'id': 9})
      ..send({'type': 'kill', 'id': 99})
      ..send({'type': 'track', 'id': 10});
    expect(await page.waitFor((m) => m['id'] == 9), {
      'type': 'error',
      'id': 9,
      'message': 'fcm_bridge does not know "dance" requests.',
    });
    expect(await page.waitFor((m) => m['type'] == 'exit'), {
      'type': 'exit',
      'id': 10,
      'code': 0,
    });
  });

  test("adb that can't start is reported", () async {
    adb.startError = const ProcessException('adb', [], 'No such file');
    final (server, _) = await startBridge();
    final page = await TestPage.open(server.port);
    page.send({'type': 'track', 'id': 1});
    final error = await page.waitFor((m) => m['id'] == 1);
    expect(error['type'], 'error');
    expect(error['message'], startsWith('Could not start adb at $adbPath'));
  });

  test(
    'pages from other sites are refused; --allow-origin lets one in',
    () async {
      final (server, log) = await startBridge(
        allowed: const ['https://fcm.example.com'],
      );
      await expectLater(
        TestPage.open(server.port, origin: 'https://evil.example'),
        throwsA(isA<WebSocketException>()),
      );
      expect(
        log,
        contains(
          'Refused a connection from https://evil.example. '
          'To allow it: --allow-origin https://evil.example',
        ),
      );
      final allowed = await TestPage.open(
        server.port,
        origin: 'https://fcm.example.com',
      );
      expect(
        (await allowed.waitFor((m) => m['type'] == 'hello'))['adb'],
        adbPath,
      );
    },
  );

  test('a page with no origin is refused', () async {
    final (server, log) = await startBridge();
    await expectLater(
      TestPage.open(server.port, origin: null),
      throwsA(isA<WebSocketException>()),
    );
    expect(log, contains('Refused a connection with no origin.'));
  });

  test('plain requests get a short explanation', () async {
    final (server, _) = await startBridge();
    final client = HttpClient();
    addTearDown(client.close);
    final request = await client.getUrl(
      Uri.parse('http://127.0.0.1:${server.port}/'),
    );
    final response = await request.close();
    expect(response.statusCode, HttpStatus.badRequest);
    expect(
      await response.transform(utf8.decoder).join(),
      'FCM Studio bridge: open FCM Studio to use it.',
    );
  });
}
