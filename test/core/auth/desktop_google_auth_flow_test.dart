import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:fcm_studio/core/auth/access_token_provider.dart';
import 'package:fcm_studio/core/auth/google_auth_flow.dart';
import 'package:fcm_studio/core/auth/google_auth_flow_io.dart';
import 'package:fcm_studio/core/auth/oauth_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../helpers/fixed_clock.dart';

/// Plays the browser: sends Google's redirect to the app's loopback server.
Future<String> redirectTo(
  Uri authUrl,
  Map<String, String> query, {
  String path = '/',
}) async {
  final redirect = Uri.parse(authUrl.queryParameters['redirect_uri']!);
  final socket = await Socket.connect(redirect.host, redirect.port);
  final target = Uri(path: path, queryParameters: query).toString();
  socket.write(
    'GET $target HTTP/1.1\r\nHost: ${redirect.host}:${redirect.port}\r\n'
    'Connection: close\r\n\r\n',
  );
  await socket.flush();
  final response = await utf8.decoder.bind(socket).join();
  socket.destroy();
  return response;
}

void main() {
  final clock = FixedClock(DateTime.utc(2026, 10, 4, 12));
  late List<Map<String, String>> tokenRequests;
  late Completer<Uri> opened;

  setUp(() {
    tokenRequests = [];
    opened = Completer<Uri>();
  });

  http.Client tokenEndpoint({int status = 200, Map<String, Object?>? body}) =>
      MockClient((request) async {
        expect(request.url, DesktopGoogleAuthFlow.tokenEndpoint);
        tokenRequests.add(request.bodyFields);
        return http.Response(
          jsonEncode(
            body ??
                {
                  'access_token': 'ya29.desktop',
                  'expires_in': 3599,
                  'refresh_token': '1//refresh',
                  'scope': googleScopes.join(' '),
                  'token_type': 'Bearer',
                },
          ),
          status,
        );
      });

  DesktopGoogleAuthFlow flow({
    http.Client? client,
    bool browserOpens = true,
    Duration timeout = const Duration(minutes: 5),
  }) => DesktopGoogleAuthFlow(
    clientId: 'desktop-id',
    clientSecret: 'desktop-secret',
    httpClient: client ?? tokenEndpoint(),
    openBrowser: (url) async {
      opened.complete(url);
      return browserOpens;
    },
    timeout: timeout,
    clock: clock,
  );

  test(
    'signs in through the browser and exchanges the code with PKCE',
    () async {
      final signIn = flow().signIn(loginHint: 'dev@example.com');
      final url = await opened.future;
      expect(url.origin, 'https://accounts.google.com');
      expect(url.path, '/o/oauth2/v2/auth');
      expect(url.queryParameters['client_id'], 'desktop-id');
      expect(url.queryParameters['scope'], googleScopes.join(' '));
      expect(url.queryParameters['code_challenge_method'], 'S256');
      expect(url.queryParameters['prompt'], 'select_account consent');
      expect(url.queryParameters['login_hint'], 'dev@example.com');
      expect(
        url.queryParameters['redirect_uri'],
        startsWith('http://127.0.0.1:'),
      );

      final page = await redirectTo(url, {
        'code': 'auth-code',
        'state': url.queryParameters['state']!,
      });
      expect(page, contains('You can close this tab'));

      final credentials = await signIn;
      expect(
        credentials.accessToken,
        AccessToken(
          'ya29.desktop',
          clock.now().add(const Duration(seconds: 3599)),
        ),
      );
      expect(credentials.refreshToken, '1//refresh');
      expect(credentials.missingScopes, isEmpty);

      final form = tokenRequests.single;
      expect(form['grant_type'], 'authorization_code');
      expect(form['code'], 'auth-code');
      expect(form['client_secret'], 'desktop-secret');
      expect(form['redirect_uri'], url.queryParameters['redirect_uri']);
      final challenge = base64Url
          .encode(sha256.convert(ascii.encode(form['code_verifier']!)).bytes)
          .replaceAll('=', '');
      expect(challenge, url.queryParameters['code_challenge']);
    },
  );

  test(
    'ignores stray requests and a wrong state, then takes the real answer',
    () async {
      final signIn = flow().signIn();
      final url = await opened.future;
      expect(await redirectTo(url, {}, path: '/favicon.ico'), contains('404'));
      expect(
        await redirectTo(url, {'code': 'forged', 'state': 'wrong'}),
        contains('404'),
      );
      await redirectTo(url, {
        'code': 'auth-code',
        'state': url.queryParameters['state']!,
      });
      expect((await signIn).refreshToken, '1//refresh');
      expect(tokenRequests.single['code'], 'auth-code');
    },
  );

  test(
    'cancelling on the Google page ends the sign-in without a token request',
    () async {
      final signIn = flow().signIn();
      // Listen first: the sign-in can fail before the fake browser returns.
      final cancelled = expectLater(
        signIn,
        throwsA(isA<GoogleSignInCancelled>()),
      );
      final url = await opened.future;
      await redirectTo(url, {
        'error': 'access_denied',
        'state': url.queryParameters['state']!,
      });
      await cancelled;
      expect(tokenRequests, isEmpty);
    },
  );

  test('Cancel in the app stops waiting and frees the port', () async {
    final cancel = Completer<void>();
    final signIn = flow().signIn(cancel: cancel.future);
    final url = await opened.future;
    cancel.complete();
    await expectLater(signIn, throwsA(isA<GoogleSignInCancelled>()));
    final port = Uri.parse(url.queryParameters['redirect_uri']!).port;
    await expectLater(
      Socket.connect('127.0.0.1', port),
      throwsA(isA<SocketException>()),
    );
  });

  test('stops waiting after the timeout', () async {
    final signIn = flow(timeout: const Duration(milliseconds: 200)).signIn();
    await opened.future;
    await expectLater(
      signIn,
      throwsA(
        isA<AuthException>().having(
          (e) => e.message,
          'message',
          contains('timed out'),
        ),
      ),
    );
  });

  test('a browser that cannot open fails at once', () async {
    await expectLater(
      flow(browserOpens: false).signIn(),
      throwsA(
        isA<AuthException>().having(
          (e) => e.message,
          'message',
          contains('open the browser'),
        ),
      ),
    );
  });

  test('refresh gets a new access token and keeps the refresh token', () async {
    final credentials = await flow(
      client: tokenEndpoint(
        body: {
          'access_token': 'ya29.refreshed',
          'expires_in': 3599,
          'scope': googleScopes.join(' '),
          'token_type': 'Bearer',
        },
      ),
    ).refresh('1//stored');
    expect(credentials.accessToken.value, 'ya29.refreshed');
    expect(credentials.refreshToken, '1//stored');
    expect(tokenRequests.single, {
      'client_id': 'desktop-id',
      'client_secret': 'desktop-secret',
      'refresh_token': '1//stored',
      'grant_type': 'refresh_token',
    });
  });

  test('an expired or revoked refresh token is reported as expired', () async {
    await expectLater(
      flow(
        client: tokenEndpoint(
          status: 400,
          body: {
            'error': 'invalid_grant',
            'error_description': 'Token has been expired or revoked.',
          },
        ),
      ).refresh('1//old'),
      throwsA(isA<GoogleSignInExpired>()),
    );
  });

  test('a code Google rejects is not called an expired sign-in', () async {
    final signIn = flow(
      client: tokenEndpoint(status: 400, body: {'error': 'invalid_grant'}),
    ).signIn();
    // Listen first: the exchange can fail before the fake browser returns.
    final rejected = expectLater(
      signIn,
      throwsA(
        isA<AuthException>()
            .having((e) => e, 'type', isNot(isA<GoogleSignInExpired>()))
            .having((e) => e.message, 'message', contains('Try again')),
      ),
    );
    final url = await opened.future;
    await redirectTo(url, {
      'code': 'used',
      'state': url.queryParameters['state']!,
    });
    await rejected;
  });

  test('the desktop factory needs a desktop client', () {
    expect(createGoogleAuthFlow(null, tokenEndpoint()), isNull);
    expect(
      createGoogleAuthFlow(
        const OAuthConfig(webClientId: 'w'),
        tokenEndpoint(),
      ),
      isNull,
    );
    expect(
      createGoogleAuthFlow(
        const OAuthConfig(desktopClientId: 'd', desktopClientSecret: 's'),
        tokenEndpoint(),
      ),
      isA<DesktopGoogleAuthFlow>(),
    );
  });
}
