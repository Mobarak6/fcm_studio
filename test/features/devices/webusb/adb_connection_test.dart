import 'dart:async';
import 'dart:convert';

import 'package:fcm_studio/features/devices/data/adb_exception.dart';
import 'package:fcm_studio/features/devices/data/webusb/adb_connection.dart';
import 'package:fcm_studio/features/devices/data/webusb/adb_message.dart';
import 'package:fcm_studio/features/devices/data/webusb/usb_transport.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/adb_key_fixture.dart';
import '../../../helpers/fake_usb_transport.dart';

const keyName = 'fcm-studio@example.com';
const phoneBanner = 'device::ro.product.model=2409BRN2CA;features=shell_v2,cmd';

void main() {
  late FakeUsbTransport phone;
  late AdbConnection connection;
  var keyLoads = 0;

  setUp(() {
    phone = FakeUsbTransport();
    keyLoads = 0;
    connection = AdbConnection(
      transport: phone,
      loadKey: () async {
        keyLoads++;
        return testAdbKey();
      },
      keyName: keyName,
    );
  });

  AdbMessage banner([String text = phoneBanner]) =>
      AdbMessage.text(AdbCommand.cnxn, 0x01000001, 256 * 1024, text);
  AdbMessage token() =>
      AdbMessage(AdbCommand.auth, 1, 0, List<int>.generate(20, (i) => i));

  Future<void> ready() async {
    final connected = connection.connect();
    await phone.nextHostMessage();
    phone.phoneSends(banner());
    await connected;
  }

  group('handshake', () {
    test('opens with CNXN: version, max payload and shell_v2', () async {
      unawaited(connection.connect());
      expect(
        await phone.nextHostMessage(),
        AdbMessage.text(
          AdbCommand.cnxn,
          0x01000001,
          1048576,
          'host::features=shell_v2,cmd',
        ),
      );
    });

    test('a phone that needs no key is ready at once', () async {
      final connected = connection.connect();
      await phone.nextHostMessage();
      phone.phoneSends(banner());
      final result = await connected;
      expect(result.hasShellV2, isTrue);
      expect(result.model, '2409BRN2CA');
      expect(keyLoads, 0);
    });

    test(
      'a phone that trusts the key gets a signature, then is ready',
      () async {
        final connected = connection.connect();
        await phone.nextHostMessage();
        phone.phoneSends(token());
        final signature = await phone.nextHostMessage();
        expect((signature.command, signature.arg0), (AdbCommand.auth, 2));
        expect(
          signature.payload,
          testAdbKey().sign(List<int>.generate(20, (i) => i)),
        );
        phone.phoneSends(banner());
        await connected;
      },
    );

    test('an unknown key is offered; the phone asks, then accepts', () async {
      var asked = false;
      final connected = connection.connect(
        onWaitingForApproval: () => asked = true,
      );
      await phone.nextHostMessage();
      phone.phoneSends(token());
      await phone.nextHostMessage(); // the signature
      phone.phoneSends(token()); // not trusted
      final offer = await phone.nextHostMessage();
      expect((offer.command, offer.arg0), (AdbCommand.auth, 3));
      expect(
        offer.text,
        startsWith(base64.encode(testAdbKey().androidPublicKey())),
      );
      expect(utf8.decode(offer.payload), endsWith(' $keyName\u0000'));
      expect(asked, isTrue);
      phone.phoneSends(banner());
      await connected;
    });

    test('while the user has not answered, the handshake waits', () async {
      var done = false;
      unawaited(connection.connect().then((_) => done = true));
      await phone.nextHostMessage();
      phone.phoneSends(token());
      await phone.nextHostMessage();
      phone.phoneSends(token());
      await phone.nextHostMessage();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(done, isFalse);
    });

    test('a banner without shell_v2 says so', () async {
      final connected = connection.connect();
      await phone.nextHostMessage();
      phone.phoneSends(banner('device::ro.product.model=old;features=cmd'));
      expect((await connected).hasShellV2, isFalse);
    });

    test('unplugging during the handshake fails it', () async {
      final connected = connection.connect();
      await phone.nextHostMessage();
      phone.unplug();
      await expectLater(connected, throwsA(isA<UsbDisconnectedException>()));
      expect(await connection.lost, isA<UsbDisconnectedException>());
    });

    test('a bad header from the phone breaks the connection', () async {
      final connected = connection.connect();
      await phone.nextHostMessage();
      phone.phoneSendsBytes(List<int>.filled(24, 0));
      await expectLater(connected, throwsA(isA<AdbProtocolException>()));
    });
  });

  group('streams', () {
    test('OPEN, OKAY, data with an OKAY each, and the phone closing', () async {
      await ready();
      final opening = connection.open('shell,v2,raw:getprop');
      expect(
        await phone.nextHostMessage(),
        AdbMessage.text(AdbCommand.open, 1, 0, 'shell,v2,raw:getprop\u0000'),
      );
      phone.phoneSends(AdbMessage(AdbCommand.okay, 100, 1));
      final stream = await opening;
      final received = <List<int>>[];
      final done = Completer<void>();
      stream.data.listen(received.add, onDone: done.complete);
      phone.phoneSends(AdbMessage(AdbCommand.wrte, 100, 1, [1, 2]));
      expect(
        await phone.nextHostMessage(),
        AdbMessage(AdbCommand.okay, 1, 100),
      );
      phone.phoneSends(AdbMessage(AdbCommand.clse, 100, 1));
      await done.future;
      expect(received, [
        [1, 2],
      ]);
    });

    test('a refused command is an AdbException', () async {
      await ready();
      final opening = connection.open('shell,v2,raw:nope');
      await phone.nextHostMessage();
      phone.phoneSends(AdbMessage(AdbCommand.clse, 0, 1));
      await expectLater(opening, throwsA(isA<AdbException>()));
    });

    test('two streams at once get their own data', () async {
      await ready();
      final first = connection.open('shell,v2,raw:a');
      await phone.nextHostMessage();
      final second = connection.open('shell,v2,raw:b');
      await phone.nextHostMessage();
      phone
        ..phoneSends(AdbMessage(AdbCommand.okay, 200, 2))
        ..phoneSends(AdbMessage(AdbCommand.okay, 100, 1));
      final a = await first;
      final b = await second;
      final aData = <int>[];
      final bData = <int>[];
      a.data.listen(aData.addAll);
      b.data.listen(bData.addAll);
      phone
        ..phoneSends(AdbMessage(AdbCommand.wrte, 200, 2, [2]))
        ..phoneSends(AdbMessage(AdbCommand.wrte, 100, 1, [1]));
      expect(
        await phone.nextHostMessage(),
        AdbMessage(AdbCommand.okay, 2, 200),
      );
      expect(
        await phone.nextHostMessage(),
        AdbMessage(AdbCommand.okay, 1, 100),
      );
      expect(aData, [1]);
      expect(bData, [2]);
    });

    test('closing a stream sends CLSE', () async {
      await ready();
      final opening = connection.open('shell,v2,raw:logcat');
      await phone.nextHostMessage();
      phone.phoneSends(AdbMessage(AdbCommand.okay, 100, 1));
      await (await opening).close();
      expect(
        await phone.nextHostMessage(),
        AdbMessage(AdbCommand.clse, 1, 100),
      );
    });

    test(
      'unplugging fails open streams with the disconnected message',
      () async {
        await ready();
        final opening = connection.open('shell,v2,raw:logcat');
        await phone.nextHostMessage();
        phone.phoneSends(AdbMessage(AdbCommand.okay, 100, 1));
        final stream = await opening;
        final errors = <Object>[];
        final done = Completer<void>();
        stream.data.listen((_) {}, onError: errors.add, onDone: done.complete);
        phone.unplug();
        await done.future;
        expect(
          errors.single,
          isA<AdbException>().having(
            (e) => e.message,
            'message',
            'The phone was disconnected. Plug it in and click Retry.',
          ),
        );
        await expectLater(
          connection.open('shell,v2,raw:x'),
          throwsA(isA<AdbException>()),
        );
      },
    );

    test('a message split across many USB reads still arrives whole', () async {
      phone.maxChunk = 3;
      await ready();
      final opening = connection.open('shell,v2,raw:cat');
      await phone.nextHostMessage();
      phone.phoneSends(AdbMessage(AdbCommand.okay, 100, 1));
      final stream = await opening;
      final received = <List<int>>[];
      stream.data.listen(received.add);
      phone.phoneSends(
        AdbMessage(AdbCommand.wrte, 100, 1, List<int>.generate(10, (i) => i)),
      );
      await phone.nextHostMessage(); // the OKAY
      expect(received, [List<int>.generate(10, (i) => i)]);
    });

    test('close() releases the transport and fails open streams', () async {
      await ready();
      final opening = connection.open('shell,v2,raw:logcat');
      await phone.nextHostMessage();
      phone.phoneSends(AdbMessage(AdbCommand.okay, 100, 1));
      final stream = await opening;
      final done = Completer<void>();
      stream.data.listen((_) {}, onError: (Object _) {}, onDone: done.complete);
      await connection.close();
      await done.future;
      expect(phone.closed, isTrue);
    });
  });
}
