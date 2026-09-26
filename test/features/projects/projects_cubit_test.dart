import 'package:fcm_studio/core/firebase/firebase_projects_api.dart';
import 'package:fcm_studio/core/storage/app_database.dart';
import 'package:fcm_studio/core/storage/secret_store.dart';
import 'package:fcm_studio/features/projects/cubit/projects_cubit.dart';
import 'package:fcm_studio/features/projects/data/project_auth_registry.dart';
import 'package:fcm_studio/features/projects/data/projects_repository.dart';
import 'package:fcm_studio/features/projects/domain/project.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../helpers/fake_google.dart';
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

  ProjectsCubit buildCubit([http.Client? client]) {
    final httpClient = client ?? fakeGoogle();
    return ProjectsCubit(
      repository: repository,
      authRegistry: ProjectAuthRegistry(
        repository: repository,
        httpClient: httpClient,
      ),
      firebaseApi: FirebaseProjectsApi(httpClient: httpClient),
    );
  }

  test('adds a project from a service account key and selects it', () async {
    final cubit = buildCubit();
    await cubit.load();

    final result = await cubit.addFromServiceAccount(
      serviceAccountJson(),
      persistKey: true,
    );

    expect(
      result,
      isA<AddProjectSuccess>().having(
        (r) => r.needsProjectNumber,
        'needsProjectNumber',
        isFalse,
      ),
    );
    expect(cubit.state.selected, testProject);
    expect(await repository.loadAll(), [testProject]);
    expect(await repository.readSelectedProjectId(), testProjectId);
    expect(await secrets.read('sa:$testClientEmail'), isNotNull);
  });

  test(
    'uses the project ID as the name when the key cannot read project details',
    () async {
      final cubit = buildCubit(fakeGoogle(firebaseStatus: 403));
      await cubit.load();

      final result = await cubit.addFromServiceAccount(
        serviceAccountJson(),
        persistKey: true,
      );

      expect(
        result,
        isA<AddProjectSuccess>().having(
          (r) => r.needsProjectNumber,
          'needsProjectNumber',
          isTrue,
        ),
      );
      expect(cubit.state.selected?.displayName, testProjectId);
      expect(cubit.state.selected?.projectNumber, isNull);
    },
  );

  test('reports an invalid key file and changes nothing', () async {
    final cubit = buildCubit();
    await cubit.load();

    final result = await cubit.addFromServiceAccount('{}', persistKey: true);

    expect(result, isA<AddProjectFailure>());
    expect(cubit.state.projects, isEmpty);
  });

  test('reports a key that Google rejects and saves nothing', () async {
    final cubit = buildCubit(fakeGoogle(tokenStatus: 400));
    await cubit.load();

    final result = await cubit.addFromServiceAccount(
      serviceAccountJson(),
      persistKey: true,
    );

    expect(
      result,
      isA<AddProjectFailure>().having(
        (r) => r.message,
        'message',
        contains('rejected this key'),
      ),
    );
    expect(await repository.loadAll(), isEmpty);
    expect(await secrets.read('sa:$testClientEmail'), isNull);
  });

  test('adding the same project again keeps its environment', () async {
    final cubit = buildCubit();
    await cubit.load();
    await cubit.addFromServiceAccount(serviceAccountJson(), persistKey: true);
    await cubit.setEnvironment(testProjectId, ProjectEnvironment.prod);

    await cubit.addFromServiceAccount(serviceAccountJson(), persistKey: true);

    expect(cubit.state.projects, hasLength(1));
    expect(cubit.state.selected?.environment, ProjectEnvironment.prod);
  });

  test('load restores projects and the selected project', () async {
    await buildCubit().addFromServiceAccount(
      serviceAccountJson(),
      persistKey: true,
    );

    final restored = buildCubit();
    await restored.load();

    expect(restored.state.status, ProjectsStatus.ready);
    expect(restored.state.selectedId, testProjectId);
    expect(restored.state.projects, [testProject]);
  });

  test(
    'remove deletes the project and its key and selects another project',
    () async {
      final cubit = buildCubit();
      await cubit.load();
      await cubit.addFromServiceAccount(
        serviceAccountJson(
          projectId: 'other-project',
          clientEmail: 'sender@other-project.iam.gserviceaccount.com',
        ),
        persistKey: true,
      );
      await cubit.addFromServiceAccount(serviceAccountJson(), persistKey: true);

      await cubit.remove(testProjectId);

      expect(cubit.state.projects.map((p) => p.id), ['other-project']);
      expect(cubit.state.selectedId, 'other-project');
      expect(await secrets.read('sa:$testClientEmail'), isNull);
      expect(await repository.readSelectedProjectId(), 'other-project');
    },
  );

  test('setProjectNumber trims the value, and empty clears it', () async {
    final cubit = buildCubit(fakeGoogle(firebaseStatus: 403));
    await cubit.load();
    await cubit.addFromServiceAccount(serviceAccountJson(), persistKey: true);

    await cubit.setProjectNumber(testProjectId, ' 42 ');
    expect(cubit.state.selected?.projectNumber, '42');

    await cubit.setProjectNumber(testProjectId, '');
    expect(cubit.state.selected?.projectNumber, isNull);
  });
}
