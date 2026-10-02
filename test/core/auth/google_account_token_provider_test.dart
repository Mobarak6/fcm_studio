import 'package:fcm_studio/core/auth/access_token_provider.dart';
import 'package:fcm_studio/core/auth/google_account_token_provider.dart';
import 'package:fcm_studio/core/auth/google_auth_flow.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_google_auth_flow.dart';
import '../../helpers/fixed_clock.dart';

void main() {
  late FixedClock clock;

  setUp(() => clock = FixedClock(DateTime.utc(2026, 10, 4, 12)));

  GoogleAccountTokenProvider desktop(
    FakeGoogleAuthFlow flow, {
    AccessToken? initial,
  }) => GoogleAccountTokenProvider(
    email: testGoogleEmail,
    flow: flow,
    userInfo: FakeGoogleUserInfo(),
    refreshToken: '1//stored',
    initialToken: initial,
    clock: clock,
  );

  GoogleAccountTokenProvider browser(
    FakeGoogleAuthFlow flow,
    FakeGoogleUserInfo info,
  ) => GoogleAccountTokenProvider(
    email: testGoogleEmail,
    flow: flow,
    userInfo: info,
    clock: clock,
  );

  test(
    'desktop: one refresh serves concurrent callers, then it is cached',
    () async {
      final flow = FakeGoogleAuthFlow(
        refresh: googleCredentials(
          token: 'ya29.r1',
          expiresAt: clock.now().add(const Duration(hours: 1)),
        ),
      );
      final provider = desktop(flow);
      final tokens = await Future.wait([
        provider.getToken(),
        provider.getToken(),
      ]);
      expect(tokens.map((t) => t.value), ['ya29.r1', 'ya29.r1']);
      expect(await provider.getToken(), tokens.first);
      expect(flow.calls, ['refresh 1//stored']);
      expect(provider.extraHeaders('demo-project'), {
        'x-goog-user-project': 'demo-project',
      });
    },
  );

  test(
    'refreshes when less than 5 minutes remain, and on forceRefresh',
    () async {
      final flow = FakeGoogleAuthFlow(
        refresh: googleCredentials(
          token: 'ya29.r',
          expiresAt: clock.now().add(const Duration(hours: 1)),
        ),
      );
      final provider = desktop(flow);
      await provider.getToken();
      clock.advance(const Duration(minutes: 56));
      await provider.getToken();
      await provider.getToken(forceRefresh: true);
      expect(flow.calls, [
        'refresh 1//stored',
        'refresh 1//stored',
        'refresh 1//stored',
      ]);
    },
  );

  test('the token from the sign-in itself is used first', () async {
    final flow = FakeGoogleAuthFlow();
    final initial = AccessToken(
      'ya29.fresh',
      clock.now().add(const Duration(hours: 1)),
    );
    expect(await desktop(flow, initial: initial).getToken(), initial);
    expect(flow.calls, isEmpty);
  });

  test('desktop: an expired sign-in says to sign in again', () async {
    final flow = FakeGoogleAuthFlow(
      refresh: const GoogleSignInExpired(
        'Google says this sign-in has expired.',
      ),
    );
    await expectLater(
      desktop(flow).getToken(),
      throwsA(
        isA<AuthException>().having(
          (e) => e.message,
          'message',
          allOf(
            contains(testGoogleEmail),
            contains('Sign in again'),
            contains('7 days'),
          ),
        ),
      ),
    );
  });

  test(
    'desktop: without a stored refresh token it never opens the browser',
    () async {
      final flow = FakeGoogleAuthFlow();
      final provider = GoogleAccountTokenProvider(
        email: testGoogleEmail,
        flow: flow,
        userInfo: FakeGoogleUserInfo(),
        clock: clock,
      );
      await expectLater(
        provider.getToken(),
        throwsA(
          isA<AuthException>().having(
            (e) => e.message,
            'message',
            contains('Sign in again'),
          ),
        ),
      );
      expect(flow.calls, isEmpty);
    },
  );

  test('browser: no token yet opens the popup for the same account', () async {
    final flow = FakeGoogleAuthFlow(
      canRefresh: false,
      signIns: [googleCredentials(token: 'ya29.popup', refreshToken: null)],
    );
    final info = FakeGoogleUserInfo();
    expect((await browser(flow, info).getToken()).value, 'ya29.popup');
    expect(flow.calls, ['signIn $testGoogleEmail']);
    expect(info.tokens, ['ya29.popup']);
  });

  test(
    'browser: another account in the popup is refused and nothing is cached',
    () async {
      final flow = FakeGoogleAuthFlow(
        canRefresh: false,
        signIns: [googleCredentials(refreshToken: null)],
      );
      final provider = browser(
        flow,
        FakeGoogleUserInfo(['other@example.com', testGoogleEmail]),
      );
      await expectLater(
        provider.getToken(),
        throwsA(
          isA<AuthException>().having(
            (e) => e.message,
            'message',
            allOf(contains('other@example.com'), contains(testGoogleEmail)),
          ),
        ),
      );
      await provider.getToken();
      expect(flow.calls, [
        'signIn $testGoogleEmail',
        'signIn $testGoogleEmail',
      ]);
    },
  );

  test('browser: closing the popup says what to do', () async {
    final flow = FakeGoogleAuthFlow(
      canRefresh: false,
      signIns: const [GoogleSignInCancelled()],
    );
    await expectLater(
      browser(flow, FakeGoogleUserInfo()).getToken(),
      throwsA(
        isA<AuthException>().having(
          (e) => e.message,
          'message',
          contains('closed'),
        ),
      ),
    );
  });

  test('browser: unticked permissions are refused', () async {
    final flow = FakeGoogleAuthFlow(
      canRefresh: false,
      signIns: [
        googleCredentials(refreshToken: null, scopes: const ['openid']),
      ],
    );
    await expectLater(
      browser(flow, FakeGoogleUserInfo()).getToken(),
      throwsA(
        isA<AuthException>().having(
          (e) => e.message,
          'message',
          missingScopesMessage,
        ),
      ),
    );
  });
}
