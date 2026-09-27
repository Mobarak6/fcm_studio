import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fcm_studio/core/auth/access_token_provider.dart';
import 'package:fcm_studio/core/fcm/fcm_client.dart';
import 'package:fcm_studio/core/fcm/fcm_error.dart';
import 'package:fcm_studio/core/fcm/fcm_send_result.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../helpers/fake_token_provider.dart';
import '../../helpers/fcm_fixtures.dart';

void main() {
  const projectId = 'demo-project';
  final body = <String, Object?>{
    'message': {
      'token': 'abc',
      'notification': {'title': 'Hi'},
    },
  };

  test(
    'posts the body with a bearer token and reads the message name',
    () async {
      late http.Request captured;
      final client = FcmClient(
        httpClient: MockClient((request) async {
          captured = request;
          return http.Response(successBody, 200);
        }),
      );

      final result = await client.send(
        projectId: projectId,
        body: body,
        auth: FakeTokenProvider(),
      );

      expect(
        result,
        isA<FcmSendSuccess>().having(
          (r) => r.messageName,
          'messageName',
          'projects/demo-project/messages/0:1',
        ),
      );
      expect(captured.method, 'POST');
      expect(
        captured.url.toString(),
        'https://fcm.googleapis.com/v1/projects/demo-project/messages:send',
      );
      expect(captured.headers['Authorization'], 'Bearer token-1');
      expect(captured.headers['Content-Type'], startsWith('application/json'));
      expect(jsonDecode(captured.body), body);
    },
  );

  test('adds the provider extra headers', () async {
    late http.Request captured;
    final client = FcmClient(
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response(successBody, 200);
      }),
    );
    await client.send(
      projectId: projectId,
      body: body,
      auth: FakeTokenProvider(headers: {'x-goog-user-project': projectId}),
    );
    expect(captured.headers['x-goog-user-project'], projectId);
  });

  test('after a 401 it refreshes the token once and resends', () async {
    final authHeaders = <String?>[];
    final auth = FakeTokenProvider();
    final client = FcmClient(
      httpClient: MockClient((request) async {
        authHeaders.add(request.headers['Authorization']);
        return authHeaders.length == 1
            ? http.Response(
                '{"error":{"code":401,"status":"UNAUTHENTICATED"}}',
                401,
              )
            : http.Response(successBody, 200);
      }),
    );

    final result = await client.send(
      projectId: projectId,
      body: body,
      auth: auth,
    );

    expect(result, isA<FcmSendSuccess>());
    expect(authHeaders, ['Bearer token-1', 'Bearer token-2']);
    expect(auth.forceRefreshCalls, [false, true]);
  });

  test('stops after the second 401', () async {
    var requests = 0;
    final client = FcmClient(
      httpClient: MockClient((_) async {
        requests++;
        return http.Response(
          '{"error":{"code":401,"status":"UNAUTHENTICATED"}}',
          401,
        );
      }),
    );
    final result = await client.send(
      projectId: projectId,
      body: body,
      auth: FakeTokenProvider(),
    );
    expect(requests, 2);
    expect(
      result,
      isA<FcmSendFailure>().having((r) => r.httpStatus, 'httpStatus', 401),
    );
  });

  test('does not retry server errors', () async {
    var requests = 0;
    final client = FcmClient(
      httpClient: MockClient((_) async {
        requests++;
        return http.Response(
          '{"error":{"code":503,"status":"UNAVAILABLE"}}',
          503,
        );
      }),
    );
    final result = await client.send(
      projectId: projectId,
      body: body,
      auth: FakeTokenProvider(),
    );
    expect(requests, 1);
    expect(
      result,
      isA<FcmSendFailure>().having(
        (r) => r.error.status,
        'status',
        'UNAVAILABLE',
      ),
    );
  });

  test('parses FCM error responses', () async {
    final client = FcmClient(
      httpClient: MockClient((_) async => http.Response(unregisteredBody, 404)),
    );
    final result = await client.send(
      projectId: projectId,
      body: body,
      auth: FakeTokenProvider(),
    );
    expect(
      result,
      isA<FcmSendFailure>()
          .having((r) => r.error.fcmErrorCode, 'fcmErrorCode', 'UNREGISTERED')
          .having((r) => r.responseBody, 'responseBody', unregisteredBody),
    );
  });

  test('reports a timeout', () async {
    final client = FcmClient(
      httpClient: MockClient((_) => Completer<http.Response>().future),
      timeout: const Duration(milliseconds: 10),
    );
    final result = await client.send(
      projectId: projectId,
      body: body,
      auth: FakeTokenProvider(),
    );
    expect(
      result,
      isA<FcmSendFailure>().having(
        (r) => r.error.transport,
        'transport',
        FcmTransportError.timeout,
      ),
    );
  });

  test('reports a network error', () async {
    final client = FcmClient(
      httpClient: MockClient(
        (_) async => throw http.ClientException('Failed host lookup'),
      ),
    );
    final result = await client.send(
      projectId: projectId,
      body: body,
      auth: FakeTokenProvider(),
    );
    expect(
      result,
      isA<FcmSendFailure>().having(
        (r) => r.error.transport,
        'transport',
        FcmTransportError.network,
      ),
    );
  });

  test('reports a failure to get a token', () async {
    final client = FcmClient(
      httpClient: MockClient((_) async => http.Response(successBody, 200)),
    );
    final result = await client.send(
      projectId: projectId,
      body: body,
      auth: FakeTokenProvider(
        error: const AuthException('Google rejected this key'),
      ),
    );
    expect(
      result,
      isA<FcmSendFailure>()
          .having((r) => r.error.transport, 'transport', FcmTransportError.auth)
          .having(
            (r) => r.error.message,
            'message',
            'Google rejected this key',
          ),
    );
  });

  test(
    'reports a TLS failure (e.g. an intercepting proxy) as a network error',
    () async {
      final client = FcmClient(
        httpClient: MockClient(
          (_) async => throw HandshakeException(
            'CERTIFICATE_VERIFY_FAILED: self signed certificate',
          ),
        ),
      );
      final result = await client.send(
        projectId: projectId,
        body: body,
        auth: FakeTokenProvider(),
      );
      expect(
        result,
        isA<FcmSendFailure>()
            .having(
              (r) => r.error.transport,
              'transport',
              FcmTransportError.network,
            )
            .having(
              (r) => r.error.message,
              'message',
              contains('CERTIFICATE_VERIFY_FAILED'),
            ),
      );
    },
  );

  test('a 200 without a message name is not reported as sent', () async {
    final client = FcmClient(
      httpClient: MockClient(
        (_) async => http.Response('<html>Sign in to Wi-Fi</html>', 200),
      ),
    );
    final result = await client.send(
      projectId: projectId,
      body: body,
      auth: FakeTokenProvider(),
    );
    expect(
      result,
      isA<FcmSendFailure>()
          .having((r) => r.error.fromGoogle, 'fromGoogle', isFalse)
          .having((r) => r.httpStatus, 'httpStatus', 200),
    );
  });
}
