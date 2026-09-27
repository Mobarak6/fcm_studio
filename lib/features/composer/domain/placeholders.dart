import 'package:fcm_studio/features/composer/domain/render_issue.dart';
import 'package:fcm_studio/features/presets/domain/variable_def.dart';

/// Values of the built-in placeholders `{{now_iso}}`, `{{now_ms}}` and
/// `{{uuid}}`. Each has one value per render, so `{{uuid}}` used twice gives
/// the same id twice.
class BuiltinValues {
  const BuiltinValues({required this.now, required this.uuid});

  static const names = {'now_iso', 'now_ms', 'uuid'};

  final DateTime now;
  final String uuid;

  String? valueOf(String name) => switch (name) {
    'now_iso' => now.toUtc().toIso8601String(),
    'now_ms' => '${now.millisecondsSinceEpoch}',
    'uuid' => uuid,
    _ => null,
  };
}

abstract final class Placeholders {
  /// `{{key}}`, with optional spaces inside the braces.
  static final RegExp pattern = RegExp(
    r'\{\{\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*\}\}',
  );
  static final RegExp _whole = RegExp(
    r'^\{\{\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*\}\}$',
  );

  /// The key when [text] is exactly one placeholder, otherwise null.
  static String? wholeKey(String text) => _whole.firstMatch(text)?.group(1);

  /// Every placeholder key in the string values of [value], in order of first use.
  static List<String> keysIn(Object? value) {
    final keys = <String>{};
    void visit(Object? node) {
      switch (node) {
        case final String text:
          for (final match in pattern.allMatches(text)) {
            keys.add(match.group(1)!);
          }
        case final Map<String, Object?> map:
          map.values.forEach(visit);
        case final List<Object?> list:
          list.forEach(visit);
      }
    }

    visit(value);
    return keys.toList();
  }
}

/// Marks a value to be left out of its object.
const Object _remove = Object();

/// Step 1 of the rendering pipeline (spec §5.2): replaces `{{key}}` in string
/// values (not in keys), recursively. Problems go into [errors] and [notes].
class PlaceholderSubstitution {
  PlaceholderSubstitution({
    required this.definitions,
    required this.values,
    required this.builtins,
    required this.notes,
    required this.errors,
  });

  final Map<String, VariableDef> definitions;
  final Map<String, String> values;
  final BuiltinValues builtins;
  final List<RenderIssue> notes;
  final List<RenderIssue> errors;

  /// Each problem is reported once per key, at its first use.
  final Set<String> _reported = {};

  Map<String, Object?> apply(Map<String, Object?> template) =>
      _map(template, '');

  Map<String, Object?> _map(Map<String, Object?> map, String path) {
    final result = <String, Object?>{};
    map.forEach((key, value) {
      final substituted = _value(value, path.isEmpty ? key : '$path.$key');
      if (!identical(substituted, _remove)) {
        result[key] = substituted;
      }
    });
    return result;
  }

  Object? _value(Object? value, String path) {
    switch (value) {
      case final String text:
        return _string(text, path);
      case final Map<String, Object?> map:
        return _map(map, path);
      case final List<Object?> list:
        final result = <Object?>[];
        for (final (index, item) in list.indexed) {
          final substituted = _value(item, '$path[$index]');
          if (!identical(substituted, _remove)) {
            result.add(substituted);
          }
        }
        return result;
      default:
        return value;
    }
  }

  Object? _string(String text, String path) {
    final definition = definitions[Placeholders.wholeKey(text)];
    if (definition != null &&
        (definition.type == VariableType.number ||
            definition.type == VariableType.boolean)) {
      return _typed(definition, text, path);
    }
    return text.replaceAllMapped(
      Placeholders.pattern,
      (match) => _text(match.group(1)!, path) ?? match.group(0)!,
    );
  }

  /// The text for `{{key}}`, or null after reporting why it can't be filled.
  /// A definition wins over a built-in with the same name.
  String? _text(String key, String path) {
    final definition = definitions[key];
    if (definition == null) {
      final builtin = builtins.valueOf(key);
      if (builtin == null) {
        _error(
          key,
          path,
          'Unknown placeholder {{$key}}. Add it under Variables.',
        );
      }
      return builtin;
    }
    final value = values[key] ?? definition.defaultValue;
    if (definition.required && value.trim().isEmpty) {
      _error(key, path, 'Fill in "${definition.label}" ({{$key}}).');
      return null;
    }
    return value;
  }

  /// A string that is exactly one number or boolean placeholder becomes that
  /// type, so `apns.payload.aps.badge` stays an integer.
  Object? _typed(VariableDef definition, String original, String path) {
    final key = definition.key;
    final text = (values[key] ?? definition.defaultValue).trim();
    if (text.isEmpty) {
      if (definition.required) {
        _error(key, path, 'Fill in "${definition.label}" ({{$key}}).');
        return original;
      }
      notes.add(RenderIssue(path, 'Removed because {{$key}} is empty.'));
      return _remove;
    }
    if (definition.type == VariableType.boolean) {
      if (text == 'true' || text == 'false') {
        return text == 'true';
      }
      _error(
        key,
        path,
        '"${definition.label}" must be true or false, not "$text".',
      );
      return original;
    }
    final number = VariableDef.parseNumber(text);
    if (number == null) {
      _error(key, path, '"${definition.label}" must be a number, not "$text".');
      return original;
    }
    return number;
  }

  void _error(String key, String path, String message) {
    if (_reported.add(key)) {
      errors.add(RenderIssue(path, message));
    }
  }
}
