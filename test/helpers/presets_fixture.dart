import 'dart:io';

/// Reads the bundled built-in presets straight from disk, for tests.
Future<String> loadBuiltInPresetsFromFile() async =>
    File('assets/presets/builtin.json').readAsStringSync();
