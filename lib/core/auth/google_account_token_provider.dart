import 'dart:async';

import 'package:fcm_studio/core/auth/access_token_provider.dart';
import 'package:fcm_studio/core/auth/google_auth_flow.dart';
import 'package:fcm_studio/core/auth/google_user_info.dart';
import 'package:fcm_studio/core/utils/clock.dart';

/// Access tokens for one Google account (spec §4.1). On desktop they come
/// from the stored refresh token; in the browser, from Google's popup.
class GoogleAccountTokenProvider implements AccessTokenProvider {
  GoogleAccountTokenProvider({
    required this.email,
    required this._flow,
    required this._userInfo,
    this._refreshToken,
    AccessToken? initialToken,
    this._clock = const SystemClock(),
  }) : _cached = initialToken;

  static const refreshMargin = Duration(minutes: 5);

  final String email;
  final GoogleAuthFlow _flow;
  final GoogleUserInfo _userInfo;
  final String? _refreshToken;
  final Clock _clock;
  AccessToken? _cached;
  Future<AccessToken>? _inFlight;

  /// Set after the popup returned another account: the next popup shows the
  /// account picker instead of taking the browser's current account.
  bool _pickAccount = false;

  /// The stored sign-in no longer works (plan Decision 6).
  static String expiredMessage(String email) =>
      'The Google sign-in for $email has expired or was revoked. '
      'Use "Sign in again…" in the project menu. '
      '(While the OAuth app is in Testing, Google ends sign-ins after 7 days.)';

  static String notStoredMessage(String email) =>
      'The Google sign-in for $email is not stored on this computer. '
      'Use "Sign in again…" in the project menu.';

  @override
  Future<AccessToken> getToken({bool forceRefresh = false}) {
    final cached = _cached;
    if (!forceRefresh &&
        cached != null &&
        cached.isValidAt(_clock.now(), margin: refreshMargin)) {
      return Future.value(cached);
    }
    return _inFlight ??= _fetch().whenComplete(() => _inFlight = null);
  }

  /// Quota and billing go to the target project, not the OAuth client's
  /// (spec §4.1).
  @override
  Map<String, String> extraHeaders(String projectId) => {
    'x-goog-user-project': projectId,
  };

  Future<AccessToken> _fetch() async {
    final credentials = await _newCredentials();
    _cached = credentials.accessToken;
    return credentials.accessToken;
  }

  Future<GoogleCredentials> _newCredentials() async {
    final refreshToken = _refreshToken;
    if (refreshToken != null) {
      try {
        return await _flow.refresh(refreshToken);
      } on GoogleSignInExpired {
        throw AuthException(expiredMessage(email));
      }
    }
    if (_flow.canRefresh) {
      throw AuthException(notStoredMessage(email));
    }
    // The browser has no refresh token: ask Google again with a popup.
    final GoogleCredentials credentials;
    try {
      credentials = await _flow.signIn(loginHint: _pickAccount ? null : email);
    } on GoogleSignInCancelled {
      throw AuthException(
        'The Google sign-in for $email was closed. Try again and finish '
        'signing in.',
      );
    }
    if (credentials.missingScopes.isNotEmpty) {
      throw const AuthException(missingScopesMessage);
    }
    final signedIn = await _userInfo.emailOf(credentials.accessToken);
    if (signedIn != email) {
      _pickAccount = true;
      throw AuthException(
        'You signed in as $signedIn, but this project uses $email. '
        'Try again and choose $email.',
      );
    }
    _pickAccount = false;
    return credentials;
  }
}
