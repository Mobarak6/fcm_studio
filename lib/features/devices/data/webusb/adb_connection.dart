import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:fcm_studio/features/devices/data/adb_exception.dart';
import 'package:fcm_studio/features/devices/data/webusb/adb_key.dart';
import 'package:fcm_studio/features/devices/data/webusb/adb_message.dart';
import 'package:fcm_studio/features/devices/data/webusb/usb_transport.dart';

/// What a broken connection means for the user (design §7).
String connectionFailureMessage(Object error) => switch (error) {
  UsbDisconnectedException() =>
    'The phone was disconnected. Plug it in and click Retry.',
  _ =>
    'The connection to the phone failed. Unplug it, plug it in again, and '
        'click Retry.',
};

/// What the phone said about itself in its `CNXN` (design §4.4).
class AdbBanner {
  const AdbBanner({this.properties = const {}, this.features = const {}});

  /// Parses `device::ro.product.model=…;…;features=shell_v2,cmd`.
  factory AdbBanner.parse(String text) {
    final separator = text.indexOf('::');
    final body = separator < 0 ? '' : text.substring(separator + 2);
    final properties = <String, String>{};
    var features = <String>{};
    for (final part in body.split(';')) {
      final equals = part.indexOf('=');
      if (equals <= 0) {
        continue;
      }
      final key = part.substring(0, equals);
      final value = part.substring(equals + 1);
      if (key == 'features') {
        features = {
          for (final feature in value.split(','))
            if (feature.isNotEmpty) feature,
        };
      } else {
        properties[key] = value;
      }
    }
    return AdbBanner(properties: properties, features: features);
  }

  final Map<String, String> properties;
  final Set<String> features;

  /// Android 7 and newer: commands report stdout, stderr and an exit code.
  bool get hasShellV2 => features.contains('shell_v2');

  String? get model => properties['ro.product.model'];
}

/// One adb connection to a phone over USB (design §4.4).
class AdbConnection {
  AdbConnection({
    required this._transport,
    required this._loadKey,
    required this._keyName,
  }) {
    // Errors reach whoever awaits connect(); never report them twice.
    _handshake.future.ignore();
  }

  /// adb 0x01000001 and later skip checksums.
  static const version = 0x01000001;
  static const maxPayload = 1024 * 1024;
  static const hostBanner = 'host::features=shell_v2,cmd';
  static const _authToken = 1;
  static const _authSignature = 2;
  static const _authPublicKey = 3;

  final UsbTransport _transport;
  final Future<AdbKey> Function() _loadKey;

  /// Shown on the phone after the key, e.g. `fcm-studio@studio.example.com`.
  final String _keyName;

  final Map<int, AdbStream> _streams = {};
  final Completer<AdbBanner> _handshake = Completer<AdbBanner>();
  final Completer<Object> _lost = Completer<Object>();
  void Function()? _onWaitingForApproval;
  Future<void> _writes = Future<void>.value();
  int _nextLocalId = 1;
  bool _sentSignature = false;
  bool _started = false;
  bool _closed = false;
  Object? _failure;

  /// Completes with the error when the connection breaks. Never completes
  /// after [close].
  Future<Object> get lost => _lost.future;

  /// Runs the handshake. [onWaitingForApproval] is called when the phone
  /// shows "Allow USB debugging?". Throws what broke the connection.
  Future<AdbBanner> connect({void Function()? onWaitingForApproval}) {
    if (_started) {
      throw StateError('connect() was already called.');
    }
    _started = true;
    _onWaitingForApproval = onWaitingForApproval;
    unawaited(_readLoop());
    unawaited(
      _send(
        AdbMessage.text(AdbCommand.cnxn, version, maxPayload, hostBanner),
      ).catchError((Object error) => _fail(error)),
    );
    return _handshake.future;
  }

  /// Opens [service], e.g. `shell,v2,raw:getprop`. Throws [AdbException]
  /// when the phone refuses it or the connection is gone.
  Future<AdbStream> open(String service) async {
    final failure = _failure;
    if (failure != null) {
      throw AdbException(connectionFailureMessage(failure));
    }
    if (_closed) {
      throw const AdbException('The connection to the phone is closed.');
    }
    final stream = AdbStream._(this, _nextLocalId++);
    _streams[stream.localId] = stream;
    try {
      await _send(
        AdbMessage.text(AdbCommand.open, stream.localId, 0, '$service\u0000'),
      );
    } on Object catch (error) {
      _fail(error);
    }
    await stream._opened.future;
    return stream;
  }

