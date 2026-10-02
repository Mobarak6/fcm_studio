import 'package:fcm_studio/core/auth/access_token_provider.dart';
import 'package:fcm_studio/core/auth/google_auth_flow.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('missingScopes lists the Firebase scopes the user did not grant', () {
    final credentials = GoogleCredentials(
      accessToken: AccessToken('ya29.x', DateTime.utc(2100)),
      scopes: const [
        'openid',
        'https://www.googleapis.com/auth/userinfo.email',
      ],
    );
    expect(credentials.missingScopes, requiredGoogleScopes);
    expect(
      GoogleCredentials(
        accessToken: AccessToken('ya29.x', DateTime.utc(2100)),
        scopes: googleScopes,
      ).missingScopes,
      isEmpty,
    );
  });

  test('credentials never print their tokens', () {
    final credentials = GoogleCredentials(
      accessToken: AccessToken('ya29.secret', DateTime.utc(2100)),
      refreshToken: '1//secret',
      scopes: googleScopes,
    );
    expect('$credentials', isNot(contains('secret')));
  });

  test(
    'web errors: a closed popup is a cancel, a blocked one says what to do',
    () {
      expect(
        describeGoogleWebError('GoogleIdentityServicesErrorType.popup_closed'),
        isA<GoogleSignInCancelled>(),
      );
      expect(
        describeGoogleWebError('access_denied'),
        isA<GoogleSignInCancelled>(),
      );
      expect(
        describeGoogleWebError('popup_failed_to_open'),
        isA<AuthException>().having(
          (e) => e.message,
          'message',
          contains('Allow pop-ups'),
        ),
      );
      expect(
        describeGoogleWebError('invalid_client', description: 'bad id'),
        isA<AuthException>().having(
          (e) => e.message,
          'message',
          'Google sign-in failed (invalid_client: bad id).',
        ),
      );
    },
  );
}
