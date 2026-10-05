// @dart=3.0
// FCM Studio bridge. Design: docs/superpowers/specs/2026-10-05-web-bridge-design.md
//
// Lets the FCM Studio web page read FCM tokens from phones through this
// computer's adb, so the phone stays shared with Android Studio and other
// tools. Run it with:
//
//   dart fcm_bridge.dart [--adb <path>] [--allow-origin <origin>]...
//
// It listens on 127.0.0.1 only, accepts only FCM Studio pages, and runs only
// the few adb commands FCM Studio needs. It imports only dart: libraries, so
// it runs without a package, and it stays at Dart 3.0 for older SDKs.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// The page checks this against its own (bridge design §4.2). Raise it
/// whenever the allow-list or the messages change.
const bridgeProtocol = 1;

/// adb's own port is 5037.
const bridgePort = 15037;

/// The hosted FCM Studio addresses. Empty until the hosting URL is decided;
/// until then, use --allow-origin.
const hostedOrigins = <String>[];

/// Sent in `hello` and printed when adb wasn't found.
const noAdbProblem =
    "adb wasn't found. Start the bridge with --adb <path to adb>.";

const _getprop = 'getprop ro.product.marketname; getprop ro.product.model; '
    'getprop ro.product.brand; getprop ro.build.version.release';
const _tokenFile = 'shared_prefs/com.google.android.gms.appid.xml';
final _package = RegExp(r'^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$');
final _serial = RegExp(r'^[A-Za-z0-9._:-]+$');
final _pid = RegExp(r'^--pid=[0-9]{1,10}$');

/// Whether FCM Studio may run [text] as a [kind] command: only the commands
/// its token reading uses (bridge design §4.3).
bool isAllowedCommand(String kind, String text) {
  switch (kind) {
    case 'shell':
      return text == _getprop ||
          text == 'pm list packages -3' ||
          _withPackage(
            text,
            'monkey -p ',
            ' -c android.intent.category.LAUNCHER 1',
          ) ||
          _withPackage(text, 'am force-stop ', '') ||
          _withPackage(text, 'pidof ', '');
    case 'execOut':
      return _withPackage(text, 'run-as ', ' cat $_tokenFile');
    case 'logcat':
      return _pid.hasMatch(text);
    default:
      return false;
  }
}

/// [text] is [prefix], a package name, then [suffix].
bool _withPackage(String text, String prefix, String suffix) {
  if (!text.startsWith(prefix) ||
      !text.endsWith(suffix) ||
      text.length < prefix.length + suffix.length) {
    return false;
  }
  return _package.hasMatch(
    text.substring(prefix.length, text.length - suffix.length),
  );
}

/// A serial adb accepts after `-s`, which can't be mistaken for an option.
bool isAllowedSerial(String serial) =>
    _serial.hasMatch(serial) && !serial.startsWith('-');

/// Whether a page from [origin] may connect (bridge design §4.3).
bool isAllowedOrigin(String? origin, List<String> allowed) {
  if (origin == null) {
    return false;
  }
  if (allowed.contains(origin) || hostedOrigins.contains(origin)) {
    return true;
  }
  final uri = Uri.tryParse(origin);
  return uri != null &&
      uri.scheme == 'http' &&
      (uri.host == 'localhost' || uri.host == '127.0.0.1');
}

/// Whether the Host header names this computer on [port], so a site can't
/// reach the bridge through DNS rebinding.
bool isAllowedHost(String? host, int port) =>
    host == '127.0.0.1:$port' || host == 'localhost:$port';

/// Where adb is, or null (bridge design §4.1): --adb, PATH, ANDROID_HOME,
/// ANDROID_SDK_ROOT, then the Android SDK's usual folder.
String? findAdb({
  required String? flag,
  required Map<String, String> environment,
  required bool isWindows,
  required bool isMacOS,
  required bool Function(String path) exists,
}) {
  if (flag != null) {
    return exists(flag) ? flag : null;
  }
  final separator = isWindows ? r'\' : '/';
  final name = isWindows ? 'adb.exe' : 'adb';
  String inTools(String sdk) => '$sdk${separator}platform-tools$separator$name';
  final candidates = <String>[
    for (final folder
        in (environment['PATH'] ?? '').split(isWindows ? ';' : ':'))
      if (folder.isNotEmpty) '$folder$separator$name',
    for (final key in const ['ANDROID_HOME', 'ANDROID_SDK_ROOT'])
      if ((environment[key] ?? '').isNotEmpty) inTools(environment[key]!),
  ];
  final home = environment['HOME'] ?? '';
  final localAppData = environment['LOCALAPPDATA'] ?? '';
  if (isWindows) {
    if (localAppData.isNotEmpty) {
      candidates.add(inTools('$localAppData\\Android\\Sdk'));
    }
  } else if (home.isNotEmpty) {
    candidates.add(
      inTools(isMacOS ? '$home/Library/Android/sdk' : '$home/Android/Sdk'),
    );
  }
  for (final candidate in candidates) {
    if (exists(candidate)) {
      return candidate;
    }
  }
  return null;
}