  /// Closes every stream and releases the phone.
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    const closed = AdbException('The connection to the phone is closed.');
    if (_started && !_handshake.isCompleted) {
      _handshake.completeError(closed);
    }
    for (final stream in [..._streams.values]) {
      stream._onFailed(closed);
    }
    _streams.clear();
    await _transport.close();
  }

  Future<void> _readLoop() async {
    try {
      while (!_closed) {
        await _handle(await _readMessage());
      }
    } on Object catch (error) {
      _fail(error);
    }
  }

  Future<AdbMessage> _readMessage() async {
    final header = AdbMessage.parseHeader(
      await _readExactly(AdbMessage.headerLength),
    );
    final payload = header.length == 0
        ? Uint8List(0)
        : await _readExactly(header.length);
    return AdbMessage(header.command, header.arg0, header.arg1, payload);
  }

  /// USB may deliver a message in several transfers.
  Future<Uint8List> _readExactly(int length) async {
    final bytes = BytesBuilder(copy: false);
    while (bytes.length < length) {
      bytes.add(await _transport.read(length - bytes.length));
    }
    return bytes.takeBytes();
  }

  Future<void> _handle(AdbMessage message) async {
    switch (message.command) {
      case AdbCommand.cnxn:
        if (!_handshake.isCompleted) {
          _handshake.complete(AdbBanner.parse(message.text));
        }
      case AdbCommand.auth:
        await _onAuth(message);
      case AdbCommand.okay:
        _streams[message.arg1]?._onOkay(message.arg0);
      case AdbCommand.wrte:
        final stream = _streams[message.arg1];
        if (stream == null) {
          await _send(AdbMessage(AdbCommand.clse, 0, message.arg0));
        } else {
          stream._onData(message.payload);
          await _send(AdbMessage(AdbCommand.okay, message.arg1, message.arg0));
        }
      case AdbCommand.clse:
        _streams.remove(message.arg1)?._onClosed();
    }
  }

  /// The first token gets a signature; a second one means the phone doesn't
  /// know the key yet, so it gets the public key and asks the user.
  Future<void> _onAuth(AdbMessage message) async {
    if (message.arg0 != _authToken) {
      return;
    }
    final key = await _loadKey();
    if (!_sentSignature) {
      _sentSignature = true;
      await _send(
        AdbMessage(
          AdbCommand.auth,
          _authSignature,
          0,
          key.sign(message.payload),
        ),
      );
    } else {
      // The phone shows "Allow USB debugging?" as soon as the key arrives.
      _onWaitingForApproval?.call();
      await _send(
        AdbMessage(
          AdbCommand.auth,
          _authPublicKey,
          0,
          utf8.encode(key.publicKeyPayload(_keyName)),
        ),
      );
    }
  }

  /// Header and payload go out as separate transfers, one message at a time.
  Future<void> _send(AdbMessage message) {
    final sent = _writes.then((_) async {
      await _transport.write(message.header());
      if (message.payload.isNotEmpty) {
        await _transport.write(message.payload);
      }
    });
    _writes = sent.catchError((Object _) {});
    return sent;
  }

  void _fail(Object error) {
    if (_closed || _failure != null) {
      return;
    }
    _failure = error;
    if (_started && !_handshake.isCompleted) {
      _handshake.completeError(error);
    }
    final failure = AdbException(connectionFailureMessage(error));
    for (final stream in [..._streams.values]) {
      stream._onFailed(failure);
    }
    _streams.clear();
    _lost.complete(error);
  }
}

/// One open service on a phone, e.g. a running shell command.
class AdbStream {
  AdbStream._(this._connection, this.localId) {
    // Errors reach open()'s caller; never report them as uncaught.
    _opened.future.ignore();
  }

  final AdbConnection _connection;
  final int localId;
  int? _remoteId;
  final Completer<void> _opened = Completer<void>();
  final StreamController<Uint8List> _data = StreamController<Uint8List>();
  bool _done = false;

  /// What the phone writes, until it closes the stream. Errors are
  /// [AdbException]s.
  Stream<Uint8List> get data => _data.stream;

  void _onOkay(int remoteId) {
    _remoteId ??= remoteId;
    if (!_opened.isCompleted) {
      _opened.complete();
    }
  }

  void _onData(Uint8List bytes) {
    if (!_done) {
      _data.add(bytes);
    }
  }

  void _onClosed() {
    if (!_opened.isCompleted) {
      _opened.completeError(
        const AdbException('The phone refused to run the command.'),
      );
    }
    _finish();
  }

  void _onFailed(AdbException error) {
    if (!_opened.isCompleted) {
      _opened.completeError(error);
    } else if (!_done) {
      _data.addError(error);
    }
    _finish();
  }

  void _finish() {
    if (!_done) {
      _done = true;
      unawaited(_data.close());
    }
  }

  /// Closes the stream, which stops its command on the phone.
  Future<void> close() async {
    if (_done) {
      return;
    }
    _finish();
    _connection._streams.remove(localId);
    final remoteId = _remoteId;
    if (remoteId == null ||
        _connection._closed ||
        _connection._failure != null) {
      return;
    }
    try {
      await _connection._send(AdbMessage(AdbCommand.clse, localId, remoteId));
    } on Object {
      // The connection is going away anyway.
    }
  }
}
