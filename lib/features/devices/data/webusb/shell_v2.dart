import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:fcm_studio/features/devices/data/adb_exception.dart';
import 'package:fcm_studio/features/devices/data/process_runner.dart';
import 'package:fcm_studio/features/devices/data/webusb/adb_connection.dart';

/// The shell protocol v2 (Android 7+): stdout, stderr and the exit code
/// arrive as separate packets (design §4.6).
abstract final class ShellV2 {
  static const stdout = 1;
  static const stderr = 2;
  static const exit = 3;

  /// No terminal, so the output is passed through byte for byte.
  static String service(String command) => 'shell,v2,raw:$command';

  /// A packet as the phone sends it: id, little-endian length, data.
  static Uint8List packet(int id, List<int> data) {
    final bytes = Uint8List(5 + data.length)..[0] = id;
    ByteData.sublistView(bytes).setUint32(1, data.length, Endian.little);
    return bytes..setRange(5, bytes.length, data);
  }
}

class ShellV2Packet {
  const ShellV2Packet(this.id, this.data);

  final int id;
  final Uint8List data;
}

/// Splits stream data into packets, which may be split across chunks or
/// several to a chunk.
class ShellV2Decoder {
  Uint8List _pending = Uint8List(0);

  List<ShellV2Packet> add(List<int> chunk) {
    final data = Uint8List(_pending.length + chunk.length)
      ..setAll(0, _pending)
      ..setAll(_pending.length, chunk);
    final packets = <ShellV2Packet>[];
    var offset = 0;
    while (data.length - offset >= 5) {
      final length = ByteData.sublistView(
        data,
        offset + 1,
        offset + 5,
      ).getUint32(0, Endian.little);
      if (data.length - offset - 5 < length) {
        break;
      }
      packets.add(
        ShellV2Packet(
          data[offset],
          data.sublist(offset + 5, offset + 5 + length),
        ),
      );
      offset += 5 + length;
    }
    _pending = data.sublist(offset);
    return packets;
  }
}

/// Runs [command] on the phone to the end. Throws [AdbException] when the
/// phone refuses it or the connection breaks.
Future<ProcessOutput> runShellV2(
  AdbConnection connection,
  String command,
) async {
  final stream = await connection.open(ShellV2.service(command));
  final decoder = ShellV2Decoder();
  final stdout = BytesBuilder(copy: false);
  final stderr = BytesBuilder(copy: false);
  int? exitCode;
  try {
    await for (final chunk in stream.data) {
      for (final packet in decoder.add(chunk)) {
        switch (packet.id) {
          case ShellV2.stdout:
            stdout.add(packet.data);
          case ShellV2.stderr:
            stderr.add(packet.data);
          case ShellV2.exit:
            exitCode = packet.data.isEmpty ? 0 : packet.data.first;
        }
      }
      if (exitCode != null) {
        break;
      }
    }
  } finally {
    await stream.close();
  }
  final code = exitCode;
  if (code == null) {
    throw const AdbException(
      'The phone ended the command without an exit code.',
    );
  }
  return ProcessOutput(
    exitCode: code,
    stdout: utf8.decode(stdout.takeBytes(), allowMalformed: true),
    stderr: utf8.decode(stderr.takeBytes(), allowMalformed: true),
  );
}

/// A long-running command, e.g. `logcat --pid=…`. [kill] closes its stream,
/// which stops it on the phone.
class ShellV2Process implements RunningProcess {
  ShellV2Process._(this._stream) {
    _subscription = _stream.data.listen(
      _onData,
      onError: _onError,
      onDone: () => _finish(-1),
    );
  }

  static Future<ShellV2Process> start(
    AdbConnection connection,
    String command,
  ) async => ShellV2Process._(await connection.open(ShellV2.service(command)));

  final AdbStream _stream;
  final StreamController<List<int>> _stdout = StreamController<List<int>>();
  final Completer<int> _exit = Completer<int>();
  final ShellV2Decoder _decoder = ShellV2Decoder();
  late final StreamSubscription<Uint8List> _subscription;

  @override
  Stream<List<int>> get stdout => _stdout.stream;

  @override
  Future<int> get exitCode => _exit.future;

  void _onData(Uint8List chunk) {
    for (final packet in _decoder.add(chunk)) {
      switch (packet.id) {
        case ShellV2.stdout:
          if (!_stdout.isClosed) {
            _stdout.add(packet.data);
          }
        case ShellV2.exit:
          _finish(packet.data.isEmpty ? 0 : packet.data.first);
      }
    }
  }

  void _onError(Object error, StackTrace stackTrace) {
    if (!_stdout.isClosed) {
      _stdout.addError(error, stackTrace);
    }
    _finish(-1);
  }

  void _finish(int code) {
    if (!_exit.isCompleted) {
      _exit.complete(code);
      unawaited(_stdout.close());
    }
  }

  @override
  void kill() {
    _finish(-9);
    unawaited(_subscription.cancel());
    unawaited(_stream.close());
  }
}
