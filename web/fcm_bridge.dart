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
