import 'dart:convert';

import 'package:fcm_studio/core/fcm/fcm_client.dart';

/// Builds a bash `curl` command for an FCM send (spec §8.3). Only bash quoting
/// is supported; on Windows it works in Git Bash or WSL.
abstract final class CurlBuilder {
  static const tokenVariable = r'$FCM_ACCESS_TOKEN';

  /// With [accessToken] null, the command reads the token from
  /// `$FCM_ACCESS_TOKEN` (double-quoted, so bash expands it).
  static String build({
    required String projectId,
    required Map<String, Object?> body,
    String? accessToken,
    Map<String, String> extraHeaders = const {},
  }) {
    final authorization = accessToken == null
        ? '"Authorization: Bearer $tokenVariable"'
        : quote('Authorization: Bearer $accessToken');
    return [
      'curl -X POST ${quote(FcmClient.sendUri(projectId).toString())}',
      '-H $authorization',
      "-H 'Content-Type: application/json; charset=utf-8'",
      for (final header in extraHeaders.entries)
        '-H ${quote('${header.key}: ${header.value}')}',
      '-d ${quote(jsonEncode(body))}',
    ].join(' \\\n  ');
  }

  /// Single-quotes [value] for bash. A `'` inside becomes `'\''`.
  static String quote(String value) => "'${value.replaceAll("'", r"'\''")}'";
}
