import 'dart:async';
import 'dart:convert';

import 'package:fcm_studio/features/devices/data/parsers/device_list_parser.dart';
import 'package:fcm_studio/features/devices/domain/adb_device.dart';

/// Splits `adb track-devices -l` output into device lists. Each message is a
/// 4-hex-digit length followed by that many bytes of device list (spec §9.2).
/// A message may arrive in several chunks, and a chunk may hold several.
class TrackDevicesDecoder
    extends StreamTransformerBase<List<int>, List<AdbDevice>> {
  const TrackDevicesDecoder();

  @override
  Stream<List<AdbDevice>> bind(Stream<List<int>> stream) async* {
    final buffer = <int>[];
    await for (final chunk in stream) {
      buffer.addAll(chunk);
      while (buffer.length >= 4) {
        final length = int.tryParse(
          ascii.decode(buffer.sublist(0, 4), allowInvalid: true),
          radix: 16,
        );
        if (length == null) {
          throw const FormatException(
            'adb track-devices sent data without a length prefix.',
          );
        }
        if (buffer.length < 4 + length) {
          break;
        }
        final payload = utf8.decode(
          buffer.sublist(4, 4 + length),
          allowMalformed: true,
        );
        buffer.removeRange(0, 4 + length);
        yield parseDeviceList(payload);
      }
    }
  }
}
