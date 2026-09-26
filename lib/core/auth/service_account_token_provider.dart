import 'dart:async';
import 'dart:convert';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:fcm_studio/core/auth/access_token_provider.dart';
import 'package:fcm_studio/core/auth/service_account_key.dart';
import 'package:fcm_studio/core/utils/clock.dart';
import 'package:fcm_studio/core/utils/redact.dart';
import 'package:http/http.dart' as http;

/// Gets access tokens by signing a JWT with a service account key (works on every platform).
class ServiceAccountTokenProvider implements AccessTokenProvider {
  ServiceAccountTokenProvider({
    required this.key,
    required http.Client httpClient,
    this._clock = const SystemClock(),
  }) : _http = httpClient,
       _signingKey = RSAPrivateKey(key.privateKeyPem);

  static final Uri tokenEndpoint = Uri.parse(
    'https://oauth2.googleapis.com/token',
  );
  static const scopes = [
    'https://www.googleapis.com/auth/firebase.messaging',
    'https://www.googleapis.com/auth/firebase.readonly',
  ];
  static const refreshMargin = Duration(minutes: 5);
  static const _requestTimeout = Duration(seconds: 20);

  final ServiceAccountKey key;
  final http.Client _http;
  final Clock _clock;
  final RSAPrivateKey _signingKey;
  AccessToken? _cached;
  Future<AccessToken>? _inFlight;

  @override
  Future<AccessToken> getToken({bool forceRefresh = false}) {
    final cached = _cached;
    if (!forceRefresh &&
        cached != null &&
        cached.isValidAt(_clock.now(), margin: refreshMargin)) {
      return Future.value(cached);
    }
    return _inFlight ??= _fetch().whenComplete(() => _inFlight = null);
  }

  @override
  Map<String, String> extraHeaders(String projectId) => const {};

  /// The signed JWT sent to Google's token endpoint. Visible for tests.
  String buildAssertion() {
    final issuedAt = _clock.now().millisecondsSinceEpoch ~/ 1000;
    final jwt = JWT(
      {
        'iss': key.clientEmail,
        'sub': key.clientEmail,
        'aud': tokenEndpoint.toString(),
        'scope': scopes.join(' '),
        'iat': issuedAt,
        'exp': issuedAt + 3600,
      },
      header: {'kid': key.privateKeyId},
    );
    return jwt.sign(
      _signingKey,
      algorithm: JWTAlgorithm.RS256,
      noIssueAt: true,
    );
  }

  Future<AccessToken> _fetch() async {
    final http.Response response;
    try {
      response = await _http
          .post(
            tokenEndpoint,
            body: {
              'grant_type': 'urn:ietf:params:oauth:grant-type:jwt-bearer',
              'assertion': buildAssertion(),
            },
          )
          .timeout(_requestTimeout);
    } on TimeoutException {
      throw const AuthException(
        'Google did not answer the token request within 20 seconds.',
      );
    } on http.ClientException catch (e) {
      throw AuthException(
        'Network error while getting an access token: ${redact(e.message)}',
      );
    }

    final body = _decode(response.body);
    if (response.statusCode != 200) {
      throw AuthException(
        _describeError(response.statusCode, body),
        statusCode: response.statusCode,
      );
    }
    final token = body?['access_token'];
    final expiresIn = body?['expires_in'];
    if (token is! String || expiresIn is! num) {
      throw const AuthException(
        'Google returned an unexpected token response.',
      );
    }
    final accessToken = AccessToken(
      token,
      _clock.now().add(Duration(seconds: expiresIn.toInt())),
    );
    _cached = accessToken;
    return accessToken;
  }

  static Map<String, Object?>? _decode(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, Object?> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  static String _describeError(int status, Map<String, Object?>? body) {
    final error = body?['error'];
    final description = body?['error_description'];
    final detail = [
      if (error is String) error,
      if (description is String) description,
    ].join(': ');
    if (error == 'invalid_grant') {
      return 'Google rejected this key ($detail). '
          'The key may have been deleted or the service account disabled.';
    }
    return 'Token request failed (HTTP $status${detail.isEmpty ? '' : ', $detail'}).';
  }
}
