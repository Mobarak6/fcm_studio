import 'package:fcm_studio/features/devices/data/parsers/fcm_token_pattern.dart';

final _pemPrivateKey = RegExp(
  r'-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----',
);
final _secretJsonField = RegExp(
  r'("(?:private_key|refresh_token|access_token|assertion)"\s*:\s*")[^"]*(")',
);
final _bearer = RegExp(r'(Bearer\s+)[A-Za-z0-9._~+/=-]+');
final _googleAccessToken = RegExp(r'ya29\.[A-Za-z0-9._-]+');

/// Removes private keys, OAuth tokens and device tokens from [input] so it can be shown or logged.
String redact(String input) {
  return input
      .replaceAll(_pemPrivateKey, '[REDACTED PRIVATE KEY]')
      .replaceAllMapped(_secretJsonField, (m) => '${m[1]}[REDACTED]${m[2]}')
      .replaceAllMapped(_bearer, (m) => '${m[1]}[REDACTED]')
      .replaceAll(_googleAccessToken, 'ya29.[REDACTED]')
      .replaceAll(FcmTokenPattern.inText, '[REDACTED]');
}
