import 'package:fcm_studio/core/auth/service_account_key.dart';
import 'package:fcm_studio/core/storage/app_database.dart';
import 'package:fcm_studio/core/storage/secret_store.dart';
import 'package:fcm_studio/features/projects/data/projects_repository.dart';
import 'package:fcm_studio/features/projects/domain/project.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_google_auth_flow.dart';
import '../../helpers/project_fixture.dart';
import '../../helpers/service_account_fixture.dart';

void main() {
  late AppDatabase database;
  late MemorySecretStore secrets;
  late ProjectsRepository repository;

  setUp(() async {
    database = await AppDatabase.inMemory();
    secrets = MemorySecretStore();
    repository = ProjectsRepository(database: database, secrets: secrets);
  });

  tearDown(() => database.close());

  const other = Project(
    id: 'other-project',
    displayName: 'Another',
    credential: ServiceAccountRef(
      'sender@other-project.iam.gserviceaccount.com',
    ),
  );

  test('saves projects and loads them sorted by name', () async {
    await repository.save(testProject);
    await repository.save(other);
    expect((await repository.loadAll()).map((p) => p.id), [
      'other-project',
      'demo-project',
    ]);
  });

  test('round-trips every field', () async {
    final project = testProject.copyWith(environment: ProjectEnvironment.prod);
    await repository.save(project);
    expect(await repository.loadAll(), [project]);
  });

  test(
    'removing a project deletes its key when no other project uses it',
    () async {
      await secrets.write(testProject.credential.secretKey, 'key');
      await repository.save(testProject);
      await repository.remove(testProject);
      expect(await repository.loadAll(), isEmpty);
      expect(await secrets.read(testProject.credential.secretKey), isNull);
    },
  );

  test('removing a project keeps a key another project still uses', () async {
    const sibling = Project(
      id: 'sibling',
      displayName: 'Sibling',
      credential: ServiceAccountRef(testClientEmail),
    );
    await secrets.write(testProject.credential.secretKey, 'key');
    await repository.save(testProject);
    await repository.save(sibling);
    await repository.remove(testProject);
    expect(await secrets.read(testProject.credential.secretKey), 'key');
  });

  test('stores and clears the selected project id', () async {
    expect(await repository.readSelectedProjectId(), isNull);
    await repository.writeSelectedProjectId(testProjectId);
    expect(await repository.readSelectedProjectId(), testProjectId);
    await repository.writeSelectedProjectId(null);
    expect(await repository.readSelectedProjectId(), isNull);
  });

  test('stores and reads a service account key', () async {
    final key = ServiceAccountKey.parse(serviceAccountJson());
    await repository.saveServiceAccountKey(key, persist: true);
    expect(
      await repository.readServiceAccountKey(
        const ServiceAccountRef(testClientEmail),
      ),
      key,
    );
  });

  test('returns null when the key is missing', () async {
    expect(
      await repository.readServiceAccountKey(
        const ServiceAccountRef(testClientEmail),
      ),
      isNull,
    );
  });

  test('Project.fromJson rejects unknown credential kinds', () {
    expect(
      () => Project.fromJson({
        ...testProject.toJson(),
        'credential': {'kind': 'mystery'},
      }),
      throwsFormatException,
    );
  });

  test('label shows the id only when it differs from the name', () {
    expect(testProject.label, 'Demo Project (demo-project)');
    expect(
      testProject.copyWith(displayName: testProjectId).label,
      testProjectId,
    );
  });

  test('a Google-account project round-trips', () async {
    await repository.save(testGoogleProject);
    expect(await repository.loadAll(), [testGoogleProject]);
  });

  test('stores a Google refresh token under google:<email>', () async {
    const account = GoogleAccountRef(testGoogleEmail);
    await repository.saveGoogleRefreshToken(account, '1//r');
    expect(
      await secrets.read('google:dev@example.com'),
      '{"refreshToken":"1//r"}',
    );
    expect(await repository.readGoogleRefreshToken(account), '1//r');
  });

  test('an unreadable stored sign-in reads as missing', () async {
    await secrets.write('google:dev@example.com', 'not json');
    expect(
      await repository.readGoogleRefreshToken(
        const GoogleAccountRef(testGoogleEmail),
      ),
      isNull,
    );
  });
}
