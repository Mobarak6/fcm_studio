import 'dart:async';

import 'package:fcm_studio/features/devices/data/adb_exception.dart';
import 'package:fcm_studio/features/devices/data/process_runner.dart';
import 'package:fcm_studio/features/devices/data/webusb/usb_transport.dart';
import 'package:fcm_studio/features/devices/data/webusb/web_usb_adb_service.dart';
import 'package:fcm_studio/features/devices/domain/adb_device.dart';
import 'package:fcm_studio/features/devices/domain/token_read_results.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/adb_key_fixture.dart';
import '../../../helpers/device_fixtures.dart';
import '../../../helpers/fake_adbd.dart';
import '../../../helpers/fake_usb_phone.dart';

void main() {
  late FakeUsbPhoneSource source;
  late WebUsbAdbService service;
  late List<List<AdbDevice>> lists;
  StreamSubscription<List<AdbDevice>>? tracking;

  WebUsbAdbService create({bool isWindows = false}) => WebUsbAdbService(
    source: source,
    loadKey: () async => testAdbKey(),
    keyName: 'fcm-studio@example.com',
    isWindows: isWindows,
  );

  setUp(() {
    source = FakeUsbPhoneSource();
    service = create();
    lists = [];
  });

  tearDown(() => tracking?.cancel());

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 30));

  Future<void> track() async {
    tracking = service.trackDevices().listen(lists.add);
    await settle();
  }

  AdbDevice only() => lists.last.single;

  test('starts with the phones this site may use, and connects them', () async {
    source.permittedPhones.add(FakeUsbPhone());
    await track();
    expect(lists.first, isEmpty);
    expect(only().serial, redmiSerial);
    expect(only().state, DeviceState.device);
    expect(only().model, '2409BRN2CA');
    expect(only().note, isNull);
    expect(
      lists.any(
        (devices) => devices.any(
          (d) =>
              d.rawState == 'connecting' &&
              d.note == WebUsbAdbService.connectingNote,
        ),
      ),
      isTrue,
    );
  });

  test('waiting for "Allow USB debugging?" shows as unauthorized', () async {
    final phone = FakeUsbPhone(
      adbd: FakeAdbd(trustsKey: false, approves: false),
    );
    source.permittedPhones.add(phone);
    await track();
    expect(only().state, DeviceState.unauthorized);
    expect(only().note, isNull);
    expect(phone.adbd.sawPublicKey, isTrue);
  });

  test('a phone held by Android Studio is offline with what to do', () async {
    source.permittedPhones.add(
      FakeUsbPhone()..openError = const UsbClaimException('Unable to claim'),
    );
    await track();
    expect(only().state, DeviceState.offline);
    expect(only().note, WebUsbAdbService.inUseNote);
  });

  test('on Windows the in-use note adds the driver hint', () async {
    service = create(isWindows: true);
    source.permittedPhones.add(
      FakeUsbPhone()..openError = const UsbClaimException('x'),
    );
    await track();
    expect(
      only().note,
      '${WebUsbAdbService.inUseNote}${WebUsbAdbService.windowsDriverNote}',
    );
  });

  test('Retry connects again once the phone is free', () async {
    final phone = FakeUsbPhone()..openError = const UsbClaimException('x');
    source.permittedPhones.add(phone);
    await track();
    phone.openError = null;
    await service.retry(redmiSerial);
    await settle();
    expect(only().state, DeviceState.device);
  });

  test('a phone without shell_v2 is too old', () async {
    source.permittedPhones.add(
      FakeUsbPhone(
        adbd: FakeAdbd(banner: 'device::ro.product.model=old;features=cmd'),
      ),
    );
    await track();
    expect(only().state, DeviceState.offline);
    expect(only().note, WebUsbAdbService.tooOldNote);
  });

  test('plugging in and unplugging update the list', () async {
    await track();
    final phone = FakeUsbPhone();
    source.connectedController.add(phone);
    await settle();
    expect(only().state, DeviceState.device);
    source.disconnectedController.add(phone);
    await settle();
    expect(lists.last, isEmpty);
    expect(phone.adbd.transport.closed, isTrue);
  });

  test('unplugged while waiting for approval, then plugged in again', () async {
    final first = FakeUsbPhone(
      adbd: FakeAdbd(trustsKey: false, approves: false),
    );
    source.permittedPhones.add(first);
    await track();
    expect(only().state, DeviceState.unauthorized);
    source.disconnectedController.add(first);
    await settle();
    expect(lists.last, isEmpty);
    // The browser gives a replugged phone a new device object.
    source.connectedController.add(FakeUsbPhone());
    await settle();
    expect(lists.last, hasLength(1));
    expect(only().state, DeviceState.device);
  });

  test(
    'Connect a phone adds the chosen phone; a closed chooser does nothing',
    () async {
      await track();
      await service.connectPhone();
      await settle();
      expect(lists.last, isEmpty);
      source.chosen = FakeUsbPhone();
      await service.connectPhone();
      await settle();
      expect(only().state, DeviceState.device);
    },
  );

  test(
    'choosing a phone that is already listed and offline retries it, no duplicate',
    () async {
      final phone = FakeUsbPhone()..openError = const UsbClaimException('x');
      source.permittedPhones.add(phone);
      await track();
      phone.openError = null;
      source.chosen = phone;
      await service.connectPhone();
      await settle();
      expect(lists.last, hasLength(1));
      expect(only().state, DeviceState.device);
    },
  );

  test('Forget removes the phone and revokes access', () async {
    final phone = FakeUsbPhone();
    source.permittedPhones.add(phone);
    await track();
    await service.forget(redmiSerial);
    await settle();
    expect(lists.last, isEmpty);
    expect(phone.forgotten, isTrue);
  });

  test(
    'two phones with the same serial get a fallback for the second',
    () async {
      source.permittedPhones
        ..add(FakeUsbPhone())
        ..add(FakeUsbPhone(vendorId: 0x18D1, productId: 0x4EE7));
      await track();
      expect(lists.last.map((d) => d.serial), [redmiSerial, 'usb:18d1:4ee7#1']);
    },
  );

  test('two quick retries while a phone waits leave it ready', () async {
    final phone = FakeUsbPhone(
      adbd: FakeAdbd(trustsKey: false, approves: false),
    );
    source.permittedPhones.add(phone);
    await track();
    expect(only().state, DeviceState.unauthorized);
    // The user taps Allow on the phone, then clicks Retry twice quickly.
    phone.adbd = FakeAdbd();
    await service.retry(redmiSerial);
    await service.retry(redmiSerial);
    await settle();
    expect(only().state, DeviceState.device);
    expect(only().note, isNull);
  });

  test(
    'unplugging during a logcat read says the phone was disconnected',
    () async {
      const app = 'com.syldel.delivery';
      final phone = FakeUsbPhone();
      phone.adbd.commands
        ..['am force-stop $app'] = const ProcessOutput(exitCode: 0)
        ..['monkey -p $app -c android.intent.category.LAUNCHER 1'] =
            const ProcessOutput(exitCode: 0, stdout: 'Events injected: 1\n')
        ..['pidof $app'] = const ProcessOutput(exitCode: 0, stdout: '4242\n');
      phone.adbd.running['logcat --pid=4242'] = StreamController<String>();
      source.permittedPhones.add(phone);
      await track();
      final progress = <LogcatProgress>[];
      final done = Completer<void>();
      service
          .readTokenFromLogcat(redmiSerial, app)
          .listen(progress.add, onDone: done.complete);
      await settle();
      expect(progress.last, const LogcatWatching(4242));

      // Chrome may deliver the disconnect event before the failed transfer.
      source.disconnectedController.add(phone);
      await done.future.timeout(const Duration(seconds: 2));
      expect(
        progress.last,
        const LogcatFailed(
          'The phone was disconnected. Plug it in and click Retry.',
        ),
      );
    },
  );

  test(
    'commands run over the connection; a lost phone names the command',
    () async {
      final phone = FakeUsbPhone();
      phone.adbd.commands['pm list packages -3'] = const ProcessOutput(
        exitCode: 0,
        stdout: 'package:com.b\npackage:com.a\n',
      );
      source.permittedPhones.add(phone);
      await track();
      expect(await service.listPackages(redmiSerial), ['com.a', 'com.b']);

      phone.adbd.transport.unplug();
      await settle();
      expect(only().state, DeviceState.offline);
      expect(
        only().note,
        'The phone was disconnected. Plug it in and click Retry.',
      );
      await expectLater(
        service.listPackages(redmiSerial),
        throwsA(
          isA<AdbException>().having(
            (e) => e.message,
            'message',
            '`pm list packages -3` on Redmi 14C failed: '
                'The phone is not connected. Plug it in and click Retry.',
          ),
        ),
      );
    },
  );
}
