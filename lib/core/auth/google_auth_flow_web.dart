import 'package:fcm_studio/core/auth/access_token_provider.dart';
import 'package:fcm_studio/core/auth/google_auth_flow.dart';
import 'package:fcm_studio/core/auth/oauth_config.dart';
import 'package:googleapis_auth/auth_browser.dart' as gauth;
import 'package:http/http.dart' as http;

/// The browser sign-in, or null when `config/oauth.json` has no web client.
GoogleAuthFlow? createGoogleAuthFlow(
  OAuthConfig? config,
  http.Client httpClient,
) {
  final clientId = config?.webClientId;
  return clientId == null ? null : WebGoogleAuthFlow(clientId: clientId);
}

/// Google sign-in in the browser: Google's popup (spec §4.1). It gives no
/// refresh token, so an expired token means a new popup (plan Decision 5).
class WebGoogleAuthFlow implements GoogleAuthFlow {
  WebGoogleAuthFlow({required this.clientId});

  final String clientId;

  @override
  bool get canRefresh => false;

  @override
  Future<GoogleCredentials> signIn({
    String? loginHint,
    Future<void>? cancel,
  }) async {
    final gauth.AccessCredentials credentials;
    try {
      // Cancel must work even if Google's popup never calls back.
      credentials = await cancellable(
        gauth.requestAccessCredentials(
          clientId: clientId,
          scopes: googleScopes,
          // googleapis_auth can't pass a login hint. With a known account the
          // popup takes the browser's current account without a picker; after
          // a wrong account the provider asks again without a hint, which
          // shows the picker.
          prompt: loginHint == null ? 'select_account' : '',
        ),
        cancel,
      );
    } on gauth.AuthenticationException catch (e) {
      throw describeGoogleWebError(e.error, description: e.errorDescription);
    }
    final token = credentials.accessToken;
    return GoogleCredentials(
      accessToken: AccessToken(token.data, token.expiry),
      scopes: credentials.scopes,
    );
  }

  @override
  Future<GoogleCredentials> refresh(String refreshToken) =>
      throw UnsupportedError('Browser sign-ins have no refresh token.');
}