/// The command line.
class BridgeOptions {
  BridgeOptions({this.adb, this.allowedOrigins = const [], this.help = false});

  final String? adb;
  final List<String> allowedOrigins;
  final bool help;
}

/// Reads the command line; throws [FormatException] for a bad one.
BridgeOptions parseArguments(List<String> arguments) {
  String? adb;
  final origins = <String>[];
  var help = false;
  for (var i = 0; i < arguments.length; i++) {
    final argument = arguments[i];
    if (argument == '--help' || argument == '-h') {
      help = true;
    } else if (argument == '--adb' || argument == '--allow-origin') {
      if (i + 1 >= arguments.length) {
        throw FormatException('$argument needs a value.');
      }
      final value = arguments[++i];
      if (argument == '--adb') {
        adb = value;
      } else {
        origins.add(normalizeOrigin(value));
      }
    } else {
      throw FormatException('Unknown option: $argument');
    }
  }
  return BridgeOptions(adb: adb, allowedOrigins: origins, help: help);
}

/// Browsers send an origin without a trailing slash.
String normalizeOrigin(String origin) =>
    origin.endsWith('/') ? origin.substring(0, origin.length - 1) : origin;

/// What `--help` prints.
const usage = '''
FCM Studio bridge: lets the FCM Studio web page read FCM tokens from phones
through this computer's adb, so the phone stays shared with your IDE.

Usage: dart fcm_bridge.dart [--adb <path>] [--allow-origin <origin>]...

  --adb <path>             the adb to use (default: PATH, ANDROID_HOME,
                           ANDROID_SDK_ROOT, then the Android SDK's folder)
  --allow-origin <origin>  also accept FCM Studio from this address,
                           e.g. https://fcm-studio.example.com
  --help                   show this help
''';

/// Starts a process; tests pass a fake.
typedef StartProcess = Future<Process> Function(
  String executable,
  List<String> arguments,
);

/// adb's arguments for a `run` request, exactly as FCM Studio's desktop app
/// builds them (bridge design §4.2).
List<String> adbArguments(String serial, String kind, String text) => [
      '-s',
      serial,
      ...switch (kind) {
        'shell' => ['shell', text],
        'execOut' => ['exec-out', ...text.split(' ')],
        _ => ['logcat', ...text.split(' ')],
      },
    ];

/// Accepts FCM Studio pages and serves each one (bridge design §4.1, §4.3).
class BridgeServer {
  BridgeServer({
    required this.adbPath,
    required this.allowedOrigins,
    required this.startProcess,
    required this.log,
  });

  final String? adbPath;
  final List<String> allowedOrigins;
  final StartProcess startProcess;
  final void Function(String line) log;

  /// Serves [server] until it closes.
  Future<void> serve(HttpServer server) async {
    await for (final request in server) {
      unawaited(_handle(request, server.port));
    }
  }

  Future<void> _handle(HttpRequest request, int port) async {
    try {
      if (!WebSocketTransformer.isUpgradeRequest(request)) {
        request.response
          ..statusCode = HttpStatus.badRequest
          ..write('FCM Studio bridge: open FCM Studio to use it.');
        await request.response.close();
        return;
      }
      final host = '${request.headers.host}:${request.headers.port}';
      final origin = request.headers.value('origin');
      if (!isAllowedHost(host, port)) {
        log('Refused a connection for host $host.');
        await _refuse(request);
        return;
      }
      if (!isAllowedOrigin(origin, allowedOrigins)) {
        log(origin == null
            ? 'Refused a connection with no origin.'
            : 'Refused a connection from $origin. '
                'To allow it: --allow-origin $origin');
        await _refuse(request);
        return;
      }
      final socket = await WebSocketTransformer.upgrade(request);
      log('FCM Studio connected ($origin).');
      await BridgeSession(
        socket: socket,
        adbPath: adbPath,
        startProcess: startProcess,
        log: log,
      ).run();
      log('FCM Studio disconnected ($origin).');
    } on Object catch (error) {
      log('A connection failed: $error');
    }
  }

  Future<void> _refuse(HttpRequest request) async {
    request.response.statusCode = HttpStatus.forbidden;
    await request.response.close();
  }
}

