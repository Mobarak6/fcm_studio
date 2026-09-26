import 'package:fcm_studio/core/auth/access_token_provider.dart';
import 'package:fcm_studio/core/auth/service_account_key.dart';
import 'package:fcm_studio/core/auth/service_account_token_provider.dart';
import 'package:fcm_studio/core/storage/app_database.dart';
import 'package:fcm_studio/core/storage/secret_store.dart';
import 'package:fcm_studio/features/projects/data/project_auth_registry.dart';
import 'package:fcm_studio/features/projects/data/projects_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

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
}
