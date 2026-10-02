import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:fcm_studio/core/auth/access_token_provider.dart';
import 'package:fcm_studio/core/auth/google_auth_flow.dart';
import 'package:fcm_studio/core/auth/oauth_config.dart';
import 'package:fcm_studio/core/utils/clock.dart';
import 'package:fcm_studio/core/utils/redact.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

/// The desktop sign-in, or null when `config/oauth.json` has no desktop client.
GoogleAuthFlow? createGoogleAuthFlow(
  OAuthConfig? config,
  http.Client httpClient,
) {
  final clientId = config?.desktopClientId;
  final clientSecret = config?.desktopClientSecret;
  if (clientId == null || clientSecret == null) {
    return null;
  }
  return DesktopGoogleAuthFlow(
    clientId: clientId,
    clientSecret: clientSecret,
    httpClient: httpClient,
  );
}

/// Google sign-in for desktop apps: the system browser, with Google's answer
/// sent to a one-off server on 127.0.0.1 (spec §4.1, plan Decision 1).
class DesktopGoogleAuthFlow implements GoogleAuthFlow {
  DesktopGoogleAuthFlow({
    required this.clientId,
    required this.clientSecret,
    required http.Client httpClient,
    Future<bool> Function(Uri url)? openBrowser,
    this.timeout = const Duration(minutes: 5),
    this._clock = const SystemClock(),
  }) : _http = httpClient,
       _openBrowser = openBrowser ?? _launch;

  static final Uri authorizationEndpoint = Uri.parse(
    'https://accounts.google.com/o/oauth2/v2/auth',
  );
  static final Uri tokenEndpoint = Uri.parse(
    'https://oauth2.googleapis.com/token',
  );
  static const _requestTimeout = Duration(seconds: 20);

  final String clientId;
  final String clientSecret;
  final Duration timeout;
  final http.Client _http;
  final Future<bool> Function(Uri url) _openBrowser;
  final Clock _clock;

  @override
  bool get canRefresh => true;

