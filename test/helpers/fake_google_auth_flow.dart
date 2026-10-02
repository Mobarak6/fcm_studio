import 'dart:async';

import 'package:fcm_studio/core/auth/access_token_provider.dart';
import 'package:fcm_studio/core/auth/google_auth_flow.dart';
import 'package:fcm_studio/core/auth/google_user_info.dart';

const testGoogleEmail = 'dev@example.com';

GoogleCredentials googleCredentials({
  String token = 'ya29.google-1',
  String? refreshToken = '1//refresh-1',
  List<String> scopes = googleScopes,
  DateTime? expiresAt,
}) => GoogleCredentials(
  accessToken: AccessToken(token, expiresAt ?? DateTime.utc(2100)),
  refreshToken: refreshToken,
  scopes: scopes,
);

/// A scripted Google sign-in. Each answer is a [GoogleCredentials], or an
/// exception to throw. The last answer repeats.
class FakeGoogleAuthFlow implements GoogleAuthFlow {
  FakeGoogleAuthFlow({
    this.canRefresh = true,
    List<Object>? signIns,
    Object? refresh,
  }) : signIns = signIns ?? [googleCredentials()],
       refreshAnswers = [refresh ?? googleCredentials(token: 'ya29.refreshed')];

  @override
  final bool canRefresh;
  final List<Object> signIns;
  final List<Object> refreshAnswers;
  final List<String> calls = [];

  /// When set, [signIn] waits for it, or for its `cancel` future.
  Completer<void>? signInGate;

  /// How many sign-ins ended because their `cancel` future completed.
  int cancels = 0;
  int _signIns = 0;
  int _refreshes = 0;

  @override
  Future<GoogleCredentials> signIn({
    String? loginHint,
    Future<void>? cancel,
  }) async {
    calls.add('signIn ${loginHint ?? '-'}');
    final gate = signInGate;
    if (gate != null) {
      var cancelled = false;
      await Future.any<void>([
        gate.future,
        if (cancel != null) cancel.then((_) => cancelled = true),
      ]);
      if (cancelled) {
        cancels++;
        throw const GoogleSignInCancelled();
      }
    }
    return _answer(signIns, _signIns++);
  }

  @override
  Future<GoogleCredentials> refresh(String refreshToken) async {
    calls.add('refresh $refreshToken');
    return _answer(refreshAnswers, _refreshes++);
  }

  static GoogleCredentials _answer(List<Object> answers, int index) {
    final answer = answers[index < answers.length ? index : answers.length - 1];
    if (answer is GoogleCredentials) {
      return answer;
    }
    throw answer;
  }
}

/// Says which account signed in. Answers in order; the last one repeats.
class FakeGoogleUserInfo implements GoogleUserInfo {
  FakeGoogleUserInfo([this.emails = const [testGoogleEmail]]);

  final List<String> emails;

  /// The access tokens it was asked about.
  final List<String> tokens = [];

  @override
  Future<String> emailOf(AccessToken token) async {
    tokens.add(token.value);
    final index = tokens.length - 1;
    return emails[index < emails.length ? index : emails.length - 1];
  }
}
