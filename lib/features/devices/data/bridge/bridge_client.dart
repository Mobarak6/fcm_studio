import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:fcm_studio/features/devices/data/adb_exception.dart';
import 'package:fcm_studio/features/devices/data/bridge/bridge_channel.dart';
import 'package:fcm_studio/features/devices/data/bridge/bridge_protocol.dart';
import 'package:fcm_studio/features/devices/data/bridge/bridge_status.dart';

/// A chunk of a command's output.
class BridgeOutput {
  const BridgeOutput({required this.bytes, this.isError = false});

  final List<int> bytes;

  /// From standard error rather than standard output.
  final bool isError;
}

/// One request's replies (bridge design §4.2): output chunks, then the exit
/// code. An `error` reply, or losing the connection, ends [output] with an
/// [AdbException] and completes [exitCode] with -1.
class BridgeCall {
  BridgeCall._(this.id, this._kill);

  final int id;
  final void Function() _kill;
  final StreamController<BridgeOutput> _output =
      StreamController<BridgeOutput>();
  final Completer<int> _exit = Completer<int>();

  /// Single-subscription; buffered until listened to.
  Stream<BridgeOutput> get output => _output.stream;

  Future<int> get exitCode => _exit.future;

  /// Asks the bridge to stop the process.
  void kill() => _kill();

  void _add(BridgeOutput chunk) {
    if (!_output.isClosed) {
      _output.add(chunk);
    }
  }

  void _finish(int code) {
    if (!_output.isClosed) {
      unawaited(_output.close());
    }
    if (!_exit.isCompleted) {
      _exit.complete(code);
    }
  }

  void _fail(AdbException error) {
    if (!_output.isClosed) {
      _output.addError(error);
      unawaited(_output.close());
    }
    if (!_exit.isCompleted) {
      _exit.complete(-1);
    }
  }
}

/// What the app asks of the bridge (bridge design §4.4, §4.6).
abstract interface class BridgeControl {
  BridgeStatus get status;

  /// Every status change. Never ends.
  Stream<BridgeStatus> get statuses;

  /// At app start: connects when auto-connect is on or the page is local.
  Future<void> start();

  /// Connects now and keeps retrying until connected; also "Try again".
  void connect();

  /// Closes the connection, stops retrying and turns auto-connect off.
  Future<void> disconnect();

  /// Saves fcm_bridge.dart from this site.
  void download();

  /// Sends [message] with a new id. Throws [AdbException] unless connected.
  BridgeCall request(Map<String, Object?> message);
}

/// The page's side of the bridge: one WebSocket, retried while wanted, with
/// replies routed by request id.
class BridgeClient implements BridgeControl {
  BridgeClient({
    required this._connector,
    required this._readAutoConnect,
    required this._writeAutoConnect,
    this._isBlocked = _neverBlocked,
    this._download = _noDownload,
    this._alwaysAutoConnect = false,
    this._backoff = defaultBackoff,
    this._helloTimeout = const Duration(seconds: 5),
  });

  static const notConnectedMessage = 'The bridge is not connected.';
  static const stoppedMessage = 'The bridge stopped.';

  /// What the bridge says when it has no adb; also used if it says nothing.
  static const noAdbProblem =
      "adb wasn't found. Start the bridge with --adb <path to adb>.";

  /// 1, 2, 4, 8, 16, then 30 seconds; the same as DevicesBloc's.
  static Duration defaultBackoff(int attempt) =>
      Duration(seconds: min(30, 1 << (attempt - 1).clamp(0, 5)));

  static Future<bool> _neverBlocked() async => false;

  static void _noDownload() {}

  final BridgeConnector _connector;
  final Future<bool> Function() _readAutoConnect;
  final Future<void> Function(bool on) _writeAutoConnect;
  final Future<bool> Function() _isBlocked;
  final void Function() _download;
  final bool _alwaysAutoConnect;
  final Duration Function(int attempt) _backoff;
  final Duration _helloTimeout;

  final StreamController<BridgeStatus> _statuses =
      StreamController<BridgeStatus>.broadcast();
  final Map<int, BridgeCall> _calls = {};
  BridgeStatus _status = const BridgeOff();
  BridgeChannel? _channel;
  StreamSubscription<String>? _subscription;
  Completer<Map<String, Object?>?>? _hello;
  Timer? _retry;
  bool _wanted = false;
  bool _opening = false;
  int _attempt = 0;
  int _nextId = 1;

  /// Bumped by every open and by disconnect, so late events are ignored.
  int _generation = 0;

  @override
  BridgeStatus get status => _status;

  @override
  Stream<BridgeStatus> get statuses => _statuses.stream;

  @override
  Future<void> start() async {
    if (_alwaysAutoConnect || await _readAutoConnect()) {
      connect();
    }
  }

  @override
  void connect() {
    _wanted = true;
    _attempt = 0;
    _retry?.cancel();
    _retry = null;
    if (_channel == null && !_opening) {
      unawaited(_open());
    }
  }

