import 'dart:async';

import 'package:fcm_studio/core/auth/access_token_provider.dart';
import 'package:fcm_studio/core/fcm/fcm_client.dart';
import 'package:fcm_studio/core/fcm/fcm_error.dart';
import 'package:fcm_studio/core/fcm/fcm_send_result.dart';
import 'package:fcm_studio/features/composer/cubit/composer_cubit.dart';
import 'package:fcm_studio/features/composer/domain/target.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../helpers/fake_google.dart';
import '../../helpers/fake_token_provider.dart';
import '../../helpers/fcm_fixtures.dart';
import '../../helpers/project_fixture.dart';

void main() {
  const token = 'abc:APA91bxyz';

  ComposerCubit build({http.Client? client, FakeResolver? auth}) =>
      ComposerCubit(
        fcmClient: FcmClient(httpClient: client ?? fakeGoogle()),
        auth: auth ?? FakeResolver(),
      );

  test('starts with the default template and asks for a token', () {
    final cubit = build();
    expect(cubit.state.template, isNotNull);
    expect(cubit.state.render.errors.single.message, 'Enter a device token.');
    expect(cubit.state.canSend, isFalse);
  });

  test('reports invalid JSON with its line number', () {
    final cubit = build()..updateTemplateText('{\n  "data": {},\n}');
    expect(cubit.state.template, isNull);
    expect(cubit.state.jsonError, contains('line 3'));
    expect(cubit.state.canSend, isFalse);
  });

  test('rejects a top-level value that is not an object', () {
    final cubit = build()..updateTemplateText('[]');
    expect(cubit.state.jsonError, contains('must be a JSON object'));
  });

  test('rejects empty text', () {
    final cubit = build()..updateTemplateText('   ');
    expect(cubit.state.jsonError, contains('empty'));
  });

  test('renders the request once a token is entered', () {
    final cubit = build()..setTargetValue(token);
    expect(cubit.state.canSend, isTrue);
    final message =
        cubit.state.render.request!['message']! as Map<String, Object?>;
    expect(message['token'], token);
  });

  test('switching to topic re-renders with the same value', () {
    final cubit = build()
      ..setTargetValue('/topics/news')
      ..setTargetKind(TargetKind.topic);
    final message =
        cubit.state.render.request!['message']! as Map<String, Object?>;
    expect(message['topic'], 'news');
  });

  test('sends and stores the result', () async {
    final cubit = build()..setTargetValue(token);
    await cubit.send(testProject);
    expect(cubit.state.sendStatus, SendStatus.done);
    expect(cubit.state.lastResult, isA<FcmSendSuccess>());
    expect(cubit.state.lastExplanation, isNull);
  });

  test('explains a failed send', () async {
    final cubit = build(
      client: fakeGoogle(fcmStatus: 404, fcmBody: unregisteredBody),
    )..setTargetValue(token);
    await cubit.send(testProject);
    expect(cubit.state.lastResult, isA<FcmSendFailure>());
    expect(cubit.state.lastExplanation?.title, 'Token is no longer valid');
  });

  test('explains a missing key instead of throwing', () async {
    final cubit = build(
      auth: FakeResolver(
        error: const AuthException(
          'The service account key for demo-project is not available in this session. '
          'Add the project again with the same key file.',
        ),
      ),
    )..setTargetValue(token);

    await cubit.send(testProject);

    expect(
      cubit.state.lastResult,
      isA<FcmSendFailure>().having(
        (r) => r.error.transport,
        'transport',
        FcmTransportError.auth,
      ),
    );
    expect(cubit.state.lastExplanation?.title, 'Could not get an access token');
    expect(
      cubit.state.lastExplanation?.explanation,
      contains('Add the project again'),
    );
  });

  test('ignores Send while a send is in progress', () async {
    final gate = Completer<http.Response>();
    var requests = 0;
    final cubit = build(
      client: MockClient((_) {
        requests++;
        return gate.future;
      }),
    )..setTargetValue(token);

    final first = cubit.send(testProject);
    await Future<void>.delayed(Duration.zero);
    await cubit.send(testProject);
    gate.complete(http.Response(successBody, 200));
    await first;

    expect(requests, 1);
    expect(cubit.state.lastResult, isA<FcmSendSuccess>());
  });

  test('does not send when the message has errors', () async {
    var requests = 0;
    final cubit = build(
      client: MockClient((_) async {
        requests++;
        return http.Response(successBody, 200);
      }),
    );
    await cubit.send(testProject);
    expect(requests, 0);
    expect(cubit.state.sendStatus, SendStatus.idle);
  });

  test(
    'an unexpected failure ends the send instead of leaving it stuck',
    () async {
      final cubit = build(
        auth: FakeResolver(error: Exception('Keychain access denied')),
      )..setTargetValue(token);

      await cubit.send(testProject);

      expect(cubit.state.sendStatus, SendStatus.done);
      expect(
        cubit.state.lastResult,
        isA<FcmSendFailure>()
            .having(
              (r) => r.error.transport,
              'transport',
              FcmTransportError.unexpected,
            )
            .having(
              (r) => r.error.message,
              'message',
              contains('Keychain access denied'),
            ),
      );
      expect(cubit.state.canSend, isTrue);
    },
  );
}
