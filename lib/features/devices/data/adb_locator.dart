import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:fcm_studio/features/devices/data/process_runner.dart';
import 'package:path/path.dart' as p;

/// Where adb was found (spec §9.1).
enum AdbSource {
  settings,
  androidHome,
  androidSdkRoot,
  sdkDefault,
  homebrew,
  usrLocal,
  path,
}

class AdbLocation extends Equatable {
  const AdbLocation({
    required this.path,
    required this.source,
    required this.version,
  });

  final String path;
  final AdbSource source;

  /// The first line of `adb version`, e.g. "Android Debug Bridge version 1.0.41".
  final String version;

  @override
  List<Object?> get props => [path, source, version];
}

class AdbSearch extends Equatable {
  const AdbSearch({this.found, this.tried = const []});

  final AdbLocation? found;

  /// Every path tried, in order, for the "not found" message.
  final List<String> tried;

  @override
  List<Object?> get props => [found, tried];
}

/// Finds a working adb (spec §9.1). Apps started from Finder don't get the
/// shell's PATH, so known locations come before the PATH lookup.
class AdbLocator {
  AdbLocator({
    required this._runner,
    required this._environment,
    required this._isWindows,
  });

  final ProcessRunner _runner;
  final Map<String, String> _environment;
  final bool _isWindows;

  Future<AdbSearch> locate({String? userPath}) async {
    final tried = <String>[];
    Future<AdbLocation?> attempt(String path, AdbSource source) async {
      if (tried.contains(path)) {
        return null;
      }
      tried.add(path);
      final version = await _version(path);
      return version == null
          ? null
          : AdbLocation(path: path, source: source, version: version);
    }

    for (final (path, source) in _knownLocations(userPath)) {
      final found = await attempt(path, source);
      if (found != null) {
        return AdbSearch(found: found, tried: tried);
      }
    }
    final onPath = await _lookUpOnPath();
    if (onPath != null) {
      final found = await attempt(onPath, AdbSource.path);
      if (found != null) {
        return AdbSearch(found: found, tried: tried);
      }
    }
    return AdbSearch(tried: tried);
  }

  List<(String, AdbSource)> _knownLocations(String? userPath) {
    final context = _isWindows ? p.windows : p.posix;
    final adb = _isWindows ? 'adb.exe' : 'adb';
    String? env(String name) {
      final value = _environment[name];
      return value == null || value.isEmpty ? null : value;
    }

    final androidHome = env('ANDROID_HOME');
    final sdkRoot = env('ANDROID_SDK_ROOT');
    final localAppData = env('LOCALAPPDATA');
    final home = env('HOME');
    return [
      if (userPath != null && userPath.trim().isNotEmpty)
        (userPath.trim(), AdbSource.settings),
      if (androidHome != null)
        (
          context.join(androidHome, 'platform-tools', adb),
          AdbSource.androidHome,
        ),
      if (sdkRoot != null)
        (
          context.join(sdkRoot, 'platform-tools', adb),
          AdbSource.androidSdkRoot,
        ),
      if (_isWindows && localAppData != null)
        (
          context.join(localAppData, 'Android', 'Sdk', 'platform-tools', adb),
          AdbSource.sdkDefault,
        ),
      if (!_isWindows && home != null)
        (
          context.join(
            home,
            'Library',
            'Android',
            'sdk',
            'platform-tools',
            adb,
          ),
          AdbSource.sdkDefault,
        ),
      if (!_isWindows) ('/opt/homebrew/bin/adb', AdbSource.homebrew),
      if (!_isWindows) ('/usr/local/bin/adb', AdbSource.usrLocal),
    ];
  }

  Future<String?> _lookUpOnPath() async {
    try {
      final output = await _runner.run(_isWindows ? 'where' : 'which', const [
        'adb',
      ]);
      if (output.exitCode != 0) {
        return null;
      }
      return const LineSplitter()
          .convert(output.stdout)
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .firstOrNull;
    } on ProcessRunException {
      return null;
    }
  }

  /// The first line of `adb version`, or null when [path] doesn't run adb.
  Future<String?> _version(String path) async {
    try {
      final output = await _runner.run(path, const ['version']);
      if (output.exitCode != 0 ||
          !output.stdout.contains('Android Debug Bridge')) {
        return null;
      }
      return const LineSplitter().convert(output.stdout).first.trim();
    } on ProcessRunException {
      return null;
    }
  }
}
