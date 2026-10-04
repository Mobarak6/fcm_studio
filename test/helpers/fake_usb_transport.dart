import 'dart:async';
import 'dart:typed_data';

import 'package:fcm_studio/features/devices/data/webusb/adb_message.dart';
import 'package:fcm_studio/features/devices/data/webusb/usb_transport.dart';

/// The phone end of a [UsbTransport]: the test queues what the phone sends
/// and reads back what the host wrote.
class FakeUsbTransport implements UsbTransport {
  /// At most this many bytes per read, to test messages split across USB
  /// transfers.
  int maxChunk = 1 << 20;
  bool closed = false;

  final List<int> _incoming = [];
  Completer<void>? _arrived;
  Object? _failure;
  final StreamController<AdbMessage> _hostMessages =
      StreamController<AdbMessage>();
  late final StreamIterator<AdbMessage> _host = StreamIterator(
    _hostMessages.stream,
  );
  AdbHeader? _pendingHeader;

  /// The phone sends [message]: header, then payload.
  void phoneSends(AdbMessage message) =>
      phoneSendsBytes([...message.header(), ...message.payload]);

  void phoneSendsBytes(List<int> bytes) {
    _incoming.addAll(bytes);
    _wake();
  }

  /// Every pending and later transfer fails, as when the phone is unplugged.
  void unplug() {
    _failure = const UsbDisconnectedException();
    _wake();
  }

  /// The next message the host wrote.
  Future<AdbMessage> nextHostMessage() async {
    final more = await _host.moveNext().timeout(const Duration(seconds: 2));
    if (!more) {
      throw StateError('The host wrote nothing more.');
    }
    return _host.current;
  }

  void _wake() {
    final arrived = _arrived;
    _arrived = null;
    arrived?.complete();
  }

  @override
  Future<Uint8List> read(int length) async {
    while (true) {
      final failure = _failure;
      if (failure != null) {
        throw failure;
      }
      if (closed) {
        throw const UsbDisconnectedException('The transport is closed.');
      }
      if (_incoming.isNotEmpty) {
        var count = length < _incoming.length ? length : _incoming.length;
        if (count > maxChunk) {
          count = maxChunk;
        }
        final chunk = Uint8List.fromList(_incoming.sublist(0, count));
        _incoming.removeRange(0, count);
        return chunk;
      }
      await (_arrived ??= Completer<void>()).future;
    }
  }

  @override
  Future<void> write(Uint8List bytes) async {
    final failure = _failure;
    if (failure != null) {
      throw failure;
    }
    final header = _pendingHeader;
    if (header == null) {
      final parsed = AdbMessage.parseHeader(bytes);
      if (parsed.length == 0) {
        _hostMessages.add(AdbMessage(parsed.command, parsed.arg0, parsed.arg1));
      } else {
        _pendingHeader = parsed;
      }
    } else {
      _pendingHeader = null;
      _hostMessages.add(
        AdbMessage(header.command, header.arg0, header.arg1, bytes),
      );
    }
  }

  @override
  Future<void> close() async {
    closed = true;
    _wake();
  }
}
