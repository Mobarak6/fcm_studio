import 'dart:convert';

import 'package:fcm_studio/core/auth/access_token_provider.dart';
import 'package:fcm_studio/core/auth/google_user_info.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final token = AccessToken('ya29.who', DateTime.utc(2100));

  test('reads the account email (lowercase) with the access token', () async {
    late http.Request captured;
    final info = GoogleUserInfoApi(
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({'sub': '1', 'email': 'Dev@Example.com'}),
          200,
        );
      }),
    );
    expect(await info.emailOf(token), 'dev@example.com');
    expect(captured.url, GoogleUserInfoApi.endpoint);
    expect(captured.headers['Authorization'], 'Bearer ya29.who');
  });

  test(
    'an answer without an email is an error that names the status',
    () async {
      final info = GoogleUserInfoApi(
        httpClient: MockClient((_) async => http.Response('{}', 401)),
      );
      await expectLater(
        info.emailOf(token),
        throwsA(
          isA<AuthException>().having(
            (e) => e.message,
            'message',
            contains('HTTP 401'),
          ),
        ),
      );
    },
  );
}
