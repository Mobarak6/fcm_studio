import 'package:fcm_studio/core/fcm/fcm_error.dart';
import 'package:fcm_studio/core/fcm/fcm_error_explainer.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fcm_fixtures.dart';

void main() {
  const explainer = FcmErrorExplainer();
  ErrorExplanation explain(FcmError error) =>
      explainer.explain(error, projectId: 'demo-project');

  ErrorExplanation explainGoogle(FcmError error) =>
      explainer.explain(error, projectId: 'demo-project', googleAccount: true);

  test('USER_PROJECT_DENIED names the Service Usage Consumer role', () {
    final e = explainGoogle(FcmError.fromResponse(403, userProjectDeniedBody));
    expect(e.action, contains('Service Usage Consumer'));
    expect(e.link?.host, 'console.cloud.google.com');
  });

  test('a missing scope asks to sign in again and allow every permission', () {
    final e = explainGoogle(FcmError.fromResponse(403, scopeInsufficientBody));
    expect(
      e.action,
      allOf(contains('Sign in again'), contains('every permission')),
    );
  });

  test('Google accounts: an auth failure points to Sign in again', () {
    final e = explainGoogle(
      const FcmError(transport: FcmTransportError.auth, message: 'expired'),
    );
    expect(e.explanation, 'expired');
    expect(e.action, contains('Sign in again'));
  });

  test('Google accounts: a 401 points to Sign in again', () {
    final e = explainGoogle(
      const FcmError(httpStatus: 401, status: 'UNAUTHENTICATED'),
    );
    expect(e.action, contains('Sign in again'));
  });

  test(
    'Google accounts: a 403 is about your account, not a service account',
    () {
      final e = explainGoogle(
        const FcmError(httpStatus: 403, status: 'PERMISSION_DENIED'),
      );
      expect(e.explanation, contains('Your Google account'));
      expect(e.action, contains('Firebase Cloud Messaging API Admin'));
      expect(
        '${e.explanation} ${e.action}',
        isNot(contains('service account')),
      );
    },
  );

  test('service accounts keep their advice', () {
    final e = explain(
      const FcmError(transport: FcmTransportError.auth, message: 'bad key'),
    );
    expect(e.action, contains('service account key file'));
  });

  test('UNREGISTERED: the token is stale', () {
    expect(
      explain(FcmError.fromResponse(404, unregisteredBody)).title,
      'Token is no longer valid',
    );
  });

  test('INVALID_ARGUMENT lists each field violation', () {
    final e = explain(FcmError.fromResponse(400, invalidArgumentBody));
    expect(e.title, 'FCM rejected the message');
    expect(e.explanation, contains('message.data[0].value'));
  });

  test('SENDER_ID_MISMATCH: token from another project', () {
    const error = FcmError(
      httpStatus: 403,
      status: 'PERMISSION_DENIED',
      fcmErrorCode: 'SENDER_ID_MISMATCH',
    );
    expect(explain(error).title, 'Token belongs to another Firebase project');
  });

  test('QUOTA_EXCEEDED: sending too fast', () {
    const error = FcmError(
      httpStatus: 429,
      status: 'RESOURCE_EXHAUSTED',
      fcmErrorCode: 'QUOTA_EXCEEDED',
    );
    expect(explain(error).title, 'Sending too fast');
  });

  test('UNAVAILABLE and INTERNAL: temporary problem', () {
    expect(
      explain(const FcmError(httpStatus: 503, status: 'UNAVAILABLE')).title,
      'Temporary FCM problem',
    );
    expect(
      explain(const FcmError(httpStatus: 500, status: 'INTERNAL')).title,
      'Temporary FCM problem',
    );
  });

  test('a non-JSON 502 is a temporary problem that shows the raw text', () {
    final e = explain(FcmError.fromResponse(502, '<html>Bad Gateway</html>'));
    expect(e.title, 'Temporary FCM problem');
    expect(e.explanation, contains('Bad Gateway'));
  });

  test('THIRD_PARTY_AUTH_ERROR links to Cloud Messaging settings', () {
    const error = FcmError(
      httpStatus: 401,
      status: 'UNAUTHENTICATED',
      fcmErrorCode: 'THIRD_PARTY_AUTH_ERROR',
    );
    final e = explain(error);
    expect(e.title, 'APNs or web push credentials problem');
    expect(
      e.link,
      Uri.parse(
        'https://console.firebase.google.com/project/demo-project/settings/cloudmessaging',
      ),
    );
  });

  test('SERVICE_DISABLED links to the API page', () {
    final e = explain(FcmError.fromResponse(403, serviceDisabledBody));
    expect(e.title, 'The FCM API is not enabled');
    expect(
      e.link.toString(),
      contains('fcm.googleapis.com/overview?project=demo-project'),
    );
  });

  test('a 401 without an FCM code: token rejected after refresh', () {
    expect(
      explain(const FcmError(httpStatus: 401, status: 'UNAUTHENTICATED')).title,
      'Access token rejected',
    );
  });

  test('other 403s: permission denied, names the role', () {
    final e = explain(
      const FcmError(httpStatus: 403, status: 'PERMISSION_DENIED'),
    );
    expect(e.title, 'Permission denied');
    expect(e.action, contains('Firebase Cloud Messaging API Admin'));
  });

  test('a 404 without an FCM code: not found', () {
    final e = explain(
      const FcmError(
        httpStatus: 404,
        status: 'NOT_FOUND',
        message: 'Requested entity was not found.',
      ),
    );
    expect(e.title, 'Not found');
  });

  test('transport errors', () {
    expect(
      explain(
        const FcmError(transport: FcmTransportError.network, message: 'x'),
      ).title,
      'Network error',
    );
    expect(
      explain(const FcmError(transport: FcmTransportError.timeout)).title,
      'FCM did not respond',
    );
    final auth = explain(
      const FcmError(
        transport: FcmTransportError.auth,
        message: 'Key missing.',
      ),
    );
    expect(auth.title, 'Could not get an access token');
    expect(auth.explanation, 'Key missing.');
  });

  test('unknown errors fall back to the raw message', () {
    final e = explain(const FcmError(httpStatus: 418, message: 'teapot'));
    expect(e.title, 'FCM returned an error (HTTP 418)');
    expect(e.explanation, 'teapot');
  });

  test('an HTML 403 from a proxy is not blamed on IAM roles', () {
    final e = explain(
      FcmError.fromResponse(403, '<html>Blocked by corporate firewall</html>'),
    );
    expect(e.title, 'Unexpected response (HTTP 403)');
    expect(e.explanation, contains('did not come from FCM'));
    expect(e.explanation, contains('Blocked by corporate firewall'));
  });

  test('unexpected transport failures are explained', () {
    final e = explain(
      const FcmError(
        transport: FcmTransportError.unexpected,
        message: 'Keychain access denied',
      ),
    );
    expect(e.title, 'Something went wrong');
    expect(e.explanation, 'Keychain access denied');
  });
}
