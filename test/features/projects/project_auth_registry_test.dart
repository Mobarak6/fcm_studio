import 'package:fcm_studio/core/auth/access_token_provider.dart';
import 'package:fcm_studio/core/auth/google_account_token_provider.dart';
import 'package:fcm_studio/core/auth/google_auth_flow.dart';
import 'package:fcm_studio/core/auth/service_account_key.dart';
import 'package:fcm_studio/core/auth/service_account_token_provider.dart';
import 'package:fcm_studio/core/storage/app_database.dart';
import 'package:fcm_studio/core/storage/secret_store.dart';
import 'package:fcm_studio/features/projects/data/project_auth_registry.dart';
import 'package:fcm_studio/features/projects/data/projects_repository.dart';
import 'package:fcm_studio/features/projects/domain/project.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../helpers/fake_google_auth_flow.dart';
import '../../helpers/project_fixture.dart';
import '../../helpers/service_account_fixture.dart';

void main() {
  late AppDatabase database;
  late ProjectsRepository repository;
  late ProjectAuthRegistry registry;

  setUp(() async {
    database = await AppDatabase.inMemory();
    repository = ProjectsRepository(
      database: database,
      secrets: MemorySecretStore(),
    );
    registry = ProjectAuthRegistry(
      repository: repository,
      httpClient: MockClient((_) async => http.Response('unused', 500)),
    );
  });

  tearDown(() => database.close());

  test('loads the stored key once and caches the provider', () async {
    await repository.saveServiceAccountKey(
      ServiceAccountKey.parse(serviceAccountJson()),
      persist: true,
    );
    final first = await registry.providerFor(testProject);
    final second = await registry.providerFor(testProject);
    expect(first, isA<ServiceAccountTokenProvider>());
    expect(second, same(first));
  });

  test('explains a missing key (e.g. web reload without "remember")', () async {
    await expectLater(
      registry.providerFor(testProject),
      throwsA(
        isA<AuthException>().having(
          (e) => e.message,
          'message',
          contains('Add the project again'),
        ),
      ),
    );
  });

  test(
    'registerKey replaces the provider for the same service account',
    () async {
      final key = ServiceAccountKey.parse(serviceAccountJson());
      final first = registry.registerKey(key);
      final second = registry.registerKey(key);
      expect(second, isNot(same(first)));
      expect(await registry.providerFor(testProject), same(second));
    },
  );

  test('forget drops the cached provider', () async {
    final key = ServiceAccountKey.parse(serviceAccountJson());
    await repository.saveServiceAccountKey(key, persist: true);
    final first = registry.registerKey(key);
    registry.forget(testProject.credential);
    expect(await registry.providerFor(testProject), isNot(same(first)));
  });

  group('Google accounts', () {
    ProjectAuthRegistry google(
      FakeGoogleAuthFlow? flow, [
      FakeGoogleUserInfo? info,
    ]) => ProjectAuthRegistry(
      repository: repository,
      httpClient: MockClient((_) async => http.Response('unused', 500)),
      googleFlow: flow,
      googleUserInfo: info ?? FakeGoogleUserInfo(),
    );

    test('signs in, checks permissions and finds the account', () async {
      final flow = FakeGoogleAuthFlow();
      final session = await google(flow).signInWithGoogle();
      expect(session.email, testGoogleEmail);
      expect(session.account, const GoogleAccountRef(testGoogleEmail));
      expect(session.credentials.refreshToken, '1//refresh-1');
      expect(
        await session.provider.getToken(),
        googleCredentials().accessToken,
      );
      expect(flow.calls, ['signIn -']);
    });

    test('a sign-in without the Firebase permissions is refused', () async {
      final flow = FakeGoogleAuthFlow(
        signIns: [
          googleCredentials(scopes: const ['openid']),
        ],
      );
      await expectLater(
        google(flow).signInWithGoogle(),
        throwsA(
          isA<AuthException>().having(
            (e) => e.message,
            'message',
            missingScopesMessage,
          ),
        ),
      );
    });

    test('without the OAuth set-up, Google sign-in is unavailable', () async {
      final registry = google(null);
      expect(registry.canSignInWithGoogle, isFalse);
      await expectLater(
        registry.signInWithGoogle(),
        throwsA(
          isA<AuthException>().having(
            (e) => e.message,
            'message',
            contains('docs/oauth-setup.md'),
          ),
        ),
      );
      await expectLater(
        registry.providerFor(testGoogleProject),
        throwsA(
          isA<AuthException>().having(
            (e) => e.message,
            'message',
            contains('not set up'),
          ),
        ),
      );
    });

    test(
      'desktop: loads the stored refresh token once and refreshes with it',
      () async {
        await repository.saveGoogleRefreshToken(
          const GoogleAccountRef(testGoogleEmail),
          '1//stored',
        );
        final flow = FakeGoogleAuthFlow();
        final registry = google(flow);
        final provider = await registry.providerFor(testGoogleProject);
        expect(provider, isA<GoogleAccountTokenProvider>());
        expect(await registry.providerFor(testGoogleProject), same(provider));
        await provider.getToken();
        expect(flow.calls, ['refresh 1//stored']);
      },
    );

    test('desktop: a missing stored sign-in asks to sign in again', () async {
      await expectLater(
        google(FakeGoogleAuthFlow()).providerFor(testGoogleProject),
        throwsA(
          isA<AuthException>().having(
            (e) => e.message,
            'message',
            contains('Sign in again'),
          ),
        ),
      );
    });

    test('browser: nothing is stored; the popup supplies tokens', () async {
      final flow = FakeGoogleAuthFlow(
        canRefresh: false,
        signIns: [googleCredentials(refreshToken: null)],
      );
      final provider = await google(flow).providerFor(testGoogleProject);
      await provider.getToken();
      expect(flow.calls, ['signIn $testGoogleEmail']);
    });

    test(
      'registerGoogle replaces the cached provider for that account',
      () async {
        await repository.saveGoogleRefreshToken(
          const GoogleAccountRef(testGoogleEmail),
          '1//stored',
        );
        final registry = google(FakeGoogleAuthFlow());
        final old = await registry.providerFor(testGoogleProject);
        final session = await registry.signInWithGoogle();
        registry.registerGoogle(session);
        final current = await registry.providerFor(testGoogleProject);
        expect(current, same(session.provider));
        expect(current, isNot(same(old)));
      },
    );
  });
}
