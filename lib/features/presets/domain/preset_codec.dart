import 'dart:convert';

import 'package:fcm_studio/core/utils/ids.dart';
import 'package:fcm_studio/features/presets/domain/preset.dart';

class PresetFormatException implements Exception {
  const PresetFormatException(this.message);

  final String message;

  @override
  String toString() => 'PresetFormatException: $message';
}

/// What to do with an imported preset whose name already exists (spec §6).
enum ImportConflictChoice { keepBoth, replace, skip }

/// A read import file, and the names in it that already exist.
class ImportPreview {
  const ImportPreview({required this.incoming, required this.conflicts});

  final List<Preset> incoming;
  final List<String> conflicts;
}

/// The `*.fcmpresets.json` export format and the import rules (spec §6).
abstract final class PresetCodec {
  static const format = 'fcm-studio.presets';
  static const version = 1;
  static const fileExtension = '.fcmpresets.json';

  /// An export file. Presets hold no credentials, targets or history.
  static String encode(List<Preset> presets, {required DateTime exportedAt}) =>
      const JsonEncoder.withIndent('  ').convert({
        'format': format,
        'version': version,
        'exportedAt': exportedAt.toUtc().toIso8601String(),
        'presets': [
          for (final preset in presets)
            preset.toJson()
              ..remove('schemaVersion')
              ..['builtIn'] = false,
        ],
      });

  /// Reads an export file. Throws [PresetFormatException] that says what is wrong.
  static List<Preset> decode(String text) {
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      throw const PresetFormatException('This file is not valid JSON.');
    }
    if (decoded is! Map<String, Object?> || decoded['format'] != format) {
      throw const PresetFormatException(
        'This is not an FCM Studio presets file '
        '(expected "format": "fcm-studio.presets").',
      );
    }
    final fileVersion = decoded['version'];
    if (fileVersion is! int || fileVersion < 1) {
      throw const PresetFormatException(
        'The file has no valid format version.',
      );
    }
    if (fileVersion > version) {
      throw PresetFormatException(
        'This file was made by a newer FCM Studio (format version $fileVersion). '
        'Update FCM Studio to import it.',
      );
    }
    final presets = decoded['presets'];
    if (presets is! List<Object?>) {
      throw const PresetFormatException('The file has no "presets" list.');
    }
    final result = <Preset>[];
    for (final (index, raw) in presets.indexed) {
      if (raw is! Map<String, Object?>) {
        throw PresetFormatException('Preset ${index + 1} is not an object.');
      }
      try {
        result.add(Preset.fromJson(raw));
      } on FormatException catch (e) {
        throw PresetFormatException('Preset ${index + 1}: ${e.message}');
      }
    }
    return result;
  }

  /// Lists the incoming presets whose name already exists in their group,
  /// ignoring case, as [fullName]s.
  static ImportPreview preview({
    required List<Preset> existing,
    required List<Preset> incoming,
  }) {
    final taken = {for (final p in existing) identityOf(p)};
    return ImportPreview(
      incoming: incoming,
      conflicts: [
        for (final p in incoming)
          if (taken.contains(identityOf(p))) fullName(p),
      ],
    );
  }

  /// The presets to store for an import. Imported presets are never built-in
  /// and get a new id, unless they replace an existing user preset, which
  /// keeps its id and createdAt. A clash (the same name in the same group, as
  /// an existing preset or an earlier one in the file) is skipped, or kept
  /// with " (2)". Replace only
  /// applies to an existing non-built-in preset, once; any other clash is kept
  /// as a copy. Result ids are unique.
  static List<Preset> resolve({
    required List<Preset> existing,
    required List<Preset> incoming,
    required ImportConflictChoice choice,
    required IdGenerator newId,
    required DateTime now,
  }) {
    final taken = {for (final p in existing) identityOf(p): p};
    final replaceable = {
      for (final p in existing)
        if (!p.builtIn) identityOf(p): p,
    };
    final result = <Preset>[];
    for (final preset in incoming) {
      final key = identityOf(preset);
      final clash = taken[key];
      if (clash != null && choice == ImportConflictChoice.skip) {
        continue;
      }
      final replaced = clash != null && choice == ImportConflictChoice.replace
          ? replaceable.remove(key)
          : null;
      final stored = preset.copyWith(
        id: replaced?.id ?? newId(),
        name: clash == null || replaced != null
            ? preset.name
            : uniqueName(preset.name, namesIn(taken.values, preset.group)),
        builtIn: false,
        createdAt: replaced?.createdAt ?? preset.createdAt,
        updatedAt: now,
      );
      taken[identityOf(stored)] = stored;
      result.add(stored);
    }
    return result;
  }

  /// [name], or `name (2)`, `name (3)`… whichever is not in [taken]
  /// (a set of [normalizeName]d names).
  static String uniqueName(String name, Set<String> taken) {
    if (!taken.contains(normalizeName(name))) {
      return name;
    }
    var n = 2;
    while (taken.contains(normalizeName('$name ($n)'))) {
      n++;
    }
    return '$name ($n)';
  }

  /// How names are compared: trimmed and lower-cased.
  static String normalizeName(String name) => name.trim().toLowerCase();

  /// What tells presets apart: their group and name, compared with
  /// [normalizeName]. Presets in different groups may share a name.
  static String identity(String group, String name) =>
      '${normalizeName(group)}\u0000${normalizeName(name)}';

  static String identityOf(Preset preset) =>
      identity(preset.group, preset.name);

  /// The [normalizeName]d names that [presets] use in [group].
  static Set<String> namesIn(Iterable<Preset> presets, String group) => {
    for (final p in presets)
      if (normalizeName(p.group) == normalizeName(group)) normalizeName(p.name),
  };

  /// [preset]'s name after its group, e.g. "StackFood › Customer app · Order
  /// status", for places that show it without a group header.
  static String fullName(Preset preset) {
    final group = preset.group.trim();
    return group.isEmpty ? preset.name : '$group › ${preset.name}';
  }
}
