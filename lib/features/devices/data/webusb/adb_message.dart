import 'dart:convert';
import 'dart:typed_data';

import 'package:equatable/equatable.dart';

/// The phone sent something the adb protocol doesn't allow.
class AdbProtocolException implements Exception {
  const AdbProtocolException(this.message);

  final String message;

  @override
  String toString() => 'AdbProtocolException: $message';
}

/// The adb wire commands (AOSP `adb/protocol.txt`), little-endian ASCII.
abstract final class AdbCommand {
  static const cnxn = 0x4E584E43;
  static const auth = 0x48545541;
  static const open = 0x4E45504F;
  static const okay = 0x59414B4F;
  static const wrte = 0x45545257;
  static const clse = 0x45534C43;
}

/// What [AdbMessage.parseHeader] reads from 24 header bytes.
class AdbHeader {
  const AdbHeader(this.command, this.arg0, this.arg1, this.length);

  final int command;
  final int arg0;
  final int arg1;

  /// The payload length.
  final int length;
}

/// One adb message: a 24-byte header and its payload (design §4.3).
class AdbMessage extends Equatable {
  AdbMessage(this.command, this.arg0, this.arg1, [List<int> payload = const []])
    : payload = Uint8List.fromList(payload);

  AdbMessage.text(int command, int arg0, int arg1, String text)
    : this(command, arg0, arg1, utf8.encode(text));

  static const headerLength = 24;

  final int command;
  final int arg0;
  final int arg1;
  final Uint8List payload;

  /// The payload as text, without NUL characters.
  String get text =>
      utf8.decode(payload, allowMalformed: true).replaceAll('\u0000', '');

  /// Six little-endian uint32s: command, arg0, arg1, payload length,
  /// payload checksum and magic (`command ^ 0xFFFFFFFF`).
  Uint8List header() {
    final data = ByteData(headerLength)
      ..setUint32(0, command, Endian.little)
      ..setUint32(4, arg0, Endian.little)
      ..setUint32(8, arg1, Endian.little)
      ..setUint32(12, payload.length, Endian.little)
      ..setUint32(16, checksum(payload), Endian.little)
      ..setUint32(20, command ^ 0xFFFFFFFF, Endian.little);
    return data.buffer.asUint8List();
  }

  /// The sum of the payload's bytes. Phones on adb 0x01000001 and later
  /// don't check it, but older ones do.
  static int checksum(List<int> bytes) {
    var sum = 0;
    for (final byte in bytes) {
      sum = (sum + byte) & 0xFFFFFFFF;
    }
    return sum;
  }

  /// Reads a header. Throws [AdbProtocolException] for a wrong size or magic.
  static AdbHeader parseHeader(List<int> bytes) {
    if (bytes.length != headerLength) {
      throw AdbProtocolException(
        'Expected a $headerLength-byte message header, got ${bytes.length} bytes.',
      );
    }
    final data = ByteData.sublistView(Uint8List.fromList(bytes));
    final command = data.getUint32(0, Endian.little);
    if (data.getUint32(20, Endian.little) != command ^ 0xFFFFFFFF) {
      throw const AdbProtocolException(
        'The phone sent a message with a bad header.',
      );
    }
    return AdbHeader(
      command,
      data.getUint32(4, Endian.little),
      data.getUint32(8, Endian.little),
      data.getUint32(12, Endian.little),
    );
  }

  @override
  List<Object?> get props => [command, arg0, arg1, payload];

  @override
  String toString() {
    final name = String.fromCharCodes([
      for (var shift = 0; shift < 32; shift += 8) (command >> shift) & 0xFF,
    ]);
    return 'AdbMessage($name, $arg0, $arg1, "$text")';
  }
}
