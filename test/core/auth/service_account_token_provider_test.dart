import 'dart:convert';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:fcm_studio/core/auth/access_token_provider.dart';
import 'package:fcm_studio/core/auth/service_account_key.dart';
import 'package:fcm_studio/core/auth/service_account_token_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../helpers/fixed_clock.dart';
import '../../helpers/service_account_fixture.dart';

http.Response tokenResponse({
  String token = 'ya29.test-token',
  int expiresIn = 3599,
}) => http.Response(
  jsonEncode({
    'access_token': token,
    'expires_in': expiresIn,
    'token_type': 'Bearer',
  }),
  200,
);

void main() {
  late FixedClock clock;
  late ServiceAccountKey key;

  setUp(() {
    clock = FixedClock(DateTime.utc(2026, 1, 1, 12));
    key = ServiceAccountKey.parse(serviceAccountJson());
  });

  ServiceAccountTokenProvider provider(MockClientHandler handler) =>
      ServiceAccountTokenProvider(
        key: key,
        httpClient: MockClient(handler),
        clock: clock,
      );

  test('builds an RS256 assertion with the claims Google expects', () {
    final assertion = provider((_) async => tokenResponse()).buildAssertion();
    final jwt = JWT.verify(
      assertion,
      RSAPublicKey(testPublicKeyPem()),
      checkExpiresIn: false,
    );
    final payload = jwt.payload as Map<String, dynamic>;
    final issuedAt = clock.now().millisecondsSinceEpoch ~/ 1000;

    expect(payload['iss'], testClientEmail);
    expect(payload['sub'], testClientEmail);
    expect(payload['aud'], 'https://oauth2.googleapis.com/token');
    expect(
      payload['scope'],
      'https://www.googleapis.com/auth/firebase.messaging '
      'https://www.googleapis.com/auth/firebase.readonly',
    );
    expect(payload['iat'], issuedAt);
    expect(payload['exp'], issuedAt + 3600);
    expect(jwt.header?['alg'], 'RS256');
    expect(jwt.header?['kid'], 'test-key-id-1');
  });

  test('exchanges the assertion for an access token', () async {
    late http.Request captured;
    final token = await provider((request) async {
      captured = request;
      return tokenResponse();
    }).getToken();

    expect(token.value, 'ya29.test-token');
    expect(token.expiresAt, clock.now().add(const Duration(seconds: 3599)));
    expect(captured.url.toString(), 'https://oauth2.googleapis.com/token');
    expect(
      captured.bodyFields['grant_type'],
      'urn:ietf:params:oauth:grant-type:jwt-bearer',
    );
    expect(captured.bodyFields['assertion'], isNotEmpty);
  });

  test('reuses the token until 5 minutes before it expires', () async {
    var calls = 0;
    final p = provider((_) async {
      calls++;
      return tokenResponse(token: 'ya29.token-$calls');
    });

    expect((await p.getToken()).value, 'ya29.token-1');
    clock.advance(const Duration(minutes: 50));
    expect((await p.getToken()).value, 'ya29.token-1');
    clock.advance(const Duration(minutes: 5));
    expect((await p.getToken()).value, 'ya29.token-2');
    expect(calls, 2);
  });

  test('forceRefresh always fetches a new token', () async {
    var calls = 0;
    final p = provider((_) async {
      calls++;
      return tokenResponse();
    });
    await p.getToken();
    await p.getToken(forceRefresh: true);
    expect(calls, 2);
  });

  test('concurrent callers share one request', () async {
    var calls = 0;
    final p = provider((_) async {
      calls++;
      return tokenResponse();
    });
    await Future.wait([p.getToken(), p.getToken(), p.getToken()]);
    expect(calls, 1);
  });

  test('explains a key that Google rejects', () async {
    final p = provider(
      (_) async => http.Response(
        jsonEncode({
          'error': 'invalid_grant',
          'error_description': 'Invalid JWT Signature.',
        }),
        400,
      ),
    );
    await expectLater(
      p.getToken(),
      throwsA(
        isA<AuthException>()
            .having((e) => e.message, 'message', contains('rejected this key'))
            .having((e) => e.statusCode, 'statusCode', 400),
      ),
    );
  });

  test('turns network failures into AuthException', () async {
    final p = provider(
      (_) async => throw http.ClientException('Failed host lookup'),
    );
    await expectLater(
      p.getToken(),
      throwsA(
        isA<AuthException>().having(
          (e) => e.message,
          'message',
          contains('Network error'),
        ),
      ),
    );
  });

  test('a failed request does not block later attempts', () async {
    var calls = 0;
    final p = provider((_) async {
      calls++;
      return calls == 1 ? http.Response('oops', 500) : tokenResponse();
    });
    await expectLater(p.getToken(), throwsA(isA<AuthException>()));
    expect((await p.getToken()).value, 'ya29.test-token');
  });
}