/// One page's connection: its requests, and the adb processes they started.
/// When it closes, they are all killed.
class BridgeSession {
  BridgeSession({
    required this.socket,
    required this.adbPath,
    required this.startProcess,
    required this.log,
  });

  final WebSocket socket;
  final String? adbPath;
  final StartProcess startProcess;
  final void Function(String line) log;
  final Map<int, Process> _processes = {};
  bool _closed = false;

  Future<void> run() async {
    final hello = <String, Object?>{
      'type': 'hello',
      'protocol': bridgeProtocol,
      'adb': adbPath,
    };
    if (adbPath == null) {
      hello['problem'] = noAdbProblem;
    }
    _send(hello);
    try {
      await for (final message in socket) {
        if (message is String) {
          _onMessage(message);
        }
      }
    } on Object {
      // A broken connection ends the session like a closed one.
    } finally {
      _closed = true;
      for (final process in _processes.values) {
        process.kill();
      }
      _processes.clear();
    }
  }

  void _onMessage(String text) {
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      return;
    }
    if (decoded is! Map<String, Object?>) {
      return;
    }
    final id = decoded['id'];
    if (id is! int) {
      return;
    }
    final type = decoded['type'];
    if (type == 'track') {
      unawaited(_start(id, const ['track-devices', '-l']));
    } else if (type == 'run') {
      _run(id, decoded['serial'], decoded['kind'], decoded['text']);
    } else if (type == 'kill') {
      _processes.remove(id)?.kill();
    } else {
      _send({
        'type': 'error',
        'id': id,
        'message': 'fcm_bridge does not know "$type" requests.',
      });
    }
  }

  void _run(int id, Object? serial, Object? kind, Object? text) {
    if (serial is! String ||
        kind is! String ||
        text is! String ||
        !isAllowedSerial(serial) ||
        !isAllowedCommand(kind, text)) {
      log('Refused a command: ${kind is String ? kind : '?'} '
          '${text is String ? text : ''}');
      _send({
        'type': 'error',
        'id': id,
        'message': 'fcm_bridge refused this command.',
      });
      return;
    }
    unawaited(_start(id, adbArguments(serial, kind, text)));
  }

  Future<void> _start(int id, List<String> arguments) async {
    final adb = adbPath;
    if (adb == null) {
      _send({'type': 'error', 'id': id, 'message': noAdbProblem});
      return;
    }
    final Process process;
    try {
      process = await startProcess(adb, arguments);
    } on Object catch (error) {
      _send({
        'type': 'error',
        'id': id,
        'message': 'Could not start adb at $adb: $error',
      });
      return;
    }
    if (_closed) {
      process.kill();
      return;
    }
    _processes[id] = process;
    final output = Future.wait([
      process.stdout
          .listen((data) => _send({
                'type': 'stdout',
                'id': id,
                'data': base64Encode(data),
              }))
          .asFuture<void>(),
      process.stderr
          .listen((data) => _send({
                'type': 'stderr',
                'id': id,
                'data': base64Encode(data),
              }))
          .asFuture<void>(),
    ]);
    final code = await process.exitCode;
    try {
      // A helper (the adb server) may keep a pipe open, or a pipe broke.
      await output.timeout(const Duration(seconds: 1));
    } on Object {
      // Send the exit anyway.
    }
    _processes.remove(id);
    _send({'type': 'exit', 'id': id, 'code': code});
  }

  void _send(Map<String, Object?> message) {
    if (_closed || socket.closeCode != null) {
      return;
    }
    socket.add(jsonEncode(message));
  }
}

Future<void> main(List<String> arguments) async {
  final BridgeOptions options;
  try {
    options = parseArguments(arguments);
  } on FormatException catch (error) {
    stderr
      ..writeln(error.message)
      ..write(usage);
    exitCode = 64;
    return;
  }
  if (options.help) {
    stdout.write(usage);
    return;
  }
  final adb = findAdb(
    flag: options.adb,
    environment: Platform.environment,
    isWindows: Platform.isWindows,
    isMacOS: Platform.isMacOS,
    exists: (path) => File(path).existsSync(),
  );
  final HttpServer server;
  try {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, bridgePort);
  } on SocketException {
    stderr.writeln(
      'Port $bridgePort is in use; is another bridge already running?',
    );
    exitCode = 1;
    return;
  }
  if (adb == null) {
    stderr.writeln(noAdbProblem);
  }
  stdout.writeln(
    'FCM Studio bridge ready on 127.0.0.1:$bridgePort '
    '(adb: ${adb ?? 'not found'}). Keep this window open.',
  );
  await BridgeServer(
    adbPath: adb,
    allowedOrigins: options.allowedOrigins,
    startProcess: Process.start,
    log: stdout.writeln,
  ).serve(server);
}
