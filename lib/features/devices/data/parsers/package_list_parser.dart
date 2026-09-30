import 'dart:convert';

/// Parses `pm list packages -3`: one `package:<name>` per line. Sorted.
List<String> parsePackageList(String text) => [
  for (final line in const LineSplitter().convert(text))
    if (line.trim().startsWith('package:'))
      line.trim().substring('package:'.length),
]..sort();
