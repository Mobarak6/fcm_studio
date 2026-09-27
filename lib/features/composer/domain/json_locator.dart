/// Finds where a field is in the JSON editor's text, for "Show in JSON".
abstract final class JsonLocator {
  static final RegExp _segment = RegExp(r'^([A-Za-z0-9_\-]+)(?:\[(\d+)\])?$');

  /// Turns an FCM field path such as `message.android.notification.color` or
  /// `message.data[0].value` into keys of [template]. `data[0]` is the first
  /// entry of the `data` object. Stops at the first part that doesn't exist.
  static List<String> resolve(String fieldPath, Map<String, Object?> template) {
    final path = fieldPath.startsWith('message.')
        ? fieldPath.substring('message.'.length)
        : fieldPath;
    final result = <String>[];
    Object? node = template;
    for (final part in path.split('.')) {
      final match = _segment.firstMatch(part);
      final key = match == null ? null : _findKey(node, match.group(1)!);
      if (match == null || key == null) {
        break;
      }
      result.add(key);
      node = (node as Map<String, Object?>)[key];
      final index = match.group(2);
      if (index == null) {
        continue;
      }
      final i = int.parse(index);
      if (node is Map<String, Object?>) {
        final keys = node.keys.toList();
        if (i < keys.length) {
          result.add(keys[i]);
        }
        // What follows (`.key`, `.value`) belongs to the map entry.
        return result;
      }
      if (node is! List<Object?> || i >= node.length) {
        break;
      }
      result.add('$i');
      node = node[i];
    }
    return result;
  }

  /// FCM reports proto names (`click_action`); the JSON may use either form.
  static String? _findKey(Object? node, String name) {
    if (node is! Map<String, Object?>) {
      return null;
    }
    for (final candidate in [name, _camel(name), _snake(name)]) {
      if (node.containsKey(candidate)) {
        return candidate;
      }
    }
    return null;
  }

  static String _camel(String name) =>
      name.replaceAllMapped(RegExp('_([a-z])'), (m) => m[1]!.toUpperCase());

  static String _snake(String name) =>
      name.replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]!.toLowerCase()}');

  /// The 1-based line of the key at [path] in [text], or of its closest
  /// ancestor that exists. Null when not even the first key exists.
  /// Array items are addressed by their index as a string.
  static int? lineOf(String text, List<String> path) {
    if (path.isEmpty) {
      return null;
    }
    final frames = <_Frame>[];
    var line = 1;
    int? bestLine;
    var bestLength = 0;
    var i = 0;
    while (i < text.length) {
      final char = text[i];
      if (char == '"') {
        final buffer = StringBuffer();
        i++;
        while (i < text.length && text[i] != '"') {
          if (text[i] == r'\' && i + 1 < text.length) {
            buffer.write(text[i + 1]);
            i += 2;
          } else {
            buffer.write(text[i]);
            i++;
          }
        }
        final frame = frames.lastOrNull;
        if (frame != null && frame.isObject && frame.expectingKey) {
          frame
            ..key = buffer.toString()
            ..expectingKey = false;
          final current = [for (final f in frames) f.segment];
          if (current.length > bestLength && _startsWith(path, current)) {
            bestLength = current.length;
            bestLine = line;
            if (bestLength == path.length) {
              return line;
            }
          }
        }
      } else if (char == '\n') {
        line++;
      } else if (char == '{' || char == '[') {
        frames.add(_Frame(isObject: char == '{'));
      } else if (char == '}' || char == ']') {
        if (frames.isNotEmpty) {
          frames.removeLast();
        }
      } else if (char == ',') {
        final frame = frames.lastOrNull;
        if (frame != null) {
          if (frame.isObject) {
            frame.expectingKey = true;
          } else {
            frame.index++;
          }
        }
      }
      i++;
    }
    return bestLine;
  }

  static bool _startsWith(List<String> path, List<String> prefix) {
    if (prefix.length > path.length) {
      return false;
    }
    for (var i = 0; i < prefix.length; i++) {
      if (path[i] != prefix[i]) {
        return false;
      }
    }
    return true;
  }
}

/// An object or array the scanner is inside.
class _Frame {
  _Frame({required this.isObject});

  final bool isObject;
  bool expectingKey = true;
  String key = '';
  int index = 0;

  String get segment => isObject ? key : '$index';
}
