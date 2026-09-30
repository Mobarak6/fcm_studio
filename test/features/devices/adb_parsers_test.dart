import 'dart:async';
import 'dart:convert';

import 'package:fcm_studio/features/devices/data/parsers/device_list_parser.dart';
import 'package:fcm_studio/features/devices/data/parsers/fcm_token_pattern.dart';
import 'package:fcm_studio/features/devices/data/parsers/package_list_parser.dart';
import 'package:fcm_studio/features/devices/data/parsers/run_as_outcome.dart';
import 'package:fcm_studio/features/devices/data/parsers/track_devices_decoder.dart';
import 'package:fcm_studio/features/devices/data/process_runner.dart';
import 'package:fcm_studio/features/devices/domain/adb_device.dart';
import 'package:flutter_test/flutter_test.dart';

// Printed by the Redmi 14C (Android 16) on 2026-10-04.
const redmiLine =
    'DETWFUOZZHZ5SWFQ       device usb:34603008X product:pond_global '
    'model:2409BRN2CA device:pond transport_id:1\n';

String frame(String payload) =>
    '${utf8.encode(payload).length.toRadixString(16).padLeft(4, '0')}$payload';

Future<List<List<AdbDevice>>> decode(List<String> chunks) =>
    Stream<List<int>>.fromIterable([
      for (final chunk in chunks) utf8.encode(chunk),
    ]).transform(const TrackDevicesDecoder()).toList();

void main() {
  group('device list', () {
    test('parses adb devices -l, skipping the header and daemon lines', () {
      final devices = parseDeviceList(
        '* daemon not running; starting now at tcp:5037\n'
        '* daemon started successfully\n'
        'List of devices attached\n'
        '$redmiLine'
        'R58M123ABC             unauthorized usb:336855040X transport_id:3\n'
        'emulator-5554          offline transport_id:4\n'
        '\n',
      );
      expect(devices, [
        const AdbDevice(
          serial: 'DETWFUOZZHZ5SWFQ',
          state: DeviceState.device,
          rawState: 'device',
          model: '2409BRN2CA',
          product: 'pond_global',
          transportId: '1',
        ),
        const AdbDevice(
          serial: 'R58M123ABC',
          state: DeviceState.unauthorized,
          rawState: 'unauthorized',
          transportId: '3',
        ),
        const AdbDevice(
          serial: 'emulator-5554',
          state: DeviceState.offline,
          rawState: 'offline',
          transportId: '4',
        ),
      ]);
      expect(devices.first.isReady, isTrue);
      expect(devices[1].isReady, isFalse);
    });

    test('keeps unknown states as "other"', () {
      final device = parseDeviceList('ABC123 recovery transport_id:9\n').single;
      expect(device.state, DeviceState.other);
      expect(device.rawState, 'recovery');
    });
  });

  group('track-devices framing', () {
    test('the real Redmi message is 0x6c bytes long', () {
      expect(utf8.encode(redmiLine).length, 0x6c);
    });

    test(
      'decodes one message per device list, including an empty one',
      () async {
        final lists = await decode(['${frame(redmiLine)}${frame('')}']);
        expect(lists, hasLength(2));
        expect(lists.first.single.serial, 'DETWFUOZZHZ5SWFQ');
        expect(lists.last, isEmpty);
      },
    );

    test('a message split across chunks is joined', () async {
      final message = frame(redmiLine);
      final lists = await decode([
        message.substring(0, 2),
        message.substring(2, 40),
        message.substring(40),
      ]);
      expect(lists.single.single.model, '2409BRN2CA');
    });

    test('data that is not a length prefix is an error', () async {
      await expectLater(decode(['zzzzhello']), throwsFormatException);
    });
  });

  test('pm list packages -3 becomes a sorted list of names', () {
    expect(
      parsePackageList(
        'package:com.syldel.delivery\n'
        'package:com.alpha.app\n'
        '\n'
        'WARNING: something\n'
        'package:com.zeta.app\n',
      ),
      ['com.alpha.app', 'com.syldel.delivery', 'com.zeta.app'],
    );
  });

  group('run-as output', () {
    ProcessOutput out(String text, {int exitCode = 0}) =>
        ProcessOutput(exitCode: exitCode, stdout: text);

    test('the token file', () {
      expect(
        classifyRunAs(out("<?xml version='1.0' ?>\n<map>\n</map>\n")),
        RunAsOutcome.file,
      );
    });

    test('a release build', () {
      expect(
        classifyRunAs(
          out(
            'run-as: package not debuggable: com.syldel.delivery',
            exitCode: 1,
          ),
        ),
        RunAsOutcome.notDebuggable,
      );
    });

    test('no token file yet', () {
      expect(
        classifyRunAs(
          out(
            'cat: shared_prefs/com.google.android.gms.appid.xml: No such file or directory',
            exitCode: 1,
          ),
        ),
        RunAsOutcome.noSuchFile,
      );
    });

    test('a package that is not installed, in both wordings', () {
      expect(
        classifyRunAs(
          out('run-as: unknown package: com.does.not.exist', exitCode: 1),
        ),
        RunAsOutcome.unknownPackage,
      );
      expect(
        classifyRunAs(
          out("Package 'com.does.not.exist' is unknown", exitCode: 1),
        ),
        RunAsOutcome.unknownPackage,
      );
    });

    test('anything else is an error', () {
      expect(
        classifyRunAs(
          const ProcessOutput(exitCode: 1, stderr: 'error: device offline'),
        ),
        RunAsOutcome.error,
      );
    });
  });

  group('FCM token pattern', () {
    final token = 'fakeInstanceId0000000:APA91b${'a' * 60}';

    test('finds a token inside a log line', () {
      expect(
        FcmTokenPattern.firstIn('10-04 12:00:01 I/flutter: FCM token: $token'),
        token,
      );
    });

    test('ignores text that only resembles a token', () {
      expect(FcmTokenPattern.firstIn('short:APA91babc'), isNull);
    });

    test('recognises a whole token, current or legacy', () {
      expect(FcmTokenPattern.looksLikeToken(token), isTrue);
      expect(FcmTokenPattern.looksLikeToken('APA91b${'b' * 120}'), isTrue);
      expect(FcmTokenPattern.looksLikeToken('hello'), isFalse);
    });
  });
}
