import 'package:equatable/equatable.dart';
import 'package:fcm_studio/core/auth/access_token_provider.dart';

/// The scopes every Google sign-in asks for: the two Firebase scopes
/// (spec §4.1), plus `openid` and `userinfo.email` so the app can tell which
/// account signed in (plan Decision 2).
const googleScopes = [
  'https://www.googleapis.com/auth/firebase.messaging',
  'https://www.googleapis.com/auth/firebase.readonly',
  'openid',
  'https://www.googleapis.com/auth/userinfo.email',
];

/// Without these nothing works, so a sign-in that lacks one is refused.
const requiredGoogleScopes = [
  'https://www.googleapis.com/auth/firebase.messaging',
  'https://www.googleapis.com/auth/firebase.readonly',
];

const missingScopesMessage =
    'FCM Studio needs permission to send messages and to read your Firebase '
    'projects. Sign in again and allow both.';

/// What a finished sign-in or refresh gives back.
class GoogleCredentials extends Equatable {
  const GoogleCredentials({
    required this.accessToken,
    required this.scopes,
    this.refreshToken,
  });

  final AccessToken accessToken;

  /// Only desktop sign-ins have one (spec §4.1).
  final String? refreshToken;
  final List<String> scopes;

  /// The required scopes the user did not grant (Google lets them untick some).
  List<String> get missingScopes => [
    for (final scope in requiredGoogleScopes)
      if (!scopes.contains(scope)) scope,
  ];

  @override
  List<Object?> get props => [accessToken, refreshToken, scopes];

  @override
  String toString() =>
      'GoogleCredentials(expiresAt: ${accessToken.expiresAt}, scopes: $scopes)';
}

/// The user closed or cancelled Google's sign-in.
class GoogleSignInCancelled implements Exception {
  const GoogleSignInCancelled();

  @override
  String toString() => 'GoogleSignInCancelled';
}

/// Google says the stored sign-in expired or was revoked (`invalid_grant`).
class GoogleSignInExpired extends AuthException {
  const GoogleSignInExpired(super.message);
}

/// Signs in to Google: a browser tab on desktop, a popup on the web.
abstract interface class GoogleAuthFlow {
  /// True when sign-ins come with a refresh token (desktop).
  bool get canRefresh;

  /// Opens Google's sign-in. [loginHint] preselects an account. Completing
  /// [cancel] stops waiting (desktop only). Throws [GoogleSignInCancelled] or
  /// [AuthException].
  Future<GoogleCredentials> signIn({String? loginHint, Future<void>? cancel});

  /// Gets a new access token with [refreshToken] (desktop only). Throws
  /// [GoogleSignInExpired] when Google no longer accepts it.
  Future<GoogleCredentials> refresh(String refreshToken);
}

/// Turns a Google Identity Services error into what the user should know.
Exception describeGoogleWebError(String error, {String? description}) {
  if (error.contains('popup_closed') || error == 'access_denied') {
    return const GoogleSignInCancelled();
  }
  if (error.contains('popup_failed_to_open')) {
    return const AuthException(
      'Your browser blocked the Google sign-in pop-up. '
      'Allow pop-ups for this site, then try again.',
    );
  }
  return AuthException(
    'Google sign-in failed ($error${description == null ? '' : ': $description'}).',
  );
}
