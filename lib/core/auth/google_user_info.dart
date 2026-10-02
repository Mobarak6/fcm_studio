import 'dart:async';
import 'dart:convert';

import 'package:fcm_studio/core/auth/access_token_provider.dart';
import 'package:fcm_studio/core/utils/redact.dart';
import 'package:http/http.dart' as http;

/// Finds which Google account an access token belongs to.
abstract interface class GoogleUserInfo {
  /// The account's email, in lowercase. Throws [AuthException].
  Future<String> emailOf(AccessToken token);
}

/// Google's OpenID Connect userinfo endpoint (plan Decision 2).
class GoogleUserInfoApi implements GoogleUserInfo {
  GoogleUserInfoApi({required http.Client httpClient}) : _http = httpClient;

  static final Uri endpoint = Uri.parse(
    'https://openidconnect.googleapis.com/v1/userinfo',
  );

  final http.Client _http;

  @override
  Future<String> emailOf(AccessToken token) async {
    final http.Response response;
    try {
      response = await _http
          .get(endpoint, headers: {'Authorization': 'Bearer ${token.value}'})
          .timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw const AuthException(
        'Google did not say which account signed in within 20 seconds.',
      );
    } on Exception catch (e) {
      throw AuthException(
        'Network error while reading the signed-in account: ${redact('$e')}',
      );
    }
    Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      decoded = null;
    }
    final email = decoded is Map<String, Object?> ? decoded['email'] : null;
    if (response.statusCode != 200 || email is! String || email.isEmpty) {
      throw AuthException(
        'Could not read which Google account signed in '
        '(HTTP ${response.statusCode}).',
        statusCode: response.statusCode,
      );
    }
    return email.toLowerCase();
  }
}
