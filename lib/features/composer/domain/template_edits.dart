import 'dart:convert';

/// Pure edits on a message template, used by the Form tab (spec §5.3).
/// Every function returns a new map and keeps the fields it doesn't touch.
abstract final class TemplateEdits {
  /// Top-level objects that stay even when empty: removing `notification`
  /// would turn the message into a data-only one.
  static const keepWhenEmpty = {'notification'};

  /// The settings "Data only" adds for background delivery (spec §5.3).
  static const _backgroundSettings = <(List<String>, Object)>[
    (['apns', 'headers', 'apns-priority'], '5'),
    (['apns', 'headers', 'apns-push-type'], 'background'),
    (['apns', 'payload', 'aps', 'content-available'], 1),
  ];

  /// A deep, modifiable copy.
  static Map<String, Object?> copy(Map<String, Object?> template) =>
      jsonDecode(jsonEncode(template)) as Map<String, Object?>;

  /// The value at [path], or null when any part of it is missing.
  static Object? read(Map<String, Object?> template, List<String> path) {
    Object? node = template;
    for (final key in path) {
      if (node is! Map<String, Object?>) {
        return null;
      }
      node = node[key];
    }
    return node;
  }

  /// Sets [value] at [path], creating objects on the way. A null or empty
  /// string removes the key, and objects left empty by that are removed too.
  static Map<String, Object?> write(
    Map<String, Object?> template,
    List<String> path,
    Object? value,
  ) {
    final result = copy(template);
    _write(result, path, value, topLevel: true);
    return result;
  }

  static bool _isEmptyValue(Object? value) => value == null || value == '';

  static void _write(
    Map<String, Object?> map,
    List<String> path,
    Object? value, {
    required bool topLevel,
  }) {
    final key = path.first;
    if (path.length == 1) {
      if (_isEmptyValue(value)) {
        map.remove(key);
      } else {
        map[key] = value;
      }
      return;
    }
    if (map[key] is! Map<String, Object?>) {
      if (_isEmptyValue(value)) {
        return;
      }
      map[key] = <String, Object?>{};
    }
    final child = map[key]! as Map<String, Object?>;
    _write(child, path.sublist(1), value, topLevel: false);
    if (child.isEmpty && !(topLevel && keepWhenEmpty.contains(key))) {
      map.remove(key);
    }
  }

  static bool isDataOnly(Map<String, Object?> template) =>
      !template.containsKey('notification');

  /// Switches to a data-only (background) message.
  static Map<String, Object?> toDataOnly(Map<String, Object?> template) {
    var result = copy(template)..remove('notification');
    result = write(result, ['android', 'priority'], 'high');
    for (final (path, value) in _backgroundSettings) {
      result = write(result, path, value);
    }
    return result;
  }

  /// Switches back to a visible notification: adds an empty `notification`
  /// first and removes the background settings that [toDataOnly] added.
  static Map<String, Object?> toNotification(Map<String, Object?> template) {
    if (!isDataOnly(template)) {
      return copy(template);
    }
    var result = <String, Object?>{
      'notification': <String, Object?>{'title': '', 'body': ''},
      ...copy(template),
    };
    for (final (path, value) in _backgroundSettings) {
      if (read(result, path) == value) {
        result = write(result, path, null);
      }
    }
    return result;
  }

  /// The `data` entries in order; empty when `data` is missing or not an object.
  static List<MapEntry<String, Object?>> dataEntries(
    Map<String, Object?> template,
  ) {
    final data = template['data'];
    return data is Map<String, Object?> ? data.entries.toList() : const [];
  }

  /// Replaces `data` with [entries] in their order. No entries removes `data`.
  static Map<String, Object?> withData(
    Map<String, Object?> template,
    List<MapEntry<String, Object?>> entries,
  ) {
    final result = copy(template);
    if (entries.isEmpty) {
      result.remove('data');
    } else {
      result['data'] = Map<String, Object?>.fromEntries(entries);
    }
    return result;
  }
}
