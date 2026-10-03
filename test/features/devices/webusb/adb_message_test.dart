import 'dart:typed_data';

import 'package:fcm_studio/features/devices/data/webusb/adb_message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a CNXN header has the AOSP layout', () {
    final message = AdbMessage.text(
      AdbCommand.cnxn,
      0x01000001,
      1048576,
      'host::features=shell_v2,cmd',
    );
    final header = message.header();
    final data = ByteData.sublistView(header);
    expect(header, hasLength(24));
    // 'CNXN' in ASCII, little-endian.
    expect(header.sublist(0, 4), [0x43, 0x4E, 0x58, 0x4E]);
    expect(data.getUint32(4, Endian.little), 0x01000001);
    expect(data.getUint32(8, Endian.little), 1048576);
    expect(data.getUint32(12, Endian.little), 27);
    expect(
      data.getUint32(16, Endian.little),
      'host::features=shell_v2,cmd'.codeUnits.fold<int>(0, (a, b) => a + b),
    );
    expect(data.getUint32(20, Endian.little), 0x4E584E43 ^ 0xFFFFFFFF);
  });

  test('every command reads back from its own header', () {
    for (final command in [
      AdbCommand.cnxn,
      AdbCommand.auth,
      AdbCommand.open,
      AdbCommand.okay,
      AdbCommand.wrte,
      AdbCommand.clse,
    ]) {
      final header = AdbMessage.parseHeader(
        AdbMessage(command, 7, 9, [1, 2, 3]).header(),
      );
      expect(
        (header.command, header.arg0, header.arg1, header.length),
        (command, 7, 9, 3),
      );
    }
  });

  test('a payload over 64 KiB keeps its length and checksum', () {
    final payload = List<int>.filled(70000, 0xFF);
    final data = ByteData.sublistView(
      AdbMessage(AdbCommand.wrte, 1, 2, payload).header(),
    );
    expect(data.getUint32(12, Endian.little), 70000);
    expect(data.getUint32(16, Endian.little), 70000 * 0xFF);
  });

  test('a bad magic or a short header is a protocol error', () {
    final header = AdbMessage(AdbCommand.okay, 1, 2).header()..[20] ^= 1;
    expect(
      () => AdbMessage.parseHeader(header),
      throwsA(isA<AdbProtocolException>()),
    );
    expect(
      () => AdbMessage.parseHeader([1, 2, 3]),
      throwsA(isA<AdbProtocolException>()),
    );
  });

  test('text drops the trailing NUL', () {
    expect(
      AdbMessage.text(AdbCommand.open, 1, 0, 'shell:x\u0000').text,
      'shell:x',
    );
  });
}
