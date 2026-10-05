import 'dart:convert';

import 'package:fcm_studio/features/devices/data/adb_exception.dart';
import 'package:fcm_studio/features/devices/data/bridge/bridge_client.dart';
import 'package:fcm_studio/features/devices/data/bridge/bridge_status.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/eventually.dart';
import '../../../helpers/fake_bridge_channel.dart';

Matcher adbError(String message) =>
    isA<AdbException>().having((e) => e.message, 'message', message);

Map<String, Object?> out(int id, String text) => {
  'type': 'stdout',
  'id': id,
  'data': base64Encode(utf8.encode(text)),
};

void main() {
  late FakeBridgeConnector bridge;
  late List<bool> saved;
  late int downloads;
  final clients = <BridgeClient>[];

  setUp(() {
    bridge = FakeBridgeConnector();
    saved = [];
    downloads = 0;
  });

  tearDown(() async {
    for (final client in clients) {
      await client.dispose();
    }
    clients.clear();
  });

  BridgeClient client({
    bool autoConnect = false,
    bool local = false,
    bool blocked = false,
    Duration helloTimeout = const Duration(seconds: 1),
  }) {
    final created = BridgeClient(
      connector: bridge.connect,
      readAutoConnect: () async => autoConnect,
      writeAutoConnect: (on) async => saved.add(on),
      isBlocked: () async => blocked,
      download: () => downloads++,
      alwaysAutoConnect: local,
      backoff: (_) => const Duration(milliseconds: 10),
      helloTimeout: helloTimeout,
    );
    clients.add(created);
    return created;
  }

  Future<BridgeClient> connected() async {
    final created = client()..connect();
    await eventually(() => bridge.channels.isNotEmpty);
    bridge.channels.last.hello();
    await eventually(() => created.status == const BridgeConnected('/sdk/adb'));
    return created;
  }

  test(
    'connects, checks hello, reports each status and saves auto-connect',
    () async {
      final created = client();
      final statuses = <BridgeStatus>[];
      created.statuses.listen(statuses.add);
      expect(created.status, const BridgeOff());
      created.connect();
      await eventually(() => bridge.channels.isNotEmpty);
      bridge.channels.single.hello();
      await eventually(() => statuses.length == 2);
      expect(statuses, [
        const BridgeConnecting(),
        const BridgeConnected('/sdk/adb'),
      ]);
      expect(saved, [true]);
    },
  );

  test(
    'start connects only when auto-connect is on, or on a local page',
    () async {
      await client().start();
      expect(bridge.attempts, 0);
      expect(clients.last.status, const BridgeOff());
      await client(autoConnect: true).start();
      expect(bridge.attempts, 1);
      await client(local: true).start();
      expect(bridge.attempts, 2);
    },
  );

  test('a bridge that is not running is retried until it starts', () async {
    bridge.running = false;
    final created = client()..connect();
    await eventually(() => created.status == const BridgeNotRunning());
    await eventually(() => bridge.attempts >= 3);
    bridge.running = true;
    await eventually(() => bridge.channels.isNotEmpty);
    bridge.channels.last.hello();
    await eventually(() => created.status == const BridgeConnected('/sdk/adb'));
    expect(saved, [true]);
  });

  test('blocked when the browser says so', () async {
    bridge.running = false;
    final created = client(blocked: true)..connect();
    await eventually(() => created.status == const BridgeBlocked());
  });

  test('another protocol shows wrongVersion and waits for connect', () async {
    final created = client()..connect();
    await eventually(() => bridge.channels.isNotEmpty);
    bridge.channels.last.hello(protocol: 2);
    await eventually(() => created.status == const BridgeWrongVersion(2));
    expect(bridge.channels.last.closed, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(bridge.attempts, 1);
    expect(saved, isEmpty);
    created.connect();
    await eventually(() => bridge.attempts == 2);
  });

  test('no hello in time counts as not running', () async {
    final created = client(helloTimeout: const Duration(milliseconds: 20))
      ..connect();
    await eventually(() => created.status == const BridgeNotRunning());
    expect(bridge.channels.first.closed, isTrue);
    await eventually(() => bridge.attempts >= 2);
  });

  test('hello without adb reports the problem and stays connected', () async {
    final created = client()..connect();
    await eventually(() => bridge.channels.isNotEmpty);
    bridge.channels.last.hello(adb: null, problem: 'adb is missing');
    await eventually(
      () => created.status == const BridgeNoAdb('adb is missing'),
    );
    expect(bridge.channels.last.closed, isFalse);
    expect(saved, [true]);
    expect(
      () => created.request(const {'type': 'track'}),
      throwsA(adbError(BridgeClient.notConnectedMessage)),
    );
  });

  test('restarting the bridge with adb moves noAdb to connected', () async {
    final created = client()..connect();
    await eventually(() => bridge.channels.isNotEmpty);
    bridge.channels.last.hello(adb: null, problem: 'adb is missing');
    await eventually(() => created.status is BridgeNoAdb);
    await bridge.channels.last.drop();
    await eventually(() => bridge.channels.length == 2);
    bridge.channels.last.hello();
    await eventually(() => created.status == const BridgeConnected('/sdk/adb'));
  });

  test('replies are routed by id', () async {
    final created = await connected();
    final channel = bridge.channels.last;
    final first = created.request(const {
      'type': 'run',
      'serial': 'S',
      'kind': 'shell',
      'text': 'pm list packages -3',
    });
    final second = created.request(const {'type': 'track'});
    expect(channel.sent, [
      {
        'type': 'run',
        'serial': 'S',
        'kind': 'shell',
        'text': 'pm list packages -3',
        'id': 1,
      },
      {'type': 'track', 'id': 2},
    ]);
    channel
      ..fromBridge(out(2, '0000'))
      ..fromBridge({'type': 'exit', 'id': 2, 'code': 0})
      ..fromBridge({
        'type': 'error',
        'id': 1,
        'message': 'fcm_bridge refused this command.',
      });
    final chunks = await second.output.toList();
    expect(utf8.decode(chunks.single.bytes), '0000');
    expect(chunks.single.isError, isFalse);
    expect(await second.exitCode, 0);
    await expectLater(
      first.output.toList(),
      throwsA(adbError('fcm_bridge refused this command.')),
    );
    expect(await first.exitCode, -1);
  });

  test('garbage from the bridge is ignored', () async {
    final created = await connected();
    final channel = bridge.channels.last;
    final call = created.request(const {'type': 'track'});
    channel
      ..fromBridgeText('not json')
      ..fromBridge({'type': 'stdout', 'id': 99, 'data': 'AAAA'})
      ..fromBridge({'type': 'stdout', 'id': 1, 'data': '%%%'})
      ..fromBridge({'type': 'dance', 'id': 1})
      ..fromBridge(out(1, 'ok'))
      ..fromBridge({'type': 'exit', 'id': 1, 'code': 0});
    final chunks = await call.output.toList();
    expect(chunks.map((c) => utf8.decode(c.bytes)), ['ok']);
    expect(created.status, const BridgeConnected('/sdk/adb'));
  });

  test('losing the connection fails pending calls and retries', () async {
    final created = await connected();
    final call = created.request(const {'type': 'track'});
    await bridge.channels.last.drop();
    await expectLater(
      call.output.toList(),
      throwsA(adbError(BridgeClient.stoppedMessage)),
    );
    expect(await call.exitCode, -1);
    await eventually(() => bridge.attempts == 2);
    expect(created.status, isNot(const BridgeOff()));
  });

  test(
    'disconnect closes, stops retrying and turns auto-connect off',
    () async {
      final created = await connected();
      await created.disconnect();
      expect(created.status, const BridgeOff());
      expect(bridge.channels.last.closed, isTrue);
      expect(saved, [true, false]);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(bridge.attempts, 1);
    },
  );

  test('a request before connecting throws', () {
    expect(
      () => client().request(const {'type': 'track'}),
      throwsA(adbError(BridgeClient.notConnectedMessage)),
    );
  });

  test('kill asks the bridge to stop that request', () async {
    final created = await connected();
    created.request(const {'type': 'track'}).kill();
    expect(bridge.channels.last.sent.last, {'type': 'kill', 'id': 1});
  });

  test('download uses the page download', () {
    client().download();
    expect(downloads, 1);
  });
}