  @override
  Future<GoogleCredentials> signIn({
    String? loginHint,
    Future<void>? cancel,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    try {
      final redirectUri = 'http://127.0.0.1:${server.port}';
      final state = _randomString(32);
      final verifier = _randomString(64);
      final url = authorizationEndpoint.replace(
        queryParameters: {
          'client_id': clientId,
          'redirect_uri': redirectUri,
          'response_type': 'code',
          'scope': googleScopes.join(' '),
          'code_challenge': _challenge(verifier),
          'code_challenge_method': 'S256',
          'state': state,
          'access_type': 'offline',
          // "consent" makes Google return a refresh token every time.
          'prompt': 'select_account consent',
          'login_hint': ?loginHint,
        },
      );
      if (!await _openBrowser(url)) {
        throw const AuthException(
          'Could not open the browser for Google sign-in.',
        );
      }
      final code = await _waitForCode(server, state, cancel);
      final body = await _post({
        'code': code,
        'client_id': clientId,
        'client_secret': clientSecret,
        'redirect_uri': redirectUri,
        'grant_type': 'authorization_code',
        'code_verifier': verifier,
      }, isRefresh: false);
      final refreshToken = body['refresh_token'];
      return _credentials(
        body,
        refreshToken: refreshToken is String ? refreshToken : null,
      );
    } finally {
      await server.close(force: true);
    }
  }

  @override
  Future<GoogleCredentials> refresh(String refreshToken) async {
    final body = await _post({
      'client_id': clientId,
      'client_secret': clientSecret,
      'refresh_token': refreshToken,
      'grant_type': 'refresh_token',
    }, isRefresh: true);
    // Google doesn't send the refresh token again; keep the one we have.
    return _credentials(body, refreshToken: refreshToken);
  }

  Future<String> _waitForCode(
    HttpServer server,
    String state,
    Future<void>? cancel,
  ) {
    final result = Completer<String>();
    final subscription = server.listen((request) async {
      final query = request.uri.queryParameters;
      if (request.uri.path != '/' || query['state'] != state) {
        // e.g. the browser asking for /favicon.ico, or a forged request.
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      final error = query['error'];
      final code = query['code'];
      final succeeded = error == null && code != null && code.isNotEmpty;
      await _answer(request, succeeded ? _donePage : _stoppedPage);
      if (result.isCompleted) {
        return;
      }
      if (succeeded) {
        result.complete(code);
      } else if (error == 'access_denied') {
        result.completeError(const GoogleSignInCancelled());
      } else {
        result.completeError(
          AuthException(
            'Google sign-in failed (${error ?? 'no code returned'}).',
          ),
        );
      }
    });
    unawaited(
      cancel?.then((_) {
        if (!result.isCompleted) {
          result.completeError(const GoogleSignInCancelled());
        }
      }),
    );
    return result.future
        .timeout(
          timeout,
          onTimeout: () => throw const AuthException(
            'Google sign-in timed out. Try again, and finish signing in in '
            'your browser.',
          ),
        )
        .whenComplete(subscription.cancel);
  }

  Future<Map<String, Object?>> _post(
    Map<String, String> form, {
    required bool isRefresh,
  }) async {
    final http.Response response;
    try {
      response = await _http
          .post(tokenEndpoint, body: form)
          .timeout(_requestTimeout);
    } on TimeoutException {
      throw const AuthException(
        'Google did not answer the sign-in request within 20 seconds.',
      );
    } on Exception catch (e) {
      throw AuthException(
        'Network error during Google sign-in: ${redact('$e')}',
      );
    }
    final body = _decode(response.body);
    if (response.statusCode == 200 && body != null) {
      return body;
    }
    final error = body?['error'];
    final description = body?['error_description'];
    if (error == 'invalid_grant') {
      if (isRefresh) {
        throw GoogleSignInExpired(
          'Google says this sign-in has expired or was revoked'
          '${description is String ? ' ($description)' : ''}.',
        );
      }
      throw const AuthException('Google rejected the sign-in code. Try again.');
    }
    throw AuthException(
      'Google sign-in request failed (HTTP ${response.statusCode}'
      '${error is String ? ', $error' : ''}).',
      statusCode: response.statusCode,
    );
  }

  GoogleCredentials _credentials(
    Map<String, Object?> body, {
    required String? refreshToken,
  }) {
    final token = body['access_token'];
    final expiresIn = body['expires_in'];
    final scope = body['scope'];
    if (token is! String || expiresIn is! num) {
      throw const AuthException(
        'Google returned an unexpected sign-in response.',
      );
    }
    return GoogleCredentials(
      accessToken: AccessToken(
        token,
        _clock.now().add(Duration(seconds: expiresIn.toInt())),
      ),
      refreshToken: refreshToken,
      scopes: scope is String ? scope.split(' ') : const [],
    );
  }

  static const _donePage =
      '<!doctype html><meta charset="utf-8"><title>FCM Studio</title>'
      '<p style="font-family: sans-serif">Signed in. You can close this tab '
      'and go back to FCM Studio.</p>';
  static const _stoppedPage =
      '<!doctype html><meta charset="utf-8"><title>FCM Studio</title>'
      '<p style="font-family: sans-serif">Sign-in was not completed. You can '
      'close this tab.</p>';

  static Future<void> _answer(HttpRequest request, String html) async {
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.html
      ..write(html);
    await request.response.close();
  }

  static Map<String, Object?>? _decode(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, Object?> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  static final _random = Random.secure();
  static const _alphabet =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';

  static String _randomString(int length) => String.fromCharCodes([
    for (var i = 0; i < length; i++)
      _alphabet.codeUnitAt(_random.nextInt(_alphabet.length)),
  ]);

  static String _challenge(String verifier) => base64Url
      .encode(sha256.convert(ascii.encode(verifier)).bytes)
      .replaceAll('=', '');

  static Future<bool> _launch(Uri url) =>
      launchUrl(url, mode: LaunchMode.externalApplication);
}
