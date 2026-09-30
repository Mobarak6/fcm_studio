import 'dart:convert';

import 'package:fcm_studio/features/devices/data/parsers/fcm_token_pattern.dart';
import 'package:fcm_studio/features/devices/domain/device_token.dart';

/// Reads FCM tokens from `shared_prefs/com.google.android.gms.appid.xml`
/// (spec §9.3). A token key is `<anything>|T|<sender id>|<scope>`. Current
/// SDKs store JSON `{"token", "appVersion", "timestamp"}`; older ones store
/// the raw token.
abstract final class AppIdPrefsParser {
  static final RegExp _entry = RegExp(
    r'<string name="([^"]*)">([\s\S]*?)</string>',
  );
  static final RegExp _tokenKey = RegExp(r'^(.*)\|T\|(\d+)\|(.*)$');
  static final RegExp _entity = RegExp(
    r'&(#x[0-9a-fA-F]+|#\d+|quot|amp|lt|gt|apos);',
  );

  /// One token per sender ID, sorted by sender ID.
  static List<FoundToken> parse(String xml) {
    final bySender = <String, String>{};
    for (final match in _entry.allMatches(xml)) {
      final key = _tokenKey.firstMatch(_unescape(match.group(1)!));
      if (key == null) {
        continue;
      }
      final token = _tokenFrom(_unescape(match.group(2)!));
      if (token != null) {
        bySender[key.group(2)!] = token;
      }
    }
    final senders = bySender.keys.toList()..sort();
    return [
      for (final sender in senders)
        FoundToken(token: bySender[sender]!, senderId: sender),
    ];
  }

  static String? _tokenFrom(String value) {
    final trimmed = value.trim();
    if (!trimmed.startsWith('{')) {
      return FcmTokenPattern.looksLikeToken(trimmed) ? trimmed : null;
    }
    try {
      final json = jsonDecode(trimmed);
      final token = json is Map<String, Object?> ? json['token'] : null;
      return token is String && FcmTokenPattern.looksLikeToken(token)
          ? token
          : null;
    } on FormatException {
      return null;
    }
  }

  static String _unescape(String text) => text.replaceAllMapped(_entity, (m) {
    final entity = m.group(1)!;
    return switch (entity) {
      'quot' => '"',
      'amp' => '&',
      'lt' => '<',
      'gt' => '>',
      'apos' => "'",
      _ when entity.startsWith('#x') => String.fromCharCode(
        int.parse(entity.substring(2), radix: 16),
      ),
      _ => String.fromCharCode(int.parse(entity.substring(1))),
    };
  });
}
