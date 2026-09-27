/// Shortens a long value for lists, e.g. `fAbC12…9xYz`. Short values are
/// returned unchanged.
String shortenMiddle(String value, {int head = 6, int tail = 4}) =>
    value.length <= head + tail + 1
    ? value
    : '${value.substring(0, head)}…${value.substring(value.length - tail)}';