  @override
  Future<void> disconnect() async {
    _wanted = false;
    _retry?.cancel();
    _retry = null;
    _generation++;
    _opening = false;
    await _drop();
    _setStatus(const BridgeOff());
    await _writeAutoConnect(false);
  }

  @override
  void download() => _download();

  @override
  BridgeCall request(Map<String, Object?> message) {
    if (_channel == null || _status is! BridgeConnected) {
      throw const AdbException(notConnectedMessage);
    }
    final id = _nextId++;
    final call = BridgeCall._(id, () => _send({'type': 'kill', 'id': id}));
    _calls[id] = call;
    _send({...message, 'id': id});
    return call;
  }

  /// Stops retrying and closes the connection (tests and shutdown).
  Future<void> dispose() async {
    _wanted = false;
    _retry?.cancel();
    _generation++;
    await _drop();
    await _statuses.close();
  }

  Future<void> _open() async {
    final generation = ++_generation;
    _opening = true;
    _setStatus(const BridgeConnecting());
    final BridgeChannel channel;
    try {
      channel = await _connector(BridgeProtocol.url);
    } on Object {
      if (generation == _generation) {
        _opening = false;
        await _failed(generation);
      }
      return;
    }
    if (generation != _generation) {
      unawaited(channel.close());
      return;
    }
    final hello = Completer<Map<String, Object?>?>();
    _channel = channel;
    _hello = hello;
    _subscription = channel.messages.listen(
      _onMessage,
      onError: (Object _) {},
      onDone: () => _onClosed(generation),
    );
    final first = await hello.future.timeout(
      _helloTimeout,
      onTimeout: () => null,
    );
    if (generation != _generation) {
      return;
    }
    _opening = false;
    final protocol = first?['protocol'];
    if (first == null || first['type'] != 'hello' || protocol is! int) {
      await _drop();
      await _failed(generation);
      return;
    }
    if (protocol != BridgeProtocol.version) {
      await _drop();
      _setStatus(BridgeWrongVersion(protocol));
      return;
    }
    _attempt = 0;
    final adb = first['adb'];
    final problem = first['problem'];
    _setStatus(
      adb is String
          ? BridgeConnected(adb)
          : BridgeNoAdb(problem is String ? problem : noAdbProblem),
    );
    await _writeAutoConnect(true);
  }

  void _onMessage(String text) {
    Map<String, Object?>? message;
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, Object?>) {
        message = decoded;
      }
    } on FormatException {
      message = null;
    }
    final hello = _hello;
    if (hello != null) {
      _hello = null;
      if (!hello.isCompleted) {
        hello.complete(message);
      }
      return;
    }
    if (message == null) {
      return;
    }
    final id = message['id'];
    final call = id is int ? _calls[id] : null;
    if (call == null) {
      return;
    }
    switch (message['type']) {
      case 'stdout' || 'stderr':
        final data = message['data'];
        if (data is String) {
          try {
            call._add(
              BridgeOutput(
                bytes: base64Decode(data),
                isError: message['type'] == 'stderr',
              ),
            );
          } on FormatException {
            // A broken chunk is dropped.
          }
        }
      case 'exit':
        _calls.remove(id);
        final code = message['code'];
        call._finish(code is int ? code : -1);
      case 'error':
        _calls.remove(id);
        final reason = message['message'];
        call._fail(
          AdbException(reason is String ? reason : 'The bridge failed.'),
        );
    }
  }

  void _onClosed(int generation) {
    if (generation != _generation) {
      return;
    }
    final hello = _hello;
    if (hello != null) {
      // Closed before hello: _open sees no hello and handles it.
      _hello = null;
      if (!hello.isCompleted) {
        hello.complete(null);
      }
      return;
    }
    _channel = null;
    _subscription = null;
    _failCalls();
    if (_status is BridgeWrongVersion) {
      return;
    }
    unawaited(_failed(generation));
  }

  Future<void> _failed(int generation) async {
    final blocked = await _isBlocked();
    if (generation != _generation) {
      return;
    }
    _setStatus(blocked ? const BridgeBlocked() : const BridgeNotRunning());
    if (!_wanted) {
      return;
    }
    _retry?.cancel();
    _retry = Timer(_backoff(++_attempt), () {
      _retry = null;
      if (_wanted && _channel == null && !_opening) {
        unawaited(_open());
      }
    });
  }

  /// Closes the channel without the close counting as the bridge stopping.
  Future<void> _drop() async {
    final channel = _channel;
    final subscription = _subscription;
    _channel = null;
    _subscription = null;
    final hello = _hello;
    _hello = null;
    if (hello != null && !hello.isCompleted) {
      hello.complete(null);
    }
    _failCalls();
    await subscription?.cancel();
    await channel?.close();
  }

  void _failCalls() {
    final calls = List.of(_calls.values);
    _calls.clear();
    for (final call in calls) {
      call._fail(const AdbException(stoppedMessage));
    }
  }

  void _send(Map<String, Object?> message) =>
      _channel?.send(jsonEncode(message));

  void _setStatus(BridgeStatus status) {
    if (status == _status) {
      return;
    }
    _status = status;
    if (!_statuses.isClosed) {
      _statuses.add(status);
    }
  }
}
