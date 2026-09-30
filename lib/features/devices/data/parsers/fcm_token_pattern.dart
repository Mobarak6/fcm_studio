/// How an FCM registration token looks (spec §9.3).
abstract final class FcmTokenPattern {
  /// A token inside other text, e.g. a log line.
  static final RegExp inText = RegExp(
    r'[A-Za-z0-9_-]{20,}:APA91b[A-Za-z0-9_-]{50,}',
  );

  /// A whole token: the current format, or the older one without an instance ID.
  static final RegExp _whole = RegExp(
    r'^(?:[A-Za-z0-9_-]{20,}:APA91b[A-Za-z0-9_-]{50,}|APA91b[A-Za-z0-9_-]{100,})$',
  );

  static String? firstIn(String text) => inText.firstMatch(text)?.group(0);

  static bool looksLikeToken(String value) => _whole.hasMatch(value.trim());
}
